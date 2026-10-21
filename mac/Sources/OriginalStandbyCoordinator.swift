import Foundation

// One authenticated persistent control connection per device and local route.
// A process session identifies a running Pad; an optional random installation
// identifier groups its routes across restarts. Neither is a hardware serial.
@MainActor final class StandbyCoordinator {
 enum Route:String,CaseIterable {case usb,lan,internet;var local:Bool{self != .internet}}
 enum Availability:String {case idle,busy,backgroundUnsupported}
 enum RequestState:String {case waitingForEdge,waitingForMedia}
 struct Path {let id:UUID,deviceID:String,edgeSession:String,route:Route,send:(String)->Void;var lastSeen:TimeInterval,availability:Availability;var rttMedianMs:Double?,rttP95Ms:Double?,goodputMbps:Double?}
 struct Device {let id:String;var session:String,name:String,paths:[Route:UUID]}
 struct Request {let id:String,pathID:UUID,deviceID:String,edgeSession:String;var deadline:TimeInterval,state:RequestState}
 private(set) var paths:[UUID:Path]=[:]
 private(set) var devices:[String:Device]=[:]
 private(set) var request:Request?,selectedDeviceID:String?,activeDeviceID:String?
 private(set) var lastError=""
 var onChanged:(()->Void)?,onClosePath:((UUID)->Void)?
 let now:()->TimeInterval,requestID:()->String
 init(now:@escaping()->TimeInterval,requestID:@escaping()->String){self.now=now;self.requestID=requestID}
 static func identifier(_ value:String)->Bool{value.count==32 && value.allSatisfy{$0.isHexDigit}}
 static func displayName(_ value:String)->String{String(String.UnicodeScalarView(value.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0)}.prefix(64)))}
 private func fresh(_ p:Path)->Bool{let t=now();return t>=p.lastSeen && t-p.lastSeen<=45}
 func attach(id:UUID,edgeSession:String,route:Route,availability:Availability,deviceID:String?=nil,name:String?=nil,send:@escaping(String)->Void)->Bool {
  guard Self.identifier(edgeSession),route.local else{return false}
  let key=deviceID.flatMap{Self.identifier($0) ? $0:nil} ?? edgeSession
  guard devices[key] != nil || devices.count<8 else{return false}
  if let previous=devices[key],previous.session != edgeSession {
   if request?.deviceID==key{cancelRequest(reason:"平板已重新启动，请再次连接")}
   let old=Array(previous.paths.values);devices[key]=nil
   for item in old{paths[item]=nil;onClosePath?(item)}
  }
  var device=devices[key] ?? Device(id:key,session:edgeSession,name:"平板 · "+String(key.prefix(4)).uppercased(),paths:[:])
  if let name{let clean=Self.displayName(name);if !clean.isEmpty{device.name=clean}}
  if let old=device.paths[route],old != id {
   if request?.pathID==old{cancelRequest(reason:"连接正在更新，请再次连接")}
   paths[old]=nil;onClosePath?(old)
  }
  device.paths[route]=id;devices[key]=device
  paths[id]=Path(id:id,deviceID:key,edgeSession:edgeSession,route:route,send:send,lastSeen:now(),availability:availability)
  if selectedDeviceID==nil{selectedDeviceID=key}
  send("READY OK standby-v1");onChanged?();return true
 }
 func heartbeat(id:UUID,availability:Availability)->Bool {guard var p=paths[id] else{return false};let changed=p.availability != availability;p.lastSeen=now();p.availability=availability;paths[id]=p;if changed{onChanged?()};return true}
 func metric(id:UUID,median:Double,tail:Double,goodput:Double)->Bool {
  guard median.isFinite,tail.isFinite,median>0,tail>=median,tail<=10000,goodput.isFinite,goodput>=0,goodput<=100000,var p=paths[id] else{return false};p.rttMedianMs=median;p.rttP95Ms=tail;p.goodputMbps=goodput;paths[id]=p;onChanged?();return true
 }
 func knownDevices()->[(id:String,name:String,ready:Bool)] {devices.values.filter{d in d.paths.values.contains{if let p=paths[$0]{return fresh(p)};return false}}.map{($0.id,$0.name,bestLocalRoute(deviceID:$0.id) != nil)}.sorted{$0.id<$1.id}}
 func availableDevices()->[(id:String,name:String)] {
  devices.values.filter{device in device.paths.values.contains{if let p=paths[$0]{return fresh(p) && p.availability == .idle};return false}}.map{($0.id,$0.name)}.sorted{$0.name==$1.name ? $0.id<$1.id:$0.name.localizedStandardCompare($1.name) == .orderedAscending}
 }
 func select(_ id:String){guard devices[id] != nil else{return};selectedDeviceID=id;onChanged?()}
 func bestLocalRoute(deviceID:String)->Route? {
  guard let d=devices[deviceID] else{return nil};let ready=d.paths.values.compactMap{paths[$0]}.filter{$0.route.local && fresh($0) && $0.availability == .idle}
  return ready.sorted{let a=score($0),b=score($1);return a==b ? ($0.route == .usb && $1.route != .usb):a<b}.first?.route
 }
 var bestLocalRoute:Route?{if let selectedDeviceID,let route=bestLocalRoute(deviceID:selectedDeviceID){return route};guard let first=availableDevices().first else{return nil};return bestLocalRoute(deviceID:first.id)}
 private func score(_ p:Path)->Double {var result=(p.rttP95Ms ?? 1000)+max(0,(p.rttP95Ms ?? 0)-(p.rttMedianMs ?? 0));if let speed=p.goodputMbps,speed>0{result+=1000*40/(60*speed);if speed<50{result+=50*(50/speed-1)}}else{result+=25};return result}
 func startExtension(deviceID:String,preferred:Route,hostIdle:Bool)->Bool {
  expire();guard hostIdle,request==nil else{lastError="请先结束当前会话";onChanged?();return false}
  guard preferred.local,let d=devices[deviceID],let pathID=d.paths[preferred],let p=paths[pathID],fresh(p),p.availability == .idle else{lastError="平板暂时不可连接，请保持映桥已打开";onChanged?();return false}
  let id=requestID();guard Self.identifier(id) else{return false};selectedDeviceID=deviceID
  request=Request(id:id,pathID:p.id,deviceID:deviceID,edgeSession:p.edgeSession,deadline:now()+10,state:.waitingForEdge)
  lastError="";p.send("START \(id) extend \(preferred.rawValue)");onChanged?();return true
 }
 func startExtension(preferred:Route,hostIdle:Bool)->Bool {guard let id=selectedDeviceID ?? availableDevices().first?.id else{return false};return startExtension(deviceID:id,preferred:preferred,hostIdle:hostIdle)}
 func acknowledge(id:UUID,requestID:String,accepted:Bool)->Bool {
  expire();guard var r=request,r.id==requestID,r.pathID==id,r.state == .waitingForEdge,let p=paths[id],p.edgeSession==r.edgeSession else{return false}
  if !accepted{request=nil;lastError="平板未能启动扩展屏";onChanged?();return true};r.state = .waitingForMedia;r.deadline=now()+20;request=r;onChanged?();return true
 }
 // Even a valid host token cannot accidentally satisfy another Pad's pending
 // start. The media handshake names the same random process session as STANDBY.
 func mediaSession(_ declared:String?,route:Route)->String? {
  let matches=paths.values.filter{$0.route==route && fresh($0) && (declared==nil || $0.edgeSession==declared)}
  let sessions=Set(matches.map(\.edgeSession));guard sessions.count==1,let session=sessions.first else{return nil}
  if let request,request.edgeSession != session{return nil};return session
 }
 func mediaStarted(edgeSession:String,mode:String){guard mode=="extend",let p=paths.values.first(where:{$0.edgeSession==edgeSession && fresh($0)}) else{return};activeDeviceID=p.deviceID;selectedDeviceID=p.deviceID;if request?.edgeSession==edgeSession{request=nil};lastError="";onChanged?()}
 func mediaEnded(){activeDeviceID=nil;onChanged?()}
 func deviceForSession(_ session:String)->String?{devices.values.first{$0.session==session}?.id}
 func processForDevice(_ device:String)->String?{devices[device]?.session}
 func liveSession(_ session:String)->Bool{paths.values.contains{$0.edgeSession==session && fresh($0)}}
 func ownsPath(_ id:UUID,session:String)->Bool{guard let p=paths[id] else{return false};return p.edgeSession==session && fresh(p)}
 func endParkedExtension(owner:String,sessionID:UInt32){for p in paths.values where p.edgeSession==owner && fresh(p){p.send("END \(sessionID)")}}
 func endExtension(sessionID:UInt32){guard sessionID>0,let activeDeviceID else{return};for p in paths.values where p.deviceID==activeDeviceID && p.route.local{p.send("END \(sessionID)")}}
 func detach(id:UUID){guard let p=paths.removeValue(forKey:id) else{return};devices[p.deviceID]?.paths[p.route]=nil;if devices[p.deviceID]?.paths.isEmpty==true{devices[p.deviceID]=nil;if selectedDeviceID==p.deviceID{selectedDeviceID=nil}};if request?.pathID==id{cancelRequest(reason:"平板连接已断开")};onChanged?()}
 func cancelRequest(reason:String=""){if let r=request,let p=paths[r.pathID]{p.send("CANCEL \(r.id)")};request=nil;if !reason.isEmpty{lastError=reason};onChanged?()}
 func expire(){if let r=request,now()>=r.deadline{cancelRequest(reason:"平板未及时响应，请检查平板上的映桥")}}
 func stop(){cancelRequest();let ids=Array(paths.keys);paths.removeAll();devices.removeAll();selectedDeviceID=nil;activeDeviceID=nil;for id in ids{onClosePath?(id)};onChanged?()}
 func snapshot()->[String:Any]{let active=paths.values.filter{fresh($0)};return ["pending":request != nil,"requestState":request?.state.rawValue ?? "idle","lastError":lastError,"devices":availableDevices().map{["id":$0.id,"name":$0.name]},"selectedDeviceID":selectedDeviceID ?? "","routes":active.map{p in ["kind":p.route.rawValue,"online":true,"availability":p.availability.rawValue,"deviceID":p.deviceID] as [String:Any]}]}
 static func selfTest(){
  var now:TimeInterval=1;var sentA:[String]=[],sentB:[String]=[],closed:[UUID]=[]
  let c=StandbyCoordinator(now:{now},requestID:{String(repeating:"f",count:32)}),a=String(repeating:"a",count:32),b=String(repeating:"b",count:32),aLAN=UUID(),aUSB=UUID(),bLAN=UUID()
  c.onClosePath={closed.append($0)}
  precondition(c.attach(id:aLAN,edgeSession:a,route:.lan,availability:.idle,send:{sentA.append($0)}))
  precondition(c.attach(id:aUSB,edgeSession:a,route:.usb,availability:.idle,send:{sentA.append($0)}))
  precondition(c.attach(id:bLAN,edgeSession:b,route:.lan,availability:.idle,send:{sentB.append($0)}));precondition(c.availableDevices().count==2 && c.paths.count==3 && closed.isEmpty)
  _ = c.metric(id:aUSB,median:20,tail:24,goodput:80);_ = c.metric(id:aLAN,median:3,tail:4,goodput:100)
  precondition(c.bestLocalRoute(deviceID:a) == .lan)
  _ = c.metric(id:aUSB,median:1,tail:2,goodput:200);precondition(c.bestLocalRoute(deviceID:a) == .usb)
  precondition(c.startExtension(deviceID:b,preferred:.lan,hostIdle:true))
  precondition(!sentA.contains{$0.hasPrefix("START ")} && sentB.contains{$0.hasPrefix("START ")})
  precondition(c.mediaSession(a,route:.lan)==nil && c.mediaSession(nil,route:.lan)==nil && c.mediaSession(b,route:.lan)==b)
  c.mediaStarted(edgeSession:b,mode:"extend");c.endExtension(sessionID:1)
  precondition(!sentA.contains("END 1") && sentB.contains("END 1"))
  c.detach(id:aLAN);precondition(c.paths[bLAN] != nil && c.bestLocalRoute(deviceID:a) == .usb && c.availableDevices().count==2)
  c.detach(id:aUSB);precondition(c.paths[bLAN] != nil && c.availableDevices().count==1 && c.availableDevices().first?.id==b)
  let stable=String(repeating:"c",count:32),first=String(repeating:"d",count:32),second=String(repeating:"e",count:32),old=UUID(),new=UUID()
  precondition(c.attach(id:old,edgeSession:first,route:.lan,availability:.idle,deviceID:stable,name:"我的平板",send:{_ in}))
  precondition(c.attach(id:new,edgeSession:second,route:.lan,availability:.idle,deviceID:stable,name:"我的平板",send:{_ in}))
  precondition(c.paths[old]==nil && c.paths[new] != nil && c.paths[bLAN] != nil && closed.contains(old))
  precondition(c.liveSession(b) && c.ownsPath(bLAN,session:b) && !c.ownsPath(bLAN,session:second))
  c.mediaEnded();c.endParkedExtension(owner:b,sessionID:9);precondition(sentB.contains("END 9"))
  now=50;precondition(c.availableDevices().isEmpty && !c.liveSession(b) && !c.ownsPath(bLAN,session:b))
 }
}
