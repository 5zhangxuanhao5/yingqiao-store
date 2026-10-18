import AppKit
import Network
import CryptoKit
import Darwin

// Public discovery is a candidate list, never a grant of trust. A Mac-start
// invitation only asks the Pad to perform the normal explicit LINK approval.
@MainActor final class StoreNearbyPads:NSObject {
 struct Pad {let id:String,name:String,host:String,port:UInt16}
 private let browser=NetServiceBrowser()
 private var services:[String:NetService]=[:],resolved:[String:Pad]=[:]
 private var running=false,invitation:NWConnection?
 private struct USBHint{let pad:Pad;var expires:TimeInterval}
 private var usbHints:[String:USBHint]=[:],usbStartRequests:[String:TimeInterval]=[:],hintTimer:Timer?
 private let clock:()->TimeInterval,usesHintTimer:Bool
 init(clock:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime},usesHintTimer:Bool=true){self.clock=clock;self.usesHintTimer=usesHintTimer;super.init()}

 var onChanged:(()->Void)?
 var pads:[Pad]{var unique:[String:Pad]=[:];for (id,hint) in usbHints where hint.expires>clock(){unique[id]=hint.pad};for pad in resolved.values{unique[pad.id]=pad};return unique.values.sorted{$0.name==$1.name ? $0.id<$1.id:$0.name.localizedStandardCompare($1.name) == .orderedAscending}}
 func start(){guard !running else{return};running=true;browser.delegate=self;browser.searchForServices(ofType:"_yingqiaopad._udp.",inDomain:"local.")}
 func stop(){running=false;browser.stop();browser.delegate=nil;for service in services.values{service.stop();service.delegate=nil};services.removeAll();resolved.removeAll();usbHints.removeAll();usbStartRequests.removeAll();hintTimer?.invalidate();hintTimer=nil;invitation?.cancel();invitation=nil;onChanged?()}
 private func key(_ s:NetService)->String{s.domain+"/"+s.type+"/"+s.name}
 private func ipv4(_ data:Data)->String?{guard data.count>=MemoryLayout<sockaddr_in>.size else{return nil};var a=sockaddr_in();withUnsafeMutableBytes(of:&a){_ = data.copyBytes(to:$0,count:MemoryLayout<sockaddr_in>.size)};guard a.sin_family==sa_family_t(AF_INET) else{return nil};var ip=a.sin_addr,out=[CChar](repeating:0,count:Int(INET_ADDRSTRLEN));guard inet_ntop(AF_INET,&ip,&out,socklen_t(out.count)) != nil else{return nil};let host=String(cString:out);return privateLANAddress(host) ? host:nil}
 // Public USB hints are accepted only by the compiled development USB
 // DISCOVER handler. They do not authenticate, add a standby path, or start media.
 func observeUSBMetadata(_ value:String)->String? {
  #if ORIGINAL_USB_TEST
  guard let (id,name)=Self.parseUSBMetadata(value) else{return nil};pruneUSBHints()
  guard usbHints[id] != nil || usbHints.count<8 else{return nil}
  let changed=usbHints[id]?.pad.name != name;usbHints[id]=USBHint(pad:Pad(id:id,name:name,host:"127.0.0.1",port:0),expires:clock()+15)
  ensureHintTimer();if changed{onChanged?()};return id
  #else
  return nil
  #endif
 }
 func consumeUSBStartRequest(_ id:String)->Bool {
  #if ORIGINAL_USB_TEST
  guard let until=usbStartRequests.removeValue(forKey:id),until>clock(),let hint=usbHints[id],hint.expires>clock() else{return false};return true
  #else
  return false
  #endif
 }
 private static func parseUSBMetadata(_ value:String)->(String,String)?{
  guard value.utf8.count<=240 else{return nil};let parts=value.split(separator:":",omittingEmptySubsequences:false).map(String.init)
  guard parts.count==3,parts[0]=="device-v1",StandbyCoordinator.identifier(parts[1]),parts[2].utf8.count<=172 else{return nil}
  var encoded=parts[2].replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/");encoded+=String(repeating:"=",count:(4-encoded.count%4)%4)
  guard let bytes=Data(base64Encoded:encoded),bytes.count<=128,let raw=String(data:bytes,encoding:.utf8) else{return nil};let name=StandbyCoordinator.displayName(raw);return name.isEmpty ? nil:(parts[1],name)
 }
 private func pruneUSBHints(){let before=usbHints.count,t=clock();usbHints=usbHints.filter{$0.value.expires>t};usbStartRequests=usbStartRequests.filter{$0.value>t && usbHints[$0.key] != nil};if usbHints.isEmpty && usbStartRequests.isEmpty{hintTimer?.invalidate();hintTimer=nil};if before != usbHints.count{onChanged?()}}
 private func ensureHintTimer(){guard usesHintTimer,hintTimer==nil else{return};hintTimer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in DispatchQueue.main.async{self?.pruneUSBHints()}}}
 func cancelInvitation(){invitation?.cancel();invitation=nil;usbStartRequests.removeAll()}

 func invite(id:String,macDiscoveryID:String,completion:@escaping(Bool)->Void){
  guard let pad=pads.first(where:{$0.id==id}),macDiscoveryID.count==24,macDiscoveryID.allSatisfy({$0.isHexDigit}) else{completion(false);return}
  #if ORIGINAL_USB_TEST
  if let hint=usbHints[id],hint.expires>clock(){cancelInvitation();usbStartRequests[id]=clock()+20;ensureHintTimer();completion(true);return}
  #endif
  guard pad.port>0 else{completion(false);return}
  cancelInvitation();let connection=NWConnection(host:NWEndpoint.Host(pad.host),port:NWEndpoint.Port(rawValue:pad.port)!,using:.udp);invitation=connection
  var completed=false
  let finish:(Bool)->Void={[weak self,weak connection] success in guard !completed else{return};completed=true;connection?.cancel();if self?.invitation===connection{self?.invitation=nil};completion(success)}
  connection.stateUpdateHandler={[weak self,weak connection] state in DispatchQueue.main.async{
   guard let self,let connection,self.invitation===connection else{return};switch state {
   case .ready:
    guard case let .hostPort(host,_)?=connection.currentPath?.localEndpoint,privateLANAddress(host.debugDescription),!host.debugDescription.contains(":") else{finish(false);return}
    let message=Data("YQSTART1 \(macDiscoveryID) \(host.debugDescription)".utf8)
    connection.send(content:message,completion:.contentProcessed{error in DispatchQueue.main.async{finish(error==nil)}})
   case .failed,.cancelled:finish(false)
   default:break
   }
  }}
  connection.start(queue:.main);DispatchQueue.main.asyncAfter(deadline:.now()+3){finish(false)}
 }
 static func selfTest(){
  let id=String(repeating:"a",count:32),name="测试平板",encoded=Data(name.utf8).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
  precondition(parseUSBMetadata("device-v1:\(id):\(encoded)")?.1==name)
  precondition(parseUSBMetadata("device-v1:invalid:\(encoded)")==nil)
  #if ORIGINAL_USB_TEST
  var time:TimeInterval=1;let browser=StoreNearbyPads(clock:{time},usesHintTimer:false)
  precondition(browser.observeUSBMetadata("device-v1:\(id):\(encoded)")==id && browser.pads.count==1 && browser.pads[0].port==0)
  var accepted=false;browser.invite(id:id,macDiscoveryID:String(repeating:"b",count:24)){accepted=$0};precondition(accepted)
  precondition(browser.consumeUSBStartRequest(id));precondition(!browser.consumeUSBStartRequest(id))
  browser.resolved["fixture"]=Pad(id:id,name:name,host:"192.168.1.2",port:49568);precondition(browser.pads.count==1)
  browser.resolved.removeAll();time=12;_ = browser.observeUSBMetadata("device-v1:\(id):\(encoded)");time=20;precondition(browser.pads.count==1)
  time=28;browser.pruneUSBHints();precondition(browser.pads.isEmpty)
  _ = browser.observeUSBMetadata("device-v1:\(id):\(encoded)");browser.invite(id:id,macDiscoveryID:String(repeating:"b",count:24)){_ in};browser.cancelInvitation();precondition(!browser.consumeUSBStartRequest(id))
  browser.stop()
  #endif
 }

}
extension StoreNearbyPads:NetServiceBrowserDelegate,NetServiceDelegate {
 nonisolated func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool){DispatchQueue.main.async{[weak self] in guard let self,self.running,self.services.count<16 else{return};let key=self.key(service);guard self.services[key]==nil else{return};self.services[key]=service;service.delegate=self;service.resolve(withTimeout:4)}}
 nonisolated func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool){DispatchQueue.main.async{[weak self] in guard let self else{return};let key=self.key(service);self.services.removeValue(forKey:key)?.stop();self.resolved.removeValue(forKey:key);self.onChanged?()}}
 nonisolated func netServiceDidResolveAddress(_ service:NetService){DispatchQueue.main.async{[weak self] in
  guard let self,self.running,self.services[self.key(service)]===service,let txt=service.txtRecordData() else{return};let values=NetService.dictionary(fromTXTRecord:txt)
  guard let rawID=values["id"],let id=String(data:rawID,encoding:.utf8),StandbyCoordinator.identifier(id),let rawName=values["name"],rawName.count<=128,let name=String(data:rawName,encoding:.utf8),let host=service.addresses?.compactMap({self.ipv4($0)}).first,service.port==49568 else{return}
  let clean=StandbyCoordinator.displayName(name);guard !clean.isEmpty else{return};self.resolved[self.key(service)]=Pad(id:id,name:clean,host:host,port:49568);self.onChanged?()
 }}
 nonisolated func netService(_ service:NetService,didNotResolve errorDict:[String:NSNumber]){DispatchQueue.main.async{[weak self] in guard let self else{return};let key=self.key(service);self.services.removeValue(forKey:key)?.stop();self.resolved.removeValue(forKey:key);self.onChanged?()}}
}
