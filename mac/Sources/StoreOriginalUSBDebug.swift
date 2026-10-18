import Foundation

// Performance-baseline adapter only. A consumer build must not define
// ORIGINAL_USB_TEST: this uses the user's separately installed DevEco HDC and
// requires a debug-authorized device. It is not ordinary consumer USB support.
#if ORIGINAL_USB_TEST
import IOKit
import Darwin

private final class StoreUSBNotificationOwners {
 static let shared=StoreUSBNotificationOwners()
 private final class Weak {weak var value:StoreOriginalUSBDebug?;init(_ value:StoreOriginalUSBDebug){self.value=value}}
 private let lock=NSLock();private var next:UInt=1,owners:[UInt:Weak]=[:]
 func add(_ owner:StoreOriginalUSBDebug)->UInt{lock.lock();defer{lock.unlock()};let id=next;next+=1;owners[id]=Weak(owner);return id}
 func get(_ id:UInt)->StoreOriginalUSBDebug?{lock.lock();defer{lock.unlock()};return owners[id]?.value}
 func remove(_ id:UInt){lock.lock();owners.removeValue(forKey:id);lock.unlock()}
}
private func storeUSBChanged(_ context:UnsafeMutableRawPointer?,_ iterator:io_iterator_t){
 while true{let item=IOIteratorNext(iterator);if item==0{break};IOObjectRelease(item)}
 guard let context else{return};StoreUSBNotificationOwners.shared.get(UInt(bitPattern:context))?.hardwareChanged()
}

final class StoreOriginalUSBDebug:NSObject,@unchecked Sendable {
 private static let hdc="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
 private static let ports:[UInt16]=[49561,49562]
 private let queue=DispatchQueue(label:"cn.edgelink.store.original-usb-test",qos:.utility)
 private let queueKey=DispatchSpecificKey<UInt8>(),lock=NSLock()
 private var enabled=false,epoch:UInt64=0,process:Process?
 private var phase="disabled",mappingReady=false,notificationReady=false
 private var timer:DispatchSourceTimer?,deferred:DispatchWorkItem?
 private var lastCheck:TimeInterval = -100,lastCreate:[String:TimeInterval]=[:]
 private var notificationPort:IONotificationPortRef?,added:io_iterator_t=0,removed:io_iterator_t=0,ownerID:UInt?
 override init(){super.init();queue.setSpecific(key:queueKey,value:1)}
 deinit{lock.lock();enabled=false;let child=process;lock.unlock();if let child,child.isRunning{child.terminate()};if DispatchQueue.getSpecific(key:queueKey) != nil{tearDown()}else{queue.sync{tearDown()}}}

 // Safe on the main thread; checks and subprocesses run on the utility queue.
 func start(){lock.lock();guard !enabled else{lock.unlock();return};enabled=true;epoch+=1;let current=epoch;phase="checking";lock.unlock()
  queue.async{[weak self] in guard let self,self.current(current) else{return};self.registerNotifications();self.check(current)
   let timer=DispatchSource.makeTimerSource(queue:self.queue);timer.schedule(deadline:.now()+15,repeating:15,leeway:.seconds(2));timer.setEventHandler{[weak self] in self?.check(current)};self.timer=timer;timer.resume()
  }
 }
 func stop(){lock.lock();enabled=false;epoch+=1;mappingReady=false;phase="disabled";let child=process;lock.unlock()
  if let child,child.isRunning{child.terminate()};queue.async{[weak self] in self?.tearDown()}
  // As in the original manager, do not remove HDC rules: there is no atomic
  // ownership-aware removal, and another app instance may now borrow a rule.
  // Only the two dedicated test ports are ever created, never personal ports.
 }
 func status()->[String:Any]{lock.lock();defer{lock.unlock()};return ["enabled":enabled,"phase":phase,"mappingAvailable":mappingReady,"notifications":notificationReady,"debugToolRequired":true,"consumerUSB":false]}
 private func current(_ value:UInt64)->Bool{lock.lock();defer{lock.unlock()};return enabled && epoch==value}
 private func publish(_ value:String,ready:Bool=false){lock.lock();if enabled{phase=value;mappingReady=ready};lock.unlock()}
 fileprivate func hardwareChanged(){
  // Notification is only a hint. No serial is read from IOKit, and no event
  // alone marks a path ready. Debounce USB enumeration and limit HDC checks.
  guard deferred==nil else{return};let delay=max(0.35,2-(ProcessInfo.processInfo.systemUptime-lastCheck))
  let work=DispatchWorkItem{[weak self] in guard let self else{return};self.deferred=nil;self.lock.lock();let e=self.epoch;self.lock.unlock();self.check(e)};deferred=work;queue.asyncAfter(deadline:.now()+delay,execute:work)
 }
 private func registerNotifications(){
  guard notificationPort==nil,let port=IONotificationPortCreate(kIOMainPortDefault) else{return}
  notificationPort=port;IONotificationPortSetDispatchQueue(port,queue);let id=StoreUSBNotificationOwners.shared.add(self);ownerID=id
  let context=UnsafeMutableRawPointer(bitPattern:id)
  let a=IOServiceAddMatchingNotification(port,kIOFirstMatchNotification,IOServiceMatching("IOUSBHostDevice"),storeUSBChanged,context,&added)
  let b=IOServiceAddMatchingNotification(port,kIOTerminatedNotification,IOServiceMatching("IOUSBHostDevice"),storeUSBChanged,context,&removed)
  if a != KERN_SUCCESS || b != KERN_SUCCESS{removeNotifications();return}
  storeUSBChanged(context,added);storeUSBChanged(context,removed);lock.lock();notificationReady=true;lock.unlock()
 }
 private func removeNotifications(){if let ownerID{StoreUSBNotificationOwners.shared.remove(ownerID)};ownerID=nil
  if added != 0{IOObjectRelease(added);added=0};if removed != 0{IOObjectRelease(removed);removed=0};if let notificationPort{IONotificationPortDestroy(notificationPort)};notificationPort=nil;lock.lock();notificationReady=false;lock.unlock()
 }
 private func tearDown(){timer?.cancel();timer=nil;deferred?.cancel();deferred=nil;removeNotifications();lastCreate.removeAll();lastCheck = -100}

