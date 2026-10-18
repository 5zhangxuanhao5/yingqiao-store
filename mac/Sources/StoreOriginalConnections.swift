import AppKit
import Network
import CoreGraphics
import CryptoKit

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
   let service=NetService(domain:"local.",type:"_yingqiaostandby._tcp",name:"映桥-Mac",port:49562)
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
  guard [5,6].contains(a.count),a[0]=="STANDBY",let identity,constantEqual(a[1],identity.token),let route=StandbyCoordinator.Route(rawValue:a[3]),route.local,
   let state=StandbyCoordinator.Availability(rawValue:a[4]),(p.usb ? route == .usb:route == .lan && LocalIngress.lan(p.connection)) else{p.send("ERR local_standby_only");p.close();return true}
  var deviceID:String?,deviceName:String?
  if a.count==6 {
   let fields=a[5].split(separator:":",omittingEmptySubsequences:false).map(String.init)
   guard fields.count==3,fields[0]=="device-v1",StandbyCoordinator.identifier(fields[1]),fields[2].utf8.count<=172 else{p.close();return true}
   var encoded=fields[2].replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/");encoded+=String(repeating:"=",count:(4-encoded.count%4)%4)
   guard let data=Data(base64Encoded:encoded),data.count<=128,let name=String(data:data,encoding:.utf8),!name.isEmpty else{p.close();return true};deviceID=fields[1];deviceName=name
  }
  let id=UUID();standbyConnections[ObjectIdentifier(p)]=(p,id)
  if !availability.attach(id:id,edgeSession:a[2],route:route,availability:state,deviceID:deviceID,name:deviceName,send:{[weak p] line in p?.send(line)}){standbyConnections.removeValue(forKey:ObjectIdentifier(p));p.close()}
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
 func discoveryID(_ identity:StoreIdentity)->String{String(hex(Data(SHA256.hash(data:Data(identity.certificate.utf8)))).prefix(24))}
 func nearbyPadRows()->[(id:String,name:String,authenticated:Bool,ready:Bool)] {
  var result:[String:(id:String,name:String,authenticated:Bool,ready:Bool)]=[:]
  for p in nearbyPads.pads{result[p.id]=(p.id,p.name,false,true)}
  for p in availability.knownDevices(){result[p.id]=(p.id,p.name,true,p.ready)}
  return result.values.sorted{$0.name==$1.name ? $0.id<$1.id:$0.name.localizedStandardCompare($1.name) == .orderedAscending}
 }
 @objc func selectNearbyPad(_ sender:NSPopUpButton){
  guard let id=sender.selectedItem?.representedObject as? String else{selectedPadID=nil;return}
  requestExtensionOnPad(id)
 }
 private func requestExtensionOnPad(_ id:String){
  guard !busy,capture==nil,!nearbyInvitationPending,availability.request==nil,nearbyPadRows().contains(where:{$0.id==id && $0.ready}) else{return}
  selectedPadID=id;availability.select(id);UserDefaults.standard.set(id,forKey:"store.selectedPadID");pendingPermissionPadID=id
  guard requireMediaPermissions() else{return};pendingPermissionPadID=nil;performStartExtension(id)
 }
 @objc func startExtension(){
  guard !busy,capture==nil,!nearbyInvitationPending,availability.request==nil,padChoiceAlert==nil else{return}
  let rows=nearbyPadRows().filter{$0.ready};guard !rows.isEmpty else{statusMessage="没有发现可连接的平板，请在平板上打开映桥。";updateDashboard();return}
  if rows.count==1{requestExtensionOnPad(rows[0].id);return}
  let alert=NSAlert(),picker=NSPopUpButton(frame:NSRect(x:0,y:0,width:320,height:30),pullsDown:false)
  alert.messageText="选择扩展屏平板";alert.informativeText="发现多台平板，请选择这次要连接的设备。"
  for row in rows{let duplicate=rows.filter{$0.name==row.name}.count>1;picker.addItem(withTitle:duplicate ? row.name+" · "+String(row.id.prefix(4)).uppercased():row.name);picker.lastItem?.representedObject=row.id}
  if let selectedPadID,let item=picker.itemArray.first(where:{($0.representedObject as? String)==selectedPadID}){picker.select(item)}
  picker.setAccessibilityLabel("这次连接的平板");alert.accessoryView=picker;alert.addButton(withTitle:"开启扩展屏");alert.addButton(withTitle:"取消");padChoiceAlert=alert
  alert.beginSheetModal(for:window){[weak self,weak alert] response in DispatchQueue.main.async{
   guard let self,let alert,self.padChoiceAlert===alert else{return};self.padChoiceAlert=nil
   guard response == .alertFirstButtonReturn,let id=picker.selectedItem?.representedObject as? String else{return}
   self.requestExtensionOnPad(id)
  }}
 }
 func performStartExtension(_ id:String){
  guard mediaPermissionsReady,!busy,capture==nil,availability.request==nil else{return}
  guard listener != nil else{prepare();statusMessage="正在准备连接，请稍候再开启扩展屏。";return}
  if let route=availability.bestLocalRoute(deviceID:id){
   availability.select(id);if availability.startExtension(deviceID:id,preferred:route,hostIdle:true){statusMessage="已向平板请求开启扩展屏…"}else{statusMessage=availability.lastError};updateDashboard();return
  }
  guard nearbyPads.pads.contains(where:{$0.id==id}),let identity else{statusMessage="所选平板暂时不可连接，请稍后重试。";updateDashboard();return}
  nearbyInvitationEpoch+=1;let epoch=nearbyInvitationEpoch;nearbyInvitationPending=true;statusMessage="正在联系平板，首次连接将在 Mac 上确认…";updateDashboard()
  nearbyPads.invite(id:id,macDiscoveryID:discoveryID(identity)){[weak self] sent in
   guard let self,self.nearbyInvitationEpoch==epoch,self.nearbyInvitationPending else{return}
   if !sent{self.nearbyInvitationPending=false;self.statusMessage="未能联系所选平板，请确认两端映桥都已打开。";self.updateDashboard()}
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+25){[weak self] in guard let self,self.nearbyInvitationEpoch==epoch,self.nearbyInvitationPending,self.capture==nil else{return};self.nearbyInvitationPending=false;self.statusMessage="平板尚未响应，请保持映桥在前台后重试。";self.updateDashboard()}
 }
}
