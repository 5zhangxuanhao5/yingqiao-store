import Foundation
/// A discovered tablet cannot override a failed local media/standby listener.
enum StoreConnectionReadiness {
 static func canStart(service:Bool,permissions:Bool,device:Bool,busy:Bool)->Bool {service && permissions && device && !busy}
 static func selfTest(){
  precondition(!canStart(service:false,permissions:true,device:true,busy:false))
  precondition(!canStart(service:true,permissions:false,device:true,busy:false))
  precondition(!canStart(service:true,permissions:true,device:false,busy:false))
  precondition(!canStart(service:true,permissions:true,device:true,busy:true))
  precondition(canStart(service:true,permissions:true,device:true,busy:false))
  print("PASS listener failure cannot enable an otherwise discovered/authorized tablet")
 }
}
