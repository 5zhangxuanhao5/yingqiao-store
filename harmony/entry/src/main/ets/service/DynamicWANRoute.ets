import { WANRouteEvidenceState } from './DirectWANRoute';

export interface WANRouteMetrics {
 receivedFrames: number; renderSubmittedFrames: number; lostFrames: number;
 heldKeys?: number; heldButtons?: number; microphoneAllowed?: boolean;
 clockSyncValid?: boolean; clockSyncUncertaintyMs?: number | null; clockSyncRefreshes?: number;
 captureToRenderSubmitSampleCount?: number; captureToRenderSubmitWindowSamples?: number;
 captureToRenderSubmitP50ms?: number | null; captureToRenderSubmitP95ms?: number | null;
 timingWindowCapacity?: number; sessionWidthPx?: number; sessionHeightPx?: number; sessionTargetFPS?: number;
}
export interface WANRouteGate { eligible: boolean; inputIdle: boolean; epoch: number; target: string; generation: number; }
export interface WANRouteDecision { action: string; reason: string; }
export interface DynamicWANRouteState {
 phase: string; reason: string; attempted: boolean; directSamples: number;
 trialRemainingMs: number; cooldownRemainingMs: number; baselineP50ms: number; baselineP95ms: number;
}
interface RouteAnchor { at: number; received: number; rendered: number; lost: number; timed: number; clock: number; }
interface RouteMeasurement {
 p50: number; p95: number; uncertainty: number; loss: number; submission: number; at: number;
 width: number; height: number; fps: number; clock: number; renderFPS: number; receiveFPS: number;
}

