import Foundation
import Network
import CryptoKit

enum StoreUSB {
 static func status()->[String:Any]{guard let text=YQUSBStatus() else{return [:]};defer{free(text)};return (try? JSONSerialization.jsonObject(with:Data(String(cString:text).utf8))) as? [String:Any] ?? [:]}
 static func address()->String?{let value=status()["address"] as? String;return value.flatMap{privateLANAddress($0) ? $0:nil}}
}
extension StoreHost {
 func startUSB(_ identity:StoreIdentity){
  guard usbListener==nil else{return}
  do {
   let tcp=NWProtocolTCP.Options();tcp.noDelay=true;let parameters=NWParameters(tls:try identity.tlsOptions(),tcp:tcp)
   parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:49566)
   let listener=try NWListener(using:parameters,on:49566);usbListener=listener
   listener.newConnectionHandler={[weak self] connection in self?.accept(connection,usb:true)}
   listener.stateUpdateHandler={state in if case .ready=state {
    let info:[String:Any]=["schema":"store-discovery-v1","id":String(hex(Data(SHA256.hash(data:Data(identity.certificate.utf8)))).prefix(24)),"name":Host.current().localizedName ?? "Mac","certificate":identity.certificate,"port":49563]
    if let data=try? JSONSerialization.data(withJSONObject:info),let text=String(data:data,encoding:.utf8){text.withCString{YQUSBStart($0)}}
   }}
   listener.start(queue:.main)
  }catch{usbListener=nil}
 }
}
