import Foundation
import AppKit
import Network
import Security
import CryptoKit
extension StoreHost:NetServiceDelegate {
 func advertise(_ identity:StoreIdentity){
  advertisedService?.stop();bonjourReady=false
  let service=NetService(domain:"local.",type:"_yingqiaostore._tcp.",name:Host.current().localizedName ?? "Mac",port:49563)
  let certificate=Array(identity.certificate.utf8);var values:[String:Data]=["schema":Data("store-discovery-v1".utf8),"id":Data(hex(Data(SHA256.hash(data:Data(certificate)))).prefix(24).utf8)]
  let chunks=stride(from:0,to:certificate.count,by:208).map{Data(certificate[$0..<min($0+208,certificate.count)])}
  values["count"]=Data(String(chunks.count).utf8);for (i,data) in chunks.enumerated(){values["c\(i)"]=data}
  service.schedule(in:RunLoop.main,forMode:.common);service.delegate=self;service.setTXTRecord(NetService.data(fromTXTRecord:values));service.publish();advertisedService=service
 }
 func netServiceDidPublish(_ sender:NetService){bonjourReady=true;updateDashboard()}
 func netService(_ sender:NetService,didNotPublish errorDict:[String:NSNumber]){advertisedService=nil;bonjourReady=false;statusMessage="局域网设备发现尚未准备好，请允许本地网络访问后重试。"}
 func tlsLinkCode(_ c:NWConnection)->String?{
  guard let metadata=c.metadata(definition:NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else{return nil}
  let label="EXPORTER-Yingqiao-Link-v1"
  guard let secret=label.withCString({sec_protocol_metadata_create_secret(metadata.securityProtocolMetadata,label.utf8.count,$0,32)}) else{return nil}
  var bytes=Data();(secret as DispatchData).enumerateBytes{buffer,_,_ in bytes.append(buffer.baseAddress!,count:buffer.count)}
  guard bytes.count==32 else{return nil};let n=bytes.prefix(4).reduce(UInt32(0)){($0<<8)|UInt32($1)};return String(format:"%06u",n%1_000_000)
 }
 func clearLinkPrompt(){if let alert=linkAlert,alert.window.sheetParent != nil{window.endSheet(alert.window,returnCode:.abort)};linkAlert=nil;linkPeer=nil}
 func requestLink(_ peer:LinePeer,code:String){
  guard peer !== controller,controller==nil,linkPeer==nil,let identity,code.count==6,code.allSatisfy({$0.isNumber}),tlsLinkCode(peer.connection)==code else{peer.send("ERR link_unavailable");peer.close();return}
  linkPeer=peer;let alert=NSAlert();linkAlert=alert;alert.messageText="允许这台平板连接？";alert.informativeText="请确认平板也显示 \(code)。允许后可使用键盘、触控板和触屏操作扩展桌面；以后无需再次确认。";alert.addButton(withTitle:"允许连接");alert.addButton(withTitle:"取消")
  statusMessage="平板正在请求连接，确认后自动保存此设备。"
  alert.beginSheetModal(for:window){[weak self,weak peer] response in
   guard let self,let peer,self.linkPeer===peer else{return};self.linkAlert=nil;self.linkPeer=nil
   guard response == .alertFirstButtonReturn,!peer.closed,let host=StoreIdentity.addresses().first,let json=try? identity.pairingJSON(host:host) else{peer.send("ERR denied");self.statusMessage="未允许此次连接。";return}
   peer.send("LINKED "+json);self.statusMessage="已允许平板，正在建立扩展桌面。"
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+45){[weak self,weak peer] in guard let self,let peer,self.linkPeer===peer else{return};self.clearLinkPrompt();peer.send("ERR timeout");peer.close();self.statusMessage="连接请求已到期，可在平板重新连接。"}
 }
}

extension StoreHost {
 // Independent, bounded LAN probe for Wi-Fi networks that suppress mDNS.
 // This reply is public identity only; LINK approval still authenticates TLS.
 func startDatagramDiscovery(_ identity:StoreIdentity){
  guard discoveryListener==nil else{return}
  do{
   let listener=try NWListener(using:.udp,on:49565);discoveryListener=listener
   listener.newConnectionHandler={[weak self] connection in
    guard let self,case let .hostPort(host,_)=connection.endpoint,privateLANAddress(host.debugDescription),self.discoveryPeers.count<16 else{connection.cancel();return}
    let key=ObjectIdentifier(connection);self.discoveryPeers[key]=connection;connection.start(queue:.main)
    connection.receiveMessage{[weak self] data,_,_,_ in
     
     guard let self,let data,data.count<80,let query=String(data:data,encoding:.utf8),query.hasPrefix("YQDISC1 ") else{return}
     let nonce=String(query.dropFirst(8));guard nonce.count==32,nonce.allSatisfy({$0.isHexDigit && !$0.isUppercase}) else{return}
     let now=Date();self.discoveryRates=self.discoveryRates.filter{now.timeIntervalSince($0.value)<10}
     let address=host.debugDescription;guard self.discoveryRates.count<64,self.discoveryRates[address].map({now.timeIntervalSince($0)>=0.5}) ?? true else{return};self.discoveryRates[address]=now
     let id=String(hex(Data(SHA256.hash(data:Data(identity.certificate.utf8)))).prefix(24))
     let reply:[String:Any]=["schema":"store-discovery-v1","nonce":nonce,"id":id,"name":Host.current().localizedName ?? "Mac","certificate":identity.certificate,"port":49563]
     if let bytes=try? JSONSerialization.data(withJSONObject:reply),bytes.count<=8192{connection.send(content:bytes,completion:.contentProcessed{[weak self] _ in connection.cancel();self?.discoveryPeers.removeValue(forKey:key)})}
    }
    DispatchQueue.main.asyncAfter(deadline:.now()+2){[weak self] in connection.cancel();self?.discoveryPeers.removeValue(forKey:key)}
   }
   listener.stateUpdateHandler={[weak self] state in if case .failed=state{self?.discoveryListener=nil}}
   listener.start(queue:.main)
  }catch{discoveryListener=nil}
 }
}
