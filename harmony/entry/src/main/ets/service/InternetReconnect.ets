export interface InternetIntent { mode: string; transport: number; fullScreen: boolean; }
export interface InternetReconnectGuard {
 generation: number; localGeneration: number; foreground: boolean; menu: boolean;
 localPending: boolean; surfaceReady: boolean;
}
export interface InternetReconnectHooks {
 guard: () => InternetReconnectGuard;
 later: (delayMs: number, action: () => void) => number;
 clear: (timer: number) => void;
 prepare: () => Promise<boolean>;
 release: (reason: string) => void;
 start: (intent: InternetIntent) => boolean;
 status: (message: string) => void;
}
export interface InternetReconnectState {
 phase: string; intended: boolean; mode: string; transport: number; attempts: number;
 epoch: number; timerPending: boolean; preparing: boolean; lastReason: string;
}

// Preserve only a user's existing internet-session intent. No platform API,
// native callback, media polling or idle timer is owned by this controller.
export class InternetReconnect {
 private hooks: InternetReconnectHooks;
 private intent: InternetIntent | null = null;
 private epoch: number = 0;
 private workEpoch: number = 0;
 private timer: number = -1;
 private generation: number = -1;
 private localGeneration: number = -1;
 private attempts: number = 0;
 private preparing: boolean = false;
 private starting: boolean = false;
 private outage: boolean = false;
 private recovering: boolean = false;
 private phase: string = 'idle';
 private lastReason: string = '';
 constructor(hooks: InternetReconnectHooks) { this.hooks = hooks; }
 private clearWork(): void {
  this.workEpoch++;this.preparing = false;
  if (this.timer >= 0) { this.hooks.clear(this.timer);this.timer = -1; }
 }
 cancel(reason: string): void {
  this.clearWork();this.epoch++;this.intent = null;this.outage = false;this.recovering = false;this.starting = false;
  this.phase = 'idle';this.lastReason = reason;this.generation = -1;this.localGeneration = -1;
 }
 arm(intent: InternetIntent): void {
  this.cancel('new_user_intent');
  const g = this.hooks.guard();
  if (![3, 4].includes(intent.transport) || !['remote', 'extend'].includes(intent.mode) ||
   !g.foreground || g.localPending || !g.surfaceReady) { return; }
  this.intent = { mode: intent.mode, transport: intent.transport, fullScreen: intent.fullScreen };
  this.generation = g.generation;this.localGeneration = g.localGeneration;this.attempts = 0;this.phase = 'connecting';
 }
 private allowed(epoch: number, work: number): boolean {
  if (!this.intent || epoch !== this.epoch || work !== this.workEpoch) { return false; }
  const g = this.hooks.guard();
  if (!g.foreground || g.localPending || g.localGeneration !== this.localGeneration || g.generation !== this.generation || !g.surfaceReady) {
   this.cancel(!g.foreground ? 'background' : (g.localPending || g.localGeneration !== this.localGeneration ? 'local_start_owns_session' : 'session_replaced'));
   return false;
  }
  return true;
 }
 updateFullScreen(generation: number, fullScreen: boolean): void {
  if (this.intent && (generation === this.generation || this.starting)) { this.intent.fullScreen = fullScreen; }
 }
 connected(generation: number): void {
  if (!this.intent || generation !== this.generation) { return; }
  this.clearWork();this.outage = false;this.recovering = false;this.attempts = 0;this.phase = 'connected';
 }
 lost(generation: number, reason: string): boolean {
  if (!this.intent || generation !== this.generation) { return false; }
  const epoch = this.epoch, work = this.workEpoch;
  if (!this.allowed(epoch, work)) { return false; }
  if (this.recovering) { return true; } // duplicate stats/netLost must not reset backoff
  if (!this.outage) { this.attempts = 0;this.outage = true; }
  this.recovering = true;this.lastReason = reason;this.phase = 'waiting';
  // Release immediately, before preparing a network or waiting for backoff.
  // The caller retains its local menu/fullscreen intent and invalidates native
  // mouse/cursor bindings; it must not invalidate a menu's session generation.
  this.hooks.release('internet_reconnect');
  this.generation = this.hooks.guard().generation;
  if (epoch !== this.epoch || !this.intent) { return true; }
  this.hooks.status('互联网连接中断，正在重新连接…');this.queue();return true;
 }
 gatesChanged(): void {
  if (!this.intent || this.starting) { return; }
  const g = this.hooks.guard();
  if (!g.foreground) { this.cancel('background');return; }
  if (!this.allowed(this.epoch, this.workEpoch)) { return; }
  if (g.menu) { this.clearWork();if (this.recovering) { this.phase = 'menu_paused'; }return; }
  if (this.recovering && this.timer < 0 && !this.preparing) { this.queue(); }
 }
 // A real default-network/peer-online transition may accelerate a pending
 // retry. It never creates an intent after End or restores one on foreground.
 networkAvailable(): void {
  if (!this.intent || !this.recovering || this.preparing || this.starting || !this.allowed(this.epoch, this.workEpoch)) { return; }
  this.clearWork();this.attempts = 0;this.queue();
 }
 private queue(): void {
  if (!this.intent || !this.recovering || this.timer >= 0 || this.preparing || !this.allowed(this.epoch, this.workEpoch)) { return; }
  if (this.hooks.guard().menu) { this.phase = 'menu_paused';return; }
  if (this.attempts >= 8) { this.phase = 'waiting_network';this.hooks.status('当前网络暂无法恢复，等待网络变化；仍可结束会话。');return; }
  const delay = this.attempts === 0 ? 500 : (this.attempts === 1 ? 2000 : (this.attempts === 2 ? 4000 : 8000));
  const epoch = this.epoch, work = this.workEpoch;this.phase = 'waiting';
  this.timer = this.hooks.later(delay, () => {
   if (epoch !== this.epoch || work !== this.workEpoch) { return; }
   this.timer = -1;this.attempt(epoch, work);
  });
 }
 private async attempt(epoch: number, work: number): Promise<void> {
  if (!this.allowed(epoch, work) || !this.intent || this.hooks.guard().menu) { this.gatesChanged();return; }
  this.attempts++;this.preparing = true;this.phase = 'preparing';
  let ready = false;try { ready = await this.hooks.prepare(); } catch (e) { ready = false; }
  if (!this.allowed(epoch, work) || !this.intent) { return; }
  this.preparing = false;
  if (this.hooks.guard().menu) { this.phase = 'menu_paused';return; }
  if (!ready) { this.queue();return; }
  const intended: InternetIntent = { mode: this.intent.mode, transport: this.intent.transport, fullScreen: this.intent.fullScreen };
  this.starting = true;let accepted = false;
  try { accepted = this.hooks.start(intended); } catch (e) { accepted = false; } finally { this.starting = false; }
  if (!accepted) { if (this.allowed(epoch, work)) { this.queue(); }return; }
  if (epoch !== this.epoch || work !== this.workEpoch || !this.intent) { return; }
  this.generation = this.hooks.guard().generation;this.recovering = false;this.phase = 'connecting';
  // A native start is not a connected session. Only a real streaming report
  // clears the outage/backoff; a failed attempt can continue at 2/4/8 s.
 }
 state(): InternetReconnectState {
  return { phase: this.phase, intended: this.intent !== null, mode: this.intent?.mode || '', transport: this.intent?.transport || 0,
   attempts: this.attempts, epoch: this.epoch, timerPending: this.timer >= 0, preparing: this.preparing, lastReason: this.lastReason };
 }
}

export function recoverableInternetFailure(stopReason: string, error: string): boolean {
 if (['user_end', 'restart', 'udp_fallback', 'mac_cancelled_request', 'mode_changed', 'transport_changed'].includes(stopReason) ||
  stopReason.startsWith('window_') || stopReason.startsWith('ability_') || stopReason.startsWith('view_')) { return false; }
 if (['证书', '身份', '认证', '配对', '权限', '解码', '编码', '配置', 'Surface', '参数'].some((text: string) => error.includes(text))) { return false; }
 return error.length === 0 || ['连接', '网络', '超时', '握手'].some((text: string) => error.includes(text));
}
