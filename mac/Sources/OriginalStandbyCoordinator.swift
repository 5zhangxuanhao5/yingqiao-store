import Foundation

// Pure control policy. Authentication and pinned TLS must succeed before attach.
// No display, encoder, input listener, power assertion, or background polling is
// created here. Each path has one external serial TLS writer.
@MainActor final class StandbyCoordinator {
 enum Route:String,CaseIterable {case usb,lan,internet;var local:Bool{self != .internet}}
 enum Availability:String {case idle,busy,backgroundUnsupported}
 enum RequestState:String {case waitingForEdge,waitingForMedia}
 struct Path {
  let id:UUID,edgeSession:String,route:Route,send:(String)->Void
  var lastSeen:TimeInterval,availability:Availability
  var rttMedianMs:Double?,rttP95Ms:Double?,goodputMbps:Double?
 }
 struct Request {
  let id:String,pathID:UUID,edgeSession:String
  var deadline:TimeInterval,state:RequestState
 }
 private(set) var paths:[Route:Path]=[:]
 private(set) var request:Request?
 private(set) var lastError=""
 private var currentEdgeSession:String?
 var onChanged:(()->Void)?
 var onClosePath:((UUID)->Void)?
 let now:()->TimeInterval
 let requestID:()->String
 init(now:@escaping()->TimeInterval,requestID:@escaping()->String){self.now=now;self.requestID=requestID}
 func attach(id:UUID,edgeSession:String,route:Route,availability:Availability,send:@escaping(String)->Void)->Bool {
  guard edgeSession.count==32,edgeSession.allSatisfy({$0.isHexDigit}) else{return false}
  if let currentEdgeSession,currentEdgeSession != edgeSession {
   cancelRequest(reason:"Edge 已重新启动，请再次连接")
   let old=Array(paths.values);paths.removeAll();for p in old{onClosePath?(p.id)}
  }
  currentEdgeSession=edgeSession
  if let old=paths[route],old.id != id {
   if request?.pathID==old.id{cancelRequest(reason:"连接正在更新，请再次连接")}
   paths.removeValue(forKey:route);onClosePath?(old.id)
  }
  paths[route]=Path(id:id,edgeSession:edgeSession,route:route,send:send,lastSeen:now(),availability:availability)
  send("READY OK standby-v1");onChanged?();return true
 }
 func heartbeat(id:UUID,availability:Availability)->Bool {
  guard let key=paths.first(where:{$0.value.id==id})?.key else{return false}
  let changed=paths[key]?.availability != availability
  paths[key]?.lastSeen=now();paths[key]?.availability=availability
  if changed{onChanged?()};return true
 }
 func metric(id:UUID,median:Double,tail:Double,goodput:Double)->Bool {
  guard median.isFinite,tail.isFinite,median>0,tail>=median,tail<=10000,goodput.isFinite,goodput>=0,goodput<=100000,
   let key=paths.first(where:{$0.value.id==id})?.key else{return false}
  paths[key]?.rttMedianMs=median;paths[key]?.rttP95Ms=tail;paths[key]?.goodputMbps=goodput;onChanged?();return true
 }
 var bestLocalRoute:Route? {
  let t=now()
  let ready=paths.values.filter{$0.route.local&&$0.availability == .idle&&t >= $0.lastSeen&&t-$0.lastSeen<=45}
  return ready.first(where:{$0.route == .usb})?.route ?? ready.sorted{score($0) < score($1)}.first?.route
 }
 private func score(_ path:Path)->Double {
  var score=(path.rttP95Ms ?? 1000)+max(0,(path.rttP95Ms ?? 0)-(path.rttMedianMs ?? 0))
  if let goodput=path.goodputMbps,goodput>0{score += 1000*40/(60*goodput);if goodput<50{score += 50*(50/goodput-1)}}else{score += 25};return score
 }
 func endExtension(sessionID:UInt32){
  guard sessionID>0 else{return}
  for p in paths.values where p.route.local{p.send("END \(sessionID)")}
 }
 func authenticatedMediaStarted(mode:String){
  guard mode=="extend",request != nil else{return}
  request=nil;lastError="";onChanged?()
 }
 func detach(id:UUID){
  guard let key=paths.first(where:{$0.value.id==id})?.key else{return}
  paths.removeValue(forKey:key)
  if request?.pathID==id{cancelRequest(reason:"Edge 连接已断开")}
  onChanged?()
 }
 // Called only by the user's Mac start action. Internet is never a fallback for
 // an extension request. A background route comparison must run before/after,
 // not synchronously block this method.
 func startExtension(preferred:Route,hostIdle:Bool)->Bool {
  expire()
  guard hostIdle,request==nil else{lastError="请先结束当前会话";onChanged?();return false}
  guard preferred.local,let p=paths[preferred],p.route.local,
   now()>=p.lastSeen,now()-p.lastSeen<=45,p.availability == .idle else{
   lastError="请保持 Edge 的映桥已打开，并连接 USB 或同一局域网";onChanged?();return false
  }
  let id=requestID()
  guard id.count==32,id.allSatisfy({$0.isHexDigit}) else{lastError="请求标识生成失败";onChanged?();return false}
  request=Request(id:id,pathID:p.id,edgeSession:p.edgeSession,deadline:now()+10,state:.waitingForEdge)
  lastError="";p.send("START \(id) extend \(preferred.rawValue)");onChanged?();return true
 }
 func acknowledge(id:UUID,requestID:String,accepted:Bool)->Bool {
  expire()
  guard var r=request,r.id==requestID,r.pathID==id,r.state == .waitingForEdge,
   paths.values.contains(where:{$0.id==id&&$0.edgeSession==r.edgeSession}) else{return false}
  if !accepted{request=nil;lastError="Edge 未能启动扩展屏";onChanged?();return true}
  r.state = .waitingForMedia;r.deadline=now()+20;request=r;onChanged?();return true
 }
 // A stream must still authenticate through the regular media handshake. ACK
 // alone never enables capture. The caller supplies the authenticated Edge's
 // process session, not a hostname or untrusted connection-service status row.
 func mediaStarted(edgeSession:String,mode:String){
  guard let r=request,r.edgeSession==edgeSession,mode=="extend" else{return}
  request=nil;lastError="";onChanged?()
 }
 func cancelRequest(reason:String=""){
  if let r=request,let p=paths.values.first(where:{$0.id==r.pathID&&$0.edgeSession==r.edgeSession}){p.send("CANCEL \(r.id)")}
  request=nil;if !reason.isEmpty{lastError=reason};onChanged?()
 }
 func expire(){
  if let r=request,now()>=r.deadline{cancelRequest(reason:"Edge 未及时响应，请检查平板上的映桥")}
 }
 func stop(){cancelRequest();let old=Array(paths.values);paths.removeAll();currentEdgeSession=nil;for p in old{onClosePath?(p.id)};onChanged?()}
 func snapshot()->[String:Any]{
  let t=now()
  return ["pending":request != nil,"requestState":request?.state.rawValue ?? "idle","lastError":lastError,
   "routes":Route.allCases.compactMap{r->[String:Any]? in guard let p=paths[r] else{return nil};var result:[String:Any] = ["kind":r.rawValue,"online":t>=p.lastSeen&&t-p.lastSeen<=45,"availability":p.availability.rawValue];if let tail=p.rttP95Ms{result["rttP95Ms"]=tail};if let goodput=p.goodputMbps{result["goodputMbps"]=goodput};return result}]
 }
}