// No provider calls, timers or performance claims. Existing foreground samples
// can justify one bounded trial; lack of comparable evidence preserves route3.
export class DynamicWANRoute {
 private epoch: number = -1;
 private target: string = '';
 private generation: number = -1;
 private route: number = -1;
 private intended: number = -1;
 private active: boolean = false;
 private attempted: boolean = false;
 private directSamples: number = 0;
 private directSequence: number = 0;
 private directAt: number = -1;
 private cooldownUntil: number = -1;
 private trialPending: boolean = false;
 private trialUntil: number = -1;
 private anchor: RouteAnchor | null = null;
 private baseline: RouteMeasurement | null = null;
 private previous: RouteAnchor | null = null;
 private latest: RouteMeasurement | null = null;
 private pendingRevert: string = '';
 private phase: string = 'idle';
 private reason: string = '';
 private counter(value: number | undefined): boolean { return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0; }
 private scope(epoch: number, target: string): void {
  if (epoch === this.epoch && target === this.target) { return; }
  this.epoch = epoch;this.target = target;this.attempted = false;this.cooldownUntil = -1;
  this.directSamples = 0;this.directSequence = 0;this.directAt = -1;this.anchor = null;this.previous = null;this.latest = null;this.pendingRevert = '';this.baseline = null;
  this.trialPending = false;this.trialUntil = -1;
 }
 observeDirect(evidence: WANRouteEvidenceState, epoch: number, target: string, now: number): void {
  // Observations do not arm a session or revive an Ended one.
  if (this.active && (epoch !== this.epoch || target !== this.target)) { this.cancel('network_changed'); }
  this.scope(epoch, target);
  if (!evidence.direct || !this.counter(evidence.sequence) || evidence.sequence <= 0 || !Number.isFinite(now) || now < 0) {
   this.directSamples = 0;this.directSequence = 0;this.directAt = -1;return;
  }
  if (evidence.sequence === this.directSequence) { return; }
  if (evidence.sequence < this.directSequence || now < this.directAt || (this.directAt >= 0 && now - this.directAt > 15000)) { this.directSamples = 0; }
  this.directSamples = Math.min(2, this.directSamples + 1);this.directSequence = evidence.sequence;this.directAt = now;
 }
 suppressDirect(epoch: number, target: string, now: number): boolean {
  return epoch === this.epoch && target === this.target && Number.isFinite(now) && now < this.cooldownUntil;
 }
 bind(route: number, intended: number, generation: number, epoch: number, target: string, now: number): void {
  this.scope(epoch, target);this.active = intended === 3 && [3, 4].includes(route);
  this.route = route;this.intended = intended;this.generation = generation;this.anchor = null;this.previous = null;this.latest = null;this.pendingRevert = '';
  if (this.trialPending && route === 4 && this.active) { this.trialPending = false;this.trialUntil = now + 10000;this.phase = 'trial';this.reason = 'measuring_udp'; }
  else { this.trialPending = false;this.trialUntil = -1;this.baseline = null;this.phase = this.active ? (route === 3 ? (now < this.cooldownUntil ? 'cooldown' : 'stable') : 'direct') : 'idle'; }
 }
 cancel(reason: string): void {
  this.active = false;this.generation = -1;this.anchor = null;this.previous = null;this.latest = null;this.pendingRevert = '';this.baseline = null;this.trialPending = false;this.trialUntil = -1;this.phase = 'idle';this.reason = reason;
 }
 failed(now: number, reason: string): void {
  this.attempted = true;this.cooldownUntil = now + 60000;this.trialPending = false;this.trialUntil = -1;this.anchor = null;this.previous = null;this.latest = null;this.pendingRevert = '';
  this.phase = 'cooldown';this.reason = reason;
 }
 private sample(s: WANRouteMetrics, now: number): RouteMeasurement | null {
  const valid = this.counter(s.receivedFrames) && this.counter(s.renderSubmittedFrames) && this.counter(s.lostFrames) &&
   this.counter(s.captureToRenderSubmitSampleCount) && this.counter(s.clockSyncRefreshes) &&
   s.clockSyncValid === true && typeof s.clockSyncUncertaintyMs === 'number' && Number.isFinite(s.clockSyncUncertaintyMs) && s.clockSyncUncertaintyMs >= 0 && s.clockSyncUncertaintyMs <= 30 &&
   typeof s.captureToRenderSubmitP50ms === 'number' && Number.isFinite(s.captureToRenderSubmitP50ms) && s.captureToRenderSubmitP50ms >= 0 &&
   typeof s.captureToRenderSubmitP95ms === 'number' && Number.isFinite(s.captureToRenderSubmitP95ms) && s.captureToRenderSubmitP95ms >= s.captureToRenderSubmitP50ms &&
   this.counter(s.timingWindowCapacity) && s.timingWindowCapacity === 120 &&
   this.counter(s.captureToRenderSubmitWindowSamples) && s.captureToRenderSubmitWindowSamples === s.timingWindowCapacity &&
   this.counter(s.sessionWidthPx) && s.sessionWidthPx! > 0 && this.counter(s.sessionHeightPx) && s.sessionHeightPx! > 0 && this.counter(s.sessionTargetFPS) && s.sessionTargetFPS! > 0;
  if (!valid) { this.anchor = null;this.previous = null;this.latest = null;return null; }
  const next: RouteAnchor = { at: now, received: s.receivedFrames, rendered: s.renderSubmittedFrames, lost: s.lostFrames, timed: s.captureToRenderSubmitSampleCount!, clock: s.clockSyncRefreshes! };
  const previous = this.previous;this.previous = next;
  const progressed = previous !== null && next.clock === previous.clock && next.timed > previous.timed && next.rendered > previous.rendered;
  const a = this.anchor;
  if (!a || now < a.at || next.clock !== a.clock || next.received < a.received || next.rendered < a.rendered || next.lost < a.lost || next.timed < a.timed) { this.anchor = next;this.latest = null;return null; }
  const received = next.received - a.received, rendered = next.rendered - a.rendered, lost = next.lost - a.lost;
  if (!progressed || now - a.at < 3000 || next.timed - a.timed < s.timingWindowCapacity! || received < 120 || rendered < 120) { return null; }
  this.anchor = next;
  this.latest = { p50: s.captureToRenderSubmitP50ms!, p95: s.captureToRenderSubmitP95ms!, uncertainty: s.clockSyncUncertaintyMs!,
   loss: lost / Math.max(1, received + lost), submission: rendered / Math.max(1, received), at: now,
   width: s.sessionWidthPx!, height: s.sessionHeightPx!, fps: s.sessionTargetFPS!, clock: next.clock, renderFPS: rendered * 1000 / (now - a.at), receiveFPS: received * 1000 / (now - a.at) };
  return this.latest;
 }
 private comparable(a: RouteMeasurement, b: RouteMeasurement): boolean { return a.width === b.width && a.height === b.height && a.fps === b.fps; }
 private worse(base: RouteMeasurement, trial: RouteMeasurement): boolean {
  const uncertainty = base.uncertainty + trial.uncertainty;
  return trial.loss > Math.max(0.10, base.loss + 0.08) || trial.submission < base.submission - 0.15 ||
   (trial.p95 > base.p95 + Math.max(30, base.p95 * 0.25, uncertainty + 10) && trial.p50 > base.p50 + Math.max(15, uncertainty + 5));
 }
 private better(base: RouteMeasurement, trial: RouteMeasurement): boolean {
  const uncertainty = base.uncertainty + trial.uncertainty;
  return trial.renderFPS >= base.renderFPS * 0.85 && trial.receiveFPS >= base.receiveFPS * 0.85 && trial.loss <= base.loss + 0.03 && trial.submission >= base.submission - 0.05 && trial.p95 <= base.p95 + Math.max(10, uncertainty) &&
   (trial.p50 < base.p50 - Math.max(5, base.p50 * 0.10, uncertainty) || trial.p95 < base.p95 - Math.max(10, base.p95 * 0.15, uncertainty));
 }
 step(s: WANRouteMetrics, gate: WANRouteGate, evidence: WANRouteEvidenceState, now: number): WANRouteDecision {
  const none: WANRouteDecision = { action: 'none', reason: '' };
  if (!this.active || gate.generation !== this.generation || gate.epoch !== this.epoch || gate.target !== this.target || !Number.isFinite(now) || now < 0) { return none; }
  const idle = gate.inputIdle && this.counter(s.heldKeys) && s.heldKeys === 0 && this.counter(s.heldButtons) && s.heldButtons === 0 && s.microphoneAllowed === false;
  // A decided failure is immutable. Held input can defer the connection
  // transition, never collect late evidence to turn a deadline into success.
  if (this.pendingRevert) {
   if (gate.eligible && idle) { const reason = this.pendingRevert;this.failed(now, reason);return { action: 'revert', reason: reason }; }
   return none;
  }
  const priorMeasurement = this.latest;
  const fresh = this.sample(s, now);
  if (this.phase === 'trial' || (this.phase === 'direct' && this.baseline !== null)) {
   const base = this.baseline;
   let trial = fresh;
   if (this.phase === 'trial' && now >= this.trialUntil && (!trial || trial.at > this.trialUntil)) {
    trial = this.latest !== null && priorMeasurement && priorMeasurement.at <= this.trialUntil && this.trialUntil - priorMeasurement.at <= 3000 &&
     priorMeasurement.clock === s.clockSyncRefreshes && s.clockSyncValid === true && typeof s.clockSyncUncertaintyMs === 'number' &&
     Number.isFinite(s.clockSyncUncertaintyMs) && s.clockSyncUncertaintyMs >= 0 && s.clockSyncUncertaintyMs <= 30 ? priorMeasurement : null;
   }
   const validTrial = base !== null && trial !== null && this.comparable(base, trial);
   let reason = '';
   if (validTrial && this.worse(base!, trial!)) { reason = 'trial_measured_worse'; }
   else if (this.phase === 'trial' && now >= this.trialUntil) {
    if (!validTrial) { reason = 'trial_no_comparable_progress'; }
    else if (!this.better(base!, trial!)) { reason = 'trial_no_measured_gain'; }
    else { this.trialUntil = -1;this.phase = 'direct';this.reason = 'trial_measured_gain';return none; }
   }
   if (reason) {
    this.pendingRevert = reason;this.reason = reason;this.phase = 'revert_pending';this.attempted = true;this.cooldownUntil = Math.max(this.cooldownUntil, now + 60000);
    if (gate.eligible && idle) { this.failed(now, reason);return { action: 'revert', reason: reason }; }
   }
   return none;
  }
  if (this.route !== 3 || this.intended !== 3 || this.attempted || now < this.cooldownUntil || !gate.eligible || !idle) { return none; }
  if (!fresh || !evidence.direct || this.directSamples < 2 || evidence.sequence !== this.directSequence || now - this.directAt > 15000) { return none; }
  this.baseline = fresh;this.attempted = true;this.trialPending = true;this.phase = 'upgrade_pending';this.reason = 'fresh_direct_trial';
  return { action: 'upgrade', reason: this.reason };
 }
 state(now: number): DynamicWANRouteState {
  return { phase: this.phase, reason: this.reason, attempted: this.attempted, directSamples: this.directSamples,
   trialRemainingMs: this.trialUntil >= 0 ? Math.max(0, this.trialUntil - now) : 0,
   cooldownRemainingMs: Math.max(0, this.cooldownUntil - now), baselineP50ms: this.baseline?.p50 ?? -1, baselineP95ms: this.baseline?.p95 ?? -1 };
 }
}
