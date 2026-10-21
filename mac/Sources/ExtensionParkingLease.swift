import Foundation

// A parked desktop belongs to the authenticated Pad process, never just its IP.
// Healthy native standby heartbeats renew it; a lost owner gets 90 s to return.
struct ExtensionParkingLease {
 let owner:String
 let sessionID:UInt32
 private(set) var lastLive:TimeInterval
 init(owner:String,sessionID:UInt32,now:TimeInterval){self.owner=owner;self.sessionID=sessionID;lastLive=now}
 mutating func keep(now:TimeInterval,ownerOnline:Bool)->Bool {
  guard now.isFinite,now>=lastLive else{return false}
  if ownerOnline{lastLive=now}
  return now-lastLive<90
 }
 static func selfTest(){
  var lease=ExtensionParkingLease(owner:"owner",sessionID:7,now:100)
  precondition(lease.keep(now:180,ownerOnline:true))
  precondition(lease.keep(now:269,ownerOnline:false))
  precondition(!lease.keep(now:270,ownerOnline:false))
  precondition(!lease.keep(now:179,ownerOnline:true))
  precondition(!lease.keep(now:.nan,ownerOnline:false))
  print("PASS parked extension owner lease: heartbeat renewal, exact expiry, clock rollback")
 }
}
