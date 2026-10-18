import AppKit
import Network
import ApplicationServices
import VideoToolbox
import CoreImage

@MainActor final class StoreHost:NSObject,NSApplicationDelegate {
 var window:NSWindow!,enable:NSButton!,dashboard:StoreDashboard!
 var statusMessage="打开平板上的映桥，自动寻找设备。"{didSet{updateDashboard()}}
 var overview:DesktopOverview?
 var hostCursor:HostCursorMonitor?,cursorRequested=false
 var lastSessionError:String?
 var preparing=false,bonjourReady=false
 var nearbyPads=StoreNearbyPads(),selectedPadID:String?,nearbyInvitationPending=false,nearbyInvitationEpoch:UInt64=0
 var permissionAlert:NSAlert?,padChoiceAlert:NSAlert?,permissionTimer:Timer?,permissionObservationUntil:TimeInterval=0,continueInputAfterScreen=false,pendingPermissionPadID:String?
 var activePadSession:String?,retainedPadSession:String?
 var discoveryListener:NWListener?, discoveryPeers:[ObjectIdentifier:NWConnection]=[:]
 var discoveryRates:[String:Date]=[:],discoveryAnnouncements:[String:Date]=[:]
 var advertisedService:NetService?,linkPeer:LinePeer?,linkAlert:NSAlert?
 var usbListener:NWListener?;var listener:NWListener?,identity:StoreIdentity?,controller:LinePeer?,viewer:LinePeer?,sender:VideoSender?,capture:StoreCapture?,heartbeat:Timer?
 var peers:[ObjectIdentifier:LinePeer]=[:],lastPing=Date(),generation=0,busy=false
 var originalUSB=StoreOriginalUSBDebug(),originalUSBListener:NWListener?,standbyListener:NWListener?,standbyService:NetService?,requestTimer:Timer?
 var standbyConnections:[ObjectIdentifier:(peer:LinePeer,id:UUID)]=[:]
 lazy var availability=StandbyCoordinator(now:{ProcessInfo.processInfo.systemUptime},requestID:{hex(randomBytes(16))})
 var topologyRevision:UInt64=0,topologyAcknowledged:UInt64=0;var topologyUnavailableSince:TimeInterval?
 var retainedDisplay:CGVirtualDisplay?,retentionTimer:Timer?,pendingController:LinePeer?
 var handoverStartedNs:UInt64?,handoverAdoptMs:Double=0,handoverReusedDisplay=false,handoverStartWaitMs:Double=0
 let input=RemoteInput()
 func applicationDidFinishLaunching(_ n:Notification){
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="映桥";window.center();window.isReleasedWhenClosed=false;window.contentMinSize=NSSize(width:760,height:620);window.backgroundColor=BridgeTheme.fog;window.titlebarAppearsTransparent=true;window.appearance=NSAppearance(named:.aqua)
  dashboard=StoreDashboard(target:self,stop:#selector(userEndSession),screen:#selector(screenPermission),access:#selector(accessPermission),network:#selector(prepare),relayConfig:#selector(prepare),start:#selector(startExtension),power:#selector(prepare),powerSettings:#selector(prepare),remoteAccess:#selector(prepare));window.contentView=dashboard;enable=dashboard.document.startButton
  availability.onChanged={[weak self] in self?.syncRequestTimer();self?.updateDashboard()};availability.onClosePath={[weak self] id in guard let self,let key=self.standbyConnections.first(where:{$0.value.id==id})?.key else{return};self.standbyConnections.removeValue(forKey:key)?.peer.close()};nearbyPads.onChanged={[weak self] in self?.announceToNearbyPads();self?.updateDashboard()};window.orderFront(nil);updateDashboard();DispatchQueue.main.async{[weak self] in self?.explainInitialPermissions()}
 }
 func updateDashboard(){
  guard dashboard != nil else{return};let rows=nearbyPadRows()
  if let selectedPadID,!rows.contains(where:{$0.id==selectedPadID}){self.selectedPadID=nil}
  if selectedPadID==nil,rows.count==1{selectedPadID=rows[0].id}
  dashboard.render(["state":busy ? "connecting":capture == nil ? "idle":"streaming","connected":capture != nil,"discoveryReady":listener != nil && bonjourReady,"preparing":preparing,"statusMessage":statusMessage,"screenPermission":CGPreflightScreenCaptureAccess(),"inputPermission":AXIsProcessTrusted(),"screenPermissionRequested":UserDefaults.standard.bool(forKey:"store.screenPermissionRequested"),"inputPermissionRequested":UserDefaults.standard.bool(forKey:"store.inputPermissionRequested"),"networkHelperRunning":listener != nil,"localConnection":availability.snapshot(),"localExtensionAvailable":capture==nil && !busy && rows.contains(where:{$0.ready}),"nearbyPads":rows.map{["id":$0.id,"name":$0.name,"authenticated":$0.authenticated,"ready":$0.ready]},"selectedPadID":selectedPadID ?? "","invitationPending":nearbyInvitationPending])
 }


 @objc func prepare(){
  guard !preparing else{return}
  guard listener==nil else{if advertisedService==nil,let identity{advertise(identity)};nearbyPads.start();updateDashboard();return}
  enable.isEnabled=false;statusMessage="正在生成这台电脑专属的加密配对身份…"
  preparing=true;Task{@MainActor in defer{preparing=false;updateDashboard()};do{let id=try await Task.detached{try StoreIdentity.createOrRead()}.value;identity=id;let tcp=NWProtocolTCP.Options();tcp.noDelay=true;tcp.enableKeepalive=true;let params=NWParameters(tls:try id.tlsOptions(),tcp:tcp);params.allowLocalEndpointReuse=true
   let l=try NWListener(using:params,on:49563);listener=l;advertise(id);startDatagramDiscovery(id)
   l.newConnectionHandler={[weak self] c in DispatchQueue.main.async{self?.accept(c)}};l.stateUpdateHandler={[weak self] state in DispatchQueue.main.async{if case .failed=state{self?.statusMessage="局域网监听失败，请检查端口占用。";self?.listener=nil;self?.enable.isEnabled=true}}};l.start(queue:.main);startOriginalLocalConnections(id);nearbyPads.start()
   statusMessage="选择附近的平板，或在平板上选择这台 Mac。"
  }catch{listener?.cancel();listener=nil;enable.isEnabled=true;statusMessage=error.localizedDescription}}
 }
 func accept(_ connection:NWConnection,usb:Bool=false,standby:Bool=false,debugUSB:Bool=false){guard peers.count<24,case let .hostPort(host,port)=connection.endpoint,(usb ? (host.debugDescription=="127.0.0.1" && (debugUSB || YQUSBTrustedPort(port.rawValue) != 0)):privateLANAddress(host.debugDescription)) else{connection.cancel();return};let p=LinePeer(connection,usb:usb,standby:standby);peers[ObjectIdentifier(p)]=p
  p.onLine={[weak self,weak p] line in guard let self,let p else{return};self.line(p,line)};p.onClose={[weak self,weak p] in guard let self,let p else{return};self.peers.removeValue(forKey:ObjectIdentifier(p));if p===self.linkPeer{self.clearLinkPrompt()};if let entry=self.standbyConnections.removeValue(forKey:ObjectIdentifier(p)){self.availability.detach(id:entry.id)};if p===self.controller || p===self.viewer{self.stopSession(keepDisplay:true)}}
  p.start();DispatchQueue.main.asyncAfter(deadline:.now()+15){[weak self,weak p] in guard let self,let p else{return};if p !== self.controller && p !== self.viewer && p !== self.linkPeer && self.standbyConnections[ObjectIdentifier(p)]==nil{p.close()}}
 }
 func line(_ p:LinePeer,_ line:String){let a=line.split(separator:" ").map(String.init);guard !a.isEmpty else{return};if handleStandby(p,a){return}
  #if ORIGINAL_USB_TEST
  if p.usb,[2,3].contains(a.count),a[0]=="DISCOVER",a[1]=="store-v1",let identity,!p.probeReplied {
   p.probeReplied=true;var startRequested=false
   if a.count==3{guard let id=nearbyPads.observeUSBMetadata(a[2]) else{p.close();return};startRequested=nearbyPads.consumeUSBStartRequest(id)}
   let info:[String:Any]=["schema":"store-discovery-v1","id":discoveryID(identity),"name":Host.current().localizedName ?? "Mac","certificate":identity.certificate,"host":StoreIdentity.addresses().first ?? "127.0.0.1","port":49563,"startRequested":startRequested]
   if let data=try? JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),let text=String(data:data,encoding:.utf8){p.send("DISCOVERED "+text)}else{p.close()};return
  }
  #endif
  if a.count==3,a[0]=="LINK",a[1]=="store-v1"{requestLink(p,code:a[2]);return}
  if p !== controller,a.count==3,a[0]=="PATH",let identity,constantEqual(a[1],identity.token),a[2].count==32,a[2].allSatisfy({$0.isHexDigit}),!p.probeReplied {
   p.probeReplied=true;p.onLine=nil
   let reply=Data(("PATHOK \(a[2]) \((p.usb || StoreNetworkPath.isUSB(p.connection)) ? "usb-net":"lan") 32768\n").utf8)+Data(repeating:0,count:32768)
   p.connection.send(content:reply,completion:.contentProcessed{_ in DispatchQueue.main.async{p.close()}});return
  }
  if p !== controller {
   if ["AUTH","VIEW"].contains(a[0]),!p.usb,!LocalIngress.lan(p.connection){p.send("ERR extension_requires_local_connection");p.close();return}
   if a.count==2,a[0]=="VIEW",let sender,constantEqual(a[1],sender.viewerToken),viewer==nil{viewer=p;sender.attachViewer(p.connection);return}
   guard a.count>=8,a[0]=="AUTH",let identity,constantEqual(a[1],identity.token),a[2]=="extend",a[6]=="tcp",a.contains("store-v1"),let w=Int(a[3]),let h=Int(a[4]),let fps=Int(a[5]),w>=640,h>=480,w<=3840,h<=3200,w*h<=8_000_000,w%2==0,h%2==0,[30,60,90,120].contains(fps) else{p.send("ERR local_extension_only");p.close();return}
   let kbps=a.count>7 ? (Int(a[7]) ?? 0):40000;guard kbps>=1500,kbps<=(p.usb ? 240000:80000) else{p.send("ERR bitrate_configuration");p.close();return}
   guard requireMediaPermissions() else{p.send("ERR permissions_required");p.close();return}
   let sessionFields=a.filter{$0.hasPrefix("edge-session-")};guard sessionFields.count<=1 else{p.send("ERR invalid_device_session");p.close();return}
   let declared=sessionFields.first.map{String($0.dropFirst(13))};if let declared,!StandbyCoordinator.identifier(declared){p.send("ERR invalid_device_session");p.close();return}
   guard let mediaSession=availability.mediaSession(declared,route:p.usb ? .usb:.lan) else{p.send("ERR device_session_not_ready");p.close();return}
   // Handover AUTH can arrive before ScreenCaptureKit finishes Stop. Queue
   // one already authenticated, validated request instead of rejecting it and
   // forcing a full one-second client retry. Explicit End invalidates the epoch.
   if busy || controller != nil {
    guard pendingController==nil else{p.send("ERR capture_busy");p.close();return}
    pendingController=p;if controller != nil{stopSession(keepDisplay:true)};let epoch=generation,started=monotonicNanoseconds()
    Task{@MainActor in
     while self.busy && self.generation==epoch && !p.closed && monotonicNanoseconds()-started<2_000_000_000 {
      try? await Task.sleep(nanoseconds:10_000_000)
     }
     guard self.pendingController===p else{return};self.pendingController=nil
     guard self.generation==epoch,!p.closed,!self.busy,self.controller==nil else{p.send("ERR capture_busy");p.close();return}
     self.handoverStartWaitMs=Double(monotonicNanoseconds()-started)/1e6;self.line(p,line)
    };return
   }
   let codec=a.contains("codec-hevc-v1") && StoreCapture.supports(kCMVideoCodecType_HEVC) ? "hevc":"avc";guard StoreCapture.supports(codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264) else{p.send("ERR hardware_encoder_unavailable");p.close();return}
   lastSessionError=nil;controller=p;busy=true;generation+=1;let g=generation;let sender:VideoSender;do{sender=try VideoSender(port:49564,tcpMode:true,targetFPS:fps,timedFrames:true)}catch{p.send("ERR sender_setup");failSession(error.localizedDescription);return};sender.setTargetBitrate(kbps:kbps);self.sender=sender;let capture=StoreCapture(width:w,height:h,fps:fps,codec:codec,sender:sender,bitrate:kbps*1000);self.capture=capture;activePadSession=mediaSession;availability.mediaStarted(edgeSession:mediaSession,mode:"extend");nearbyInvitationPending=false;topologyRevision=0;topologyAcknowledged=0;input.liveTopology=false;input.onTopologyChanged=nil;capture.onFailure={[weak self,weak capture] text in DispatchQueue.main.async{guard let self,self.generation==g,self.capture===capture else{return};self.failSession(text)}};sender.onRecovery={[weak capture] in capture?.requestKeyframe()};sender.onReady={[weak self,weak capture,weak p] in Task{@MainActor in guard let self,let capture,let p,self.generation==g,self.capture===capture,self.controller===p else{return};do{try await capture.startMedia();guard self.generation==g,self.capture===capture,self.controller===p else{return};self.startCoreCursor()}catch{guard self.generation==g,self.capture===capture,self.controller===p else{return};self.failSession(error.localizedDescription)}}};sender.start()
   statusMessage="正在创建独立扩展屏…";Task{@MainActor in do{let retained=retainedPadSession==mediaSession ? retainedDisplay:nil;retainedDisplay=nil;retainedPadSession=nil;retentionTimer?.invalidate();retentionTimer=nil;let adoptionStarted=monotonicNanoseconds();let display=try await capture.start(adopting:retained);handoverAdoptMs=Double(monotonicNanoseconds()-adoptionStarted)/1e6;handoverReusedDisplay=capture.reusedDisplay;guard generation==g,controller===p,!p.closed else{_ = await capture.stop();return};try input.configure(displayID:display,extended:true);guard let topology=input.desktopTopology else{throw NSError(domain:"Topology",code:1)};p.send(sender.handshake(width:w,height:h,fps:fps,desktop:topology)+" local-handover-v1 codec-\(codec)-v1");busy=false;lastPing=Date();statusMessage="扩展屏运行中";heartbeat=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in guard let self else{return};if !self.checkOriginalDesktopTopology(){return};if Date().timeIntervalSince(self.lastPing)>15{self.endSession()};if var health=self.sender?.transportStats(){health["width"]=w;health["height"]=h;health["codec"]=codec;health["route"]=(p.usb || StoreNetworkPath.isUSB(p.connection)) ? "usb-original-test-tcp":"lan-tcp";health["hiDPI"]=true;health["usb"]=originalUSB.status();health["localConnection"]=availability.snapshot();health["capture"]=self.capture?.stats();if let bytes=try? JSONSerialization.data(withJSONObject:health){try? bytes.write(to:StoreIdentity.directory.appendingPathComponent("stream-health.json"),options:.atomic)}}}}catch{guard generation==g,self.capture===capture,controller===p else{return};p.send("ERR capture_start_failed");failSession(error.localizedDescription)}};return
  }
  lastPing=Date();switch a[0]{
  case "TOPOLOGY":if a==["TOPOLOGY","1"]{input.liveTopology=true;input.onTopologyChanged={[weak self] topology in guard let self else{return};self.topologyRevision+=1;self.sender?.enableCursor(false);self.sender?.sendTopology(topology,revision:self.topologyRevision)}}
  case "TOPOLOGYACK":if a.count==2,let revision=UInt64(a[1]),revision==topologyRevision{topologyAcknowledged=revision;sender?.enableCursor(cursorRequested)}
  case "RATE":if a.count==2,let kbps=Int(a[1]),kbps>=1500,kbps<=(p.usb ? 240000:80000),let cap=capture?.media{let expected=generation;cap.updateBitrate(kbps:kbps){[weak self,weak cap,weak p] status in DispatchQueue.main.async{guard let self,let p,self.generation==expected,self.capture?.media===cap,self.controller===p else{return};if status==noErr{self.sender?.setTargetBitrate(kbps:kbps);p.send("RATE_ACK \(kbps)")}else{p.send("RATE_ERR \(kbps)")}}}}
  case "CLIENTUSB":if a.count==2,let data=Data(base64Encoded:a[1]),data.count<=4096,(try? JSONSerialization.jsonObject(with:data)) != nil{try? data.write(to:StoreIdentity.directory.appendingPathComponent("client-usb-status.json"),options:.atomic)}
  case "DESKTOP":if a==["DESKTOP","overview"]{Task{@MainActor in if self.overview==nil{self.overview=DesktopOverview()};self.overview?.request(active:self.capture?.media?.startupReady==true,permission:AXIsProcessTrusted(),heldKeys:self.input.pressed.count,heldButtons:self.input.buttons.count,onChange:{})}}
  case "TIME":if a.count==2,let t0=UInt64(a[1]){let t1=monotonicNanoseconds(),t2=monotonicNanoseconds();p.send("TIME \(t0) \(t1) \(t2)")}
  case "CURSOR":if a.count==2{cursorRequested=a[1]=="1";sender?.enableCursor(cursorRequested);Task{@MainActor in if self.cursorRequested{self.startCoreCursor()}else{self.hostCursor?.stop();self.hostCursor=nil}}}
  case "ACK":if a.count==2,let id=UInt64(a[1]){sender?.acknowledge(id);if let started=handoverStartedNs{handoverStartedNs=nil;let report:[String:Any]=["stoppedToFirstRenderACKms":Double(monotonicNanoseconds()-started)/1e6,"displayAdoptionMs":handoverAdoptMs,"authenticatedStartWaitMs":handoverStartWaitMs,"reusedDisplay":handoverReusedDisplay,"route":p.usb ? "usb-original-test-tcp":"lan-tcp","at":Date().timeIntervalSince1970];if let data=try? JSONSerialization.data(withJSONObject:report){try? data.write(to:StoreIdentity.directory.appendingPathComponent("handover-health.json"),options:.atomic)}}}
  case "STOP":endSession()
  case "HANDOVER":stopSession(keepDisplay:true)
  case "RELEASE":input.reset()
  case "IDR":capture?.requestKeyframe()
  case "MOVE":guard input.refreshDesktopTopology(),topologyRevision==topologyAcknowledged else{return};if a.count>=3,let x=Double(a[1]),let y=Double(a[2]){if input.move(x,y,sequence:a.count>3 ? UInt64(a[3]):nil){Task{@MainActor in self.hostCursor?.remoteMoved()}}}
  case "BUTTON":guard topologyRevision==topologyAcknowledged else{return};if a.count>=3,let b=Int(a[1]),let d=Int(a[2]){input.button(b,d != 0,clickCount:a.count>3 ? Int(a[3]):nil)}
  case "MACKEY":if a.count==3,let code=UInt16(a[1]),code<=126{input.key("mac\(code)",code,a[2]=="1")}
  case "OPTION":if a.count==3,a[1]=="ctrlToCmd"{input.ctrlToCommand=a[2]=="1"}
  case "WHEEL":if a.count==3,let y=Int32(a[1]),let x=Int32(a[2]){input.scroll(y,x)}
  case "KEY":if a.count>=3,let c=Int(a[1]),let d=Int(a[2]){input.ohKey(c,d != 0)}
  case "SCROLL":if a.count>=3,let y=Int32(a[1]),let x=Int32(a[2]){input.scroll(y,x,phase:a.count>3 ? Int(a[3]) ?? 0:0)}
  case "TEXT":if a.count==2,let data=Data(base64Encoded:a[1]),let text=String(data:data,encoding:.utf8){input.text(text)}
  case "ZOOM":if a.count>=3,let d=Double(a[1]),let phase=Int(a[2]){input.magnify(d,phase:phase)}
  default:break
  }
 }
 @MainActor func startCoreCursor(){guard cursorRequested,hostCursor==nil,let capture,let id=capture.displayID else{return};let monitor=HostCursorMonitor(input:input,captureBounds:{CGDisplayBounds(id)},send:{[weak self] sample in self?.sender?.sendCursor(sample)});hostCursor=monitor;monitor.start()}
 func failSession(_ text:String){lastSessionError=text;if let bytes=try? JSONSerialization.data(withJSONObject:["message":text,"time":Date().timeIntervalSince1970]){try? bytes.write(to:StoreIdentity.directory.appendingPathComponent("last-session-error.json"),options:.atomic)};endSession()}
 @objc func userEndSession(){nearbyInvitationEpoch+=1;nearbyPads.cancelInvitation();nearbyInvitationPending=false;pendingPermissionPadID=nil;
  if let sender{availability.endExtension(sessionID:sender.sid)};availability.cancelRequest()
  guard let peer=controller else{endSession();return};let current=generation
  peer.connection.send(content:Data("SESSION ENDED\n".utf8),completion:.contentProcessed{[weak self] _ in DispatchQueue.main.async{guard let self,self.generation==current else{return};self.endSession()}})
  DispatchQueue.main.asyncAfter(deadline:.now()+0.3){[weak self] in guard let self,self.generation==current else{return};self.endSession()}
 }
 @objc func endSession(){pendingPermissionPadID=nil;nearbyInvitationPending=false;retainedPadSession=nil;handoverStartedNs=nil;if controller==nil && capture==nil{generation+=1;busy=false};retentionTimer?.invalidate();retentionTimer=nil;retainedDisplay=nil;stopSession(keepDisplay:false)}
 func stopSession(keepDisplay:Bool){guard controller != nil || capture != nil else{return};let oldPadSession=activePadSession;activePadSession=nil;if keepDisplay{if handoverStartedNs==nil{handoverStartedNs=monotonicNanoseconds()}}else{handoverStartedNs=nil};handoverStartWaitMs=0;generation+=1;let stopGeneration=generation;heartbeat?.invalidate();heartbeat=nil;cursorRequested=false;Task{@MainActor in self.hostCursor?.stop();self.hostCursor=nil};input.reset();let old=capture;capture=nil;sender?.stop();sender=nil;let c=controller,v=viewer;controller=nil;viewer=nil;c?.onClose=nil;v?.onClose=nil;if let c{peers.removeValue(forKey:ObjectIdentifier(c))};if let v{peers.removeValue(forKey:ObjectIdentifier(v))};c?.close();v?.close();busy=true;availability.mediaEnded()
  Task{@MainActor in let kept=await old?.stop(keepingDisplay:keepDisplay);guard generation==stopGeneration else{return};if keepDisplay,let kept{retainedDisplay=kept;retainedPadSession=oldPadSession;retentionTimer=Timer.scheduledTimer(withTimeInterval:10,repeats:false){[weak self] _ in self?.retainedDisplay=nil;self?.retainedPadSession=nil;self?.retentionTimer=nil}};busy=false;statusMessage=lastSessionError ?? (keepDisplay ? "线路暂时断开，保留工作桌面10秒等待接续。":"会话已结束，画面采集和编码已停止；可从平板再次连接。") }
 }
 func applicationWillTerminate(_ notification:Notification){nearbyPads.stop();permissionTimer?.invalidate();permissionTimer=nil;originalUSB.stop();availability.stop();requestTimer?.invalidate();YQUSBStop()}
 func applicationShouldTerminate(_ app:NSApplication)->NSApplication.TerminateReply{guard capture != nil else{return .terminateNow};endSession();Task{@MainActor in try? await Task.sleep(nanoseconds:600_000_000);app.reply(toApplicationShouldTerminate:true)};return .terminateLater}
}
if CommandLine.arguments.contains("--usb-network-probe"){
 YQUSBStart("{}");for _ in 0..<15{Thread.sleep(forTimeInterval:1);let s=StoreUSB.status();print("USB",s["state"] ?? "unknown","rx",s["rxFrames"] ?? 0,"tx",s["txFrames"] ?? 0,"addressReady",!(s["address"] as? String ?? "").isEmpty);fflush(stdout)};YQUSBStop();exit(0)
}
if CommandLine.arguments.contains("--encoder-self-test"){
 Task{do{for codec in [kCMVideoCodecType_HEVC,kCMVideoCodecType_H264]{let sender=try VideoSender(port:0,tcpMode:true);let capture=try NativeCapture(width:3120,height:2080,fps:60,sender:sender,codec:codec);await capture.stop();sender.stop();print("PASS original-core hardware encoder",codec)};exit(0)}catch{print("FAIL original-core hardware encoder",(error as NSError).code);exit(1)}};dispatchMain()
}
if CommandLine.arguments.contains("--self-test"){MainActor.assumeIsolated{StandbyCoordinator.selfTest();StoreNearbyPads.selfTest()};StoreOriginalUSBDebug.selfTest();StoreFrameWindow.selfTest();StoreEncoderSettings.selfTest();precondition(!privateLANAddress(""));precondition(!privateLANAddress("%"));precondition(!privateLANAddress("%%"));precondition(StoreUSB.address()==nil);precondition(privateLANAddress("192.168.1.5"));precondition(privateLANAddress("fd00::1"));precondition(!privateLANAddress("8.8.8.8"));precondition(!privateLANAddress("100.64.0.1"));precondition(!privateLANAddress("127.0.0.1"));print("PASS store LAN address policy; no window, listener, capture, identity, or permission request");exit(0)}
let app=NSApplication.shared,delegate=MainActor.assumeIsolated{StoreHost()};app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
