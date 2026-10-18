import Foundation
import CoreGraphics
import ApplicationServices

struct DesktopInputTopology {
 static let maximumDisplays=8,maximumCoordinate:Double=1_000_000,maximumDimension:Double=65_536
 let capture:CGRect,displays:[CGRect]
 static func valid(_ rect:CGRect)->Bool{
  let values=[rect.minX,rect.minY,rect.width,rect.height,rect.maxX,rect.maxY]
  return values.allSatisfy{$0.isFinite && abs($0)<=maximumCoordinate} && rect.width>=1 && rect.height>=1 && rect.width<=maximumDimension && rect.height<=maximumDimension
 }
 static func read(captureID:CGDirectDisplayID)->DesktopInputTopology?{
  var ids=[CGDirectDisplayID](repeating:0,count:32),count:UInt32=0
  guard CGGetActiveDisplayList(UInt32(ids.count),&ids,&count) == .success,count>0,Int(count)<=ids.count else{return nil}
  var capture:CGRect?,rects:[CGRect]=[]
  for id in ids.prefix(Int(count)){
   let rect=CGDisplayBounds(id);guard valid(rect) else{return nil}
   if id==captureID{capture=rect}
   if !rects.contains(rect){rects.append(rect)}
  }
  guard let capture,!rects.isEmpty,rects.count<=maximumDisplays else{return nil}
  rects.sort{a,b in a.minX==b.minX ? (a.minY==b.minY ? a.width<b.width:a.minY<b.minY):a.minX<b.minX}
  return DesktopInputTopology(capture:capture,displays:rects)
 }
 func valid()->Bool{Self.valid(capture) && !displays.isEmpty && displays.count<=Self.maximumDisplays && displays.allSatisfy(Self.valid) && displays.contains(capture)}
 static func project(_ point:CGPoint,to rects:[CGRect])->CGPoint?{
  guard point.x.isFinite,point.y.isFinite else{return nil};var best:CGPoint?,distance=Double.infinity
  for rect in rects where valid(rect){
   let candidate=CGPoint(x:min(rect.maxX-0.001,max(rect.minX,point.x)),y:min(rect.maxY-0.001,max(rect.minY,point.y)))
   let delta=hypot(point.x-candidate.x,point.y-candidate.y)
   if delta<distance{best=candidate;distance=delta}
  };return best
 }
 func wireFields()->String{
  func fields(_ rect:CGRect)->[String]{[rect.minX,rect.minY,rect.width,rect.height].map{String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),Double($0))}}
  return " desktop-v1 "+(fields(capture)+[String(displays.count)]+displays.flatMap(fields)).joined(separator:" ")
 }
}

