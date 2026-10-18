import { webview } from '@kit.ArkWeb';

interface RTCDescription { type: string; sdp: string; }
interface RTCCandidate { candidate: string; sdpMid: string; sdpMLineIndex: number; }
interface RTCEvent { event: string; epoch: number; session?: string; description?: RTCDescription; candidate?: RTCCandidate; }
export interface RTCIceServer { urls: Array<string>; username?: string; credential?: string; }
export class RTCArkWebTransport {
 private controller: webview.WebviewController;
 private ports: Array<webview.WebMessagePort> = [];
 private generation: number = 0;
 private active: boolean = false;
 private ready: boolean = false;
 private session: string = '';
 private pendingSignals: Array<string> = [];
 private pendingConfiguration: string = '';
 authenticatedOwnerStillCurrent: () => boolean = () => false;
 onSignal: (json: string) => void = () => {};
 // This callback must copy into a bounded NAPI worker queue and return promptly.
 // Native existing per-session AES-GCM verifier runs before decoder enqueue.
 onEncryptedRecord: (record: ArrayBuffer) => void = () => {};
 onIDRRequired: () => void = () => {};
 onStatus: (status: string) => void = () => {};
 onDiagnostic: (event: string, json: string) => void = () => {};
 constructor(controller: webview.WebviewController) { this.controller = controller; }
 start(session: string, servers: Array<RTCIceServer>, relayOnly: boolean, recordBudgetMs: number = 100): boolean {
  this.stop();
  if (!/^[a-f0-9]{32,128}$/.test(session) || servers.length > 8 || !this.authenticatedOwnerStillCurrent()) return false;
  this.session = session; this.active = true;
  this.pendingConfiguration = JSON.stringify({ session: session, role: 'receiver', iceServers: servers, relayOnly: relayOnly, recordBudgetMs: recordBudgetMs, echoCompleteRecords: false });
  return true;
 }
 // Called by the trusted local rawfile Web component's onPageEnd. The browser
 // carries encrypted video only; no camera/mic permission or user-media request.
 onPageLoaded(): void {
  if (!this.active || !this.authenticatedOwnerStillCurrent()) return;
  const epoch = this.generation;
  this.onDiagnostic('bridge-stage', JSON.stringify({stage: 'page-loaded'}));
  try {
   this.ports = this.controller.createWebMessagePorts();
   this.ports[0].onMessageEvent((message: webview.WebMessage) => {
    if (!this.active || epoch !== this.generation || !this.authenticatedOwnerStillCurrent()) return;
    if (typeof message !== 'string') {
     if (message.byteLength < 44 || message.byteLength > 2 * 1024 * 1024) { this.onIDRRequired(); return; }
     this.onEncryptedRecord(message); return;
    }
    if (message.length > 65536) { this.stop(); this.onStatus('signal-too-large'); return; }
    const event = JSON.parse(message) as RTCEvent;
    if (event.event !== 'signal') this.onDiagnostic(event.event, message);
    if (event.event === 'signal') {
     if (event.session !== this.session) { this.stop(); return; }
     this.onSignal(message);
    } else if (event.event === 'idr-needed') this.onIDRRequired();
    else if (event.event === 'channel-open') this.onStatus('channel-open');
    else if (event.event === 'failure' || event.event === 'channel-error') { this.stop(); this.onStatus('browser-transport-failed'); }
   });
   this.onDiagnostic('bridge-stage', JSON.stringify({stage: 'native-port-bound'}));
   this.controller.postMessage('edgelink-rtc-port-v1', [this.ports[1]], '*');
   this.controller.runJavaScript(`rtcBridge.createPeer(${this.pendingConfiguration}).catch(e=>{rtcBridge.reportFailure(e.message);});void 0;`).catch(() => {
    if (this.active && epoch === this.generation) { this.stop(); this.onStatus('browser-start-failed'); }
   });
   this.onDiagnostic('bridge-stage', JSON.stringify({stage: 'peer-config-sent'}));
   this.pendingConfiguration = ''; this.ready = true;
   const early = this.pendingSignals; this.pendingSignals = [];
   early.forEach(signal => this.acceptAuthenticatedSignal(signal));
  } catch (_) { this.stop(); this.onStatus('native-port-failed'); }
 }
 acceptAuthenticatedSignal(json: string): boolean {
  if (!this.active || !this.authenticatedOwnerStillCurrent() || json.length > 65536) return false;
  try {
   const event = JSON.parse(json) as RTCEvent;
   if (event.session !== this.session) return false;
   if (!this.ready) {
    if (this.pendingSignals.length >= 64 || this.pendingSignals.reduce((n: number, s: string) => n + s.length, 0) + json.length > 256 * 1024) return false;
    this.pendingSignals.push(json); return true;
   }
   const epoch = this.generation, safeJSON = JSON.stringify(event);
   this.controller.runJavaScript(`rtcBridge.acceptSignal(${safeJSON}).catch(e=>{rtcBridge.reportFailure(e.message);});void 0;`).catch(() => {
    if (this.active && epoch === this.generation) { this.stop(); this.onStatus('browser-signal-failed'); }
   }); return true;
  } catch (_) { return false; }
 }
 sendRenderAck(sid: string, id: string): void {
  if (!this.active || !this.authenticatedOwnerStillCurrent() || !/^[0-9]{1,10}$/.test(sid) || !/^[1-9][0-9]{0,18}$/.test(id)) return;
  const epoch=this.generation;
  this.controller.runJavaScript(`rtcBridge.sendRenderAckNative(${JSON.stringify(this.session)},${JSON.stringify(sid)},${JSON.stringify(id)});void 0;`).catch(() => {
   if(this.active && epoch===this.generation){this.stop();this.onStatus('browser-ack-failed');}
  });
 }
 requestSafeSnapshot(): void {
  if (!this.active || !this.ready || !this.authenticatedOwnerStillCurrent()) return;
  // Diagnostics are optional. They never terminate an otherwise valid session.
  try { this.controller.runJavaScript('rtcBridge.reportSafeSnapshot();void 0;').catch(() => {}); } catch (_) {}
 }
 stop(): void {
  this.generation++; this.active = false; this.ready = false; this.session = ''; this.pendingConfiguration = ''; this.pendingSignals = [];
  this.ports.forEach(p => { try { p.close(); } catch (_) {} }); this.ports = [];
  try { this.controller.runJavaScript('rtcBridge.stop();void 0;').catch(() => {}); } catch (_) {}
 }
}
