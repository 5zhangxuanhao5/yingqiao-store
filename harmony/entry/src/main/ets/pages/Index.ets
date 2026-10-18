import { HarmonyAccessoryCandidate } from '../store/HarmonyAccessory';
import { pasteboard, systemDateTime } from '@kit.BasicServicesKit';
import { scanBarcode } from '@kit.ScanKit';
import { validatePairing, STORE_DOWNLOAD_URL, StorePairing } from '../store/StorePairing';
import native, { NativeMouseSample, NativeCursorSample, AvailabilityEvent } from 'libedgelink.so';
import { webview } from '@kit.ArkWeb';
import { RTCArkWebTransport, RTCIceServer } from '../service/RTCArkWebTransport';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { window, display, FrameCallback } from '@kit.ArkUI';
import { connection } from '@kit.NetworkKit';
import { inputDevice, pointer } from '@kit.InputKit';
import { LocalAvailability, LocalAvailabilityStatus, LocalPath } from '../service/LocalAvailability';
import { InternetReconnect, InternetIntent, InternetReconnectState, recoverableInternetFailure } from '../service/InternetReconnect';
import { DirectWANRoute, WANPeerRoute, WANRouteSnapshot, WANRouteEvidenceState } from '../service/DirectWANRoute';
import { DynamicWANRoute, WANRouteMetrics, DynamicWANRouteState, WANRouteGate } from '../service/DynamicWANRoute';
interface RTCNativeEvent { epoch: number; session: string; kind: string; body: string; }
interface RTCMediaConfig { session: string; iceServers: Array<RTCIceServer>; relayOnly: boolean; budgetMs: number; }
interface RTCBridgeDiagnostics {
 recordBudgetMs: number; records: number; expired: number; rejected: number; queueDrops: number;
 videoRecords: number; keyframeRecords: number; deltaRecords: number;
 lastVideoBytes: number; largestVideoBytes: number; lastKeyframeBytes: number; largestKeyframeBytes: number;
 iceErrors: number; lastIceErrorCode: number; assemblyExpiryEvents: number; assemblyCapEvents: number; sendBudgetEvents: number;
 failures: number; channelErrors: number; stage: string; iceState: string; connectionState: string; updatedAt: number;
}
interface RTCBridgeSafeEvent {
 event: string; stage?: string; state?: string; code?: number; reason?: string;
 received?: number; expired?: number; rejected?: number; queueDrops?: number;
 videoRecords?: number; keyframeRecords?: number; deltaRecords?: number;
 lastVideoBytes?: number; largestVideoBytes?: number; lastKeyframeBytes?: number; largestKeyframeBytes?: number; recordBudgetMs?: number;
}
interface PlatformNetwork { name: string; prefixes: string[]; mtu: number; routeEpoch: number; netId: number; }
interface InputTrace { kind: string; action: number; source: number; tool: number; fingers: number; deviceId: number; }
interface InputDeviceDiagnostic { id: number; name: string; sources: string[]; isVirtual?: boolean; isLocal?: boolean; }
interface ClickTrace { button: number; down: boolean; count: number; intervalMs: number; distanceVp: number; }
interface TouchScreenDecision { kind: string; state: string; events: number; elapsedMs: number; x: number; y: number; distanceVp: number; held: number; relative: number; }
interface RelativeMouseSample { dx: number; dy: number; absoluteX: number; absoluteY: number; }
interface DesktopRect { x: number; y: number; width: number; height: number; }
interface DesktopPoint { x: number; y: number; }
interface NativeMouseGateCounts {
 callbacks: number; forwarded: number; unbound: number; staleEpoch: number; staleGeneration: number;
 disabled: number; notFullscreen: number; sessionInactive: number; windowInactive: number; menu: number; textEditor: number; action: number;
}
interface NativeMouseCallbackSample {
 generation: number; boundGeneration: number; callbackGeneration: number; epoch: number; callbackEpoch: number;
 dropReason: number; action: number; button: number; source: number; tool: number; deviceId: number; timeNs: number;
 rawX: number; rawY: number; x: number; y: number; held: number; relative: number;
}
interface MouseInputSample {
 action: number; button: number; source: number; sourceTool: number; deviceId?: number; timestamp: number;
 x: number; y: number; windowX: number; windowY: number; displayX: number; displayY: number;
 rawDeltaX?: number; rawDeltaY?: number;
 nativeAction?: number; nativeButton?: number; nativeTool?: number;
}
interface RelativeDragSample {
 route: number; action: number; deviceId: number; source: number; tool: number; timeNs: number;
 x: number; y: number; windowX: number; windowY: number; displayX: number; displayY: number;
 rawX: number; rawY: number; rawValid: number; held: number; relative: number; converted: number; virtualX: number; virtualY: number; nativeAction: number; nativeButton: number; nativeTool: number;
}
class AfterLayout extends FrameCallback {
 private action: () => void;
 constructor(action: () => void) { super();this.action = action; }
 onIdle(_timeLeft: number): void { this.action(); }
}
interface StoreProfile { supported: boolean; width: number; height: number; fps: number; codec: string; }
interface Pairing { token: string; cert: string; host: string; port: number; udpPort: number; }
interface Settings { host: string; transport: number; resolution: number; fps: number; ctrlToCmd: boolean; internetHost?: string; }
interface DiagnosticProfile { transport: number; resolution: number; fps: number; }
interface PendingRemoteRouteIntent { mode: string; transport: number; routeIntent: number; preserveFallback: boolean; fromDiagnostic: boolean; preservePresentation: boolean; }
interface NetworkPeer extends WANPeerRoute { relayRegion: string; rxBytes: number; txBytes: number; }
interface NetworkState extends WANRouteSnapshot { authURL?: string; ips?: string[]; peers?: NetworkPeer[]; error?: string; }
interface Statistics extends WANRouteMetrics {
 sessionID?: number;localHandoverSupported?: boolean;localHandoverCount?: number;localHandoverReason?: string;
 dynamicWANRoute?: DynamicWANRouteState;
 profileTransport?: number;autoDirectWAN?: boolean;wanRouteEvidence?: WANRouteEvidenceState;
 rtcBridgeDiagnostics?: RTCBridgeDiagnostics;
 microphoneAllowed?: boolean;microphoneState?: string;microphoneError?: string;
 internetReconnect?: InternetReconnectState;
 splitPathRequested?: boolean; splitPathActive?: boolean; controlRoute?: string; videoRoute?: string; diagnosticSplitTransport?: string;
 axisInputEnabled: boolean; axisMonitorEnabled: boolean; axisMonitorResult: number; monitorScrollEvents: number; monitorPinchEvents: number;
 stopReason: string; nativeKeyEvents: number; inputCalls: number; inputSent: number;
 touchEvents: number; mouseEvents: number; keyEvents: number; state: string; error: string;
 axisEvents: number; scrollCommands: number; zoomCommands: number; lastAxisX: number; lastAxisY: number; lastPinchScale: number;
 touchpadPanEvents: number; touchpadPinchEvents: number; lastTouchSource: number; lastTouchTool: number;
 touchScreenSingleState: string; touchScreenScrollGestures: number; touchScreenLongPressDrags: number;
 touchScreenSingleEvents: number; touchScreenDecisions: TouchScreenDecision[];
 inputTools: number[]; inputSources: number[]; inputTrace: InputTrace[]; clickTrace: ClickTrace[]; windowWarnings: string[];
 inputDevices: InputDeviceDiagnostic[]; inputDeviceStatus: string; inputDeviceFailures: number[];
 convertedTrackpadScrollEvents: number; convertedTrackpadScrollGestures: number; convertedTrackpadDeviceId: number;
 receivedFrames: number; decodedFrames: number; renderSubmittedFrames: number; lostFrames: number;
 receivedFPS: number; renderSubmittedFPS: number; displayClockFPS: number; decodeP95ms: number;
 inputQueueP95ms: number; bytesReceived: number; running: boolean;
 fullScreen: boolean; menuVisible: boolean; windowInputActive: boolean; viewportWidthPx: number; viewportHeightPx: number; windowError: string;
 systemWindowMode: string; freeWindowMode: boolean;
 udpDatagrams: number;
 fallbackReason: string; fallbackAttempted: boolean; fallbackTriggerFrames: number; fallbackFrameDelta: number; fallbackElapsedMs: number; fallbackUdpDatagramDelta: number; sessionGeneration: number; sessionTransport: number;
 cursorLocked: boolean; cursorFollowMovement: boolean; cursorLockPending: boolean; cursorLockStateUncertain: boolean; cursorLockWindowId: number; localUI: boolean;
 relativeCursorRequested: boolean; relativeCursorActive: boolean; relativeCursorAnchorReady: boolean; relativeCursorStatus: string; systemCursorHidden: boolean;
 relativeRawEvents: number; relativeMissingRawEvents: number; relativeGainVpPerHardwareUnit: number; relativeRawSamples: RelativeMouseSample[]; lastAbsoluteMouseX: number; lastAbsoluteMouseY: number; virtualCursorX: number; virtualCursorY: number;
 relativeDragTrace: RelativeDragSample[]; relativeDragTouchMoves: number; relativeDragMouseMoves: number;
 mouseRouteEvents: number[]; mouseDuplicateEvents: number;
 nativeMouseRouteBound: boolean; nativeMouseRouteBindResult: number;
 nativeMouseRouteGeneration: number; nativeMouseRouteEpoch: number;
 nativeMouseCallbackCounts: NativeMouseGateCounts; nativeMouseCallbackSamples: NativeMouseCallbackSample[];
 desktopTopologyRevision?: number; desktopTopologyValid: boolean; desktopCaptureX: number; desktopCaptureY: number; desktopCaptureWidth: number; desktopCaptureHeight: number; desktopDisplays: DesktopRect[];
 extendedPointerEnabled: boolean; relativeCursorOnPad: boolean; desktopPointerX: number; desktopPointerY: number;
 cursorChannelSupported: boolean; cursorChannelBound: boolean; cursorChannelBindResult: number;
 cursorChannelSessionEpoch: number; cursorLastSequence: number; cursorEdgeInputSequence: number; cursorSourceOwner: number;
 cursorSyncApplied: number; cursorSyncStaleSession: number; cursorSyncStaleSequence: number; cursorSyncStaleInput: number; cursorSyncInvalid: number;
 hostCursorOwner: boolean; hostCursorVisible: boolean;
}
@Entry
@Component
struct Index {
 @State storeStage: number = 0;
 @State storePairingText: string = '';
 @State storeError: string = '';
 @State storeProfileLabel: string = '自动匹配屏幕与硬件能力';
 private storeWidth: number = 1920;
 private storeHeight: number = 1280;
 private readonly accessorySDKContract: boolean = HarmonyAccessoryCandidate.sdkContractAvailable;
 private storeCodec: string = 'avc';
 private async storeFirstRun(): Promise<void> {
  try { const text = fileIo.readTextSync(`${this.context().filesDir}/store-pairing.json`);this.applyStorePairing(text, false);return; } catch (e) {}
  const choice = await this.getUIContext().getPromptAction().showDialog({ title: '电脑已安装映桥吗？', message: '平板与电脑需要各安装一端。新版使用独立配对，不读取个人版配置。', buttons: [{ text: '是，已安装', color: '#23796C' }, { text: '还没有', color: '#607A74' }] });
  this.storeStage = choice.index === 0 ? 2 : 1;
 }
 private async storeCopyLink(): Promise<void> {
  try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, STORE_DOWNLOAD_URL));this.getUIContext().getPromptAction().showToast({ message: '电脑端下载链接已复制' }); } catch(e) { this.storeError='未能复制，请选中链接手动复制。'; }
 }
 private async storeScan(): Promise<void> {
  try { const result = await scanBarcode.startScanForResult(this.context());this.applyStorePairing(result.originalValue, true); } catch(e) { this.storeError='扫码未完成，也可以粘贴电脑端的配对信息。'; }
 }
 private applyStorePairing(text: string, save: boolean): void {
  const pairing=validatePairing(text);if (!pairing) { this.storeError='配对信息无效，请使用电脑端显示的二维码或完整配对信息。';this.storeStage=2;return; }
  this.pairing=pairing;this.host=pairing.host;this.pairingLoaded=true;this.transport=1;this.storeCodec=pairing.codecs.includes('hevc') ? 'hevc':'avc';
  if (save) { this.writeFile('store-pairing.json', JSON.stringify(pairing)); }
  this.storeStage=3;this.message='已保存本机配对，可开启局域网扩展屏。';this.storeError='';this.localRouteLabel='局域网直连；消费级 USB 接续仍在验证';
 }
 private storeSelectProfile(): void {
  const panel=display.getDefaultDisplaySync();const w=panel.width,h=panel.height;
  const profile=JSON.parse(native.storeProfile(w,h,this.pairing ? this.pairing.codecs.join(','):this.storeCodec,Math.round(panel.refreshRate))) as StoreProfile;
  if (!profile.supported) { throw Error('此设备没有适合当前屏幕的硬件解码器'); }
  this.storeWidth=profile.width;this.storeHeight=profile.height;this.fps=profile.fps;this.storeCodec=profile.codec;
  this.storeProfileLabel=`${profile.width} × ${profile.height} · ${profile.fps}FPS 目标 · ${profile.codec.toUpperCase()}`;
 }

 @StorageProp('remoteInputWindowActive') @Watch('onWindowInputStateChanged') remoteInputWindowActive: boolean = false;
 @StorageProp('remoteSessionForeground') @Watch('onReconnectForegroundChanged') remoteSessionForeground: boolean = false;
 @StorageProp('diagnosticMode') diagnosticMode: string = '';
 @StorageProp('diagnosticTransport') diagnosticTransport: string = '';
 @StorageProp('diagnosticBitrateKbps') diagnosticBitrateKbps: number = 0;
 @StorageProp('diagnosticFPS') diagnosticFPS: number = 60;
 @StorageProp('diagnosticResolution') diagnosticResolution: number = -1;
 @StorageProp('diagnosticCursorLock') diagnosticCursorLock: boolean = true;
 @StorageProp('diagnosticSystemHover') diagnosticSystemHover: boolean = true;
 @StorageProp('diagnosticNoFallback') diagnosticNoFallback: boolean = false;
 @StorageProp('diagnosticRelativeCursor') @Watch('onRelativeCursorSettingChanged') diagnosticRelativeCursor: boolean = false;
 @State host: string = '';
 @State internetHost: string = '';
 @State networkMessage: string = '互联网连接尚未准备';
 @State networkAuthURL: string = '';
 @State pairingLoaded: boolean = false;
 @State networkReady: boolean = false;
 @State networkStarting: boolean = false;
 @State active: boolean = false;
 @State remoteMicEnabled: boolean = false;
 private microphoneConsentEpoch: number = 0;
 @State ready: boolean = false;
 @State fullScreen: boolean = false;
 @State menuVisible: boolean = false;
 @State streaming: boolean = false;
 @State mode: string = '';
 @State transport: number = 1;
 @State localRouteLabel: string = '正在检测 USB 与局域网…';
 @State waitingLocalStart: boolean = false;
 @State waitingRemoteStart: boolean = false;
 private remoteStartTimer: number = -1;
 private waitingRemoteIntent: PendingRemoteRouteIntent | null = null;
 private remoteWaitEpoch: number = 0;
 private availability: LocalAvailability | null = null;
 private availabilityTimer: number = -1;
 private localStartTimer: number = -1;
 private pendingMacStart: string = '';
 private activeMacStart: string = '';
 private localRequestGeneration: number = 0;
 private localHandoverCount: number = 0;
 private localHandoverReason: string = '';
 private localHandoverCapable: boolean = false;
 private localUSBRetryAfter: number = 0;
 private localHandoverDeadline: number = 0;
 private localHandoverNextAttempt: number = 0;
 private lastLocalStatus: string = '';
 @State resolution: number = 1;
 @State fps: number = 60;
 @State ctrlToCmd: boolean = true;
 @State message: string = '正在读取本机配对配置…';
 @State statistics: string = '';
 @State commandHeld: boolean = false;
 @State optionHeld: boolean = false;
 @State remoteText: string = '';
 @State showText: boolean = false;
 @State relativeCursorActive: boolean = false;
 @State virtualCursorX: number = 0;
 @State virtualCursorY: number = 0;
 @State virtualCursorOnPad: boolean = true;
 @State hostCursorVisible: boolean = false;
 @State homeWidth: number = 1000;
 @State showAdvanced: boolean = false;
 private rtcController: webview.WebviewController = new webview.WebviewController();
 private rtcBridge: RTCArkWebTransport = new RTCArkWebTransport(this.rtcController);
 private rtcSession: string = '';
 private rtcWebReady: boolean = false;
 private rtcEpoch: number = 0;
 private rtcBridgeDiagnostics: RTCBridgeDiagnostics = this.emptyRTCBridgeDiagnostics();
 private rtcLastSnapshotRequestAt: number = 0;
 private diagnosticStarted: boolean = false;
 private diagnosticProfile: DiagnosticProfile | null = null;
 private diagnosticProofProbeRequested: boolean = false;
 private activeSplitDiagnostic: string = '';
 private sessionGeneration: number = 0;
 private sessionTransport: number = 1;
 private sessionStartedAt: number = 0;
 private firstFrameReadyAt: number = 0;
 private lastRenderAt: number = 0;
 private lastRenderCount: number = 0;
 private lastVideoDatagrams: number = 0;
 private lastVideoCheckAt: number = 0;
 private videoStallEpochAt: number = 0;
 private videoStallBaselineDatagrams: number = 0;
 private fallbackSuspended: boolean = false;
 private fallbackAttempted: boolean = false;
 private fallbackReason: string = '';
 private fallbackTriggerFrames: number = 0;
 private fallbackFrameDelta: number = 0;
 private fallbackElapsedMs: number = 0;
 private fallbackUdpDatagramDelta: number = 0;
 private pairing: StorePairing | null = null;
 private controller: XComponentController = new XComponentController();
 private timer: number = -1;
 private networkTimer: number = -1;
 private internetReconnect: InternetReconnect | null = null;
 private internetRecovering: boolean = false;
 private reconnectResumeFullScreen: boolean = true;
 private networkPreparation: Promise<void> | null = null;
 private platformNetworkReady: boolean = false;
 private platformNetworkEpoch: number = 0;
 private platformNetworkSignature: string = '';
 private lastMacOnline: boolean = false;
 private wanRouteEvidence: DirectWANRoute = new DirectWANRoute();
 private autoDirectWAN: boolean = false;
 private dynamicWANRoute: DynamicWANRoute = new DynamicWANRoute();
 private networkObserver: connection.NetConnection | null = null;
 private presentationEpoch: number = 0;
 private windowError: string = '';
 private systemWindowMode: string = 'unknown';
 private freeWindowMode: boolean = false;
 private frameWidth: number = 1;
 private frameHeight: number = 1;
 private touchCount: number = 0;
 private mouseCount: number = 0;
 private keyCount: number = 0;
 private startX: number = 0;
 private startY: number = 0;
 private dragging: boolean = false;
 private touchScreenTimer: number = -1;
 private touchScreenEpoch: number = 0;
 private touchScreenState: string = '';
 @State touchScreenFeedback: string = '';
 @State touchScreenFeedbackX: number = 0;
 @State touchScreenFeedbackY: number = 0;
 private touchScreenId: number = -1;
 private touchScreenDeviceId: number = -1;
 private touchScreenStartX: number = 0;
 private touchScreenStartY: number = 0;
 private touchScreenLastX: number = 0;
 private touchScreenLastY: number = 0;
 private touchScreenTimestamp: number = 0;
 private touchScreenButtonHeld: boolean = false;
 private touchScreenScrollGestures: number = 0;
 private touchScreenLongPressDrags: number = 0;
 private touchScreenPendingSlopVp: number = 12;
 private touchScreenStartedAt: number = 0;
 private touchScreenGestureEvents: number = 0;
 private touchScreenSingleEvents: number = 0;
 private touchScreenDecisions: TouchScreenDecision[] = [];
 private twoFingers: boolean = false;
 private lastCenterX: number = 0;
 private lastCenterY: number = 0;
 private gestureKind: string = '';
 private firstCenterX: number = 0;
 private firstCenterY: number = 0;
 private firstDistance: number = 1;
 private lastDistance: number = 1;
 private axisCount: number = 0;
 private scrollCount: number = 0;
 private zoomCount: number = 0;
 private lastAxisX: number = 0;
 private lastAxisY: number = 0;
 private lastPinchScale: number = 0;
 private wheelRemainderX: number = 0;
 private wheelRemainderY: number = 0;
 private touchpadPanCount: number = 0;
 private touchpadPinchCount: number = 0;
 private lastTouchSource: number = 0;
 private lastTouchTool: number = 0;
 private inputTrace: InputTrace[] = [];
 private inputDevices: InputDeviceDiagnostic[] = [];
 private inputDeviceStatus: string = 'not_loaded';
 private inputDeviceFailures: number[] = [];
 private inputDeviceEpoch: number = 0;
 private inputDeviceWatchActive: boolean = false;
 private inputDeviceListener: (event: inputDevice.DeviceListener) => void = (event: inputDevice.DeviceListener) => {
  // Device IDs can be reused after reconnection. Invalidate before asynchronous discovery.
  this.inputDevices = this.inputDevices.filter((device: InputDeviceDiagnostic) => device.id !== event.deviceId);
  if (this.convertedTrackpadDeviceId === event.deviceId) { this.endGestures();this.twoFingers = false; }
  this.loadInputDevices();
 };
 private convertedTrackpadDeviceId: number = -1;
 private cancelledConvertedDeviceId: number = -1;
 private unconvertedTouchDeviceId: number = -1;
 private convertedTrackpadScrollActive: boolean = false;
 private convertedTrackpadLastX: number = 0;
 private convertedTrackpadLastY: number = 0;
 private convertedTrackpadScrollEvents: number = 0;
 private convertedTrackpadScrollGestures: number = 0;
 private clickTrace: ClickTrace[] = [];
 private axisInputActive: boolean = false;
 private mouseHeld: boolean[] = [false, false, false];
 private windowWarnings: string[] = [];
 private clickTimes: number[] = [0, 0, 0];
 private clickXs: number[] = [-100, -100, -100];
 private clickYs: number[] = [-100, -100, -100];
 private clickCounts: number[] = [0, 0, 0];
 private pointerX: number = 0;
 private pointerY: number = 0;
 private desktopTopologyValid: boolean = false;
 private desktopCapture: DesktopRect = { x: 0, y: 0, width: 1, height: 1 };
 private desktopDisplays: DesktopRect[] = [];
 private cursorChannelBound: boolean = false;
 private cursorChannelBindResult: number = -1;
 private cursorChannelEpoch: number = 0;
 private cursorChannelSessionEpoch: number = 0;
 private cursorLastSequence: number = 0;
 private cursorEdgeInputSequence: number = 0;
 private cursorSourceOwner: number = 0;
 private cursorPendingSample: NativeCursorSample | null = null;
 private cursorSyncApplied: number = 0;
 private cursorSyncStaleSession: number = 0;
 private cursorSyncStaleSequence: number = 0;
 private cursorSyncStaleInput: number = 0;
 private cursorSyncInvalid: number = 0;
 private hostCursorOwner: boolean = false;
 private hostCursorOnCapture: boolean = false;
 private systemCursorHidden: boolean = false;
 private relativeAnchorReady: boolean = false;
 private relativeAnchorEpoch: number = 0;
 private relativeCursorBlocked: boolean = false;
 private relativeCursorStatus: string = 'disabled';
 private relativeWindowId: number = -1;
 // API 26 raw deltas are hardware movement units, not screen pixels or vp.
 // This candidate gain is explicit and can be tuned after device measurements.
 private relativeGainVp: number = 0.5;
 private relativeRawEvents: number = 0;
 private relativeMissingRawEvents: number = 0;
 private relativeMissingRawRun: number = 0;
 private relativeRawSamples: RelativeMouseSample[] = [];
 private relativeDragTrace: RelativeDragSample[] = [];
 private relativeDragTouchMoves: number = 0;
 private relativeDragMouseMoves: number = 0;
 private mouseRouteEvents: number[] = [0, 0, 0, 0];
 private mouseDuplicateEvents: number = 0;
 private recentMouseDispatchKeys: string[] = [];
 private nativeMouseRouteBound: boolean = false;
 private nativeMouseRouteBindResult: number = -1;
 private nativeMouseRouteEpoch: number = 0;
 private nativeMouseRouteGeneration: number = -1;
 private nativeMouseRouteAttempts: number = 0;
 // Process-page lifetime diagnostics, intentionally not reset by begin().
 private nativeMouseCallbackCounts: NativeMouseGateCounts = { callbacks: 0, forwarded: 0, unbound: 0, staleEpoch: 0, staleGeneration: 0,
  disabled: 0, notFullscreen: 0, sessionInactive: 0, windowInactive: 0, menu: 0, textEditor: 0, action: 0 };
 private nativeMouseCallbackSamples: NativeMouseCallbackSample[] = [];
 private relativeLastRawTimestamp: number = -1;
 private lastAbsoluteMouseX: number = -1;
 private lastAbsoluteMouseY: number = -1;
 private trace(kind: string, action: number, source: number, tool: number, fingers: number = 0, deviceId: number = -1): void {
  const last = this.inputTrace[this.inputTrace.length - 1];
  if (last && last.kind === kind && last.action === action && last.source === source && last.tool === tool && last.fingers === fingers && last.deviceId === deviceId) { return; }
  this.inputTrace.push({ kind: kind, action: action, source: source, tool: tool, fingers: fingers, deviceId: deviceId });
  if (this.inputTrace.length > 32) { this.inputTrace.shift(); }
 }
 private async loadInputDevices(): Promise<void> {
  const epoch = ++this.inputDeviceEpoch;
  this.inputDeviceStatus = 'loading';
  const devices: InputDeviceDiagnostic[] = [], failures: number[] = [];
  try {
   const ids = await inputDevice.getDeviceList();
   for (const id of ids.slice(0, 32)) {
    if (epoch !== this.inputDeviceEpoch) { return; }
    try {
     const info = await inputDevice.getDeviceInfo(id);
     // Keep only local input capabilities; never serialize physical addresses or unique identifiers.
     devices.push({ id: info.id, name: info.name.slice(0, 96), sources: info.sources.slice(0, 8), isVirtual: info.isVirtual, isLocal: info.isLocal });
    } catch (e) { failures.push(id); }
   }
   if (epoch !== this.inputDeviceEpoch) { return; }
   this.inputDevices = devices;this.inputDeviceFailures = failures;
   this.inputDeviceStatus = failures.length > 0 ? 'partial' : 'ready';
  } catch (e) {
   if (epoch !== this.inputDeviceEpoch) { return; }
   this.inputDevices = [];this.inputDeviceFailures = [];this.inputDeviceStatus = 'list_failed';
  }
  this.saveStatus();
 }
 private watchInputDevices(): void {
  if (this.inputDeviceWatchActive) { return; }
  try { inputDevice.on('change', this.inputDeviceListener);this.inputDeviceWatchActive = true; } catch (e) { /* Discovery still runs at session start. */ }
 }
 private storeInputTimestamp(): number {
  // Public synchronous monotonic time in nanoseconds; do not depend on
  // SDK-restricted JS event timestamp fields in the store variant.
  try { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, true); }
  catch (e) { return 0; }
 }
 private button(button: number, down: boolean, timestamp: number = 0, tolerance: number = 5): void {
  if (this.mouseHeld[button] === down) { return; }this.mouseHeld[button] = down;
  const now = Number.isFinite(timestamp) && timestamp > 0 ? timestamp / 1000000 : Date.now();
  const interval = now - this.clickTimes[button];
  const distance = Math.hypot(this.pointerX - this.clickXs[button], this.pointerY - this.clickYs[button]);
  if (down) {
   this.clickCounts[button] = interval >= 0 && interval <= 500 && distance <= tolerance ? Math.min(3, this.clickCounts[button] + 1) : 1;
   this.clickTimes[button] = now;this.clickXs[button] = this.pointerX;this.clickYs[button] = this.pointerY;
  }
  this.clickTrace.push({ button: button, down: down, count: Math.max(1, this.clickCounts[button]), intervalMs: Math.round(interval), distanceVp: Math.round(distance) });
  if (this.clickTrace.length > 20) { this.clickTrace.shift(); }
  native.input(`BUTTON ${button} ${down ? 1 : 0} ${Math.max(1, this.clickCounts[button])}`);
 }
 private emptyRTCBridgeDiagnostics(): RTCBridgeDiagnostics {
  return { recordBudgetMs: 0, records: 0, expired: 0, rejected: 0, queueDrops: 0, videoRecords: 0, keyframeRecords: 0, deltaRecords: 0,
   lastVideoBytes: 0, largestVideoBytes: 0, lastKeyframeBytes: 0, largestKeyframeBytes: 0,
   iceErrors: 0, lastIceErrorCode: 0, assemblyExpiryEvents: 0, assemblyCapEvents: 0, sendBudgetEvents: 0,
   failures: 0, channelErrors: 0, stage: '', iceState: '', connectionState: '', updatedAt: 0 };
 }
 private rtcDiagnosticScalar(value: number | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
 }
 private acceptRTCBridgeDiagnostic(kind: string, json: string): void {
  if (!this.active || !this.rtcSession || json.length > 65536) return;
  try {
   const event = JSON.parse(json) as RTCBridgeSafeEvent;
   if (event.event !== kind) return;
   const d = this.rtcBridgeDiagnostics;
   if (kind === 'safe-snapshot') {
    d.records=this.rtcDiagnosticScalar(event.received,d.records);d.expired=this.rtcDiagnosticScalar(event.expired,d.expired);
    d.rejected=this.rtcDiagnosticScalar(event.rejected,d.rejected);d.queueDrops=this.rtcDiagnosticScalar(event.queueDrops,d.queueDrops);
    d.videoRecords=this.rtcDiagnosticScalar(event.videoRecords,d.videoRecords);d.keyframeRecords=this.rtcDiagnosticScalar(event.keyframeRecords,d.keyframeRecords);d.deltaRecords=this.rtcDiagnosticScalar(event.deltaRecords,d.deltaRecords);
    d.lastVideoBytes=this.rtcDiagnosticScalar(event.lastVideoBytes,d.lastVideoBytes);d.largestVideoBytes=this.rtcDiagnosticScalar(event.largestVideoBytes,d.largestVideoBytes);
    d.lastKeyframeBytes=this.rtcDiagnosticScalar(event.lastKeyframeBytes,d.lastKeyframeBytes);d.largestKeyframeBytes=this.rtcDiagnosticScalar(event.largestKeyframeBytes,d.largestKeyframeBytes);
    if (event.recordBudgetMs && [100,300,500].includes(event.recordBudgetMs)) d.recordBudgetMs=event.recordBudgetMs;
   } else if (kind === 'ice-error') { d.iceErrors++;d.lastIceErrorCode=this.rtcDiagnosticScalar(event.code,0); }
   else if (kind === 'idr-needed') {
    if (event.reason === 'assembly-expired') d.assemblyExpiryEvents++;
    else if (event.reason === 'assembly-cap') d.assemblyCapEvents++;
    else if (event.reason === 'send-budget') d.sendBudgetEvents++;
   } else if (kind === 'failure') d.failures++;
   else if (kind === 'channel-error') d.channelErrors++;
   else if (kind === 'bridge-stage' && event.stage && ['page-loaded','native-port-bound','peer-config-sent'].includes(event.stage)) d.stage=event.stage;
   else if (kind === 'channel-open') d.stage='channel-open';
   else if (kind === 'ice-state' && event.state && ['new','checking','connected','completed','disconnected','failed','closed'].includes(event.state)) d.iceState=event.state;
   else if (kind === 'connection-state' && event.state && ['new','connecting','connected','disconnected','failed','closed'].includes(event.state)) d.connectionState=event.state;
   else return;
   d.updatedAt=Date.now();
  } catch (_) {}
 }
 private prepareRTCListener(): void {
  native.bindRtcEvents((event: RTCNativeEvent) => {
   if (!this.active || this.remoteSessionForeground !== true || event.epoch < this.rtcEpoch) return;
   if (event.kind === 'config') {
    try {
     const config=JSON.parse(event.body) as RTCMediaConfig;
     if (config.session!==event.session || !/^[a-f0-9]{64}$/.test(event.session) || ![100,300,500].includes(config.budgetMs) || config.iceServers.length>8) throw Error('rtc config');
     this.rtcBridge.stop();this.rtcEpoch=event.epoch;this.rtcSession=event.session;
     this.rtcBridgeDiagnostics=this.emptyRTCBridgeDiagnostics();this.rtcBridgeDiagnostics.recordBudgetMs=config.budgetMs;this.rtcLastSnapshotRequestAt=0;
     this.rtcBridge.onDiagnostic=(kind:string,json:string) => { if(event.session===this.rtcSession && event.epoch===this.rtcEpoch)this.acceptRTCBridgeDiagnostic(kind,json); };
     this.rtcBridge.authenticatedOwnerStillCurrent=() => this.active && this.remoteSessionForeground && this.rtcSession===event.session;
     this.rtcBridge.onSignal=(json:string) => { if(!native.rtcSignal(event.session,json)){this.rtcBridge.stop();this.message='实时视频信令已停止';} };
     this.rtcBridge.onEncryptedRecord=(record:ArrayBuffer) => { native.rtcPush(event.session,record); };
     this.rtcBridge.onIDRRequired=() => { native.input('IDR'); };
     this.rtcBridge.onStatus=(status:string) => { if(status!=='channel-open'){this.rtcBridge.stop();this.message='实时视频连接已停止';native.disconnect('rtc_bridge_failed');} };
     if(!this.rtcBridge.start(event.session,config.iceServers,config.relayOnly,config.budgetMs))throw Error('rtc bridge owner');
     if(this.rtcWebReady)this.rtcBridge.onPageLoaded();
    } catch (_){this.rtcBridge.stop();native.disconnect('rtc_config_rejected');}
   } else if(event.session===this.rtcSession && event.epoch===this.rtcEpoch){
    if(event.kind==='signal'){if(!this.rtcBridge.acceptAuthenticatedSignal(event.body)){this.rtcBridge.stop();native.disconnect('rtc_signal_rejected');}}
    else if(event.kind==='ack'){const fields=event.body.split(' ');if(fields.length===2)this.rtcBridge.sendRenderAck(fields[0],fields[1]);}
   }
  });
 }
 private stopRTC(): void { this.rtcBridge.stop();this.rtcSession='';native.bindRtcEvents(); }
 aboutToAppear(): void { this.watchInputDevices();this.storeFirstRun();this.loadInputDevices(); }

 aboutToDisappear(): void {
  this.stop('view_disappeared');this.inputDeviceEpoch++;
  this.localRequestGeneration++;this.pendingMacStart = '';
  this.availability?.stop();this.availability = null;
  if (this.availabilityTimer >= 0) { clearInterval(this.availabilityTimer);this.availabilityTimer = -1; }
  if (this.inputDeviceWatchActive) { try { inputDevice.off('change', this.inputDeviceListener); } catch (e) {}this.inputDeviceWatchActive = false; }
  if (this.networkTimer >= 0) { clearInterval(this.networkTimer);this.networkTimer = -1; }
  if (this.networkObserver) { this.networkObserver.unregister(() => {});this.networkObserver = null; }
 }
 onBackPress(): boolean {
  if (!this.active) { return false; }
  this.openSessionMenu();return true;
 }
 private openSessionMenu(): void {
  if (this.menuVisible) { return; }
  const generation = this.sessionGeneration;
  this.endGestures();
  this.menuVisible = true;this.showText = false;this.internetReconnect?.gatesChanged();
  this.syncCursorLock();
  native.input('LOCALUI 1');this.mouseHeld = [false, false, false];this.commandHeld = false;this.optionHeld = false;
  this.dragging = false;this.twoFingers = false;this.saveStatus();
  this.getUIContext().getPromptAction().showActionMenu({
   title: this.mode === 'extend' ? '扩展屏' : '远控 Mac',
   showInSubWindow: false,
   buttons: [
    { text: this.fullScreen ? '退出全屏' : '进入全屏', color: '#307E70' },
    { text: '结束会话', color: '#963F4A' },
    { text: '桌面总览', color: '#2F628E' },
    { text: this.mode === 'remote' ? (this.remoteMicEnabled ? '关闭平板麦克风' : '启用平板麦克风') : '麦克风仅用于远控', color: '#307E70' },
    { text: '继续', color: '#2F628E' }
   ]
  }).then((result) => {
   // A closed session's dialog must never dispatch a shortcut into its successor
   // or clear that successor's current menu/focus boundary.
   if (generation !== this.sessionGeneration || !this.active) { return; }
   // Keep the native local-UI gate closed until the whole shortcut is accepted.
   // This bypasses Pad Ctrl-to-Command without exposing partial key transitions.
   const overviewAccepted: boolean = result.index === 2 ? native.input('DESKTOP overview') : true;
   this.menuVisible = false;if (result.index !== 1) { this.internetReconnect?.gatesChanged(); }
   if (result.index === 0) { this.setFullScreen(!this.fullScreen); }
   else if (result.index === 1) { this.stop('user_end'); }
   else if (result.index === 3 && this.mode === 'remote') { this.focusRemote();this.toggleRemoteMicrophone(); }
   else {
    this.focusRemote();this.saveStatus();
    if (!overviewAccepted) { this.getUIContext().getPromptAction().showToast({ message: '桌面总览操作未发送，请稍后重试。' }); }
   }
  }).catch(() => {
   if (generation !== this.sessionGeneration || !this.active) { return; }
   this.menuVisible = false;this.internetReconnect?.gatesChanged();this.focusRemote();this.saveStatus();
  });
 }
 private async toggleRemoteMicrophone(): Promise<void> {
  if (!this.active || this.mode !== 'remote') { return; }
  const generation = this.sessionGeneration, consent = ++this.microphoneConsentEpoch;
  if (this.remoteMicEnabled) { native.setMicrophoneAllowed(false);this.remoteMicEnabled = false;this.saveStatus();return; }
  try {
   const answer = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context(), ['ohos.permission.MICROPHONE']);
   if (generation !== this.sessionGeneration || consent !== this.microphoneConsentEpoch || !this.active || this.mode !== 'remote' || AppStorage.get<boolean>('remoteSessionForeground') !== true) { return; }
   if (answer.authResults.length !== 1 || answer.authResults[0] !== 0) { this.getUIContext().getPromptAction().showToast({ message: '麦克风未授权，远控画面仍可使用。' });return; }
   this.remoteMicEnabled = native.setMicrophoneAllowed(true);
   if (!this.remoteMicEnabled) { this.getUIContext().getPromptAction().showToast({ message: '声音连接尚未就绪。请稍候重试；若仍失败，请结束会话后重新连接。' }); }
   this.saveStatus();
  } catch (e) { this.remoteMicEnabled = false; }
 }
 private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
 private prepareLocalAvailability(): void { this.localRouteLabel='局域网直连'; }
 private updateAvailabilityState(): void { this.availability?.state(this.active || this.waitingRemoteStart, this.remoteInputWindowActive, this.ready); }
 private localRoute(): string { return this.pairingLoaded ? 'lan':''; }
 private refreshLocalAvailability(): void {
  this.availability?.refreshDiscovery();
  const status = this.availability?.status();if (!status) { return; }
  const usb = status.paths.some((p: LocalPath) => p.route === 'usb' && p.ready), lan = status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready);
  this.localRouteLabel = usb && lan ? (this.active && this.mode === 'extend'
   ? (this.sessionTransport === 0 ? 'USB 单路传屏 · 局域网备用' : '局域网单路传屏 · USB 备用')
   : (status.preferredRoute === 'usb' ? '优先 USB · 局域网备用' : '优先局域网 · USB 备用'))
   : (usb ? 'USB 已就绪' : (lan ? '局域网已就绪' : '未发现本地连接'));
  if (lan && this.availability && this.host !== this.availability.host) { this.host = this.availability.host;this.saveSettings(); }
  const value = JSON.stringify(status);
  if (value !== this.lastLocalStatus) { this.lastLocalStatus = value;this.writeFile('local-connection-status.json', value); }
  this.updateAvailabilityState();
  if (this.waitingLocalStart && !this.active && this.localRoute()) { this.begin('extend'); }
  this.autoDiagnostic();
 }
 private cancelRemoteStart(): void {
  this.remoteWaitEpoch++;this.waitingRemoteIntent = null;this.waitingRemoteStart = false;this.updateAvailabilityState();if (this.remoteStartTimer >= 0) { clearTimeout(this.remoteStartTimer);this.remoteStartTimer = -1; }
 }
 private cancelLocalStart(): void {
  this.waitingLocalStart = false;
  if (this.localStartTimer >= 0) { clearTimeout(this.localStartTimer);this.localStartTimer = -1; }
 }
 private waitForLocalStart(): void {
  if (this.waitingLocalStart) { this.cancelLocalStart();this.message = '已取消连接，Mac 保持待命。';return; }
  this.availability?.refresh();this.waitingLocalStart = true;this.message = '正在寻找 USB 或同一局域网的 Mac…';
  this.localStartTimer = setTimeout(() => { this.localStartTimer = -1;this.waitingLocalStart = false;this.message = '未发现本地连接。扩展屏需要 USB 数据线或同一局域网。'; }, 10000);
 }
 private onAvailabilityEvent(event: AvailabilityEvent): void {
  if (event.type === 'end' && event.requestId && this.active && this.mode === 'extend') {
   const current = JSON.parse(native.stats()) as Statistics;
   if (`${current.sessionID}` === event.requestId) { this.stop('mac_end'); }
   return;
  }
  this.refreshLocalAvailability();
  if (event.type === 'cancel' && event.requestId) {
   if (this.pendingMacStart === event.requestId) { this.pendingMacStart = '';this.localRequestGeneration++; }
   if (this.activeMacStart === event.requestId && this.active) { this.stop('mac_cancelled_request'); }
   return;
  }
  if (event.type !== 'start' || !event.requestId || !/^[0-9a-fA-F]{32}$/.test(event.requestId)) { return; }
  const id: string = event.requestId;
  if (this.active || !this.ready || !this.pairing || this.pendingMacStart || !this.localRoute()) { native.availabilityReply(id, false);return; }
  this.pendingMacStart = id;const generation = ++this.localRequestGeneration;
  const start = (): void => {
   if (generation !== this.localRequestGeneration || this.pendingMacStart !== id) { return; }
   if (this.active || !this.ready || !this.remoteInputWindowActive || !this.localRoute()) { native.availabilityReply(id, false);this.pendingMacStart = '';return; }
   if (!native.availabilityReply(id, true)) { this.pendingMacStart = '';return; }
   this.pendingMacStart = '';this.begin('extend', false, id);
  };
  if (this.remoteInputWindowActive) { start(); }
  else if (this.availability?.selfShowSupported) {
   this.context().showAbility().then(() => { this.getUIContext().postFrameCallback(new AfterLayout(start)); })
    .catch(() => { if (generation === this.localRequestGeneration && this.pendingMacStart === id) { native.availabilityReply(id, false);this.pendingMacStart = ''; } });
  } else { native.availabilityReply(id, false);this.pendingMacStart = ''; }
 }
 private saveSettings(): void {
  // A diagnostic launch must never persist its test FPS/transport as a user preference.
  if (this.diagnosticProfile) { return; }
  const value: Settings = { host: this.host, transport: this.transport, resolution: this.resolution, fps: this.fps, ctrlToCmd: this.ctrlToCmd, internetHost: this.internetHost };
  this.writeFile('settings.json', JSON.stringify(value));
 }
 private isInternetTransport(value: number = this.transport): boolean { return value === 3 || value === 4; }
 private writeFile(name: string, value: string): void {
  try {
   const f = fileIo.openSync(`${this.context().filesDir}/${name}`, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
   try { fileIo.writeSync(f.fd, value); } finally { fileIo.closeSync(f); }
  } catch (e) { /* Diagnostics must not interrupt streaming. */ }
 }
 private ensureInternetReconnect(): InternetReconnect {
  if (this.internetReconnect) { return this.internetReconnect; }
  const controller = new InternetReconnect({
   guard: () => ({ generation: this.sessionGeneration, localGeneration: this.localRequestGeneration,
    foreground: AppStorage.get<boolean>('remoteSessionForeground') === true, menu: this.menuVisible,
    localPending: this.waitingLocalStart || this.pendingMacStart.length > 0, surfaceReady: this.ready }),
   later: (delayMs: number, action: () => void): number => setTimeout(action, delayMs),
   clear: (timer: number): void => clearTimeout(timer),
   prepare: async (): Promise<boolean> => { await this.startNetwork(true);return this.platformNetworkReady && this.networkReady && this.internetHost.length > 0; },
   release: (reason: string): void => this.releaseInternetForRetry(reason),
   start: (intent: InternetIntent): boolean => {
    if (!this.pairing || !this.ready || AppStorage.get<boolean>('remoteSessionForeground') !== true || this.menuVisible || this.waitingLocalStart || this.pendingMacStart) { return false; }
    this.reconnectResumeFullScreen = intent.fullScreen;
    const before = this.sessionGeneration;
    this.begin(intent.mode, true, '', '', false, true, intent.transport);return this.sessionGeneration !== before && this.active && this.isInternetTransport(this.sessionTransport);
   },
   status: (message: string): void => { this.message = message;this.saveStatus(); }
  });
  this.internetReconnect = controller;return controller;
 }
 private releaseInternetForRetry(reason: string): void {
  if (this.sessionTransport === 4) { this.dynamicWANRoute.failed(Date.now(), 'udp_connection_lost'); }
  // Keep the logical session and current modal generation so End remains
  // clickable during an outage. Native binding epochs are still invalidated.
  this.internetRecovering = true;
  this.unbindCursorChannel();this.unbindNativeMouseRoute();this.restoreSystemCursor();this.clearDesktopTopology();
  native.input('LOCALUI 1');native.input('CURSORLOCK -1 0');this.endGestures();native.input('OBSERVE -1');
  if (this.timer >= 0) { clearInterval(this.timer);this.timer = -1; }
  native.disconnect(reason);this.streaming = false;this.axisInputActive = false;
  this.mouseHeld = [false, false, false];this.commandHeld = false;this.optionHeld = false;this.dragging = false;this.twoFingers = false;this.showText = false;
  this.updateAvailabilityState();
 }
 private onReconnectForegroundChanged(): void {
  if (AppStorage.get<boolean>('remoteSessionForeground') !== true) { this.stop('ability_background'); }
  else { this.internetReconnect?.gatesChanged(); }
 }
 private chooseTransport(value: number): void {
  if (value === this.transport) { return; }
  this.cancelRemoteStart();this.dynamicWANRoute.cancel('transport_changed');
  this.internetReconnect?.cancel('transport_changed');if (this.internetRecovering) { this.stop('transport_changed'); }
  this.transport = value;
 }
 private startNetwork(preserveProfile: boolean = false): Promise<void> {
  if (this.networkPreparation) { return this.networkPreparation; }
  const preparation = this.preparePlatformNetwork(preserveProfile);this.networkPreparation = preparation;
  const clear = (): void => { if (this.networkPreparation === preparation) { this.networkPreparation = null; } };
  preparation.then(clear, clear);return preparation;
 }
 private async preparePlatformNetwork(preserveProfile: boolean = false): Promise<void> {
  if (!preserveProfile && !this.isInternetTransport()) { this.transport = 3; }this.saveSettings();
  if (this.networkStarting) { return; }const wasPlatformReady = this.platformNetworkReady;this.networkStarting = true;this.platformNetworkReady = false;const epoch = this.platformNetworkEpoch;
  try {
   if (!this.networkObserver) {
    const observer = connection.createNetConnection();this.networkObserver = observer;
    observer.on('netAvailable', () => { if (this.isInternetTransport() || (this.active && this.isInternetTransport(this.sessionTransport))) { this.startNetwork(true); } });
    observer.on('netConnectionPropertiesChange', () => { if (this.isInternetTransport() || (this.active && this.isInternetTransport(this.sessionTransport))) { this.startNetwork(true); } });
    observer.on('netLost', () => { this.platformNetworkEpoch++;this.platformNetworkReady = false;this.wanRouteEvidence.networkChanged(this.platformNetworkEpoch, Date.now());this.networkMessage = '网络切换中，正在等待连接恢复…';if (this.isInternetTransport(this.sessionTransport)) { this.internetReconnect?.lost(this.sessionGeneration, 'network_lost'); } });
    observer.register(() => {});
   }
   const net = await connection.getDefaultNet();const props = await connection.getConnectionProperties(net);
   const config: PlatformNetwork = { name: props.interfaceName, prefixes: props.linkAddresses.map((link: connection.LinkAddress) => `${link.address.address}/${link.prefixLength}`), mtu: props.mtu, routeEpoch: epoch, netId: net.netId };
   if (epoch !== this.platformNetworkEpoch) { return; }
   const signature = JSON.stringify(config), changed = this.platformNetworkSignature.length > 0 && signature !== this.platformNetworkSignature;
   if (changed) { this.wanRouteEvidence.networkChanged(epoch, Date.now()); }
   native.network(`${this.context().filesDir}/tailnet`, signature);this.platformNetworkSignature = signature;this.platformNetworkReady = true;this.refreshNetwork();
   if (changed && this.isInternetTransport(this.sessionTransport)) { this.internetReconnect?.lost(this.sessionGeneration, 'default_network_changed'); }
   if (changed || !wasPlatformReady) { this.internetReconnect?.networkAvailable(); }
   if (this.networkTimer < 0) { this.networkTimer = setInterval(() => this.refreshNetwork(), 5000); }
  } catch (e) { this.wanRouteEvidence.clear('network_unavailable');this.networkMessage = '无法读取当前网络，请确认设备已联网';this.writeFile('network-error.json', JSON.stringify({ error: `${e}` })); }
  finally { this.networkStarting = false; }
 }
 private refreshNetwork(): void {
  try {
   const s = JSON.parse(native.network()) as NetworkState;
   this.networkReady = s.state === 'Running';
   this.networkAuthURL = s.authURL || '';
   this.networkMessage = s.state === 'Running' ? '互联网连接已就绪' : (s.error || (this.networkAuthURL ? '请登录连接服务，为这台 Edge 配对' : '正在准备互联网连接…'));
   const mac = s.peers?.find((peer: NetworkPeer) => peer.online && peer.name === 'edgelink-mac');
   const macOnline = mac !== undefined;if (macOnline && !this.lastMacOnline) { this.internetReconnect?.networkAvailable(); }this.lastMacOnline = macOnline;
   if (mac && mac.ips.length > 0) { if (this.internetHost !== mac.ips[0]) { this.internetHost = mac.ips[0];this.saveSettings(); }this.networkMessage += ` · Mac ${mac.connection === 'direct' ? '直连' : (mac.connection === 'relay' ? `中转 ${mac.relayRegion}` : '待连接')}`; }
   this.wanRouteEvidence.observe(s, this.internetHost, this.platformNetworkEpoch, this.platformNetworkReady, Date.now());
   this.dynamicWANRoute.observeDirect(this.wanRouteEvidence.state(this.internetHost, this.platformNetworkEpoch, this.platformNetworkReady, Date.now()), this.platformNetworkEpoch, this.internetHost, Date.now());
   this.writeFile('network-status.json', JSON.stringify(s));
   this.autoDiagnostic();if (this.waitingRemoteStart && this.waitingRemoteIntent && this.networkReady && this.internetHost && !this.active) {
    const intent = this.waitingRemoteIntent;this.cancelRemoteStart();this.begin(intent.mode, intent.preserveFallback, '', '', intent.fromDiagnostic, false, intent.transport, intent.routeIntent, intent.preservePresentation);
   }
  } catch (e) { this.wanRouteEvidence.clear('snapshot_unavailable');this.networkMessage = '互联网连接状态暂不可用'; }
 }
 private openNetworkLogin(): void {
  if (!this.networkAuthURL.startsWith('https://login.tailscale.com/')) { this.networkMessage = '登录入口尚未就绪';return; }
  this.context().openLink(this.networkAuthURL).catch(() => { this.networkMessage = '请在浏览器打开连接服务登录入口'; });
 }
 private autoDiagnostic(): void {
  if (!this.diagnosticStarted && !this.active && this.remoteInputWindowActive && ['bench', 'remote', 'extend'].includes(this.diagnosticMode) && this.ready && this.pairing) {
   const split = this.diagnosticTransport === 'split-usb-control' || this.diagnosticTransport === 'split-lan-control';
   if (split && !['bench', 'extend'].includes(this.diagnosticMode)) { this.message = '分流诊断仅用于扩展屏或测试画面，普通远控可照常使用。';return; }
   if (!this.diagnosticProfile) { this.diagnosticProfile = { transport: this.transport, resolution: this.resolution, fps: this.fps }; }
   const transport = split ? (this.diagnosticTransport === 'split-usb-control' ? 0 : 1) : (this.diagnosticTransport === 'internet-udp' ? 4 : (['internet','internet-rtc'].includes(this.diagnosticTransport) ? 3 : (['tcp','rtc'].includes(this.diagnosticTransport) ? 0 : (this.diagnosticTransport === 'udp' ? 2 : 1))));
   const localReady = split ? this.splitDiagnosticPathsReady() : (this.isInternetTransport(transport) || this.diagnosticLocalPathReady(transport === 0 ? 'usb' : 'lan'));
   if (!localReady) {
    if (!this.diagnosticProofProbeRequested) { this.diagnosticProofProbeRequested = true;this.availability?.refresh(); }
    this.message = split ? '分流诊断等待 USB 与真实局域网均通过配对认证…' : '单路诊断等待本地连接通过配对认证…';return;
   }
   if (this.isInternetTransport(transport) && (!this.internetHost || !this.networkReady)) { if (this.networkTimer < 0) { this.startNetwork(); }return; }
   if ([0, 1, 2].includes(this.diagnosticResolution)) { this.resolution = this.diagnosticResolution; }
   this.diagnosticStarted = true;this.transport = transport;if(['rtc','internet-rtc'].includes(this.diagnosticTransport))this.resolution=0;
   this.fps = [60, 90, 120].includes(this.diagnosticFPS) ? this.diagnosticFPS : 60;
   this.begin(this.diagnosticMode, false, '', split ? this.diagnosticTransport : '', true);
  }
 }
 private diagnosticLocalPathReady(route: string): boolean {
  const status = this.availability?.status();if (!status || !this.availability) { return false; }
  if (route === 'lan') { this.host = this.availability.host; }
  return status.paths.some((p: LocalPath) => p.route === route && p.ready);
 }
 private splitDiagnosticPathsReady(): boolean {
  const status = this.availability?.status();if (!status || !this.availability) { return false; }
  const usb = status.paths.some((p: LocalPath) => p.route === 'usb' && p.ready);
  const lan = status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready);
  if (lan) { this.host = this.availability.host; }
  return usb && lan;
 }
 private restoreDiagnosticProfile(): void {
  const profile = this.diagnosticProfile;
  this.diagnosticProfile = null;this.activeSplitDiagnostic = '';this.diagnosticProofProbeRequested = false;
  if (!profile) { return; }
  this.diagnosticStarted = true;this.transport = profile.transport;this.resolution = profile.resolution;this.fps = profile.fps;this.saveSettings();
 }
 private storeAllowsMode(mode: string): boolean { return mode === 'extend'; }
 private begin(mode: string, preserveFallback: boolean = false, macRequestId: string = '', splitDiagnostic: string = '', fromDiagnostic: boolean = false, reconnectAttempt: boolean = false, retryTransport: number = -1, routeIntent: number = -1, preservePresentation: boolean = false, localHandoverRoute: string = ''): void {
  if (!this.storeAllowsMode(mode) || this.storeStage !== 3) { this.message='上架版只提供本人配对的局域网扩展屏';return; }
  try { this.storeSelectProfile(); } catch(e) { this.message='当前设备的硬件解码能力不足，请查看兼容说明。';return; }
  const previousFullScreen = this.fullScreen;
  if (!reconnectAttempt) { this.internetReconnect?.cancel('new_user_start');if (this.internetRecovering) { this.stop('reconnect_superseded', false); } }
  if (!fromDiagnostic && !preserveFallback && !localHandoverRoute) { this.restoreDiagnosticProfile(); }
  if (!this.pairing || !this.ready) { this.message = '配对或显示尚未就绪'; return; }
  const rtc=fromDiagnostic && ['rtc','internet-rtc'].includes(this.diagnosticTransport);
  const split = fromDiagnostic && ['split-usb-control', 'split-lan-control'].includes(splitDiagnostic);
  if (split && (!['bench', 'extend'].includes(mode) || !this.splitDiagnosticPathsReady())) { this.restoreDiagnosticProfile();this.message = '分流诊断需要同时就绪的 USB 与真实局域网连接。';return; }
  if (mode === 'extend') { this.cancelRemoteStart(); }
  else { this.cancelLocalStart(); }
  const explicitDiagnosticRoute = fromDiagnostic && !split ? (['tcp','rtc'].includes(this.diagnosticTransport) ? 'usb' : (['lan', 'udp', 'handover-lan'].includes(this.diagnosticTransport) ? 'lan' : '')) : '';
  const route = mode === 'extend' ? (split ? (splitDiagnostic === 'split-usb-control' ? 'usb' : 'lan') : (localHandoverRoute || explicitDiagnosticRoute || this.localRoute())) : '';
  if (mode === 'extend' && !route) { this.waitForLocalStart();return; }
  let selectedTransport = split ? (splitDiagnostic === 'split-usb-control' ? 0 : 1) : (mode === 'extend' ? (route === 'usb' ? 0 : 1) : ([3, 4].includes(retryTransport) ? retryTransport : this.transport));
  if (mode === 'remote' && !this.isInternetTransport(selectedTransport) && !this.localRoute()) { selectedTransport = 3; }
  const intendedTransport = [3, 4].includes(routeIntent) ? routeIntent : selectedTransport;
  const selectedDirect = this.wanRouteEvidence.choose(mode, selectedTransport, this.internetHost, this.platformNetworkEpoch, this.platformNetworkReady && this.networkReady, Date.now(), fromDiagnostic || this.diagnosticProfile !== null, this.diagnosticNoFallback, (preserveFallback && this.fallbackAttempted) || this.dynamicWANRoute.suppressDirect(this.platformNetworkEpoch, this.internetHost, Date.now()));
  selectedTransport = selectedDirect;
  this.cancelLocalStart();
  if (this.pendingMacStart) { native.availabilityReply(this.pendingMacStart, false);this.pendingMacStart = '';this.localRequestGeneration++; }
  this.activeMacStart = mode === 'extend' ? macRequestId : '';
  if (this.isInternetTransport(selectedTransport) && (!this.internetHost || !this.networkReady)) {
   // The reconnect controller owns its own backoff; do not create a second
   // home-page waiting flow or mistake the retained logical session for a start.
   if (reconnectAttempt) { return; }
   if (this.waitingRemoteStart) { this.cancelRemoteStart();this.message = '已取消远控连接，Mac 保持待命。';return; }
   const waitEpoch = ++this.remoteWaitEpoch;this.waitingRemoteIntent = { mode: mode, transport: selectedTransport, routeIntent: intendedTransport, preserveFallback: preserveFallback, fromDiagnostic: fromDiagnostic, preservePresentation: preservePresentation };
   this.waitingRemoteStart = true;this.updateAvailabilityState();this.startNetwork(true);this.message = '正在准备互联网远控…';
   this.remoteStartTimer = setTimeout(() => { if (waitEpoch !== this.remoteWaitEpoch) { return; }this.remoteStartTimer = -1;this.waitingRemoteIntent = null;this.waitingRemoteStart = false;this.updateAvailabilityState();this.message = this.networkAuthURL ? '请先登录连接服务，再开始远控。' : '互联网连接尚未就绪，请检查两台设备是否联网。'; }, 20000);return;
  }
  this.cancelRemoteStart();
  // stop() invalidates and unregisters the old callback before any session reset.
  this.stop(localHandoverRoute ? 'local_handover' : 'restart', false);this.saveSettings();this.mode = mode;
  this.clearDesktopTopology();
  this.relativeCursorBlocked = false;this.relativeAnchorReady = false;this.relativeRawEvents = 0;this.relativeMissingRawEvents = 0;this.relativeMissingRawRun = 0;this.relativeRawSamples = [];this.relativeLastRawTimestamp = -1;this.lastAbsoluteMouseX = -1;this.lastAbsoluteMouseY = -1;
  this.relativeDragTrace = [];this.relativeDragTouchMoves = 0;this.relativeDragMouseMoves = 0;
  this.touchScreenSingleEvents = 0;this.touchScreenDecisions = [];
  this.mouseRouteEvents = [0, 0, 0, 0];this.mouseDuplicateEvents = 0;this.recentMouseDispatchKeys = [];
  if (!preserveFallback) { this.fallbackAttempted = false;this.fallbackReason = '';this.fallbackTriggerFrames = 0;this.fallbackFrameDelta = 0;this.fallbackElapsedMs = 0;this.fallbackUdpDatagramDelta = 0; }
  this.dynamicWANRoute.bind(selectedTransport, mode === 'remote' && !fromDiagnostic && !this.diagnosticProfile && !this.diagnosticNoFallback ? intendedTransport : -1, this.sessionGeneration, this.platformNetworkEpoch, this.internetHost, Date.now());
  this.autoDirectWAN = selectedTransport === 4 && intendedTransport === 3;this.sessionTransport = selectedTransport;this.sessionStartedAt = Date.now();this.firstFrameReadyAt = 0;this.lastRenderAt = 0;this.lastRenderCount = 0;this.fallbackSuspended = false;
  this.activeSplitDiagnostic = split ? splitDiagnostic : '';
  this.lastVideoDatagrams = 0;this.lastVideoCheckAt = 0;this.videoStallEpochAt = 0;this.videoStallBaselineDatagrams = 0;
  this.loadInputDevices();this.convertedTrackpadScrollEvents = 0;this.convertedTrackpadScrollGestures = 0;
  this.touchCount = 0;this.mouseCount = 0;this.keyCount = 0;this.axisCount = 0;this.scrollCount = 0;this.zoomCount = 0;this.streaming = false;
  this.active = true;this.menuVisible = false;this.showText = false;if(rtc)this.prepareRTCListener();
  this.setFullScreen(reconnectAttempt ? this.reconnectResumeFullScreen : (preservePresentation ? previousFullScreen : mode !== 'bench'));
  if (!reconnectAttempt && !fromDiagnostic && !this.diagnosticProfile && this.isInternetTransport(selectedTransport)) { this.ensureInternetReconnect().arm({ mode: mode, transport: intendedTransport, fullScreen: this.fullScreen }); }
  const widths: number[] = [this.storeWidth, this.storeWidth, this.storeWidth], heights: number[] = [this.storeHeight, this.storeHeight, this.storeHeight];
  if (split) {
   try {
    native.connectSplit(selectedTransport === 0 ? '127.0.0.1' : this.host.trim(), selectedTransport === 0 ? 48561 : 48563, mode,
     widths[this.resolution], heights[this.resolution], this.fps, 'tcp', this.pairing.token, this.pairing.cert,
     selectedTransport === 0 ? this.host.trim() : '127.0.0.1', selectedTransport === 0 ? 48563 : 48561);
   } catch (e) {
    this.stop('split_diagnostic_failed');this.message = '分流诊断未能启动，普通扩展屏和远控可照常使用。';
    this.writeFile('split-diagnostic-status.json', JSON.stringify({ errorCode: 'split_start_failed', time: Date.now() }));return;
   }
  } else {
   native.connect(selectedTransport === 0 ? '127.0.0.1' : (this.isInternetTransport(selectedTransport) ? this.internetHost : this.host.trim()), selectedTransport === 0 ? 48561 : this.pairing.port, mode,
    widths[this.resolution], heights[this.resolution], this.fps, rtc ? (selectedTransport===3?'tailnet-rtc':'rtc') : (selectedTransport === 4 ? 'tailnet-udp' : (selectedTransport === 3 ? 'tailnet' : (selectedTransport === 2 ? 'udp' : (this.storeCodec === 'hevc' ? 'store-hevc':'store-avc')))), this.pairing.token, this.pairing.cert, fromDiagnostic && this.diagnosticBitrateKbps >= 1500 && this.diagnosticBitrateKbps <= 240000 ? this.diagnosticBitrateKbps : 0);
  }
  this.updateAvailabilityState();
  this.bindCursorChannel();
  native.input(`OPTION ctrlToCmd ${this.ctrlToCmd ? 1 : 0}`);
  this.message = mode === 'extend' ? '正在建立扩展桌面…' : '正在连接 Mac…';
  const generation = this.sessionGeneration;
  this.timer = setInterval(() => this.refresh(generation), 1000);this.focusRemote();
 }
 private stop(reason: string = 'user_end', restore: boolean = true): void {
  if (reason !== 'restart' && reason !== 'udp_fallback') { this.dynamicWANRoute.cancel(reason); }
  if (reason !== 'restart' && reason !== 'udp_fallback') { this.internetReconnect?.cancel(reason); }this.internetRecovering = false;
  this.cancelLocalStart();this.cancelRemoteStart();
  if (reason !== 'restart' && reason !== 'local_handover') { this.activeMacStart = '';this.localRequestGeneration++;if (this.pendingMacStart) { native.availabilityReply(this.pendingMacStart, false);this.pendingMacStart = ''; } }
  if (reason !== 'restart' && reason !== 'local_handover') { this.localHandoverDeadline = 0;this.localHandoverCapable = false; }
  this.microphoneConsentEpoch++;this.remoteMicEnabled = false;
  this.sessionGeneration++;this.stopRTC();
  this.unbindCursorChannel();
  this.unbindNativeMouseRoute();
  this.restoreSystemCursor();
  this.clearDesktopTopology();
  native.input('CURSORLOCK -1 0');
  this.endGestures();
  if (this.timer >= 0) { clearInterval(this.timer);this.timer = -1; }
  native.disconnect(reason);this.active = false;this.streaming = false;this.axisInputActive = false;
  this.dragging = false;this.twoFingers = false;this.commandHeld = false;this.optionHeld = false;
  this.mouseHeld = [false, false, false];this.clickTimes = [0, 0, 0];this.clickCounts = [0, 0, 0];
  this.menuVisible = false;this.showText = false;
  if (restore) { this.setFullScreen(false); }
  if (reason !== 'restart' && reason !== 'local_handover' && reason !== 'udp_fallback') { this.restoreDiagnosticProfile(); }
  this.message = '会话已结束，Mac 回到待命状态。';this.updateAvailabilityState();this.saveStatus();
 }
 private setFullScreen(value: boolean): void {
  this.fullScreen = value;this.menuVisible = false;this.internetReconnect?.updateFullScreen(this.sessionGeneration, value);this.internetReconnect?.gatesChanged();
  if (!value) { this.restoreSystemCursor(); }
  const epoch = ++this.presentationEpoch;
  this.applyWindow(value, epoch);this.focusRemote();
 }
 private async applyWindow(value: boolean, epoch: number): Promise<void> {
  try {
   const w = AppStorage.get<window.Window>('mainWindow');
   if (!w) { return; }
   if (epoch !== this.presentationEpoch) { return; }
   this.windowWarnings = [];
   try { await w.maximize(value ? window.MaximizePresentation.ENTER_IMMERSIVE : window.MaximizePresentation.EXIT_IMMERSIVE); } catch (e) { this.windowWarnings.push(`maximize: ${e}`); }
   if (epoch !== this.presentationEpoch) { return; }
   await w.setWindowLayoutFullScreen(value);
   if (epoch !== this.presentationEpoch) { return; }
   // Retain the system's top-edge gesture target while the video draws behind it.
   await w.setWindowSystemBarEnable(value ? ['status'] : ['status', 'navigation']);
   if (epoch !== this.presentationEpoch) { return; }
   try {
    await w.setWindowSystemBarProperties({ statusBarColor: value ? '#00000000' : '#0E1726', statusBarContentColor: value ? '#00000000' : '#EDF4FC', enableStatusBarAnimation: false });
   } catch (e) { this.windowWarnings.push(`status: ${e}`); }
   if (epoch !== this.presentationEpoch) { return; }
   try { w.setWindowDecorVisible(!value); } catch (e) { this.windowWarnings.push(`decor: ${e}`); }
   try { await w.setTitleAndDockHoverShown(!value || this.diagnosticSystemHover, !value); } catch (e) { this.windowWarnings.push(`hover: ${e}`); }
   if (epoch !== this.presentationEpoch) { return; }
   // Do not use the test-directory-only window snapshot API in a store variant.
   try {
    this.freeWindowMode = w.isInFreeWindowMode();
    this.systemWindowMode = 'unknown';
   } catch (e) { this.systemWindowMode = 'unknown'; }
   this.windowError = '';this.syncCursorLock();this.saveStatus();
  } catch (e) { this.windowError = `${e}`;this.saveStatus(); }
 }
 private remoteInputAllowed(): boolean {
  return this.active && !this.internetRecovering && AppStorage.get<boolean>('remoteInputWindowActive') === true && !this.menuVisible && !this.showText;
 }
 private syncCursorLock(): void {
  this.syncNativeMouseRoute();
  if (!this.remoteInputAllowed() || !this.fullScreen || this.diagnosticCursorLock === false) { this.restoreSystemCursor();native.input('CURSORLOCK -1 0');return; }
  try {
   const w = AppStorage.get<window.Window>('mainWindow');
   if (w) {
    const relative = this.diagnosticRelativeCursor && this.nativeMouseRouteBound && this.relativeAnchorReady && !this.relativeCursorBlocked;
    if (this.diagnosticRelativeCursor && !this.nativeMouseRouteBound) { this.restoreSystemCursor();this.relativeCursorStatus = 'native_mouse_route_unavailable'; }
    if (!relative) { this.restoreSystemCursor(false, true); }
    this.relativeWindowId = w.getWindowProperties().id;
    native.input(`CURSORLOCK ${this.relativeWindowId} 1 ${relative ? 0 : 1}`);
   } else { this.restoreSystemCursor();native.input('CURSORLOCK -1 0'); }
  } catch (e) {
   this.restoreSystemCursor();
   native.input('CURSORLOCK -1 0');
   this.writeFile('cursor-lock-error.json', JSON.stringify({ error: `${e}` }));
  }
 }
 private onRelativeCursorSettingChanged(): void { this.relativeCursorBlocked = false;this.restoreSystemCursor();this.syncCursorLock(); }
 private restoreSystemCursor(resetAnchor: boolean = true, allowHost: boolean = false): void {
  this.relativeCursorActive = false;
  if (resetAnchor) { this.relativeAnchorEpoch++;this.relativeAnchorReady = false;this.relativeWindowId = -1;this.relativeLastRawTimestamp = -1;this.relativeMissingRawRun = 0; }
  this.updateCursorVisibility(allowHost);
 }
 private updateCursorVisibility(allowHost: boolean = true): void {
  const showHost = allowHost && !this.relativeCursorActive && this.hostCursorOwner && this.hostCursorOnCapture &&
   this.mode === 'extend' && this.desktopTopologyValid && this.fullScreen && this.remoteInputAllowed() && this.pointerIsOnPad();
  const hideSystem = this.relativeCursorActive || showHost;
  this.hostCursorVisible = false;
  if (this.systemCursorHidden !== hideSystem) {
   try { pointer.setPointerVisibleSync(!hideSystem);this.systemCursorHidden = hideSystem; }
   catch (e) { this.relativeCursorStatus = hideSystem ? `host_hide_failed: ${e}` : `restore_failed: ${e}`;return; }
  }
  this.hostCursorVisible = showHost;
 }
 private syncRelativeCursor(s: Statistics): void {
  const allowed = this.diagnosticRelativeCursor && this.nativeMouseRouteBound && this.nativeMouseRouteGeneration === this.sessionGeneration && this.diagnosticCursorLock !== false && !this.relativeCursorBlocked &&
   this.remoteInputAllowed() && this.fullScreen && this.relativeAnchorReady && s.running && !s.localUI;
  const confirmed = allowed && s.cursorLocked && s.cursorFollowMovement === false && !s.cursorLockPending &&
   !s.cursorLockStateUncertain && s.cursorLockWindowId === this.relativeWindowId;
  if (!confirmed) {
   this.restoreSystemCursor(false, true);
   if (!this.relativeCursorBlocked && !this.systemCursorHidden) { this.relativeCursorStatus = !this.diagnosticRelativeCursor ? 'disabled' : (!this.nativeMouseRouteBound || this.nativeMouseRouteGeneration !== this.sessionGeneration ? 'native_mouse_route_unavailable' : (!this.relativeAnchorReady ? 'waiting_for_safe_pointer_position' : 'waiting_for_lock_confirmation')); }
   return;
  }
  if (!this.systemCursorHidden) {
   try { pointer.setPointerVisibleSync(false);this.systemCursorHidden = true; }
   catch (e) { this.relativeCursorBlocked = true;this.relativeCursorStatus = `hide_failed: ${e}`;this.restoreSystemCursor();this.syncCursorLock();return; }
  }
  this.relativeCursorActive = true;this.relativeCursorStatus = 'active';
  this.hostCursorVisible = false;this.refreshVirtualCursor();
 }
 private prepareRelativeCursor(event: MouseInputSample): void {
  if (!this.diagnosticRelativeCursor || !Number.isFinite(event.x) || !Number.isFinite(event.y)) { return; }
  this.lastAbsoluteMouseX = event.x;this.lastAbsoluteMouseY = event.y;
  // A frozen system pointer cannot support press-drag through the synthetic
  // Touch route. Keep absolute movement until the local raw route is bound.
  if (!this.nativeMouseRouteBound || this.nativeMouseRouteGeneration !== this.sessionGeneration) { this.relativeCursorStatus = 'native_mouse_route_unavailable';return; }
  if (this.relativeAnchorReady || this.relativeCursorBlocked || !this.fullScreen || this.diagnosticCursorLock === false) { return; }
  const inset = Math.min(64, this.frameWidth / 4, this.frameHeight / 4);
  if (this.frameWidth <= 1 || this.frameHeight <= 1 || event.x < inset || event.y < inset || event.x > this.frameWidth - inset || event.y > this.frameHeight - inset) { return; }
  // Freeze the system pointer only after observing an actual mouse position
  // away from system hover edges; a touchscreen position is not evidence of it.
  this.relativeAnchorReady = true;this.relativeAnchorEpoch++;this.relativeCursorStatus = 'waiting_for_lock_confirmation';this.syncCursorLock();
  this.confirmRelativeCursorSoon();
 }
 private confirmRelativeCursorSoon(): void {
  const generation = this.sessionGeneration, anchorEpoch = this.relativeAnchorEpoch;
  const confirm = (): void => {
   if (generation !== this.sessionGeneration || anchorEpoch !== this.relativeAnchorEpoch || !this.relativeAnchorReady ||
    this.relativeCursorActive || this.relativeCursorBlocked || !this.nativeMouseRouteBound || this.nativeMouseRouteGeneration !== this.sessionGeneration || !this.diagnosticRelativeCursor || this.diagnosticCursorLock === false ||
    !this.fullScreen || !this.remoteInputAllowed()) { return; }
   this.saveStatus();
  };
  // A pair of bounded checks bridges the asynchronous native lock without
  // waiting for the one-second status timer or polling on each mouse event.
  setTimeout(confirm, 32);setTimeout(confirm, 80);
 }
 private unbindNativeMouseRoute(): void {
  this.nativeMouseRouteEpoch++;
  this.nativeMouseRouteGeneration = -1;
  this.nativeMouseRouteAttempts = 0;
  if (!this.nativeMouseRouteBound) { return; }
  this.nativeMouseRouteBound = false;
  try { native.unbindMouseNode(); } catch (e) { this.nativeMouseRouteBindResult = -2; }
 }
 private syncNativeMouseRoute(): void {
  if (!this.diagnosticRelativeCursor || !this.fullScreen || !this.remoteInputAllowed()) { this.unbindNativeMouseRoute();return; }
  if (this.nativeMouseRouteBound && this.nativeMouseRouteGeneration !== this.sessionGeneration) { this.unbindNativeMouseRoute(); }
  if (this.nativeMouseRouteBound || this.nativeMouseRouteAttempts >= 2) { return; }
  this.nativeMouseRouteAttempts++;
  try {
   const ui = this.getUIContext(), node = ui.getFrameNodeById('remoteVideoFrame');
   if (!node) { this.nativeMouseRouteBindResult = -3;return; }
   const epoch = ++this.nativeMouseRouteEpoch, generation = this.sessionGeneration;
   this.nativeMouseRouteBindResult = native.bindMouseNode(node, ui.vp2px(1), (sample: NativeMouseSample): void => {
    this.onNativeMouseSample(sample, epoch, generation);
   });
   this.nativeMouseRouteBound = this.nativeMouseRouteBindResult === 0;
   this.nativeMouseRouteGeneration = this.nativeMouseRouteBound ? generation : -1;
  } catch (e) { this.nativeMouseRouteBindResult = -4; }
 }
 private onNativeMouseSample(sample: NativeMouseSample, epoch: number, generation: number): void {
  const counts = this.nativeMouseCallbackCounts;counts.callbacks++;
  let reason = 0;
  // Stable numeric sample codes correspond to the named lifetime counters.
  if (!this.nativeMouseRouteBound) { reason = 1;counts.unbound++; }
  else if (epoch !== this.nativeMouseRouteEpoch) { reason = 2;counts.staleEpoch++; }
  else if (generation !== this.sessionGeneration || this.nativeMouseRouteGeneration !== this.sessionGeneration) { reason = 3;counts.staleGeneration++; }
  else if (!this.diagnosticRelativeCursor) { reason = 4;counts.disabled++; }
  else if (!this.fullScreen) { reason = 5;counts.notFullscreen++; }
  else if (!this.active) { reason = 6;counts.sessionInactive++; }
  else if (AppStorage.get<boolean>('remoteInputWindowActive') !== true) { reason = 7;counts.windowInactive++; }
  else if (this.menuVisible) { reason = 8;counts.menu++; }
  else if (this.showText) { reason = 9;counts.textEditor++; }
  else if (sample.nativeAction !== 3) { reason = 10;counts.action++; }
  const finite = (value: number): number => Number.isFinite(value) ? value : 0;
  this.nativeMouseCallbackSamples.push({ generation: this.sessionGeneration, boundGeneration: this.nativeMouseRouteGeneration, callbackGeneration: generation,
   epoch: this.nativeMouseRouteEpoch, callbackEpoch: epoch, dropReason: reason, action: sample.nativeAction, button: sample.nativeButton,
   source: sample.source, tool: sample.sourceTool, deviceId: sample.deviceId, timeNs: finite(sample.timestamp), rawX: finite(sample.rawDeltaX), rawY: finite(sample.rawDeltaY),
   x: finite(sample.x), y: finite(sample.y), held: (this.mouseHeld[0] ? 1 : 0) | (this.mouseHeld[1] ? 2 : 0) | (this.mouseHeld[2] ? 4 : 0), relative: this.relativeCursorActive ? 1 : 0 });
  if (this.nativeMouseCallbackSamples.length > 48) { this.nativeMouseCallbackSamples.shift(); }
  if (reason !== 0) { return; }
  counts.forwarded++;
  const tool: SourceTool = sample.sourceTool === 3 ? SourceTool.MOUSE : (sample.sourceTool === 4 ? SourceTool.TOUCHPAD : sample.sourceTool);
  this.mouse({ action: MouseAction.Move, button: MouseButton.None, source: sample.source, sourceTool: tool,
   deviceId: sample.deviceId, timestamp: sample.timestamp, x: sample.x, y: sample.y,
   windowX: sample.windowX, windowY: sample.windowY, displayX: sample.displayX, displayY: sample.displayY,
   rawDeltaX: sample.rawDeltaX, rawDeltaY: sample.rawDeltaY, nativeAction: sample.nativeAction, nativeButton: sample.nativeButton, nativeTool: sample.sourceTool }, 3);
 }
 private relativeMouseMove(event: MouseInputSample): void {
  if (!this.relativeCursorActive || event.action !== MouseAction.Move) { return; }
  const dx = event.rawDeltaX, dy = event.rawDeltaY;
  if (typeof dx !== 'number' || typeof dy !== 'number' || !Number.isFinite(dx) || !Number.isFinite(dy)) {
   this.relativeMissingRawEvents++;this.relativeMissingRawRun++;
   if (this.relativeMissingRawRun >= 5) { this.relativeCursorBlocked = true;this.relativeCursorStatus = 'raw_delta_unavailable';this.restoreSystemCursor();this.syncCursorLock(); }
   return;
  }
  if (event.timestamp > 0 && event.timestamp === this.relativeLastRawTimestamp) { return; }
  this.relativeLastRawTimestamp = event.timestamp;this.relativeMissingRawRun = 0;this.relativeRawEvents++;
  this.relativeRawSamples.push({ dx: dx, dy: dy, absoluteX: Number.isFinite(event.x) ? event.x : this.lastAbsoluteMouseX, absoluteY: Number.isFinite(event.y) ? event.y : this.lastAbsoluteMouseY });
  if (this.relativeRawSamples.length > 16) { this.relativeRawSamples.shift(); }
  if (dx === 0 && dy === 0) { return; }
  this.move(this.pointerX + dx * this.relativeGainVp, this.pointerY + dy * this.relativeGainVp, true);
 }
 private recordRelativeDrag(route: number, action: number, deviceId: number, source: number, tool: number, timeNs: number,
  x: number, y: number, windowX: number, windowY: number, displayX: number, displayY: number,
  rawX: number = 0, rawY: number = 0, rawValid: number = 0, nativeAction: number = -1, nativeButton: number = -1, nativeTool: number = -1): void {
  const finite = (value: number): number => Number.isFinite(value) ? value : 0;
  this.relativeDragTrace.push({ route: route, action: action, deviceId: deviceId, source: source, tool: tool, timeNs: finite(timeNs),
   x: finite(x), y: finite(y), windowX: finite(windowX), windowY: finite(windowY), displayX: finite(displayX), displayY: finite(displayY),
   rawX: finite(rawX), rawY: finite(rawY), rawValid: rawValid,
   held: (this.mouseHeld[0] ? 1 : 0) | (this.mouseHeld[1] ? 2 : 0) | (this.mouseHeld[2] ? 4 : 0),
   relative: this.relativeCursorActive ? 1 : 0, converted: this.convertedTrackpadDeviceId,
   virtualX: finite(this.pointerX), virtualY: finite(this.pointerY), nativeAction: nativeAction, nativeButton: nativeButton, nativeTool: nativeTool });
  // Retain the initial press and the latest numeric samples of just this gesture.
  if (this.relativeDragTrace.length > 48) { this.relativeDragTrace.splice(1, 1); }
 }
 private onWindowInputStateChanged(): void {
  this.updateAvailabilityState();
  if (!this.remoteInputWindowActive) {
   this.endGestures();this.axisInputActive = false;
   this.mouseHeld = [false, false, false];this.commandHeld = false;this.optionHeld = false;
   this.dragging = false;this.twoFingers = false;
  }
  // Runs on a lifecycle transition, never on the statistics timer or every frame.
  this.focusRemote();
 }
 private focusRemote(): void {
  const allowed = this.remoteInputAllowed();
  native.input(`LOCALUI ${allowed ? 0 : 1}`);
  this.syncCursorLock();
  if (!allowed) { this.endGestures();this.axisInputActive = false;return; }
  try { const w = AppStorage.get<window.Window>('mainWindow');if (w) { native.input(`OBSERVE ${w.getWindowProperties().id}`); } } catch (e) { this.writeFile('axis-observer-error.json', JSON.stringify({ error: `${e}` })); }
  // State changes become focusable only after layout. Focus failure must never end a session.
  this.getUIContext().postFrameCallback(new AfterLayout(() => {
   if (!this.remoteInputAllowed()) { this.syncCursorLock();return; }
   try { this.getUIContext().getFocusController().requestFocus('remoteSurface'); }
   catch (e) { this.writeFile('focus-status.json', JSON.stringify({ time: Date.now(), error: `${e}` })); }
   this.syncCursorLock();
  }));
 }
 private lastDiscoveryReport: string = '';
 private saveStatus(): Statistics | null {
  try {
   const discoveryReport = JSON.stringify({ host: this.availability?.host || '', discovery: this.availability?.discoveryStatus || '', status: this.availability?.status() });
   if (discoveryReport !== this.lastDiscoveryReport) { this.lastDiscoveryReport = discoveryReport;this.writeFile('local-discovery.json', discoveryReport); }
   const s = JSON.parse(native.stats()) as Statistics;
   s.localHandoverCount = this.localHandoverCount;s.localHandoverReason = this.localHandoverReason;
   s.rtcBridgeDiagnostics=this.rtcBridgeDiagnostics;s.dynamicWANRoute = this.dynamicWANRoute.state(Date.now());
   const rtcNow=Date.now();
   if(this.active && this.rtcSession && this.remoteSessionForeground && rtcNow-this.rtcLastSnapshotRequestAt>=1000){this.rtcLastSnapshotRequestAt=rtcNow;this.rtcBridge.requestSafeSnapshot();}
   this.updateDesktopTopology(s);
   this.applyPendingCursorSample();
   this.syncRelativeCursor(s);
   s.touchEvents = this.touchCount;s.mouseEvents = this.mouseCount;s.keyEvents = this.keyCount;
   s.axisEvents = this.axisCount;s.scrollCommands = this.scrollCount;s.zoomCommands = this.zoomCount;
   s.lastAxisX = this.lastAxisX;s.lastAxisY = this.lastAxisY;s.lastPinchScale = this.lastPinchScale;
   s.touchpadPanEvents = this.touchpadPanCount;s.touchpadPinchEvents = this.touchpadPinchCount;s.lastTouchSource = this.lastTouchSource;s.lastTouchTool = this.lastTouchTool;
   s.touchScreenSingleState = this.touchScreenState;s.touchScreenScrollGestures = this.touchScreenScrollGestures;s.touchScreenLongPressDrags = this.touchScreenLongPressDrags;
   s.touchScreenSingleEvents = this.touchScreenSingleEvents;s.touchScreenDecisions = this.touchScreenDecisions;
   s.inputTools = [SourceTool.Finger, SourceTool.MOUSE, SourceTool.TOUCHPAD];s.inputSources = [SourceType.Mouse, SourceType.TouchScreen];s.inputTrace = this.inputTrace;s.clickTrace = this.clickTrace;s.windowWarnings = this.windowWarnings;
   s.inputDevices = this.inputDevices;s.inputDeviceStatus = this.inputDeviceStatus;s.inputDeviceFailures = this.inputDeviceFailures;
   s.convertedTrackpadScrollEvents = this.convertedTrackpadScrollEvents;s.convertedTrackpadScrollGestures = this.convertedTrackpadScrollGestures;s.convertedTrackpadDeviceId = this.convertedTrackpadDeviceId;
   s.fullScreen = this.fullScreen;s.menuVisible = this.menuVisible;s.windowInputActive = AppStorage.get<boolean>('remoteInputWindowActive') === true;
   s.viewportWidthPx = this.getUIContext().vp2px(this.frameWidth);s.viewportHeightPx = this.getUIContext().vp2px(this.frameHeight);s.windowError = this.windowError;
   s.systemWindowMode = this.systemWindowMode;s.freeWindowMode = this.freeWindowMode;
   s.fallbackReason = this.fallbackReason;s.fallbackAttempted = this.fallbackAttempted;s.fallbackTriggerFrames = this.fallbackTriggerFrames;s.fallbackFrameDelta = this.fallbackFrameDelta;s.fallbackElapsedMs = this.fallbackElapsedMs;s.fallbackUdpDatagramDelta = this.fallbackUdpDatagramDelta;
   s.sessionGeneration = this.sessionGeneration;s.sessionTransport = this.sessionTransport;s.profileTransport = this.transport;s.autoDirectWAN = this.autoDirectWAN;s.wanRouteEvidence = this.wanRouteEvidence.state(this.internetHost, this.platformNetworkEpoch, this.platformNetworkReady, Date.now());s.internetReconnect = this.internetReconnect?.state();
   s.diagnosticSplitTransport = this.activeSplitDiagnostic;
   s.relativeCursorRequested = this.diagnosticRelativeCursor;s.relativeCursorActive = this.relativeCursorActive;s.relativeCursorAnchorReady = this.relativeAnchorReady;s.relativeCursorStatus = this.relativeCursorStatus;s.systemCursorHidden = this.systemCursorHidden;
   s.relativeRawEvents = this.relativeRawEvents;s.relativeMissingRawEvents = this.relativeMissingRawEvents;s.relativeGainVpPerHardwareUnit = this.relativeGainVp;s.relativeRawSamples = this.relativeRawSamples;
   s.lastAbsoluteMouseX = this.lastAbsoluteMouseX;s.lastAbsoluteMouseY = this.lastAbsoluteMouseY;s.virtualCursorX = this.virtualCursorX;s.virtualCursorY = this.virtualCursorY;
   s.relativeDragTrace = this.relativeDragTrace;s.relativeDragTouchMoves = this.relativeDragTouchMoves;s.relativeDragMouseMoves = this.relativeDragMouseMoves;
   s.mouseRouteEvents = this.mouseRouteEvents;s.mouseDuplicateEvents = this.mouseDuplicateEvents;
   s.nativeMouseRouteBound = this.nativeMouseRouteBound;s.nativeMouseRouteBindResult = this.nativeMouseRouteBindResult;
   s.nativeMouseRouteGeneration = this.nativeMouseRouteGeneration;s.nativeMouseRouteEpoch = this.nativeMouseRouteEpoch;
   s.nativeMouseCallbackCounts = this.nativeMouseCallbackCounts;s.nativeMouseCallbackSamples = this.nativeMouseCallbackSamples;
   s.extendedPointerEnabled = this.canMoveAcrossDisplays();s.relativeCursorOnPad = this.virtualCursorOnPad;
   s.desktopPointerX = this.desktopTopologyValid ? this.desktopCapture.x + this.pointerX / this.frameWidth * this.desktopCapture.width : 0;
   s.desktopPointerY = this.desktopTopologyValid ? this.desktopCapture.y + this.pointerY / this.frameHeight * this.desktopCapture.height : 0;
   s.cursorChannelBound = this.cursorChannelBound;s.cursorChannelBindResult = this.cursorChannelBindResult;
   s.cursorChannelSessionEpoch = this.cursorChannelSessionEpoch;s.cursorLastSequence = this.cursorLastSequence;
   s.cursorEdgeInputSequence = this.cursorEdgeInputSequence;s.cursorSourceOwner = this.cursorSourceOwner;
   s.cursorSyncApplied = this.cursorSyncApplied;s.cursorSyncStaleSession = this.cursorSyncStaleSession;s.cursorSyncStaleSequence = this.cursorSyncStaleSequence;
   s.cursorSyncStaleInput = this.cursorSyncStaleInput;s.cursorSyncInvalid = this.cursorSyncInvalid;
   s.hostCursorOwner = this.hostCursorOwner;s.hostCursorVisible = this.hostCursorVisible;
   this.writeFile('session-status.json', JSON.stringify(s));return s;
  } catch (e) { return null; }
 }
 private checkMediaFallback(s: Statistics, generation: number, now: number = Date.now()): boolean {
  if (generation !== this.sessionGeneration || !this.active || this.sessionTransport !== 4 || this.diagnosticNoFallback || this.fallbackAttempted || !s.running) { return false; }
  if (!this.remoteInputAllowed()) { this.fallbackSuspended = true;return false; }
  if (this.fallbackSuspended || now < this.sessionStartedAt) {
   this.fallbackSuspended = false;this.sessionStartedAt = now;this.firstFrameReadyAt = 0;
   this.lastRenderCount = s.renderSubmittedFrames;this.lastRenderAt = this.lastRenderCount > 0 ? now : 0;
   this.lastVideoCheckAt = 0;
  }
  const delta = s.renderSubmittedFrames - this.lastRenderCount;
  if (delta > 0) { this.lastRenderAt = now;this.lastRenderCount = s.renderSubmittedFrames; }
  const datagrams = Number.isFinite(s.udpDatagrams) && s.udpDatagrams >= 0 ? s.udpDatagrams : 0;
  const packetProgress = datagrams > this.lastVideoDatagrams && this.lastVideoCheckAt > 0 && now >= this.lastVideoCheckAt && now - this.lastVideoCheckAt <= 2500;
  // SCK intentionally sends no frames for a static desktop. Require positive
  // UDP progress in consecutive samples; silence or a timer gap starts a new epoch.
  if (!packetProgress || delta > 0) { this.videoStallEpochAt = now;this.videoStallBaselineDatagrams = datagrams; }
  this.lastVideoDatagrams = datagrams;this.lastVideoCheckAt = now;
  if (this.firstFrameReadyAt === 0 && s.state === 'ready') { this.firstFrameReadyAt = now; }
  let elapsed = 0, reason = '';
  if (this.lastRenderCount > 0) {
   elapsed = now - this.videoStallEpochAt;
   if (packetProgress && elapsed >= 3000) { reason = 'UDP 视频包持续到达但画面连续3秒未更新，切回稳定连接'; }
  } else if (this.firstFrameReadyAt > 0) {
   elapsed = now - this.firstFrameReadyAt;if (elapsed >= 4000) { reason = 'UDP 就绪后4秒未收到首帧，切回稳定连接'; }
  } else {
   elapsed = now - this.sessionStartedAt;if (elapsed >= 15000) { reason = 'UDP 连接准备超过15秒，切回稳定连接'; }
  }
  if (!reason) { return false; }
  this.fallbackAttempted = true;this.fallbackReason = reason;this.fallbackTriggerFrames = s.renderSubmittedFrames;this.fallbackFrameDelta = delta;this.fallbackElapsedMs = elapsed;this.fallbackUdpDatagramDelta = Math.max(0, datagrams - this.videoStallBaselineDatagrams);
  const mode = this.mode;this.dynamicWANRoute.failed(now, 'udp_watchdog');
  // Stop the old media even if the network is no longer ready for the replacement.
  this.stop('udp_fallback', false);this.begin(mode, true, '', '', false, false, 3, 3, true);this.saveStatus();return true;
 }
 private checkDynamicWANRoute(s: Statistics, generation: number, now: number = Date.now()): boolean {
  const evidence = this.wanRouteEvidence.state(this.internetHost, this.platformNetworkEpoch, this.platformNetworkReady && this.networkReady, now);
  const gate: WANRouteGate = { generation: generation, epoch: this.platformNetworkEpoch, target: this.internetHost,
   eligible: generation === this.sessionGeneration && this.active && this.mode === 'remote' && s.running && (s.state === 'streaming' || this.sessionTransport === 4) &&
    this.remoteInputAllowed() && !this.internetRecovering && !this.waitingLocalStart && !this.waitingRemoteStart && !this.pendingMacStart &&
    !this.menuVisible && !this.showText && !this.diagnosticNoFallback && !this.diagnosticProfile && !this.activeSplitDiagnostic &&
    this.platformNetworkReady && this.networkReady && !this.fallbackAttempted,
   inputIdle: !this.mouseHeld.some((held: boolean) => held) && !this.commandHeld && !this.optionHeld && !this.dragging && !this.twoFingers &&
    !this.touchScreenState && !this.touchScreenButtonHeld && !this.gestureKind && !this.convertedTrackpadScrollActive && !this.remoteMicEnabled };
  const decision = this.dynamicWANRoute.step(s, gate, evidence, now);
  if (decision.action === 'upgrade') {
   // This is a bounded comparison, not a seamless transport migration. Reuse
   // the existing connection lifecycle and preserve the user's saved profile.
   this.begin('remote', true, '', '', false, false, 4, 3, true);this.saveStatus();return true;
  }
  if (decision.action === 'revert') {
   this.fallbackAttempted = true;this.fallbackReason = decision.reason;
   this.stop('udp_fallback', false);this.begin('remote', true, '', '', false, false, 3, 3, true);this.saveStatus();return true;
  }
  return false;
 }
 private checkLocalHandover(s: Statistics): boolean {
  if (s.stopReason === 'mac_end') { return false; }
  if (!this.active || this.mode !== 'extend' || this.activeSplitDiagnostic || (this.diagnosticMode !== '' && this.diagnosticTransport !== 'handover-lan') || !this.remoteInputWindowActive) { return false; }
  if (s.localHandoverSupported) { this.localHandoverCapable = true; }
  if (!this.localHandoverCapable) { return false; }
  const now = Date.now(), status = this.availability?.status();if (!status) { return false; }
  if (s.running && s.renderSubmittedFrames > 0) { this.localHandoverDeadline = 0; }
  const usb = status.paths.some((p: LocalPath) => p.route === 'usb' && p.ready);
  const lan = status.paths.some((p: LocalPath) => p.route === 'lan' && p.ready);
  let route = '';
  if (!s.running) {
   if (this.localHandoverDeadline === 0) { this.localHandoverDeadline = now + 8500; }
   if (now >= this.localHandoverDeadline) { return false; }
   if (this.sessionTransport === 0) { this.localUSBRetryAfter = now + 15000;route = lan ? 'lan' : ''; }
   else { route = usb && now >= this.localUSBRetryAfter ? 'usb' : (lan ? 'lan' : ''); }
   if (!route || now < this.localHandoverNextAttempt) { this.message = '正在恢复本地连接，扩展桌面保持不变…';return true; }
  } else if (this.sessionTransport === 1 && usb && now >= this.localUSBRetryAfter && now - this.sessionStartedAt > 2500 && s.renderSubmittedFrames > 20 && !this.menuVisible && !this.dragging && !this.mouseHeld.some((v: boolean) => v)) {
   route = 'usb';
  }
  if (!route) { return false; }
  this.localHandoverNextAttempt = now + 750;this.localHandoverCount++;
  this.localHandoverReason = s.running ? 'usb_available' : 'active_path_lost';
  this.begin('extend', false, '', '', false, false, -1, -1, true, route);
  return true;
 }
 private refresh(generation: number = this.sessionGeneration): void {
  if (generation !== this.sessionGeneration) { return; }
  const s = this.saveStatus();if (!s) { return; }
  if (this.checkLocalHandover(s)) { return; }
  if (this.checkMediaFallback(s, generation)) { return; }
  if (this.checkDynamicWANRoute(s, generation)) { return; }
  this.remoteMicEnabled = s.microphoneAllowed === true;
  this.axisInputActive = s.axisInputEnabled;
  this.streaming = s.state === 'streaming';
  if (this.streaming && s.running && s.renderSubmittedFrames > 0) { this.internetReconnect?.connected(generation); }
  this.message = this.streaming ? (this.mode === 'extend' ? '扩展屏运行中' : '远控运行中') : (s.error || (s.running ? '连接中…' : '会话已停止'));
  this.statistics = `接收 ${s.receivedFPS.toFixed(1)} FPS · 提交显示 ${s.renderSubmittedFPS.toFixed(1)} FPS · 解码 ${s.decodeP95ms.toFixed(1)} ms · 丢帧 ${s.lostFrames} · 输入 ${s.inputSent}（触 ${this.touchCount} / 鼠 ${this.mouseCount} / 键 ${this.keyCount + s.nativeKeyEvents}）`;
  if (!s.running) {
   if (this.isInternetTransport(this.sessionTransport) && recoverableInternetFailure(s.stopReason, s.error) && this.internetReconnect?.lost(generation, s.error || 'native_connection_ended')) { this.saveStatus();return; }
   this.internetReconnect?.cancel('nonrecoverable_session_end');this.internetRecovering = false;
   this.unbindCursorChannel();
   native.input('OBSERVE -1');this.axisInputActive = false;
   if (this.timer >= 0) { clearInterval(this.timer);this.timer = -1; }
   this.active = false;this.menuVisible = false;this.setFullScreen(false);this.restoreDiagnosticProfile();this.updateAvailabilityState();this.saveStatus();
  }
 }
 private bindCursorChannel(): void {
  if (!this.active || this.mode !== 'extend') { return; }
  const generation = this.sessionGeneration, epoch = ++this.cursorChannelEpoch;
  try {
   this.cursorChannelBindResult = native.bindCursorChannel((sample: NativeCursorSample): void => this.onCursorSample(sample, generation, epoch));
   this.cursorChannelBound = this.cursorChannelBindResult === 0;
  } catch (e) { this.cursorChannelBindResult = -1;this.cursorChannelBound = false; }
 }
 private unbindCursorChannel(): void {
  this.cursorChannelEpoch++;
  if (this.cursorChannelBound) { try { native.unbindCursorChannel(); } catch (e) {} }
  this.cursorChannelBound = false;this.cursorChannelSessionEpoch = 0;this.cursorLastSequence = 0;this.cursorEdgeInputSequence = 0;this.cursorSourceOwner = 0;
  this.cursorPendingSample = null;this.hostCursorOwner = false;this.hostCursorOnCapture = false;this.hostCursorVisible = false;
 }
 private validCursorSequence(value: number, positive: boolean = false): boolean {
  return Number.isFinite(value) && Math.floor(value) === value && value >= (positive ? 1 : 0) && value <= 9007199254740991;
 }
 private onCursorSample(sample: NativeCursorSample, generation: number, epoch: number): void {
  if (!this.cursorChannelBound || generation !== this.sessionGeneration || epoch !== this.cursorChannelEpoch || !this.active || this.mode !== 'extend') { this.cursorSyncStaleSession++;return; }
  if (!this.validCursorSequence(sample.sessionEpoch, true) || !this.validCursorSequence(sample.cursorSequence, true) ||
   !this.validCursorSequence(sample.edgeInputAck) || !Number.isFinite(sample.x) || !Number.isFinite(sample.y) || Math.abs(sample.x) > 10000000 || Math.abs(sample.y) > 10000000 ||
   (sample.sourceOwner !== 1 && sample.sourceOwner !== 2) || (sample.visible !== 0 && sample.visible !== 1)) { this.cursorSyncInvalid++;return; }
  if (this.cursorChannelSessionEpoch !== 0 && sample.sessionEpoch !== this.cursorChannelSessionEpoch) { this.cursorSyncStaleSession++;return; }
  this.cursorChannelSessionEpoch = sample.sessionEpoch;
  if (sample.cursorSequence <= this.cursorLastSequence) { this.cursorSyncStaleSequence++;return; }
  this.cursorLastSequence = sample.cursorSequence;this.cursorPendingSample = null;
  // A newer local MOVE may still be in transit. Never apply a host position
  // sampled before that MOVE was applied, or an impossible future acknowledgement.
  if (sample.edgeInputAck !== this.cursorEdgeInputSequence) { this.cursorSyncStaleInput++;return; }
  this.cursorSourceOwner = sample.sourceOwner;
  if (sample.sourceOwner === 2) { return; }
  this.cursorPendingSample = sample;this.applyPendingCursorSample();
 }
 private applyPendingCursorSample(): void {
  const sample: NativeCursorSample | null = this.cursorPendingSample;
  if (!sample || !this.cursorChannelBound || !this.active || this.mode !== 'extend') { return; }
  if (sample.edgeInputAck !== this.cursorEdgeInputSequence) { this.cursorPendingSample = null;this.cursorSyncStaleInput++;return; }
  if (!this.desktopTopologyValid || this.frameWidth <= 1 || this.frameHeight <= 1) { return; }
  this.cursorPendingSample = null;
  const capture = this.desktopCapture;
  const globalX = capture.x + sample.x * capture.width, globalY = capture.y + sample.y * capture.height;
  if (!Number.isFinite(globalX) || !Number.isFinite(globalY)) { this.cursorSyncInvalid++;return; }
  const projected = this.projectDesktopPoint(globalX, globalY);
  this.pointerX = (projected.x - capture.x) / capture.width * this.frameWidth;
  this.pointerY = (projected.y - capture.y) / capture.height * this.frameHeight;
  this.hostCursorOwner = true;this.hostCursorOnCapture = sample.visible === 1;this.cursorSyncApplied++;
  this.refreshVirtualCursor();this.updateCursorVisibility();
 }
 private takeLocalCursorOwnership(): void {
  this.cursorPendingSample = null;
  if (!this.hostCursorOwner && !this.hostCursorVisible) { return; }
  this.hostCursorOwner = false;this.hostCursorOnCapture = false;this.updateCursorVisibility();
 }
 private clearDesktopTopology(): void { this.desktopTopologyValid = false;this.desktopDisplays = []; }
 private validDesktopRect(rect: DesktopRect): boolean {
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) && Number.isFinite(rect.width) && Number.isFinite(rect.height) &&
   Math.abs(rect.x) <= 10000000 && Math.abs(rect.y) <= 10000000 && rect.width >= 1 && rect.height >= 1 && rect.width <= 100000 && rect.height <= 100000;
 }
 private adoptedDesktopRevision: number = 0;
 private updateDesktopTopology(s: Statistics): void {
  if (this.mode !== 'extend' || !s.running || s.desktopTopologyValid !== true || !s.desktopDisplays || s.desktopDisplays.length < 1 || s.desktopDisplays.length > 8) { this.clearDesktopTopology();return; }
  const capture: DesktopRect = { x: s.desktopCaptureX, y: s.desktopCaptureY, width: s.desktopCaptureWidth, height: s.desktopCaptureHeight };
  if (!this.validDesktopRect(capture) || s.desktopDisplays.some((rect: DesktopRect) => !this.validDesktopRect(rect))) { this.clearDesktopTopology();return; }
  const revision = s.desktopTopologyRevision || 0;
  if (revision !== this.adoptedDesktopRevision && this.desktopTopologyValid && this.frameWidth > 0 && this.frameHeight > 0) {
   const globalX = this.desktopCapture.x + this.pointerX / this.frameWidth * this.desktopCapture.width;
   const globalY = this.desktopCapture.y + this.pointerY / this.frameHeight * this.desktopCapture.height;
   this.pointerX = (globalX - capture.x) / capture.width * this.frameWidth;
   this.pointerY = (globalY - capture.y) / capture.height * this.frameHeight;
  }
  this.desktopCapture = capture;this.desktopDisplays = s.desktopDisplays;this.desktopTopologyValid = true;
  if (revision !== this.adoptedDesktopRevision) {
   this.adoptedDesktopRevision = revision;
   this.mouseHeld = [false, false, false];this.commandHeld = false;this.optionHeld = false;
   this.cancelTouchScreenGesture();
   if (revision > 0) { native.input(`TOPOLOGYACK ${revision}`); }
  }
 }
 private canMoveAcrossDisplays(): boolean { return this.mode === 'extend' && this.relativeCursorActive && this.desktopTopologyValid; }
 private pointerIsOnPad(): boolean { return this.pointerX >= 0 && this.pointerX < this.frameWidth && this.pointerY >= 0 && this.pointerY < this.frameHeight; }
 private shouldPreserveCrossDisplayPointer(): boolean {
  return this.mode === 'extend' && this.desktopTopologyValid && !this.pointerIsOnPad() && this.fullScreen && this.diagnosticCursorLock !== false &&
   this.diagnosticRelativeCursor && !this.relativeCursorBlocked && this.nativeMouseRouteBound && this.nativeMouseRouteGeneration === this.sessionGeneration;
 }
 private onViewportChanged(width: number, height: number): void {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width < 1 || height < 1) { return; }
  if (this.mode === 'extend' && this.desktopTopologyValid && this.frameWidth > 1 && this.frameHeight > 1) {
   // Preserve the desktop location through full-screen and windowed layout changes,
   // including while the relative lock is temporarily released for a local menu.
   this.pointerX = this.pointerX / this.frameWidth * width;this.pointerY = this.pointerY / this.frameHeight * height;
  }
  this.frameWidth = width;this.frameHeight = height;this.applyPendingCursorSample();this.refreshVirtualCursor();this.updateCursorVisibility();this.saveStatus();
 }
 private refreshVirtualCursor(): void {
  this.virtualCursorOnPad = this.hostCursorOwner ? this.hostCursorOnCapture && this.pointerIsOnPad() : (!this.canMoveAcrossDisplays() || this.pointerIsOnPad());
  this.virtualCursorX = Math.max(0, Math.min(this.frameWidth - 1, this.pointerX));this.virtualCursorY = Math.max(0, Math.min(this.frameHeight - 1, this.pointerY));
 }
 private projectDesktopPoint(x: number, y: number): DesktopPoint {
  let closest: DesktopPoint = { x: this.desktopCapture.x, y: this.desktopCapture.y }, distance = Number.POSITIVE_INFINITY;
  for (const rect of this.desktopDisplays) {
   // Use a sub-point inset, not one pixel, so tiny movements can cross adjoining displays.
   const point: DesktopPoint = { x: Math.max(rect.x, Math.min(rect.x + rect.width - 0.001, x)), y: Math.max(rect.y, Math.min(rect.y + rect.height - 0.001, y)) };
   const squared = (point.x - x) * (point.x - x) + (point.y - y) * (point.y - y);
   if (squared < distance) { closest = point;distance = squared; }
  }
  return closest;
 }
 private move(x: number, y: number, relativeMovement: boolean = false): void {
  if (!Number.isFinite(x) || !Number.isFinite(y) || this.frameWidth <= 0 || this.frameHeight <= 0) { return; }
  this.takeLocalCursorOwnership();
  const acrossDisplays = relativeMovement && this.canMoveAcrossDisplays();
  if (acrossDisplays) {
   const capture = this.desktopCapture;
   const globalX = capture.x + x / this.frameWidth * capture.width, globalY = capture.y + y / this.frameHeight * capture.height;
   if (!Number.isFinite(globalX) || !Number.isFinite(globalY)) { return; }
   const projected = this.projectDesktopPoint(globalX, globalY);
   x = (projected.x - capture.x) / capture.width * this.frameWidth;y = (projected.y - capture.y) / capture.height * this.frameHeight;
  } else {
   // Absolute touchscreen input always addresses the image visible on the Pad.
   x = Math.max(0, Math.min(this.frameWidth - 1, x));y = Math.max(0, Math.min(this.frameHeight - 1, y));
  }
  this.pointerX = x;this.pointerY = y;
  this.refreshVirtualCursor();
  if (this.mode === 'extend') {
   const sequence = this.cursorEdgeInputSequence + 1;
   if (this.validCursorSequence(sequence, true) && native.input(`MOVE ${x / this.frameWidth} ${y / this.frameHeight} ${sequence}`) === true) { this.cursorEdgeInputSequence = sequence; }
  } else { native.input(`MOVE ${x / this.frameWidth} ${y / this.frameHeight}`); }
 }
 private isConvertedTrackpadTouch(event: TouchEvent): boolean {
  if (event.source !== SourceType.TouchScreen || event.sourceTool !== SourceTool.Finger) { return false; }
  const deviceId = event.deviceId ?? -1;
  // Keep the classification of an already-started drag if device discovery finishes mid-gesture.
  if (deviceId >= 0 && deviceId === this.unconvertedTouchDeviceId) { return false; }
  if (deviceId >= 0 && deviceId === this.convertedTrackpadDeviceId) { return true; }
  const device = this.inputDevices.find((item: InputDeviceDiagnostic) => item.id === deviceId);
  // A mixed touchscreen device must retain normal touch dragging, even if it also exposes pointer input.
  return device !== undefined && device.sources.length === 1 && device.sources[0] === 'touchpad';
 }
 private endConvertedTrackpadScroll(): void {
  if (this.convertedTrackpadScrollActive) { this.scroll(0, 0, 4);this.convertedTrackpadScrollEvents++; }
  this.convertedTrackpadScrollActive = false;
 }
 private convertedTrackpadTouch(event: TouchEvent, fingers: TouchObject[]): boolean {
  if (!this.isConvertedTrackpadTouch(event)) { return false; }
  const deviceId = event.deviceId ?? -1;
  if (this.convertedTrackpadDeviceId !== deviceId) {
   // Ignore an orphaned continuation after a menu, cancellation, or focus loss. Never turn its Up into a tap.
   if (event.type !== TouchType.Down) { return true; }
   this.endGestures();this.button(0, false, this.storeInputTimestamp());this.dragging = false;this.twoFingers = false;
   this.convertedTrackpadDeviceId = deviceId;
  }
  if (fingers.length >= 2) {
   // Pinch is delivered as multiple touch points. Finish a preceding converted scroll and use the existing algorithm.
   this.endConvertedTrackpadScroll();return false;
  }
  if (this.twoFingers) { this.endGestures();this.twoFingers = false;return true; }
  const point = event.changedTouches[0];
  if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.endGestures();return true; }
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) { return true; }
  if (event.type === TouchType.Down && !this.convertedTrackpadScrollActive) {
   this.convertedTrackpadLastX = point.x;this.convertedTrackpadLastY = point.y;
   this.convertedTrackpadScrollActive = true;this.convertedTrackpadScrollGestures++;
   this.scroll(0, 0, 1);this.convertedTrackpadScrollEvents++;
  } else if (event.type === TouchType.Move && this.convertedTrackpadScrollActive) {
   this.scroll((point.y - this.convertedTrackpadLastY) * 2, (point.x - this.convertedTrackpadLastX) * 2, 2);
   this.convertedTrackpadLastX = point.x;this.convertedTrackpadLastY = point.y;this.convertedTrackpadScrollEvents++;
  }
  return true;
 }
 private recordTouchScreenDecision(kind: string, pointX: number = this.touchScreenLastX, pointY: number = this.touchScreenLastY): void {
  const x = Number.isFinite(pointX) ? pointX : this.touchScreenStartX;
  const y = Number.isFinite(pointY) ? pointY : this.touchScreenStartY;
  this.touchScreenDecisions.push({ kind: kind, state: this.touchScreenState, events: this.touchScreenGestureEvents,
   elapsedMs: Math.max(0, Math.round(Date.now() - this.touchScreenStartedAt)), x: x, y: y,
   distanceVp: Math.round(Math.hypot(x - this.touchScreenStartX, y - this.touchScreenStartY) * 10) / 10,
   held: this.touchScreenButtonHeld ? 1 : 0, relative: this.relativeCursorActive ? 1 : 0 });
  if (this.touchScreenDecisions.length > 24) { this.touchScreenDecisions.shift(); }
 }
 private cancelTouchScreenGesture(timestamp: number = 0): void {
  if (this.touchScreenState) { this.recordTouchScreenDecision('end'); }
  this.touchScreenFeedback = '';
  this.touchScreenEpoch++;
  if (this.touchScreenTimer >= 0) { clearTimeout(this.touchScreenTimer);this.touchScreenTimer = -1; }
  if (this.touchScreenState === 'scroll') { this.scroll(0, 0, 4);this.wheelRemainderX = 0;this.wheelRemainderY = 0; }
  if (this.touchScreenButtonHeld) {
   this.button(0, false, timestamp);this.dragging = false;
   // A held selection is one click, not the start of a later double click.
   this.clickTimes[0] = 0;this.clickCounts[0] = 0;
  }
  this.touchScreenButtonHeld = false;this.touchScreenState = '';this.touchScreenId = -1;this.touchScreenDeviceId = -1;
 }
 private touchScreenSingle(event: TouchEvent, fingers: TouchObject[]): void {
  this.touchScreenSingleEvents++;
  if (event.type === TouchType.Down) {
   this.cancelTouchScreenGesture();
   const point = event.changedTouches[0];
   if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) { return; }
   this.touchScreenState = 'pending';this.touchScreenId = point.id;this.touchScreenDeviceId = event.deviceId ?? -1;
   this.touchScreenStartX = this.touchScreenLastX = point.x;this.touchScreenStartY = this.touchScreenLastY = point.y;
   this.touchScreenStartedAt = Date.now();this.touchScreenGestureEvents = 1;this.recordTouchScreenDecision('pending');
   this.touchScreenFeedbackX = point.x;this.touchScreenFeedbackY = point.y;this.touchScreenFeedback = 'pending';
   this.touchScreenTimestamp = this.storeInputTimestamp();this.dragging = false;this.twoFingers = false;this.move(point.x, point.y);
   const epoch = this.touchScreenEpoch, generation = this.sessionGeneration;
   this.touchScreenTimer = setTimeout(() => {
    if (epoch !== this.touchScreenEpoch || generation !== this.sessionGeneration) { return; }
    this.touchScreenTimer = -1;
    if (this.touchScreenState !== 'pending' || !this.remoteInputAllowed() || this.mouseHeld[0]) { this.cancelTouchScreenGesture();return; }
    this.touchScreenState = 'drag';this.touchScreenLongPressDrags++;
    this.move(this.touchScreenStartX, this.touchScreenStartY);
    // Do not turn a long press on an arbitrary Mac button into a double click.
    this.clickTimes[0] = 0;this.clickCounts[0] = 0;
    this.button(0, true, this.touchScreenTimestamp, 24);this.touchScreenButtonHeld = true;this.dragging = true;
    this.touchScreenFeedback = 'drag';
    this.recordTouchScreenDecision('long_press');
   }, 400);
   return;
  }
  if (!this.touchScreenState) {
   if (event.type === TouchType.Up && fingers.length === 0) { this.twoFingers = false;this.unconvertedTouchDeviceId = -1; }
   return;
  }
  if ((event.deviceId ?? -1) !== this.touchScreenDeviceId) { return; }
  const point = event.changedTouches.find((item: TouchObject) => item.id === this.touchScreenId);
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
   if (event.type === TouchType.Up) { this.cancelTouchScreenGesture(this.storeInputTimestamp());if (fingers.length === 0) { this.unconvertedTouchDeviceId = -1;this.twoFingers = false; } }
   return;
  }
  this.touchScreenGestureEvents++;
  if (event.type === TouchType.Move) {
   if (this.touchScreenState === 'pending' && Math.hypot(point.x - this.touchScreenStartX, point.y - this.touchScreenStartY) > this.touchScreenPendingSlopVp) {
    if (this.touchScreenTimer >= 0) { clearTimeout(this.touchScreenTimer);this.touchScreenTimer = -1; }
    this.touchScreenEpoch++;this.touchScreenState = 'scroll';this.touchScreenScrollGestures++;
    this.touchScreenFeedback = '';
    this.scroll(0, 0, 1);this.scroll((point.y - this.touchScreenStartY) * 2, (point.x - this.touchScreenStartX) * 2, 2);
    this.recordTouchScreenDecision('scroll', point.x, point.y);
   } else if (this.touchScreenState === 'scroll') {
    this.scroll((point.y - this.touchScreenLastY) * 2, (point.x - this.touchScreenLastX) * 2, 2);
   } else if (this.touchScreenState === 'drag') { this.move(point.x, point.y);this.touchScreenFeedbackX = point.x;this.touchScreenFeedbackY = point.y; }
   this.touchScreenLastX = point.x;this.touchScreenLastY = point.y;
  } else if (event.type === TouchType.Up) {
   // Coalesced input can deliver Down/Up without the intermediate Move. A
   // completed swipe must not become a click on the release position.
   this.touchScreenLastX = point.x;this.touchScreenLastY = point.y;
   if (this.touchScreenState === 'pending' && Math.hypot(point.x - this.touchScreenStartX, point.y - this.touchScreenStartY) > this.touchScreenPendingSlopVp) {
    this.touchScreenState = 'scroll';this.touchScreenScrollGestures++;
    this.touchScreenFeedback = '';
    this.scroll(0, 0, 1);this.scroll((point.y - this.touchScreenStartY) * 2, (point.x - this.touchScreenStartX) * 2, 2);
    this.recordTouchScreenDecision('scroll');
   }
   const tap = this.touchScreenState === 'pending';
   if (tap) { this.recordTouchScreenDecision('tap'); }
   if (tap || this.touchScreenState === 'drag') { this.move(point.x, point.y); }
   this.cancelTouchScreenGesture(this.storeInputTimestamp());
   if (tap) { this.button(0, true, this.storeInputTimestamp(), 24);this.button(0, false, this.storeInputTimestamp()); }
   this.dragging = false;if (fingers.length === 0) { this.unconvertedTouchDeviceId = -1;this.twoFingers = false; }
  }
 }
 private touch(event: TouchEvent): void {
  this.touchCount++;if (!this.remoteInputAllowed()) { this.cancelTouchScreenGesture();return; }
  this.lastTouchSource = event.source;this.lastTouchTool = event.sourceTool;
  this.trace('touch', event.type, event.source, event.sourceTool, event.touches.length, event.deviceId ?? -1);
  if (event.source === SourceType.TouchScreen && event.sourceTool === SourceTool.Finger &&
   this.cancelledConvertedDeviceId >= 0 && (event.deviceId ?? -1) === this.cancelledConvertedDeviceId) {
   if (event.type !== TouchType.Down) { return; }
   this.cancelledConvertedDeviceId = -1;
  }
  // Mouse/trackpad synthetic touch movement is not a touchscreen drag.
  if (event.sourceTool === SourceTool.MOUSE) {
   // This keyboard reports clicks as synthetic touch, without MouseEvent Press/Release.
   // Share button state with onMouse so devices reporting both paths cannot double-post.
   const point = event.changedTouches[0];if (!point) { return; }
   this.takeLocalCursorOwnership();
   if (this.diagnosticRelativeCursor) {
    if (event.type === TouchType.Down && !this.mouseHeld[0]) { this.relativeDragTrace = []; }
    if (event.type === TouchType.Move) { this.relativeDragTouchMoves++; }
    this.recordRelativeDrag(0, event.type, event.deviceId ?? -1, event.source, event.sourceTool, this.storeInputTimestamp(),
     point.x, point.y, point.windowX, point.windowY, point.displayX, point.displayY);
   }
   if (this.convertedTrackpadDeviceId >= 0 && event.type === TouchType.Move) { return; }
   if (this.convertedTrackpadDeviceId >= 0 && event.type === TouchType.Down) { this.endGestures();this.twoFingers = false; }
   if (this.convertedTrackpadDeviceId < 0 && !this.relativeCursorActive && !this.shouldPreserveCrossDisplayPointer()) { this.move(point.x, point.y); }
   if (event.type === TouchType.Down) { this.focusRemote();this.button(0, true, this.storeInputTimestamp()); }
   else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.button(0, false, this.storeInputTimestamp()); }
   return;
  }
  if (event.sourceTool === SourceTool.TOUCHPAD || event.source === SourceType.Mouse) { return; }
  if (event.type === TouchType.Cancel) { this.button(0, false);this.dragging = false;this.endGestures();this.twoFingers = false;return; }
  if (event.type === TouchType.Down && this.convertedTrackpadDeviceId >= 0 && (event.deviceId ?? -1) !== this.convertedTrackpadDeviceId) { this.endGestures();this.twoFingers = false; }
  if (event.type === TouchType.Down) { this.focusRemote(); }
  const fingers = event.touches.filter((finger: TouchObject) => finger.type !== TouchType.Up && finger.type !== TouchType.Cancel);
  if (this.convertedTrackpadTouch(event, fingers)) { return; }
  if (event.type === TouchType.Down && this.convertedTrackpadDeviceId < 0) { this.unconvertedTouchDeviceId = event.deviceId ?? -1; }
  if (fingers.length >= 2) {
   this.cancelTouchScreenGesture();
   const x = (fingers[0].x + fingers[1].x) / 2, y = (fingers[0].y + fingers[1].y) / 2;
   const distance = Math.max(1, Math.hypot(fingers[0].x - fingers[1].x, fingers[0].y - fingers[1].y));
   if (!this.twoFingers) {
    if (this.dragging) { this.button(0, false); }this.twoFingers = true;this.dragging = false;this.gestureKind = '';
    this.firstCenterX = x;this.firstCenterY = y;this.firstDistance = distance;this.lastDistance = distance;
    if (this.convertedTrackpadDeviceId < 0) { this.move(x, y); }
   } else {
    if (!this.gestureKind) {
     const pan = Math.hypot(x - this.firstCenterX, y - this.firstCenterY), pinch = Math.abs(distance - this.firstDistance);
     if (pinch > Math.max(5, this.firstDistance * 0.035) && pinch > pan * 1.3) { this.gestureKind = 'zoom';this.zoom(0, 1); }
     else if (pan > 3) { this.gestureKind = 'scroll';this.scroll(0, 0, 1); }
    }
    if (this.gestureKind === 'zoom') { this.zoom(distance / this.lastDistance - 1, 2); }
    else if (this.gestureKind === 'scroll') { this.scroll((y - this.lastCenterY) * 2, (x - this.lastCenterX) * 2, 2); }
   }
   this.lastDistance = distance;this.lastCenterX = x;this.lastCenterY = y;return;
  }
  if (this.twoFingers) { this.endGestures(); }
  // Converted touchpad gestures were handled above; only real finger contact
  // changes to single-finger scrolling and long-press selection/dragging.
  if (event.source === SourceType.TouchScreen && event.sourceTool === SourceTool.Finger) { this.touchScreenSingle(event, fingers);return; }
  const point = event.changedTouches[0];if (!point) { return; }
  if (event.type === TouchType.Down) { this.startX = point.x;this.startY = point.y;this.dragging = false;this.twoFingers = false;this.move(point.x, point.y); }
  else if (event.type === TouchType.Move && !this.twoFingers) {
   if (!this.dragging && Math.hypot(point.x - this.startX, point.y - this.startY) > 8) { this.move(this.startX, this.startY);this.button(0, true, this.storeInputTimestamp(), 24);this.dragging = true; }
   this.move(point.x, point.y);
  } else if (event.type === TouchType.Up) {
   if (!this.twoFingers) { this.move(point.x, point.y);if (!this.dragging) { this.button(0, true, this.storeInputTimestamp(), 24); }this.button(0, false, this.storeInputTimestamp()); }
   this.dragging = false;if (event.touches.length === 0) { this.twoFingers = false; }
   if (fingers.length === 0) { this.unconvertedTouchDeviceId = -1; }
  }
 }
 private scroll(y: number, x: number, phase: number): void {
  if (!Number.isFinite(x) || !Number.isFinite(y)) { return; }
  this.wheelRemainderX += x;this.wheelRemainderY += y;
  const dx = Math.round(this.wheelRemainderX), dy = Math.round(this.wheelRemainderY);
  this.wheelRemainderX -= dx;this.wheelRemainderY -= dy;
  if (phase === 2 && dx === 0 && dy === 0) { return; }
  this.scrollCount++;native.input(`SCROLL ${dy} ${dx} ${phase}`);
 }
 private zoom(delta: number, phase: number): void { if (!Number.isFinite(delta)) { return; }this.zoomCount++;native.input(`ZOOM ${Math.max(-0.5, Math.min(0.5, delta))} ${phase}`); }
 private endGestures(): void {
  this.cancelTouchScreenGesture();
  if (this.convertedTrackpadDeviceId >= 0) { this.cancelledConvertedDeviceId = this.convertedTrackpadDeviceId; }
  this.endConvertedTrackpadScroll();this.convertedTrackpadDeviceId = -1;this.unconvertedTouchDeviceId = -1;
  if (this.gestureKind === 'zoom') { this.zoom(0, 4); }
  if (this.gestureKind === 'scroll') { this.scroll(0, 0, 4); }
  this.gestureKind = '';this.wheelRemainderX = 0;this.wheelRemainderY = 0;
 }
 private onJsMouse(event: MouseEvent, route: number): void {
  const sample: MouseInputSample = { action: event.action, button: event.button, source: event.source,
   sourceTool: event.sourceTool, deviceId: event.deviceId, timestamp: this.storeInputTimestamp(),
   x: event.x, y: event.y, windowX: event.windowX, windowY: event.windowY,
   displayX: event.displayX, displayY: event.displayY, rawDeltaX: event.rawDeltaX, rawDeltaY: event.rawDeltaY };
  this.mouse(sample, route);
 }
 private mouse(event: MouseInputSample, route: number = 1): void {
  this.mouseCount++;if (!this.remoteInputAllowed()) { return; }
  if (event.action === MouseAction.Press || event.action === MouseAction.Release || event.action === MouseAction.Move) { this.takeLocalCursorOwnership(); }
  if (route >= 1 && route <= 3) { this.mouseRouteEvents[route]++; }
  this.trace('mouse', event.action, event.source, event.sourceTool, 0, event.deviceId ?? -1);
  if (this.diagnosticRelativeCursor && (this.mouseHeld.some((held: boolean) => held) || event.action === MouseAction.Press)) {
   if (event.action === MouseAction.Press && !this.mouseHeld.some((held: boolean) => held)) { this.relativeDragTrace = []; }
   if (event.action === MouseAction.Move) { this.relativeDragMouseMoves++; }
   const validRaw = typeof event.rawDeltaX === 'number' && typeof event.rawDeltaY === 'number' && Number.isFinite(event.rawDeltaX) && Number.isFinite(event.rawDeltaY);
   this.recordRelativeDrag(route, event.action, event.deviceId ?? -1, event.source, event.sourceTool, event.timestamp,
    event.x, event.y, event.windowX, event.windowY, event.displayX, event.displayY, validRaw ? event.rawDeltaX! : 0, validRaw ? event.rawDeltaY! : 0, validRaw ? 1 : 0, event.nativeAction ?? -1, event.nativeButton ?? -1, event.nativeTool ?? -1);
  }
  if (Number.isFinite(event.timestamp) && event.timestamp > 0) {
   const buttonIdentity = event.nativeButton === undefined ? event.button : (event.nativeButton === 1 ? MouseButton.Left :
    (event.nativeButton === 2 ? MouseButton.Right : (event.nativeButton === 3 ? MouseButton.Middle : MouseButton.None)));
   const key = `${event.deviceId ?? -1}:${event.timestamp}:${event.action}:${buttonIdentity}`;
   if (this.recentMouseDispatchKeys.includes(key)) { this.mouseDuplicateEvents++;return; }
   this.recentMouseDispatchKeys.push(key);if (this.recentMouseDispatchKeys.length > 32) { this.recentMouseDispatchKeys.shift(); }
  }
  if (this.convertedTrackpadDeviceId >= 0 && event.action !== MouseAction.Press && event.action !== MouseAction.Release) { return; }
  this.prepareRelativeCursor(event);
  if (event.action === MouseAction.Press) { this.endGestures();this.twoFingers = false;this.focusRemote(); }
  if (this.convertedTrackpadDeviceId < 0) {
   if (this.relativeCursorActive) { this.relativeMouseMove(event); }
   else if (!this.shouldPreserveCrossDisplayPointer()) {
    // After a local menu/focus pause, wait for the relative lock to resume.
    // Its fixed system position must not teleport the Mac cursor back to the Pad.
    this.move(event.x, event.y);
   }
  }
  const button = event.button === MouseButton.Right ? 1 : (event.button === MouseButton.Middle ? 2 : 0);
  if (event.action === MouseAction.Press) { this.button(button, true, event.timestamp); }
  else if (event.action === MouseAction.Release) { this.button(button, false, event.timestamp); }
 }
 private modifier(code: number, down: boolean): void { native.input(`MACKEY ${code} ${down ? 1 : 0}`);this.focusRemote(); }
 private sendText(): void {
  if (!this.remoteText) { return; }
  const bytes = new util.TextEncoder().encodeInto(this.remoteText);
  native.input(`TEXT ${new util.Base64Helper().encodeToStringSync(bytes)}`);this.remoteText = '';this.showText = false;this.focusRemote();
 }
 private homeConnectionLabel(): string {
  if (!this.pairingLoaded) { return '正在准备配对'; }
  if (this.isInternetTransport() && this.networkStarting) { return '正在准备连接'; }
  if (this.isInternetTransport() && this.networkReady) { return '连接服务已就绪'; }
  return '已配对 · 待连接';
 }
 @Builder
 private screenBridge() {
  Row({ space: 20 }) {
   Column({ space: 9 }) {
    Column({ space: 0 }) {
     Column({ space: 6 }) {
      Row() {}.width('72%').height(5).backgroundColor('#B7D9CB').borderRadius(3)
      Row() {}.width('52%').height(5).backgroundColor('#DCEBE4').borderRadius(3)
      Row() {}.width('64%').height(5).backgroundColor('#DCEBE4').borderRadius(3)
     }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start).padding(15).width(126).height(84)
      .backgroundColor('#FFFFFF').border({ width: 2, color: '#AAC8BF' }).borderRadius(9)
     Row() {}.width(4).height(8).backgroundColor('#AAC8BF')
     Row() {}.width(38).height(4).backgroundColor('#AAC8BF').borderRadius(2)
    }.width(126).height(96)
    Text('Mac').fontSize(12).fontColor('#607A74')
   }
   Image($r('app.media.bridge_connection')).width(54).height(32).objectFit(ImageFit.Contain).margin({ bottom: 24 })
   Column({ space: 9 }) {
    Column({ space: 0 }) {
     Column({ space: 6 }) {
      Row() {}.width('72%').height(5).backgroundColor('#B7D9CB').borderRadius(3)
      Row() {}.width('52%').height(5).backgroundColor('#DCEBE4').borderRadius(3)
      Row() {}.width('64%').height(5).backgroundColor('#DCEBE4').borderRadius(3)
     }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Start).padding(12).width(126).height(84)
      .backgroundColor('#FFFFFF').border({ width: 1.5, color: '#AAC8BF' }).borderRadius(12)
     Blank().height(12)
    }.width(126).height(96)
    Text('华为平板').fontSize(12).fontColor('#607A74')
   }
  }.hitTestBehavior(HitTestMode.None).focusable(false)
 }
 @Builder
 private modeCard(mode: string, title: string, description: string, detail: string) {
  Column({ space: 16 }) {
   Row() {
    Text(mode === 'extend' ? '＋' : '↗').fontSize(25).fontWeight(FontWeight.Medium).fontColor('#23796C')
     .width(46).height(46).textAlign(TextAlign.Center).backgroundColor('#EDF5F1').borderRadius(13)
    Blank()
    Text(mode === 'extend' ? '延展工作空间' : '随时接回桌面').fontSize(12).fontColor('#607A74')
   }.width('100%')
   Text(title).fontSize(26).fontWeight(FontWeight.Bold).fontColor('#172D2C').width('100%')
   Text(description).fontSize(16).lineHeight(25).fontColor('#607A74').width('100%')
   Text(detail).fontSize(13).fontColor('#789089').width('100%')
   Button(mode === 'extend' ? (this.waitingLocalStart ? '取消连接' : '开启扩展屏') : (this.waitingRemoteStart ? '取消连接' : '开始远控')).onClick(() => this.begin(mode))
    .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').backgroundColor('#23796C')
    .height(48).width('100%').borderRadius(12).margin({ top: 4 }).hitTestBehavior(HitTestMode.Default)
  }.alignItems(HorizontalAlign.Start).padding(26).width('100%').backgroundColor('#FFFFFF')
   .border({ width: 1, color: '#E0E8E4' }).borderRadius(22).hitTestBehavior(HitTestMode.Default)
 }
 @Builder
 private connectionSettings() {
  Column({ space: 14 }) {
   Text(this.localRouteLabel).fontSize(13).fontColor('#23796C').width('100%')
   Text('扩展屏自动比较 USB 与局域网；下方选择用于远控。').fontSize(12).fontColor('#789089').width('100%')
   Text('远控连接方式').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#172D2C').width('100%')
   Select([{ value: 'USB 数据线' }, { value: '局域网直连' }, { value: '互联网连接' }])
    .selected(this.transport === 0 ? 0 : (this.isInternetTransport() ? 2 : 1))
    .onSelect((v: number) => { this.chooseTransport([0, 1, 3][v]);if (this.isInternetTransport()) { this.startNetwork(); } })
    .width('100%').height(46).font({ size: 15 }).fontColor('#172D2C').backgroundColor('#F5F7F6').borderRadius(11)
   if (this.transport === 2 || this.transport === 4) {
    Text('当前使用 UDP 试验连接').fontSize(12).fontColor('#789089').width('100%')
   }
   if (this.transport === 1 || this.transport === 2) {
    TextInput({ text: this.host, placeholder: 'Mac 的局域网地址' }).onChange((v: string) => { this.host = v;this.availability?.setHost(v.trim());this.saveSettings(); })
     .width('100%').height(46).backgroundColor('#F5F7F6').fontColor('#172D2C').placeholderColor('#8A9B96').borderRadius(11)
   } else if (this.transport === 0) {
    Text('用数据线连接后，选择扩展屏或远控即可。').fontSize(13).fontColor('#789089').width('100%')
   } else {
    Text(this.networkMessage).fontSize(13).lineHeight(21).fontColor('#607A74').width('100%')
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
     Button(this.networkStarting ? '准备连接中…' : '检查互联网连接').onClick(() => this.startNetwork())
      .enabled(!this.networkStarting).fontSize(13).fontColor('#23796C').backgroundColor('#EDF5F1')
      .height(38).borderRadius(10).margin({ right: 10, bottom: 4 }).hitTestBehavior(HitTestMode.Default)
     if (this.networkAuthURL) {
      Button('登录连接服务').onClick(() => this.openNetworkLogin()).fontSize(13).fontColor('#FFFFFF')
       .backgroundColor('#23796C').height(38).borderRadius(10).margin({ bottom: 4 }).hitTestBehavior(HitTestMode.Default)
     }
    }.width('100%')
   }
  }.alignItems(HorizontalAlign.Start).width('100%')
 }
 @Builder
 private qualitySettings() {
  Column({ space: 14 }) {
   Text('画面与流畅度').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#172D2C').width('100%')
   Row({ space: 12 }) {
    Select([{ value: '1920 × 1280' }, { value: '2400 × 1600' }, { value: '3120 × 2080' }])
     .selected(this.resolution).onSelect((v: number) => this.resolution = v).layoutWeight(1)
     .height(46).font({ size: 15 }).fontColor('#172D2C').backgroundColor('#F5F7F6').borderRadius(11)
    Select([{ value: '60 FPS' }, { value: '90 FPS' }, { value: '120 FPS' }])
     .selected(this.fps === 60 ? 0 : (this.fps === 90 ? 1 : 2)).onSelect((v: number) => this.fps = [60, 90, 120][v])
     .layoutWeight(1).height(46).font({ size: 15 }).fontColor('#172D2C').backgroundColor('#F5F7F6').borderRadius(11)
   }.width('100%')
   Text('连接后自动全屏；侧滑返回可打开操作菜单。').fontSize(13).lineHeight(21).fontColor('#789089').width('100%')
  }.alignItems(HorizontalAlign.Start).width('100%')
 }
 @Builder
 private home() {
  Column({ space: 24 }) {
   Text('映桥测试版').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#172D2C').width('100%')
   Text('让每一块屏幕，自然相连。').fontSize(19).fontColor('#607A74').width('100%')
   if (this.storeStage === 0) { Text('正在准备首次使用引导…').fontColor('#607A74') }
   if (this.storeStage === 1) {
    Text('先在电脑上安装映桥').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
    Text('1. 复制下方 GitHub 链接，在电脑浏览器中打开。\n2. 阅读 Releases 中的兼容要求；正式安装包发布后，下载适合电脑的版本。\n3. 将 Mac 应用拖到“应用程序”并打开。\n4. 点击准备扩展屏，按系统提示授予录屏、键鼠权限。\n5. 让两台设备连接同一 Wi-Fi，回到这里扫描电脑二维码。').fontSize(16).lineHeight(28).width('100%')
    Text(STORE_DOWNLOAD_URL).copyOption(CopyOptions.LocalDevice).fontColor('#23796C').width('100%')
    Button('复制电脑端下载链接').onClick(() => this.storeCopyLink()).backgroundColor('#23796C').width('100%').height(48)
    Button('电脑端已安装，继续').onClick(() => this.storeStage=2).width('100%').height(46)
   }
   if (this.storeStage === 2) {
    Text('连接你自己的电脑').fontSize(25).fontWeight(FontWeight.Bold).width('100%')
    Text('在电脑端点击“准备局域网扩展屏”，扫描它显示的二维码。配对信息只保存在你的平板，不会上传服务器。').fontSize(16).lineHeight(27).width('100%')
    Button('扫描电脑二维码').onClick(() => this.storeScan()).backgroundColor('#23796C').width('100%').height(48)
    TextArea({ text:this.storePairingText, placeholder:'或粘贴电脑端的完整配对信息' }).onChange((v:string)=>this.storePairingText=v).height(140).width('100%')
    Button('保存配对并继续').onClick(() => this.applyStorePairing(this.storePairingText,true)).width('100%').height(46)
    Button('电脑还没安装？查看步骤').onClick(() => this.storeStage=1).width('100%')
   }
   if (this.storeStage === 3) {
    Text('工作空间，再宽一点。').fontSize(27).fontWeight(FontWeight.Bold).width('100%')
    Text('软件会读取当前窗口比例和硬件解码能力，自动选择画面规格。首次安装不需要设置分辨率或码率。').fontSize(16).lineHeight(27).fontColor('#607A74').width('100%')
    Text(this.storeProfileLabel).fontSize(14).fontColor('#23796C').width('100%')
    Button('开启扩展屏').onClick(() => this.begin('extend')).backgroundColor('#23796C').height(52).width('100%')
    Text(this.message).fontSize(14).fontColor('#607A74').width('100%')
    Text('有线与无线自动接续是核心发布门槛。普通权限 USB 通道尚在验证，此开发预览不将调试线通道作为消费版能力。').fontSize(13).lineHeight(23).fontColor('#7D7257').width('100%')
    Button('重新配对或更换电脑').onClick(() => {this.storeStage=2;}).width('100%').height(44)
   }
   if (this.storeError) { Text(this.storeError).fontColor('#A04444').width('100%') }
   Text('开发预览 · 尚未上架 · 首次只在你点击后扫描配对二维码或复制链接').fontSize(12).fontColor('#789089').width('100%')
  }.padding(this.homeWidth>=740 ? 38:20).width('100%').constraintSize({maxWidth:1000}).alignItems(HorizontalAlign.Start)
 }
 @Builder
 private controls() {
  Row({ space: 8 }) {
   Button(this.commandHeld ? '⌘ 松开' : '⌘').onClick(() => { this.commandHeld = !this.commandHeld;this.modifier(55, this.commandHeld); })
    .fontSize(13).height(36).fontColor('#23796C').backgroundColor('#EAF3EE').borderRadius(9)
   Button(this.optionHeld ? '⌥ 松开' : '⌥').onClick(() => { this.optionHeld = !this.optionHeld;this.modifier(58, this.optionHeld); })
    .fontSize(13).height(36).fontColor('#23796C').backgroundColor('#EAF3EE').borderRadius(9)
   Button('文字').onClick(() => { this.setFullScreen(false);this.showText = !this.showText;this.focusRemote(); })
    .fontSize(13).height(36).fontColor('#607A74').backgroundColor('#EEF2EF').borderRadius(9)
   Button(this.fullScreen ? '退出全屏' : '进入全屏').onClick(() => this.setFullScreen(!this.fullScreen))
    .fontSize(13).height(36).fontColor('#FFFFFF').backgroundColor('#23796C').borderRadius(9)
   Button('结束').onClick(() => this.stop('user_end')).fontSize(13).height(36).fontColor('#8B4949').backgroundColor('#F6ECEA').borderRadius(9)
  }
 }
 build() {
  Stack({ alignContent: Alignment.TopStart }) {
   Stack({ alignContent: Alignment.Center }) {
    XComponent({ id: 'remote', type: XComponentType.SURFACE, libraryname: 'edgelink', controller: this.controller })
     .id('remoteSurface').focusable(this.active && !this.menuVisible && !this.showText).defaultFocus(this.active).width('100%').height('100%')
     .hitTestBehavior(!this.active || this.menuVisible || this.showText ? HitTestMode.None : HitTestMode.Default)
     .onLoad(() => { native.setSurface(this.controller.getXComponentSurfaceId());this.ready = true;this.updateAvailabilityState();this.autoDiagnostic(); })
     .onAreaChange((_old: Area, area: Area) => this.onViewportChanged(Number(area.width), Number(area.height)))
    // Keep touch/click handling here while native XComponent receives physical axis events.
    if (this.active && !this.menuVisible && !this.showText) { Column() {}
     .width('100%').height('100%').focusable(false).focusOnTouch(false)
     .hitTestBehavior(HitTestMode.Transparent).backgroundColor(Color.Transparent)
     .onAppear(() => this.focusRemote())
     .onTouch((event: TouchEvent) => this.touch(event))
     .onMouse((event: MouseEvent) => this.onJsMouse(event, 1))

    }
    if ((this.relativeCursorActive && this.virtualCursorOnPad) || this.hostCursorVisible) {
     Image($r('app.media.remote_cursor')).width(24).height(32)
      .position({ x: this.virtualCursorX - 1.5, y: this.virtualCursorY - 1.5 })
      .hitTestBehavior(HitTestMode.None).focusable(false).zIndex(2)
    }
    if (this.touchScreenFeedback && this.active && !this.menuVisible && !this.showText) {
     Column() {}.width(36).height(36).backgroundColor(this.touchScreenFeedback === 'drag' ? '#2529A37D' : Color.Transparent)
      .border({width:2,color:this.touchScreenFeedback === 'drag' ? '#6BE0AC' : '#F3DB97'}).borderRadius(18)
      .position({ x: this.touchScreenFeedbackX - 18, y: this.touchScreenFeedbackY - 18 })
      .hitTestBehavior(HitTestMode.None).focusable(false).zIndex(3)
     Text(this.touchScreenFeedback === 'drag' ? '可以拖动' : '按住不动')
      .fontSize(11).fontWeight(FontWeight.Medium).fontColor(this.touchScreenFeedback === 'drag' ? '#C5F8DF' : '#FFF0C9')
      .padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#D9233530').borderRadius(8)
      .position({ x: Math.max(2, Math.min(this.frameWidth - 90, this.touchScreenFeedbackX + 24)), y: Math.max(2, Math.min(this.frameHeight - 30, this.touchScreenFeedbackY - 12)) })
      .hitTestBehavior(HitTestMode.None).focusable(false).zIndex(3)
    }
   }.id('remoteVideoFrame').width(this.fullScreen ? '100%' : 'calc(100% - 36vp)').height(this.fullScreen ? '100%' : 'calc(100% - 120vp)')
    .position({ x: this.fullScreen ? 0 : 18, y: this.fullScreen ? 0 : 72 }).backgroundColor(Color.Black).zIndex(0)
    .opacity(this.active ? 1 : 0)
    .hitTestBehavior(!this.active || this.menuVisible || this.showText ? HitTestMode.None : HitTestMode.Default)
    .onMouse((event: MouseEvent) => this.onJsMouse(event, 2))
   if (!this.active) {
    Scroll() {
     this.home()
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor('#F5F7F6').zIndex(100)
     .hitTestBehavior(HitTestMode.Default).onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);if (Number.isFinite(width) && width > 0 && Math.abs(width - this.homeWidth) > 1) { this.homeWidth = width; }
     })
   } else {
    if (!this.fullScreen) {
     Row({ space: 12 }) {
      Text(this.message).fontSize(14).fontColor('#172D2C').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      this.controls()
     }.width('100%').height(64).padding({ left: 18, right: 18 }).backgroundColor('#F5F7F6')
     Text(this.statistics).fontSize(12).fontColor('#607A74').position({ x: 18, y: 'calc(100% - 32vp)' })
    }
    if (!this.streaming && this.fullScreen) {
     Text(this.message).fontColor(Color.White).padding(12).backgroundColor('#B3122033').borderRadius(10).position({ x: 24, y: 24 })
    }
    if (this.showText) {
     Column() {}.width('100%').height('100%').backgroundColor('#66000000').zIndex(40).hitTestBehavior(HitTestMode.Block)
     Column({ space: 16 }) {
      Row({ space: 12 }) {
       Text(this.mode === 'extend' ? '扩展屏' : '远控 Mac').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#172D2C').layoutWeight(1)
       Button('继续').onClick(() => { this.menuVisible = false;this.showText = false;this.focusRemote(); }).fontColor('#23796C').backgroundColor('#EAF3EE')
      }.width('100%')
      this.controls()
      if (this.showText) {
       Row({ space: 12 }) {
        TextInput({ text: this.remoteText, placeholder: '输入文字发送到 Mac' }).onChange((v: string) => this.remoteText = v).layoutWeight(1)
        Button('发送').onClick(() => this.sendText()).fontColor(Color.White).backgroundColor('#23796C')
       }.width('100%')
      }
      Text(this.statistics).fontSize(12).fontColor('#607A74')
     }.padding(24).width('76%').backgroundColor('#FFFFFF').borderRadius(20).position({ x: '12%', y: '12%' }).zIndex(50).hitTestBehavior(HitTestMode.Default)
    }
   }
  }.width('100%').height('100%').backgroundColor('#F5F7F6')
 }
}
