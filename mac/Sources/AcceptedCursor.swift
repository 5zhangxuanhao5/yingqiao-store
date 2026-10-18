import AppKit
import CoreGraphics

struct CursorSample {
 let owner:UInt8,visible:Bool,acknowledgedMove:UInt64,point:CGPoint,sampledAt:UInt64
 func valid()->Bool{
  [1,2].contains(owner) && acknowledgedMove<=RemoteInput.maximumCursorSequence && point.x.isFinite && point.y.isFinite && abs(point.x)<=DesktopInputTopology.maximumCoordinate && abs(point.y)<=DesktopInputTopology.maximumCoordinate
 }
 func payload()->Data{
  var data=Data("EDC1".utf8);data.append(owner);data.append(visible ? 1:0);data.appendBE(UInt16(0));data.appendBE(acknowledgedMove)
  data.appendBE(Double(point.x).bitPattern);data.appendBE(Double(point.y).bitPattern);data.appendBE(sampledAt);return data
 }
}

// All reads of the physical position and remote MOVE acknowledgements occur on
// the main thread. Mouse-only AppKit monitors do not install a CGEvent tap or
// require an additional keyboard/system-input listener.
@MainActor final class HostCursorMonitor {
 private var globalMonitor:Any?,localMonitor:Any?,pending:DispatchWorkItem?
 private var latest:CursorSample?,lastSent:CursorSample?,lastSendTime=0.0,enabled=false
 private let input:RemoteInput,captureBounds:()->CGRect?,send:(CursorSample)->Void
 private(set) var physicalEvents=0,ignoredInjectedEvents=0,ignoredOldEvents=0,sentSamples=0
 init(input:RemoteInput,captureBounds:@escaping ()->CGRect?,send:@escaping (CursorSample)->Void){self.input=input;self.captureBounds=captureBounds;self.send=send}
 private func sample(point:CGPoint,owner:UInt8)->CursorSample?{
  guard let bounds=captureBounds(),DesktopInputTopology.valid(bounds) else{return nil}
  let value=CursorSample(owner:owner,visible:bounds.contains(point),acknowledgedMove:input.acknowledgedMoveSequence,point:point,sampledAt:monotonicNanoseconds())
  return value.valid() ? value:nil
 }
 func start(initialPoint:CGPoint?=nil,installMonitors:Bool=true){
  guard !enabled else{return};enabled=true
  let mask:NSEvent.EventTypeMask=[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged]
  if installMonitors{
   globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:mask){[weak self] event in MainActor.assumeIsolated{self?.observe(event.cgEvent)}}
   localMonitor=NSEvent.addLocalMonitorForEvents(matching:mask){[weak self] event in MainActor.assumeIsolated{self?.observe(event.cgEvent)};return event}
  }
  // This first sample also covers a completely stationary desktop.
  // A MOVE can already have been applied while startCapture was awaiting SCK.
  // Do not label a potentially lagging system position with that newer ACK.
  if input.acknowledgedMoveSequence>0{
   if let value=sample(point:input.point,owner:2){publish(value,immediately:true)}
  }else if let point=initialPoint ?? CGEvent(source:nil)?.location,input.observePhysicalPointer(point,timestamp:0,initial:true),let value=sample(point:point,owner:1){publish(value,immediately:true)}
 }
 func observe(_ event:CGEvent?){
  guard enabled,let event else{return}
  if event.getIntegerValueField(.eventSourceUserData)==RemoteInput.injectedEventMarker{ignoredInjectedEvents += 1;return}
  // A delayed physical callback must not pair its old position with a newer
  // applied remote-MOVE acknowledgement.
  if event.timestamp<=input.lastInjectedMoveTimestamp{ignoredOldEvents += 1;return}
  guard input.observePhysicalPointer(event.location,timestamp:event.timestamp),let value=sample(point:input.point,owner:1) else{return};physicalEvents += 1;publish(value)
 }
 func remoteMoved(){guard enabled,let value=sample(point:input.point,owner:2) else{return};publish(value)}
 private func publish(_ value:CursorSample,immediately:Bool=false){
  if let last=latest ?? lastSent,last.owner==value.owner,last.visible==value.visible,last.acknowledgedMove==value.acknowledgedMove,last.point==value.point{return}
  latest=value
  if immediately{pending?.cancel();pending=nil;flush();return}
  guard pending==nil else{return}
  let delay=max(0,1.0/60.0-(ProcessInfo.processInfo.systemUptime-lastSendTime))
  let task=DispatchWorkItem{[weak self] in MainActor.assumeIsolated{guard let self,self.enabled else{return};self.pending=nil;self.flush()}}
  pending=task;DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:task)
 }
 private func flush(){guard enabled,let value=latest else{return};latest=nil;lastSent=value;lastSendTime=ProcessInfo.processInfo.systemUptime;sentSamples += 1;send(value)}
 func stop(){enabled=false;pending?.cancel();pending=nil;latest=nil;lastSent=nil;if let globalMonitor{NSEvent.removeMonitor(globalMonitor)};if let localMonitor{NSEvent.removeMonitor(localMonitor)};globalMonitor=nil;localMonitor=nil}
 func stats()->[String:Any]{["enabled":enabled,"globalMonitor":globalMonitor != nil,"localMonitor":localMonitor != nil,"physicalEvents":physicalEvents,"ignoredInjectedEvents":ignoredInjectedEvents,"ignoredOldEvents":ignoredOldEvents,"sentSamples":sentSamples]}
}
