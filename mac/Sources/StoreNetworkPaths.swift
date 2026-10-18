import Foundation
import Network
import IOKit
import Darwin

// A plugged-in HDC device is never classified as a usable network path.
struct StoreNetworkPath {
 let host:String,usb:Bool
 static func usbInterfaces()->Set<String>{
  var names=Set<String>(),iterator:io_iterator_t=0
  guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IONetworkInterface"),&iterator)==KERN_SUCCESS else{return names}
  defer{IOObjectRelease(iterator)}
  while case let service=IOIteratorNext(iterator),service != 0 {
   defer{IOObjectRelease(service)}
   guard let name=IORegistryEntryCreateCFProperty(service,"BSD Name" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String else{continue}
   var parent:io_registry_entry_t=0,node=service;var owned=false
   for _ in 0..<16 {
    if IOObjectConformsTo(node,"IOUSBHostDevice") != 0 || IOObjectConformsTo(node,"IOUSBDevice") != 0 {names.insert(name);break}
    let result=IORegistryEntryGetParentEntry(node,kIOServicePlane,&parent)
    if owned {IOObjectRelease(node)};owned=false
    guard result==KERN_SUCCESS else{break};node=parent;owned=true
   }
   if owned{IOObjectRelease(node)}
  }
  return names
 }
 static func current()->[StoreNetworkPath]{
  let usb=usbInterfaces();var first:UnsafeMutablePointer<ifaddrs>?;guard getifaddrs(&first)==0 else{return []};defer{freeifaddrs(first)}
  var result:[StoreNetworkPath]=[],p=first
  while let item=p {
   defer{p=item.pointee.ifa_next};let flags=Int32(item.pointee.ifa_flags)
   guard flags & IFF_UP != 0,flags & IFF_LOOPBACK == 0,let addr=item.pointee.ifa_addr,addr.pointee.sa_family==AF_INET else{continue}
   let interface=String(cString:item.pointee.ifa_name);guard !interface.hasPrefix("utun"),!interface.hasPrefix("awdl"),!interface.hasPrefix("llw") else{continue}
   var text=[CChar](repeating:0,count:Int(NI_MAXHOST));guard getnameinfo(addr,socklen_t(addr.pointee.sa_len),&text,socklen_t(text.count),nil,0,NI_NUMERICHOST)==0 else{continue}
   let host=String(cString:text);guard privateLANAddress(host) else{continue};result.append(StoreNetworkPath(host:host,usb:usb.contains(interface)))
  }
  return result
 }
 static func publicRecords()->[[String:Any]]{var records=current().prefix(7).map{["host":$0.host,"route":$0.usb ? "usb-net":"lan"]};if let host=StoreUSB.address(),!records.contains(where:{$0["host"]==host}){records.append(["host":host,"route":"usb-net"])};return records}
 static func isUSB(_ connection:NWConnection)->Bool{
  guard let path=connection.currentPath,path.usesInterfaceType(.wiredEthernet),case let .hostPort(host,_)=path.localEndpoint else{return false}
  return current().contains{$0.usb && $0.host==host.debugDescription}
 }
}
