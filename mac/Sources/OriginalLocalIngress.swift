import Foundation
import Network
import Darwin

enum LocalIngress {
 enum Listener {case media,usb,standby}
 struct IPv4Range {
  let address:UInt32,mask:UInt32
  func contains(_ remote:UInt32)->Bool{mask != 0 && (address & mask)==(remote & mask)}
 }
 static func addresses()->[String] {
  var head:UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&head)==0 else{return []};defer{freeifaddrs(head)}
  var result=[String](),entry=head
  while let current=entry {
   defer{entry=current.pointee.ifa_next};let row=current.pointee
   guard String(cString:row.ifa_name).hasPrefix("en"),row.ifa_flags & UInt32(IFF_UP) != 0,
    let address=row.ifa_addr,address.pointee.sa_family==sa_family_t(AF_INET) else{continue}
   var ip=UnsafeRawPointer(address).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr
   var text=[CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
   if inet_ntop(AF_INET,&ip,&text,socklen_t(text.count)) != nil{result.append(String(cString:text))}
  };return result
 }
 static func ipv4(_ endpoint:NWEndpoint)->IPv4Address? {
  guard case let .hostPort(host,_)=endpoint else{return nil}
  switch host{case .ipv4(let v):return v;case .ipv6(let v):return v.asIPv4;default:return nil}
 }
 static func loopback(_ connection:NWConnection)->Bool {
  let endpoint=connection.currentPath?.remoteEndpoint ?? connection.endpoint
  if let v=ipv4(endpoint){return v.isLoopback}
  if case let .hostPort(.ipv6(v),_)=endpoint{return v.isLoopback};return false
 }
 static func lan(_ connection:NWConnection)->Bool {
  guard let path=connection.currentPath,
   path.usesInterfaceType(.wifi)||path.usesInterfaceType(.wiredEthernet),
   let remote=ipv4(path.remoteEndpoint ?? connection.endpoint),!remote.isLoopback,!remote.isMulticast else{return false}
  let physical=Set(path.availableInterfaces.filter{$0.type == .wifi || $0.type == .wiredEthernet}.map(\.name))
  guard !physical.isEmpty else{return false}
  var head:UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&head)==0 else{return false};defer{freeifaddrs(head)}
  let peer=remote.rawValue.withUnsafeBytes{$0.loadUnaligned(as:UInt32.self)}
  var entry=head
  while let current=entry {
   defer{entry=current.pointee.ifa_next}
   let row=current.pointee
   guard physical.contains(String(cString:row.ifa_name)),row.ifa_flags & UInt32(IFF_UP) != 0,row.ifa_flags & UInt32(IFF_LOOPBACK)==0,
    let address=row.ifa_addr,let mask=row.ifa_netmask,address.pointee.sa_family==sa_family_t(AF_INET) else{continue}
   let ip=UnsafeRawPointer(address).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr.s_addr
   let netmask=UnsafeRawPointer(mask).assumingMemoryBound(to:sockaddr_in.self).pointee.sin_addr.s_addr
   if IPv4Range(address:ip,mask:netmask).contains(peer){return true}
  }
  return false
 }
 static func allowsStandby(_ route:StandbyCoordinator.Route,connection:NWConnection)->Bool {
  switch route{case .usb:return loopback(connection);case .lan:return lan(connection);case .internet:return false}
 }
}
