export const probe: () => string;
export const setSurface: (surfaceId: string) => void;
export const connect: (host: string, port: number, mode: string, width: number, height: number, fps: number, transport: string, token: string, certificate: string, bitrateKbps?: number) => void;
export const disconnect: (reason?: string) => void;
export const input: (command: string) => boolean;
export const stats: () => string;

export const network: (directory?: string, networkJSON?: string) => string;

export interface NativeMouseSample {
  nativeAction: number;
  nativeButton: number;
  source: number;
  sourceTool: number;
  deviceId: number;
  timestamp: number;
  x: number;
  y: number;
  windowX: number;
  windowY: number;
  displayX: number;
  displayY: number;
  rawDeltaX: number;
  rawDeltaY: number;
}
export const bindMouseNode: (frameNode: Object, densityPixels: number, callback: (sample: NativeMouseSample) => void) => number;
export const unbindMouseNode: () => void;

export interface NativeCursorSample {
  sessionEpoch: number;
  cursorSequence: number;
  sourceOwner: number;
  edgeInputAck: number;
  visible: number;
  sampleTimeNs: number;
  x: number;
  y: number;
}
export const bindCursorChannel: (callback: (sample: NativeCursorSample) => void) => number;
export const unbindCursorChannel: () => void;

export interface AvailabilityEvent {
 type: string;
 route: string;
 requestId?: string;
}
export const availabilityConfigure: (host: string, port: number, token: string, certificate: string, callback: (event: AvailabilityEvent) => void) => void;
export const availabilityState: (state: string) => void;
export const availabilityReply: (requestId: string, accepted: boolean) => boolean;
export const availabilityStop: () => void;
export const availabilityStatus: () => string;
export const availabilityRefresh: () => void;

// Explicit diagnostic candidate only. Normal UI continues to use connect().
export const connectSplit: (controlHost: string, controlPort: number, mode: string,
 width: number, height: number, fps: number, transport: string,
 token: string, certificate: string, videoHost: string, videoPort: number) => void;

// Call only after this session's explicit user action and interactive mic grant.
export const setMicrophoneAllowed: (allowed: boolean) => boolean;

export interface RTCNativeEvent { epoch: number; session: string; kind: string; body: string; }
export const bindRtcEvents: (callback?: (event: RTCNativeEvent) => void) => boolean;
export const rtcPush: (session: string, record: ArrayBuffer) => boolean;
export const rtcSignal: (session: string, json: string) => boolean;

export const storeProfile: (width:number,height:number,codec:string,refresh?:number)=>string;

export const storeLinkStart: (host:string,certificate:string)=>boolean;
export const storeLinkStatus: ()=>string;
export const storeLinkCancel: ()=>void;

export const storePathsConfigure: (hosts:string,token:string,certificate:string)=>boolean;
export const storePathsStatus: (activeHost:string,elapsedSinceSwitchMs:number,inputHeld:boolean,activeAlive:boolean)=>string;
export const storePathsStop: ()=>void;

export const storeUSBInterfaces: ()=>string;

// Lifecycle-only snapshot; does not consume/reset statistics samples.
export const storeSessionFlags: ()=>number;