 // All raw command output and target identifiers stay in memory. Only generic
 // phases leave the adapter; neither arguments nor HDC diagnostics are logged.
 private struct Result{let ok:Bool,text:String}
 private func run(_ arguments:[String],_ generation:UInt64)->Result{
  guard current(generation),FileManager.default.isExecutableFile(atPath:Self.hdc) else{return Result(ok:false,text:"")}
  let task=Process(),pipe=Pipe();task.executableURL=URL(fileURLWithPath:Self.hdc);task.arguments=arguments;task.currentDirectoryURL=URL(fileURLWithPath:"/");task.standardInput=FileHandle.nullDevice;task.standardOutput=pipe;task.standardError=pipe
  var environment=ProcessInfo.processInfo.environment;environment["LANG"]="C";environment["LC_ALL"]="C";task.environment=environment
  let fd=pipe.fileHandleForReading.fileDescriptor;_ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL)|O_NONBLOCK)
  let done=DispatchSemaphore(value:0);task.terminationHandler={_ in done.signal()}
  lock.lock();guard enabled && epoch==generation else{lock.unlock();return Result(ok:false,text:"")};process=task;lock.unlock()
  defer{task.terminationHandler=nil;try? pipe.fileHandleForReading.close();try? pipe.fileHandleForWriting.close();lock.lock();if process===task{process=nil};lock.unlock()}
  do{try task.run()}catch{return Result(ok:false,text:"")};try? pipe.fileHandleForWriting.close()
  var bytes=Data(),overflow=false,buffer=[UInt8](repeating:0,count:4096)
  func drain(){while true{let n=Darwin.read(fd,&buffer,buffer.count);if n<=0{break};if bytes.count+n>65536{overflow=true;break};bytes.append(contentsOf:buffer.prefix(n))}}
  let deadline=ProcessInfo.processInfo.systemUptime+2
  while task.isRunning && current(generation) && !overflow && ProcessInfo.processInfo.systemUptime<deadline{drain();if task.isRunning{_ = done.wait(timeout:.now()+0.02)}}
  let cancelled=task.isRunning
  if cancelled{task.terminate();if done.wait(timeout:.now()+0.2) == .timedOut,task.isRunning{_ = Darwin.kill(task.processIdentifier,SIGKILL)};_ = done.wait(timeout:.now()+0.2)}
  drain();guard !cancelled,!overflow,current(generation),!task.isRunning,task.terminationStatus==0 else{return Result(ok:false,text:"")}
  return Result(ok:true,text:String(decoding:bytes,as:UTF8.self))
 }
 private struct Rule{let device:String,first:String,second:String,direction:String}
 private static func targets(_ text:String)->[String]{
  text.split(whereSeparator:\.isNewline).compactMap{line in let a=line.split(whereSeparator:\.isWhitespace);guard a.count>=3,a[1]=="USB",a[2]=="Connected",a[0].utf8.count<=256,a[0].utf8.allSatisfy({($0>=48 && $0<=57)||($0>=65 && $0<=90)||($0>=97 && $0<=122)||$0==45||$0==95}),a[0].first != "-" else{return nil};return String(a[0])}
 }
 private static func rules(_ text:String)->[Rule]?{
  let lines=text.split(whereSeparator:\.isNewline).map{String($0).trimmingCharacters(in:.whitespaces)}
  if lines==["[Empty]"]{return []};guard !lines.isEmpty else{return nil}
  var result:[Rule]=[];for line in lines{let a=line.split(whereSeparator:\.isWhitespace).map(String.init);guard a.count==4,line.utf8.count<=1024,["[Forward]","[Reverse]"].contains(a[3]),a[1].contains(":"),a[2].contains(":") else{return nil};result.append(Rule(device:a[0],first:a[1],second:a[2],direction:a[3]))};return result
 }
 private static func owned(_ rule:Rule,target:String,port:UInt16)->Bool{rule.device==target && rule.first=="tcp:\(port)" && rule.second==rule.first && rule.direction=="[Reverse]"}
 private static func conflict(_ rules:[Rule],target:String)->Bool{
  for rule in rules{for port in ports where rule.first=="tcp:\(port)"{if !owned(rule,target:target,port:port){return true}}};return false
 }
 private func check(_ generation:UInt64){
  guard current(generation) else{return};let now=ProcessInfo.processInfo.systemUptime;guard now-lastCheck>=1.8 else{return};lastCheck=now
  guard FileManager.default.isExecutableFile(atPath:Self.hdc) else{publish("deveco_hdc_missing");return}
  let listing=run(["list","targets","-v"],generation);guard listing.ok else{publish("target_check_failed");return}
  let devices=Self.targets(listing.text);guard devices.count==1 else{publish(devices.isEmpty ? "waiting_debug_usb":"multiple_usb_devices");return};let target=devices[0]
  let listingRules=run(["-t",target,"fport","ls"],generation);guard listingRules.ok,let initial=Self.rules(listingRules.text) else{publish("rule_check_failed");return}
  guard !Self.conflict(initial,target:target) else{publish("test_port_conflict");return};var confirmed=initial
  for port in Self.ports where !confirmed.contains(where:{Self.owned($0,target:target,port:port)}){
   guard current(generation) else{return};let key=target+":\(port)";if let previous=lastCreate[key],now-previous<15{publish("mapping_retry_wait");return}
   // Recheck the unique physical transport immediately before each mutation.
   let checkTargets=run(["list","targets","-v"],generation);guard checkTargets.ok,Self.targets(checkTargets.text)==[target] else{publish("usb_changed");return}
   lastCreate[key]=now;let created=run(["-t",target,"rport","tcp:\(port)","tcp:\(port)"],generation)
   guard created.ok else{publish("mapping_create_failed");return}
   let after=run(["-t",target,"fport","ls"],generation);guard after.ok,let parsed=Self.rules(after.text),!Self.conflict(parsed,target:target),parsed.contains(where:{Self.owned($0,target:target,port:port)}) else{publish("mapping_verify_failed");return};confirmed=parsed
  }
  guard current(generation) else{return};publish("mapping_ready",ready:Self.ports.allSatisfy{p in confirmed.contains{Self.owned($0,target:target,port:p)}})
 }
 // Pure parsing checks only: no Process, IOKit, USB or network operation.
 static func selfTest(){
  precondition(targets("[Empty]").isEmpty);precondition(targets("fixture USB Connected\nother TCP Connected")==["fixture"])
  precondition(targets("one USB Connected\ntwo USB Connected").count==2)
  precondition(rules("bad output")==nil);precondition(rules("[Empty]")?.isEmpty==true)
  let good=rules("fixture tcp:49561 tcp:49561 [Reverse]\nfixture tcp:48561 tcp:48561 [Reverse]")!
  precondition(!conflict(good,target:"fixture"));precondition(owned(good[0],target:"fixture",port:49561))
  precondition(conflict(rules("other tcp:49561 tcp:49561 [Reverse]")!,target:"fixture"))
  precondition(conflict(rules("fixture tcp:49562 tcp:48562 [Reverse]")!,target:"fixture"))
  precondition(conflict(rules("fixture tcp:49561 tcp:49561 [Forward]")!,target:"fixture"))
 }
}
#else
final class StoreOriginalUSBDebug:NSObject {
 func start(){}
 func stop(){}
 func status()->[String:Any]{["enabled":false,"phase":"not_in_consumer_build","mappingAvailable":false,"debugToolRequired":false,"consumerUSB":false]}
 static func selfTest(){}
}
#endif
