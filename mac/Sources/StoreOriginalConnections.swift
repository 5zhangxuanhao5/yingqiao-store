import AppKit
import Network
import CoreGraphics

// Original persistent standby protocol. USB debug compatibility is explicitly
// compiled only for the development baseline, never silently a consumer route.
extension StoreHost {
 func startOriginalLocalConnections(_ identity:StoreIdentity){
  guard standbyListener==nil else{return}
  do {
   let tcp=NWProtocolTCP.Options();tcp.noDelay=true;tcp.enableKeepalive=true
   let parameters=NWParameters(tls:try identity.tlsOptions(),tcp:tcp);parameters.allowLocalEndpointReuse=true
   let standby=try NWListener(using:parameters,on:49562);standbyListener=standby
   standby.newConnectionHandler={[weak self] connection in DispatchQueue.main.async{
    let loopback=LocalIngress.loopback(connection)
    #if ORIGINAL_USB_TEST
    self?.accept(connection,usb:loopback,standby:true,debugUSB:loopback)
    #else
    if loopback{connection.cancel()}else{self?.accept(connection,standby:true)}
    #endif
   }};standby.start(queue:.main)
   let service=NetService(domain:"local.",type:"_yingqiaostandby._tcp",name:"映桥测试版-Mac",port:49562)
   service.schedule(in:.main,forMode:.common);service.publish();standbyService=service
   #if ORIGINAL_USB_TEST
   let localTCP=NWProtocolTCP.Options();localTCP.noDelay=true
   let local=NWParameters(tls:try identity.tlsOptions(),tcp:localTCP)
   local.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:49561);local.allowLocalEndpointReuse=true
   let media=try NWListener(using:local);originalUSBListener=media
   media.newConnectionHandler={[weak self] connection in DispatchQueue.main.async{self?.accept(connection,usb:true,debugUSB:true)}}
   media.start(queue:.main);originalUSB.start()
   #endif
  }catch{statusMessage="本地备用连接未准备好："+error.localizedDescription}
 }
 func handleStandby(_ p:LinePeer,_ a:[String])->Bool {
  guard p.standby else{return false}
  if let entry=standbyConnections[ObjectIdentifier(p)] {
   switch a.first {
   case "HOST":if a.count==1{p.send("HOST "+(LocalIngress.addresses().first ?? "none"))}else{p.close()}
   case "RTT":if a.count==2,a[1].count<=32,a[1].allSatisfy({$0.isHexDigit}){p.send("RTT \(a[1])")}else{p.close()}
   case "BURST":if a.count==2,a[1].count<=32,a[1].allSatisfy({$0.isHexDigit}){
    if controller != nil || busy{p.send("BURST_SKIP \(a[1])")}else{let line="BURST \(a[1]) "+String(repeating:"x",count:1024);for _ in 0..<64{p.send(line)}}
   }else{p.close()}
   case "METRIC":if a.count==4,let median=Double(a[1]),let tail=Double(a[2]),let goodput=Double(a[3]){_ = availability.metric(id:entry.id,median:median,tail:tail,goodput:goodput)}else{p.close()}
   case "ALIVE":if a.count==2,let state=StandbyCoordinator.Availability(rawValue:a[1]){_ = availability.heartbeat(id:entry.id,availability:state);p.send("ALIVE OK")}else{p.close()}
   case "ACK":if a.count==3,["0","1"].contains(a[2]){_ = availability.acknowledge(id:entry.id,requestID:a[1],accepted:a[2]=="1")}else{p.close()}
   default:p.close()
   };return true
  }
  guard a.count==5,a[0]=="STANDBY",let identity,constantEqual(a[1],identity.token),let route=StandbyCoordinator.Route(rawValue:a[3]),route.local,
   let state=StandbyCoordinator.Availability(rawValue:a[4]),(p.usb ? route == .usb:route == .lan && LocalIngress.lan(p.connection)) else{p.send("ERR local_standby_only");p.close();return true}
  let id=UUID();standbyConnections[ObjectIdentifier(p)]=(p,id)
  if !availability.attach(id:id,edgeSession:a[2],route:route,availability:state,send:{[weak p] line in p?.send(line)}){standbyConnections.removeValue(forKey:ObjectIdentifier(p));p.close()}
  return true
 }
 func syncRequestTimer(){
  if availability.request==nil{requestTimer?.invalidate();requestTimer=nil;return}
  guard requestTimer==nil else{return}
  requestTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in DispatchQueue.main.async{self?.availability.expire()}}
 }
 func checkOriginalDesktopTopology()->Bool {
  if let id=capture?.displayID,CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
   var transaction:CGDisplayConfigRef?
   if CGBeginDisplayConfiguration(&transaction) == .success,let transaction {
    if CGConfigureDisplayMirrorOfDisplay(transaction,id,kCGNullDirectDisplay) == .success{_ = CGCompleteDisplayConfiguration(transaction,.forSession)}else{CGCancelDisplayConfiguration(transaction)}
   }
  }
  if !input.refreshDesktopTopology(){let now=ProcessInfo.processInfo.systemUptime;if topologyUnavailableSince==nil{topologyUnavailableSince=now};if now-(topologyUnavailableSince ?? now)>5{failSession("扩展屏已不可用，请重新连接");return false}}else{topologyUnavailableSince=nil};return true
 }
 @objc func startExtension(){
  guard listener != nil else{prepare();return}
  guard let route=availability.bestLocalRoute else{statusMessage="请保持平板上的映桥测试版已打开，并连接数据线或同一局域网。";updateDashboard();return}
  if availability.startExtension(preferred:route,hostIdle:capture==nil && !busy){statusMessage="已向平板请求扩展屏…"}else{statusMessage=availability.lastError};updateDashboard()
 }
}
