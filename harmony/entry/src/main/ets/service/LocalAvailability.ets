import native, { AvailabilityEvent } from 'libedgelink.so';
import { common } from '@kit.AbilityKit';
import { mdns } from '@kit.NetworkKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';
import { image } from '@kit.ImageKit';

export interface LocalPath {
 route: string;
 ready: boolean;
 rttMedianMs?: number;
 rttP95Ms?: number;
 goodputMbps?: number;
}
export interface LocalAvailabilityStatus {
 paths: LocalPath[];
 hostHint?: string;
 preferredRoute: string;
}

// Discovery supplies candidates only. A path is ready only after exact paired
// certificate verification and the server's authenticated local-ingress READY.
export class LocalAvailability {
 private static statusBarOwner: number = 0;
 private statusBarLease: number = ++LocalAvailability.statusBarOwner;
 private statusBarRequested: boolean = false;
 private alive: boolean = true;
 private epoch: number = 1;
 private discovery: mdns.DiscoveryService | null = null;
 private lastDiscoveryAt: number = 0;
 discoveryStatus: string = 'not_started';
 private white: image.PixelMap | null = null;
 private black: image.PixelMap | null = null;
 private context: common.UIAbilityContext;
 private token: string;
 private certificate: string;
 private callback: (event: AvailabilityEvent) => void;
 private statusCallback: () => void;
 host: string;
 selfShowSupported: boolean = false;
 constructor(context: common.UIAbilityContext, host: string, token: string, certificate: string,
  callback: (event: AvailabilityEvent) => void, statusCallback: () => void) {
  this.context = context;this.host = host;this.token = token;this.certificate = certificate;
  this.callback = callback;this.statusCallback = statusCallback;
 }
 start(): void {
  this.configure();this.prepareStatusBar();this.search();
 }
 private search(): void {
  this.lastDiscoveryAt = Date.now();
  if (this.discovery) { try { this.discovery.off('serviceFound');this.discovery.stopSearchingMDNS(); } catch (e) {}this.discovery = null; }
  try {
   const discovery = mdns.createDiscoveryService(this.context, '_yingqiaostandby._tcp');this.discovery = discovery;
   discovery.on('serviceFound', (info: mdns.LocalServiceInfo) => {
    if (!this.alive || !info.serviceName.startsWith('映桥测试版-Mac')) { return; }
    this.discoveryStatus = 'found';const epoch = this.epoch;
    mdns.resolveLocalService(this.context, info).then((resolved: mdns.LocalServiceInfo) => {
     if (!this.alive || epoch !== this.epoch || resolved.port !== 49562 || !resolved.host) { return; }
     const address = resolved.host.address;this.discoveryStatus = `resolved:${address}`;
     if (!this.numericIPv4(address) || address.startsWith('127.') || address === this.host) { return; }
     // Keep a verified current LAN connection stable. Do not let another mDNS
     // advertisement bounce an active path or an in-flight local start.
     const status = this.status();if (status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready)) { return; }
     this.host = address;this.configure();
    }).catch((e: Error) => { this.discoveryStatus = `resolve_failed:${e.message}`; });
   });
   discovery.startSearchingMDNS();this.discoveryStatus = 'searching';
  } catch (e) { this.discoveryStatus = `search_failed:${e}`; }
 }
 private numericIPv4(value: string): boolean {
  const fields = value.split('.');return fields.length === 4 && fields.every((v: string) => /^\d{1,3}$/.test(v) && Number(v) <= 255);
 }
 private configure(): void {
  if (!this.alive) { return; }
  const epoch = this.epoch;
  native.availabilityConfigure(this.numericIPv4(this.host) ? this.host : '', 49562, this.token, this.certificate,
   (event: AvailabilityEvent) => { if (this.alive && epoch === this.epoch) { this.callback(event); } });
 }
 status(): LocalAvailabilityStatus {
  try { return JSON.parse(native.availabilityStatus()) as LocalAvailabilityStatus; }
  catch (e) { return { paths: [], preferredRoute: '' }; }
 }
 state(active: boolean, foreground: boolean, surfaceReady: boolean): void {
  if (!this.alive) { return; }
  native.availabilityState(active ? 'busy' : (!surfaceReady || (!foreground && !this.selfShowSupported) ? 'backgroundUnsupported' : 'idle'));
 }
 setHost(host: string): void {
  if (!this.alive || !this.numericIPv4(host) || host === this.host) { return; }
  this.host = host;this.configure();
 }
 refresh(): void {
  if (!this.alive) { return; }
  native.availabilityRefresh();
  this.refreshDiscovery();
 }
 refreshDiscovery(): void {
  if (!this.alive) { return; }
  const status = this.status();
  if (status.hostHint && status.paths.some((p: LocalPath) => p.route === 'usb' && p.ready) && !status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready)) { this.setHost(status.hostHint); }
  if (!status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready) && Date.now() - this.lastDiscoveryAt >= 15000) { this.search(); }
 }
 private async icon(white: boolean): Promise<image.PixelMap> {
  const pixels = new Uint8Array(24 * 24 * 4);
  for (let y = 0; y < 24; y++) {
   for (let x = 0; x < 24; x++) {
    const screen = ((x >= 2 && x <= 14 && y >= 4 && y <= 14) && (x <= 3 || x >= 13 || y <= 5 || y >= 13)) ||
     ((x >= 11 && x <= 21 && y >= 10 && y <= 20) && (x <= 12 || x >= 20 || y <= 11 || y >= 19));
    if (screen) { const n = (y * 24 + x) * 4;pixels[n] = white ? 255 : 23;pixels[n + 1] = white ? 255 : 45;pixels[n + 2] = white ? 255 : 44;pixels[n + 3] = 255; }
   }
  }
  return image.createPixelMap(pixels.buffer, { size: { width: 24, height: 24 }, pixelFormat: image.PixelMapFormat.RGBA_8888, editable: false });
 }
 private async prepareStatusBar(): Promise<void> {
  try {
   const supported = await statusBarManager.isStatusBarCapabilitySupported(this.context);
   if (!this.alive || !supported) { return; }
   this.white = await this.icon(true);this.black = await this.icon(false);
   if (!this.alive) { this.releaseIcons();return; }
   const item: statusBarManager.StatusBarItem = {
    icons: { white: this.white, black: this.black },
    quickOperation: { title: '映桥', height: 1, abilityName: '', moduleName: 'entry' },
    hoverTips: '映桥 · Mac 与 Edge 已准备连接',
    statusBarGroupMenu: [[{ title: '打开映桥', menuAction: { abilityName: 'EntryAbility', moduleName: 'entry' } }]]
   };
   this.statusBarRequested = true;
   statusBarManager.addToStatusBar(this.context, item, (error) => {
    if (!this.alive || this.statusBarLease !== LocalAvailability.statusBarOwner) {
     if (this.statusBarLease === LocalAvailability.statusBarOwner) { try { statusBarManager.removeFromStatusBar(this.context); } catch (e) {} }
     return;
    }
    this.selfShowSupported = !error;this.statusCallback();
   });
  } catch (e) { this.selfShowSupported = false;this.statusCallback(); }
 }
 private releaseIcons(): void {
  this.white?.release().catch(() => {});this.black?.release().catch(() => {});this.white = null;this.black = null;
 }
 stop(): void {
  this.alive = false;this.epoch++;native.availabilityStop();
  if (this.discovery) { try { this.discovery.off('serviceFound');this.discovery.stopSearchingMDNS(); } catch (e) {}this.discovery = null; }
  if (this.statusBarRequested && this.statusBarLease === LocalAvailability.statusBarOwner) { try { statusBarManager.removeFromStatusBar(this.context); } catch (e) {} }
  this.selfShowSupported = false;this.releaseIcons();
 }
}
