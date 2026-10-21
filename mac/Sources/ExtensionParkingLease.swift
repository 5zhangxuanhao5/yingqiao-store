import Foundation

// PARK is an explicit user-session suspension, not a broken media route.
// HarmonyOS may freeze even native heartbeat threads while its screen is off.
// Keep the desktop until End, Mac quit, or an authenticated replacement Pad
// process appears. The Mac dashboard always exposes End while parked.
struct ExtensionParkingLease {
 let owner:String
 let sessionID:UInt32
 let deviceID:String?
 func permitsResume(owner:String,sessionID:UInt32)->Bool{self.owner==owner && self.sessionID==sessionID && sessionID>0}
 func replaced(by currentSession:String?)->Bool{currentSession != nil && currentSession != owner}
 static func canResume(owner:String,sid:UInt32,parked:Self?,continuation:(owner:String,sid:UInt32)?,activeOwner:String?,retainedOwner:String?)->Bool{
  if parked?.permitsResume(owner:owner,sessionID:sid)==true{return true}
  return sid>0 && continuation?.owner==owner && continuation?.sid==sid && (activeOwner==owner || retainedOwner==owner)
 }
 static func selfTest(){
  let lease=ExtensionParkingLease(owner:"owner",sessionID:7,deviceID:"device")
  precondition(!lease.replaced(by:nil) && !lease.replaced(by:"owner"))
  precondition(lease.replaced(by:"replacement"))
  precondition(lease.permitsResume(owner:"owner",sessionID:7))
  precondition(!lease.permitsResume(owner:"other",sessionID:7))
  precondition(!lease.permitsResume(owner:"owner",sessionID:8))
  precondition(canResume(owner:"owner",sid:7,parked:lease,continuation:nil,activeOwner:nil,retainedOwner:nil))
  precondition(!canResume(owner:"owner",sid:7,parked:nil,continuation:nil,activeOwner:nil,retainedOwner:nil))
  precondition(canResume(owner:"owner",sid:7,parked:nil,continuation:("owner",7),activeOwner:"owner",retainedOwner:nil))
  precondition(canResume(owner:"owner",sid:7,parked:nil,continuation:("owner",7),activeOwner:nil,retainedOwner:"owner"))
  precondition(!canResume(owner:"owner",sid:7,parked:nil,continuation:("owner",7),activeOwner:nil,retainedOwner:nil))
  precondition(!canResume(owner:"intruder",sid:7,parked:lease,continuation:("owner",7),activeOwner:"owner",retainedOwner:nil))
  print("PASS parked desktop: suspended heartbeat is not End; replacement and exact resume owner/session validation")
 }
}