final class RemoteInput {
 static let maximumCursorSequence:UInt64=9_007_199_254_740_991
 static let injectedEventMarker:Int64=0x45444C4D
 // A remote controller must track its generated events independently of physical input.
 let eventSource=CGEventSource(stateID:.privateState)
 var remoteCapsLock=false
 var lastClickTime:[Int:Double]=[:],lastClickPoint:[Int:CGPoint]=[:],clickCounts:[Int:Int]=[:]
 var magnifying=false,scrollEvents=0,magnifyEvents=0
 var eventSink:((CGEvent)->Void)?
 func post(_ event:CGEvent?){guard let event else{return};event.setIntegerValueField(.eventSourceUserData,value:Self.injectedEventMarker);if let eventSink{eventSink(event)}else{event.post(tap:.cghidEventTap)}}
 private(set) var acknowledgedMoveSequence:UInt64=0,lastInjectedMoveTimestamp:UInt64=0
 var displayID:CGDirectDisplayID=CGMainDisplayID(),pressed:[String:CGKeyCode]=[:],buttons=Set<Int>(),point=CGPoint.zero,ctrlToCommand=true
 private(set) var desktopTopology:DesktopInputTopology?,allowsAcrossDisplays=false,desktopLayoutChanged=false
 var liveTopology=false
 var onTopologyChanged:((DesktopInputTopology)->Void)?
 private var lastTopologyRefresh=0.0,topologyAvailable=false
 private var releaseDisplayRects:[CGRect]=[]
 // The test sink/provider avoids both system input posting and actual display changes.
 var topologyProvider:((CGDirectDisplayID)->DesktopInputTopology?)?
 private func readTopology()->DesktopInputTopology?{if let topologyProvider{return topologyProvider(displayID)};return DesktopInputTopology.read(captureID:displayID)}
 func configure(displayID:CGDirectDisplayID,extended:Bool)throws{
  self.displayID=displayID;allowsAcrossDisplays=extended;desktopLayoutChanged=false
  acknowledgedMoveSequence=0;lastInjectedMoveTimestamp=0
  desktopTopology=nil;topologyAvailable=false;releaseDisplayRects=[]
  guard let topology=readTopology(),topology.valid() else{throw NSError(domain:"InputTopology",code:1,userInfo:[NSLocalizedDescriptionKey:"显示器布局暂不可用，请重新连接"])}
  desktopTopology=topology;releaseDisplayRects=topology.displays;topologyAvailable=true;lastTopologyRefresh=ProcessInfo.processInfo.systemUptime;point=topology.capture.origin
 }
 @discardableResult func refreshDesktopTopology(force:Bool=false)->Bool{
  guard allowsAcrossDisplays else{return true};guard !desktopLayoutChanged else{return false};let now=ProcessInfo.processInfo.systemUptime
  if !force && now-lastTopologyRefresh<0.25{return topologyAvailable && !desktopLayoutChanged}
  lastTopologyRefresh=now
  guard let next=readTopology(),next.valid(),let original=desktopTopology else{topologyAvailable=false;return false}
  releaseDisplayRects=next.displays
  if next.capture != original.capture || next.displays != original.displays {
   guard liveTopology else{desktopLayoutChanged=true;return false}
   desktopTopology=next;topologyAvailable=true
   // Release held input before rebasing; host gates new pointer input until
   // the client has adopted and acknowledged this exact layout revision.
   reset();point=DesktopInputTopology.project(point,to:next.displays) ?? next.capture.origin
   onTopologyChanged?(next);return true
  }
  desktopTopology=next;topologyAvailable=true;return true
 }
 @discardableResult func observePhysicalPointer(_ next:CGPoint,timestamp:UInt64,initial:Bool=false)->Bool{
  guard next.x.isFinite,next.y.isFinite,abs(next.x)<=DesktopInputTopology.maximumCoordinate,abs(next.y)<=DesktopInputTopology.maximumCoordinate,
   initial || timestamp>lastInjectedMoveTimestamp else{return false}
  if allowsAcrossDisplays{
   guard refreshDesktopTopology(),let topology=desktopTopology,topology.displays.contains(where:{$0.contains(next)}) else{return false}
  }
  // Physical motion transfers the position used by later remote clicks and
  // scrolling, without posting another MOVE or advancing an Edge sequence.
  point=next;return true
 }
 let ohKeys:[Int:CGKeyCode]=[2017:0, 2035:1, 2020:2, 2022:3, 2024:4, 2023:5, 2042:6, 2040:7, 2019:8, 2038:9, 2018:11, 2033:12, 2039:13, 2021:14, 2034:15, 2041:16, 2036:17, 2001:18, 2002:19, 2003:20, 2004:21, 2006:22, 2005:23, 2058:24, 2009:25, 2007:26, 2057:27, 2008:28, 2000:29, 2060:30, 2031:31, 2037:32, 2059:33, 2025:34, 2032:35, 2028:37, 2026:38, 2063:39, 2027:40, 2062:41, 2061:42, 2043:43, 2064:44, 2030:45, 2029:46, 2044:47, 2049:48, 2050:49, 2056:50, 2055:51, 2070:53, 2076:55, 2077:54, 2047:56, 2074:57, 2045:58, 2072:59, 2048:60, 2046:61, 2073:62, 0:63, 2090:122, 2091:120, 2092:99, 2093:118, 2094:96, 2095:97, 2096:98, 2097:100, 2098:101, 2099:109, 2100:103, 2101:111, 2081:115, 2082:119, 2068:116, 2069:121, 2071:117, 2014:123, 2015:124, 2013:125, 2012:126, 2054:36]
 var flags:CGEventFlags {
  let codes=Set(pressed.values);var f=CGEventFlags()
  if codes.contains(55)||codes.contains(54){f.insert(.maskCommand)}
  if codes.contains(56)||codes.contains(60){f.insert(.maskShift)}
  if codes.contains(58)||codes.contains(61){f.insert(.maskAlternate)}
  if codes.contains(59)||codes.contains(62){f.insert(.maskControl)}
  if remoteCapsLock{f.insert(.maskAlphaShift)}
  // The HID aggregate can already contain flags from our own posted events.
  // Reusing it on modifier-up would reassert Command and strand Cmd+Tab.
  return f
 }
 @discardableResult func move(_ x:Double,_ y:Double,sequence:UInt64?=nil)->Bool{
  guard eventSink != nil || AXIsProcessTrusted(),x.isFinite,y.isFinite else{return false}
  if let sequence{guard sequence>acknowledgedMoveSequence,sequence<=Self.maximumCursorSequence else{return false}}
  if allowsAcrossDisplays{
   guard refreshDesktopTopology(),let topology=desktopTopology else{return false}
   let requested=CGPoint(x:topology.capture.minX+x*topology.capture.width,y:topology.capture.minY+y*topology.capture.height)
   guard requested.x.isFinite,requested.y.isFinite,abs(requested.x)<=DesktopInputTopology.maximumCoordinate,abs(requested.y)<=DesktopInputTopology.maximumCoordinate,
    let projected=DesktopInputTopology.project(requested,to:topology.displays) else{return false};point=projected
  }else{
   let bounds:CGRect
   if let topologyProvider{guard let topology=topologyProvider(displayID),topology.valid() else{return false};bounds=topology.capture}
   else{bounds=CGDisplayBounds(displayID)}
   guard DesktopInputTopology.valid(bounds) else{return false}
   point=CGPoint(x:bounds.minX+min(1,max(0,x))*max(1,bounds.width-1),y:bounds.minY+min(1,max(0,y))*max(1,bounds.height-1))
  }
  let type:CGEventType=buttons.contains(0) ? .leftMouseDragged:(buttons.contains(1) ? .rightMouseDragged:.mouseMoved)
  guard let event=CGEvent(mouseEventSource:eventSource,mouseType:type,mouseCursorPosition:point,mouseButton:buttons.contains(1) ? .right:.left) else{return false}
  event.flags=flags;lastInjectedMoveTimestamp=event.timestamp;post(event)
  if let sequence{acknowledgedMoveSequence=sequence};return true
 }
 func button(_ b:Int,_ down:Bool,clickCount:Int?=nil){
  guard eventSink != nil || AXIsProcessTrusted(),b>=0,b<=2 else{return}
  if allowsAcrossDisplays{
   let available=refreshDesktopTopology();if down && !available{return}
   if let projected=DesktopInputTopology.project(point,to:releaseDisplayRects){point=projected}
  }
  if down {
   guard !buttons.contains(b) else{return}
   let now=ProcessInfo.processInfo.systemUptime,previous=lastClickPoint[b] ?? CGPoint(x:-10000,y:-10000)
   let nearby=hypot(point.x-previous.x,point.y-previous.y)<=5
   let successive=now-(lastClickTime[b] ?? -1)<0.5 && nearby
   clickCounts[b]=clickCount.map{max(1,min(3,$0))} ?? (successive ? min(3,(clickCounts[b] ?? 0)+1):1)
   lastClickTime[b]=now;lastClickPoint[b]=point;buttons.insert(b)
  }else{guard buttons.remove(b) != nil else{return}}
  let type:CGEventType = b==0 ? (down ? .leftMouseDown:.leftMouseUp):(b==1 ? (down ? .rightMouseDown:.rightMouseUp):(down ? .otherMouseDown:.otherMouseUp))
  let event=CGEvent(mouseEventSource:eventSource,mouseType:type,mouseCursorPosition:point,mouseButton:CGMouseButton(rawValue:UInt32(b==1 ? 1:b)) ?? .left);event?.flags=flags
  event?.setIntegerValueField(.mouseEventClickState,value:Int64(clickCounts[b] ?? 1));post(event)
 }
 func scroll(_ y:Int32,_ x:Int32,phase:Int=0){
  guard eventSink != nil || AXIsProcessTrusted() else{return}
  let e=CGEvent(scrollWheelEvent2Source:eventSource,units:.pixel,wheelCount:2,wheel1:y,wheel2:x,wheel3:0)
  e?.location=point;e?.flags=flags
  if phase != 0{e?.setIntegerValueField(.scrollWheelEventScrollPhase,value:Int64(phase));e?.setIntegerValueField(.scrollWheelEventMomentumPhase,value:0)}
  scrollEvents += 1;post(e)
 }
 func magnify(_ delta:Double,phase:Int){
  guard eventSink != nil || AXIsProcessTrusted(),delta.isFinite,[1,2,4,8].contains(phase) else{return}
  if phase==2 && !magnifying{magnify(0,phase:1)}
  if phase==4 || phase==8{guard magnifying else{return}}
  guard let event=makeMagnifyEvent(source:eventSource,delta:max(-0.5,min(0.5,delta)),phase:UInt32(phase)) else{return}
  event.location=point;event.flags=flags.union(CGEventFlags(rawValue:0x100));magnifying=phase==1 || phase==2;magnifyEvents += 1
  if let eventSink{eventSink(event)}else{event.post(tap:.cgSessionEventTap)}
 }
 func key(_ source:String,_ code:CGKeyCode,_ down:Bool){
  guard eventSink != nil || AXIsProcessTrusted(),code != 63 else{return}
  let repeated=pressed[source] != nil,modifier=(54...62).contains(code)
  if down {if repeated && modifier{return};pressed[source]=code}
  else {guard pressed.removeValue(forKey:source) != nil else{return}}
  if code==57 && down{remoteCapsLock.toggle()}
  let e=CGEvent(keyboardEventSource:eventSource,virtualKey:code,keyDown:down)
  if modifier{e?.type = .flagsChanged}
  e?.flags=flags
  if repeated && down{e?.setIntegerValueField(.keyboardEventAutorepeat,value:1)}
  post(e)
 }
 // Pad Fn controls its own layout; forwarding it can switch the Mac input source.
 func ohKey(_ code:Int,_ down:Bool){guard code != 0 else{return};var mapped=ohKeys[code];if ctrlToCommand && (code==2072||code==2073){mapped=code==2072 ? 55:54};if let mapped{key("oh\(code)",mapped,down)}}
 func text(_ value:String){guard AXIsProcessTrusted(),!value.isEmpty,value.utf16.count<=1024 else{return};let chars=Array(value.utf16);for down in [true,false]{let e=CGEvent(keyboardEventSource:eventSource,virtualKey:0,keyDown:down);e?.flags=flags;chars.withUnsafeBufferPointer{e?.keyboardSetUnicodeString(stringLength:chars.count,unicodeString:$0.baseAddress!)};post(e)}}
 func reset(){magnify(0,phase:4);for (source,code) in Array(pressed){key(source,code,false)};for b in Array(buttons){button(b,false)};pressed.removeAll();buttons.removeAll();lastClickTime.removeAll();lastClickPoint.removeAll();clickCounts.removeAll();remoteCapsLock=false}
}
