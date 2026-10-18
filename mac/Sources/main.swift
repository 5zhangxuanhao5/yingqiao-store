import AppKit
import Network
import ApplicationServices
import VideoToolbox
import CoreImage

final class StoreHost:NSObject,NSApplicationDelegate {
 var window:NSWindow!,status:NSTextField!,enable:NSButton!,pairing:NSTextView!,qr:NSImageView!
 var listener:NWListener?,identity:StoreIdentity?,controller:LinePeer?,viewer:LinePeer?,sender:StoreFrameSender?,capture:StoreCapture?,heartbeat:Timer?
 var peers:[ObjectIdentifier:LinePeer]=[:],lastPing=Date(),generation=0,busy=false
 var retainedDisplay:CGVirtualDisplay?,retentionTimer:Timer?
 let input=RemoteInput()
 func applicationDidFinishLaunching(_ n:Notification){
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:740,height:690),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="映桥测试版";window.center()
  let title=NSTextField(labelWithString:"让平板，成为另一块屏幕。");title.font = .systemFont(ofSize:27,weight:.semibold)
  let note=NSTextField(wrappingLabelWithString:"此独立测试版不会读取个人版配置。只提供同一局域网扩展屏，不开启异地远控、合盖服务或麦克风。普通USB尚未接入；先测试局域网扩展屏，尚未完成多机型认证。")
  status=NSTextField(wrappingLabelWithString:"点击准备后检查权限；首次允许录屏和键鼠控制需要你在系统设置中完成。")
  enable=NSButton(title:"准备局域网扩展屏",target:self,action:#selector(prepare))
  let copy=NSButton(title:"复制配对信息",target:self,action:#selector(copyPairing));let end=NSButton(title:"结束会话",target:self,action:#selector(endSession))
  let buttons=NSStackView(views:[enable,copy,end]);buttons.orientation = .horizontal
  qr=NSImageView();qr.imageScaling = .scaleProportionallyUpOrDown;qr.heightAnchor.constraint(equalToConstant:200).isActive=true
  pairing=NSTextView();pairing.isEditable=false;pairing.isSelectable=true;pairing.font = .monospacedSystemFont(ofSize:10,weight:.regular)
  let scroll=NSScrollView();scroll.documentView=pairing;scroll.hasVerticalScroller=true;scroll.heightAnchor.constraint(equalToConstant:120).isActive=true
  let stack=NSStackView(views:[title,note,status,buttons,qr,scroll]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:28),stack.bottomAnchor.constraint(lessThanOrEqualTo:window.contentView!.bottomAnchor,constant:-20)])
  window.makeKeyAndOrderFront(nil)
 }
 @objc func prepare(){
  guard listener==nil else{return};guard CGPreflightScreenCaptureAccess() else{CGRequestScreenCaptureAccess();NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!);status.stringValue="请在系统设置允许此预览版录屏，再重新点击准备。";return}
  guard AXIsProcessTrusted() else{_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary);NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!);status.stringValue="请在系统设置允许此预览版辅助功能，再重新点击准备。";return}
  guard let host=StoreIdentity.addresses().first else{status.stringValue="未找到局域网地址，请让电脑和平板连接同一 Wi-Fi。";return}
  enable.isEnabled=false;status.stringValue="正在生成这台电脑专属的加密配对身份…"
  Task{do{let id=try await Task.detached{try StoreIdentity.createOrRead()}.value;identity=id;let tcp=NWProtocolTCP.Options();tcp.noDelay=true;tcp.enableKeepalive=true;let params=NWParameters(tls:try id.tlsOptions(),tcp:tcp);params.allowLocalEndpointReuse=true
   let l=try NWListener(using:params,on:49563);listener=l;l.service=NWListener.Service(name:"映桥测试版",type:"_yingqiaostore._tcp")
   l.newConnectionHandler={[weak self] c in self?.accept(c)};l.stateUpdateHandler={[weak self] state in if case .failed=state{self?.status.stringValue="局域网监听失败，请检查端口占用。";self?.listener=nil;self?.enable.isEnabled=true}};l.start(queue:.main)
   pairing.string=try id.pairingJSON(host:host);drawQR(pairing.string);status.stringValue="电脑已准备：\(host)。在平板扫码或粘贴配对信息，然后开启扩展屏。";enable.title="局域网已准备"
  }catch{listener?.cancel();listener=nil;enable.isEnabled=true;status.stringValue=error.localizedDescription}}
 }
 private func drawQR(_ value:String){guard let f=CIFilter(name:"CIQRCodeGenerator") else{return};f.setValue(Data(value.utf8),forKey:"inputMessage");f.setValue("L",forKey:"inputCorrectionLevel");guard let image=f.outputImage else{return};let rep=NSCIImageRep(ciImage:image);let result=NSImage(size:rep.size);result.addRepresentation(rep);qr.image=result}
 @objc func copyPairing(){guard !pairing.string.isEmpty else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(pairing.string,forType:.string);status.stringValue="配对信息已复制；它能授权连接，请只发给你自己的平板。"}
 func accept(_ connection:NWConnection){guard peers.count<8,case let .hostPort(host,_)=connection.endpoint,privateLANAddress(host.debugDescription) else{connection.cancel();return};let p=LinePeer(connection);peers[ObjectIdentifier(p)]=p
  p.onLine={[weak self,weak p] line in guard let self,let p else{return};self.line(p,line)};p.onClose={[weak self,weak p] in guard let self,let p else{return};self.peers.removeValue(forKey:ObjectIdentifier(p));if p===self.controller || p===self.viewer{self.stopSession(keepDisplay:true)}}
  p.start();DispatchQueue.main.asyncAfter(deadline:.now()+15){[weak self,weak p] in guard let self,let p else{return};if p !== self.controller && p !== self.viewer{p.close()}}
 }
 func line(_ p:LinePeer,_ line:String){let a=line.split(separator:" ").map(String.init);guard !a.isEmpty else{return}
  if p !== controller {
   if a.count==2,a[0]=="VIEW",let sender,constantEqual(a[1],sender.viewerToken),viewer==nil{viewer=p;sender.attach(p.connection);return}
   guard a.count>=8,a[0]=="AUTH",let identity,constantEqual(a[1],identity.token),a[2]=="extend",a[6]=="tcp",a.contains("store-v1"),!busy,controller==nil,let w=Int(a[3]),let h=Int(a[4]),let fps=Int(a[5]),w>=640,h>=480,w<=3840,h<=3200,w*h<=8_000_000,w%2==0,h%2==0,[30,60].contains(fps) else{p.send("ERR local_extension_only");p.close();return}
   let codec=a.contains("codec-hevc-v1") && StoreCapture.supports(kCMVideoCodecType_HEVC) ? "hevc":"avc";guard StoreCapture.supports(codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264) else{p.send("ERR hardware_encoder_unavailable");p.close();return}
   controller=p;busy=true;generation+=1;let g=generation;let sender=StoreFrameSender();self.sender=sender;let capture=StoreCapture(width:w,height:h,fps:fps,codec:codec,sender:sender);self.capture=capture;capture.onFailure={[weak self] _ in DispatchQueue.main.async{self?.endSession()}}
   status.stringValue="正在创建独立扩展屏…";Task{do{let retained=retainedDisplay;retainedDisplay=nil;retentionTimer?.invalidate();retentionTimer=nil;let display=try await capture.start(adopting:retained);guard generation==g,controller===p,!p.closed else{_ = await capture.stop();return};try input.configure(displayID:display,extended:true);guard let topology=input.desktopTopology else{throw NSError(domain:"Topology",code:1)};p.send(sender.handshake(width:w,height:h,fps:fps,topology:topology,codec:codec));busy=false;lastPing=Date();status.stringValue="扩展屏运行中 · \(w) × \(h) · \(codec.uppercased()) · \(fps)FPS目标";heartbeat=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in guard let self else{return};if Date().timeIntervalSince(self.lastPing)>12{self.endSession()}}}catch{p.send("ERR capture_start_failed");endSession();status.stringValue=error.localizedDescription}};return
  }
  lastPing=Date();switch a[0]{
  case "STOP":endSession()
  case "HANDOVER":stopSession(keepDisplay:true)
  case "RELEASE":input.reset()
  case "IDR":capture?.requestKeyframe()
  case "MOVE":if a.count>=3,let x=Double(a[1]),let y=Double(a[2]){input.move(x,y)}
  case "BUTTON":if a.count>=3,let b=Int(a[1]),let d=Int(a[2]){input.button(b,d != 0,clickCount:a.count>3 ? Int(a[3]):nil)}
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
 @objc func endSession(){if controller==nil && capture==nil{generation+=1;busy=false};retentionTimer?.invalidate();retentionTimer=nil;retainedDisplay=nil;stopSession(keepDisplay:false)}
 func stopSession(keepDisplay:Bool){guard controller != nil || capture != nil else{return};generation+=1;let stopGeneration=generation;heartbeat?.invalidate();heartbeat=nil;input.reset();let old=capture;capture=nil;sender?.stop();sender=nil;let c=controller,v=viewer;controller=nil;viewer=nil;c?.onClose=nil;v?.onClose=nil;c?.close();v?.close();busy=true
  Task{let kept=await old?.stop(keepingDisplay:keepDisplay);guard generation==stopGeneration else{return};if keepDisplay,let kept{retainedDisplay=kept;retentionTimer=Timer.scheduledTimer(withTimeInterval:10,repeats:false){[weak self] _ in self?.retainedDisplay=nil;self?.retentionTimer=nil}};busy=false;status.stringValue=keepDisplay ? "线路暂时断开，保留工作桌面10秒等待接续。":"会话已结束，画面采集和编码已停止；可从平板再次连接。"}
 }
 func applicationShouldTerminate(_ app:NSApplication)->NSApplication.TerminateReply{guard capture != nil else{return .terminateNow};endSession();Task{try? await Task.sleep(nanoseconds:600_000_000);app.reply(toApplicationShouldTerminate:true)};return .terminateLater}
}
if CommandLine.arguments.contains("--self-test"){precondition(privateLANAddress("192.168.1.5"));precondition(privateLANAddress("fd00::1"));precondition(!privateLANAddress("8.8.8.8"));precondition(!privateLANAddress("100.64.0.1"));precondition(!privateLANAddress("127.0.0.1"));print("PASS store LAN address policy; no window, listener, capture, identity, or permission request");exit(0)}
let app=NSApplication.shared,delegate=StoreHost();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
