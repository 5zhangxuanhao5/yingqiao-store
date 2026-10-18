import AppKit

// The menu asks for Mission Control itself, so a user's keyboard-shortcut
// settings and remote modifier mappings must not change its meaning.
@MainActor final class DesktopOverview {
 static let applicationURL=URL(fileURLWithPath:"/System/Applications/Mission Control.app")
 var launcher:(URL,@escaping (Bool)->Void)->Void = {url,done in
  let options=NSWorkspace.OpenConfiguration();options.activates=true
  NSWorkspace.shared.openApplication(at:url,configuration:options){app,error in
   DispatchQueue.main.async{done(app != nil && error == nil)}
  }
 }
 var installed:()->Bool = {FileManager.default.fileExists(atPath:applicationURL.path)}
 var now:()->Double = {ProcessInfo.processInfo.systemUptime}
 private(set) var requested=0,started=0,launchCompleted=0,launchFailed=0,rejected=0
 private var operation=0,pending=false,lastStarted:Double?
 @discardableResult func request(active:Bool,permission:Bool,heldKeys:Int,heldButtons:Int,onChange:@escaping ()->Void)->Bool {
  requested += 1
  let time=now()
  guard active,permission,heldKeys==0,heldButtons==0,!pending,
    lastStarted.map({time >= $0 && time-$0 >= 0.5}) ?? true else{rejected += 1;return false}
  guard installed() else{launchFailed += 1;return false}
  pending=true;started += 1;lastStarted=time;operation += 1;let token=operation
  launcher(Self.applicationURL){[weak self] success in
   guard let self,self.operation==token,self.pending else{return}
   self.pending=false
   if success{self.launchCompleted += 1}else{self.launchFailed += 1}
   onChange()
  }
  return true
 }
 func invalidate(){operation += 1;pending=false;lastStarted=nil}
 func stats()->[String:Any]{["requested":requested,"started":started,"launchCompleted":launchCompleted,
  "launchFailed":launchFailed,"rejected":rejected,"pending":pending]}
}
