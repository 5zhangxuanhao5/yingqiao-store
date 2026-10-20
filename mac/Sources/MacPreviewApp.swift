#if MAC_RECEIVER_PREVIEW || MAC_RECEIVER_ENABLED
import AppKit
import Network
import Security
import CryptoKit
import ScreenCaptureKit
import ApplicationServices

@MainActor final class MacPreviewApp:NSObject,NSApplicationDelegate,NSWindowDelegate,NetServiceBrowserDelegate,NetServiceDelegate {
 var window:NSWindow!,videoWindow:NSWindow?,display:MacPreviewDisplay?
 var themedPage:StoreDashboard?
 let fallbackStatus=BridgeTheme.label("正在寻找提供扩展桌面的 Mac…",size:14,color:BridgeTheme.muted,wrap:true)
 var status:NSTextField { themedPage?.document.explanation ?? fallbackStatus }
 let fallbackDevices=NSPopUpButton(frame:.zero,pullsDown:false)
 var devices:NSPopUpButton { themedPage?.document.nearbySelector ?? fallbackDevices }
 var role:NSSegmentedControl!,connectButton:BridgeActionButton!,endButton:BridgeActionButton!
 let browser=NetServiceBrowser();var services:[NetService]=[],available:[NetService]=[]
 var readiness:[ObjectIdentifier:Date]=[:],probes:[ObjectIdentifier:NWConnection]=[:],discoveryTimer:Timer?
 var listener:NWListener?,advertisement:NetService?,identity:StoreIdentity?,peers:[ObjectIdentifier:LinePeer]=[:]
 var hostControl:LinePeer?,hostViewer:LinePeer?,sender:VideoSender?,capture:StoreCapture?,synthetic:NativeCapture?
 let input=RemoteInput();var hostStarting=false,hostStopping=false,hostLastPing=Date(),hostTimer:Timer?,epoch=0
 var control:NWConnection?,viewer:NWConnection?,clientBuffer=Data(),parser=MacPreviewWire.Parser(),clientTimer:Timer?
 var clientKey:SymmetricKey?,clientSID:UInt32=0,clientPrefix=Data(),targetService:NetService?,connectEpoch=0
 var requestedWidth=0,requestedHeight=0,receivedFrames=0
 var resolvedTarget:(host:String,port:NWEndpoint.Port,pin:String)?,lastEvent="launch",automaticTestAttempted=false
 var pendingTarget:NetService?,savedPresentation:NSApplication.PresentationOptions?
 var loopback:Bool{CommandLine.arguments.contains("--mac-preview-loopback")}
 var syntheticMode:Bool{loopback}
 static func fingerprint(_ pem:String)->String? {
  let text=pem.replacingOccurrences(of:"-----BEGIN CERTIFICATE-----",with:"").replacingOccurrences(of:"-----END CERTIFICATE-----",with:"").components(separatedBy:.whitespacesAndNewlines).joined()
  guard let der=Data(base64Encoded:text) else{return nil};return hex(Data(SHA256.hash(data:der)))
 }
 static func clientOptions(pin:String)->NWProtocolTLS.Options {
  let tls=NWProtocolTLS.Options();sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
  sec_protocol_options_set_verify_block(tls.securityProtocolOptions,{_,trust,complete in
   let value=sec_trust_copy_ref(trust).takeRetainedValue()
   guard let cert=SecTrustGetCertificateAtIndex(value,0) else{complete(false);return}
   let actual=hex(Data(SHA256.hash(data:SecCertificateCopyData(cert) as Data)));complete(constantEqual(actual,pin))
  },.global(qos:.userInitiated));return tls
 }
 func applicationDidFinishLaunching(_ notification:Notification){
  _ = makeInterface()
 }
 func makeInterface(in sharedWindow:NSWindow? = nil)->NSView {
  if let sharedWindow { return makeThemedInterface(in:sharedWindow) }
  let embedded = sharedWindow != nil
  if let sharedWindow { window=sharedWindow } else {
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:470),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  window.title="映桥 · Mac 接屏测试";window.center();window.isReleasedWhenClosed=false;window.delegate=self;window.backgroundColor=BridgeTheme.fog
  }
  let content=NSStackView();content.orientation = .vertical;content.alignment = .leading;content.spacing=22;content.edgeInsets=NSEdgeInsets(top:32,left:34,bottom:30,right:34)
  content.addArrangedSubview(BridgeTheme.label("另一台 Mac，也是你的屏幕",size:26,weight:.semibold))
  content.addArrangedSubview(BridgeTheme.label(embedded ? "把另一台 Mac 变成扩展屏，也可以接收它的画面。" : "独立测试版 · 保留原有映桥、Edge 与 iPad 随航",size:13,color:BridgeTheme.muted))
  role=NSSegmentedControl(labels:["接收电脑画面","向另一台 Mac 扩展"],trackingMode:.selectOne,target:self,action:#selector(changeRole))
  role.selectedSegment=CommandLine.arguments.contains("--mac-preview-host") || loopback || (embedded && !CommandLine.arguments.contains("--mac-receive")) ? 1:0;content.addArrangedSubview(role)
  devices.setAccessibilityLabel("附近可扩展的 Mac");devices.translatesAutoresizingMaskIntoConstraints=false;devices.widthAnchor.constraint(equalToConstant:570).isActive=true;content.addArrangedSubview(devices)
  status.maximumNumberOfLines=4;status.translatesAutoresizingMaskIntoConstraints=false;status.widthAnchor.constraint(equalToConstant:570).isActive=true;content.addArrangedSubview(status)
  let actions=NSStackView();actions.spacing=12;connectButton=BridgeTheme.button("连接并全屏",target:self,action:#selector(connectSelected),primary:true);endButton=BridgeTheme.button("结束接屏",target:self,action:#selector(endCurrent));actions.addArrangedSubview(connectButton);actions.addArrangedSubview(endButton);content.addArrangedSubview(actions)
  let settings=NSStackView();settings.spacing=12;settings.addArrangedSubview(BridgeTheme.button("录屏权限",target:self,action:#selector(requestScreen)));settings.addArrangedSubview(BridgeTheme.button("键鼠权限",target:self,action:#selector(requestInput)));content.addArrangedSubview(settings)
  content.addArrangedSubview(BridgeTheme.label("接收端按 Esc 结束。画面按接收窗口的真实尺寸建立，不镜像 Pro 内屏。",size:12,color:BridgeTheme.muted,wrap:true))
  if !embedded { window.contentView=content;window.orderFront(nil) };input.ctrlToCommand=false;browser.delegate=self;changeRole();trace("launched");return content
 }
 func makeThemedInterface(in sharedWindow:NSWindow)->NSView {
  window=sharedWindow
  let page=StoreDashboard(target:self,stop:#selector(endCurrent),screen:#selector(requestScreen),access:#selector(requestInput),network:#selector(refreshMacDiscovery),relayConfig:#selector(refreshMacDiscovery),start:#selector(connectSelected),power:#selector(refreshMacDiscovery),powerSettings:#selector(refreshMacDiscovery),remoteAccess:#selector(refreshMacDiscovery))
  themedPage=page
  let d=page.document;d.tagline.isHidden=true;d.devices.peerIsMac=true
  for panel in [d.permissions,d.nearby] {
   panel.layer?.backgroundColor=NSColor.clear.cgColor
   panel.layer?.borderWidth=0
  }
  role=NSSegmentedControl(labels:["扩展到另一台 Mac","接收 Mac 画面"],trackingMode:.selectOne,target:self,action:#selector(changeThemedRole))
  // Preserve the protocol controller's role indices: receiver=0, sender=1.
  role.selectedSegment=CommandLine.arguments.contains("--mac-receive") ? 1:0
  role.frame=NSRect(x:96,y:62,width:340,height:25);d.addSubview(role)
  connectButton=d.startButton;endButton=d.stopButton
  devices.target=self;devices.action=#selector(selectedMacChanged);devices.setAccessibilityLabel("选择附近的 Mac")
  d.nearbyIcon.image=NSImage(systemSymbolName:"laptopcomputer",accessibilityDescription:"Mac")
  d.nearbyTitle.stringValue="附近的 Mac";d.footnote.stringValue="接收画面时按 Esc 返回；切换页面保留连接。"
  // Internal controller continues to use its original role order.
  role.setLabel("接收 Mac 画面",forSegment:0);role.setLabel("扩展到另一台 Mac",forSegment:1)
  role.selectedSegment=CommandLine.arguments.contains("--mac-receive") ? 0:1
  input.ctrlToCommand=false;browser.delegate=self;changeRole();trace("launched")
  return page
 }
 @objc func changeThemedRole(){changeRole();refreshThemedState()}
 @objc func selectedMacChanged(){updateDevices()}
 @objc func refreshMacDiscovery(){guard role.selectedSegment==0 else{startHost();refreshThemedState();return};browser.stop();services=[];available=[];updateDevices();browser.searchForServices(ofType:MacPreviewWire.service,inDomain:"local.")}
 func refreshThemedState(){
  guard let d=themedPage?.document,let role else{return}
  let sending=role.selectedSegment==1,active=capture != nil || viewer != nil
  d.heading.stringValue=active ? "扩展屏已连接":sending ? "Mac 扩展屏":"接收 Mac 画面"
  d.devices.active=active
  d.pill.update(active ? "扩展屏中":hostStarting || control != nil ? "正在连接":sending ? "等待连接":"寻找 Mac")
  d.nearbyState.stringValue=sending ? "本机可被其他 Mac 发现":"发现 \(available.count) 台 Mac"
  let readyCount=available.filter{isReady($0)}.count
  d.nearbyHint.stringValue=sending ? "在另一台 Mac 选择接收画面，再选择本机。":available.isEmpty ? "请在另一台 Mac 打开映桥并开启发送待命。":readyCount==0 ? "正在检查连接和权限；对方就绪后才能连接。":"选择电脑后连接，首次需在对方允许。"
  d.screenState.stringValue=CGPreflightScreenCaptureAccess() ? "已允许":"发送画面时需要"
  d.inputState.stringValue=AXIsProcessTrusted() ? "已允许":"控制电脑时需要"
  d.screenButton.title="查看设置";d.inputButton.title="查看设置";d.screenButton.refreshTitle();d.inputButton.refreshTitle()
  endButton.enabled(active || hostStarting || control != nil)
 }
 @objc func requestScreen(){
  let alert=NSAlert();alert.messageText="允许映桥共享扩展桌面";alert.informativeText="这台 Mac 发送画面时需要录屏权限。映桥只在连接期间采集所建立的扩展桌面；接收画面的 Mac 无需此权限。";alert.addButton(withTitle:"继续申请");alert.addButton(withTitle:"取消")
  alert.beginSheetModal(for:window){r in if r == .alertFirstButtonReturn{_ = CGRequestScreenCaptureAccess()}}
 }
 @objc func requestInput(){_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)}
 @objc func changeRole(){endCurrent();browser.stop();discoveryTimer?.invalidate();discoveryTimer=nil;for p in probes.values{p.cancel()};probes=[:];readiness=[:];services=[];available=[];devices.removeAllItems();devices.isHidden=role.selectedSegment==1
  if role.selectedSegment==1{connectButton.title="发送端正在待命";connectButton.enabled(false);startHost()}
  else{stopHostListener();connectButton.title="连接并全屏";connectButton.enabled(false);status.stringValue="请在另一台 Mac 打开映桥，选择“扩展到另一台 Mac”。";browser.searchForServices(ofType:MacPreviewWire.service,inDomain:"local.");discoveryTimer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self] _ in self?.probeNearby()}}
  connectButton.refreshTitle()
 }
 func startHost(){guard listener==nil else{return};status.stringValue="正在准备独立的加密连接…"
  Task{@MainActor in do{
   let id=try await Task.detached{try StoreIdentity.createOrRead()}.value;identity=id
   let tcp=NWProtocolTCP.Options();tcp.noDelay=true;let params=NWParameters(tls:try id.tlsOptions(),tcp:tcp);params.includePeerToPeer=true;params.allowLocalEndpointReuse=true
   if loopback{params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)}
   let l=try NWListener(using:params,on:loopback ? .any:NWEndpoint.Port(rawValue:48673)!);listener=l
   l.newConnectionHandler={[weak self] c in DispatchQueue.main.async{self?.accept(c)}}
   l.stateUpdateHandler={[weak self] state in DispatchQueue.main.async{guard let self,self.listener===l else{return};switch state{
    case .ready:
     guard let port=l.port,let pin=Self.fingerprint(id.certificate) else{return}
     self.status.stringValue="发送端已就绪。请在 Air 打开同一个测试版并点“连接并全屏”。"
     if self.loopback{self.beginLoopback(port:port,pin:pin)}else{let s=NetService(domain:"local.",type:MacPreviewWire.service,name:(Host.current().localizedName ?? "Mac")+" · 映桥",port:Int32(port.rawValue));s.setTXTRecord(NetService.data(fromTXTRecord:["sha256":Data(pin.utf8),"schema":Data("1".utf8)]));self.advertisement=s;s.publish()}
    case .failed(let error):self.status.stringValue=error.localizedDescription;self.stopHostListener()
    default:break
   }}}
   l.start(queue:.main)
  }catch{status.stringValue=error.localizedDescription}}
 }
 func stopHostListener(){advertisement?.stop();advertisement=nil;listener?.cancel();listener=nil;for p in peers.values{p.onClose=nil;p.close()};peers=[:]}
 func accept(_ connection:NWConnection){
  guard peers.count<6,case let .hostPort(host,_)=connection.endpoint,privateLANAddress(host.debugDescription) || (loopback && host.debugDescription=="127.0.0.1") else{connection.cancel();return}
  let p=LinePeer(connection);peers[ObjectIdentifier(p)]=p;p.onLine={[weak self,weak p] s in if let self,let p{self.hostLine(p,s)}}
  p.onClose={[weak self,weak p] in guard let self,let p else{return};self.peers.removeValue(forKey:ObjectIdentifier(p));if p===self.hostControl || p===self.hostViewer{self.endHostSession()}}
  p.start();DispatchQueue.main.asyncAfter(deadline:.now()+15){[weak self,weak p] in guard let self,let p,p !== self.hostControl,p !== self.hostViewer else{return};p.close()}
 }
 func hostLine(_ p:LinePeer,_ text:String){
  let a=text.split(separator:" ").map(String.init);guard let command=a.first else{return}
  if command=="PROBE",a.count==1 {
   let ready=(syntheticMode || CGPreflightScreenCaptureAccess()) && AXIsProcessTrusted() && hostControl==nil && !hostStarting && !hostStopping
   p.connection.send(content:Data((ready ? "READY\n":"UNAVAILABLE\n").utf8),completion:.contentProcessed{_ in p.close()})
   return
  }
  if command=="HELLO" {
   trace("helloReceived")
   guard syntheticMode || CGPreflightScreenCaptureAccess() else {
    status.stringValue="需要在本机允许映桥录屏，才能向另一台 Mac 发送画面。"
    reject(p,reason:"发送端尚未获得录屏权限。请在发送端映桥中打开录屏设置，允许后重试。")
    trace("screenPermissionRequired");return
   }
   guard hostControl==nil,!hostStarting,!hostStopping,a.count==5,let w=Int(a[1]),let h=Int(a[2]),let fps=Int(a[3]),[30,60].contains(fps),w>=640,h>=480,w<=3840,h<=3200,w*h<=8_000_000,w%2==0,h%2==0,let nameData=Data(base64Encoded:a[4]),nameData.count<=256 else{p.close();return}
   let name=String(decoding:nameData,as:UTF8.self).filter{!$0.isNewline && !$0.isASCIIControl}
   hostStarting=true
   func approved(){self.createHostSession(p,width:w,height:h,fps:fps)}
   if loopback{approved();return}
   let alert=NSAlert();alert.messageText="允许这台 Mac 使用扩展屏？";alert.informativeText="\(name.prefix(64)) 请求接收 \(w) × \(h) 的独立桌面。仅接受这次连接；结束后停止采集。现有 Edge 与随航连接不会被主动关闭。";alert.addButton(withTitle:"允许连接");alert.addButton(withTitle:"拒绝")
   alert.beginSheetModal(for:window){[weak self,weak p] r in guard let self,let p else{return};if r == .alertFirstButtonReturn && !p.closed{approved()}else{self.hostStarting=false;p.close()}}
   return
  }
  if command=="VIEW",a.count==2,let sender,constantEqual(a[1],sender.viewerToken),hostViewer==nil{hostViewer=p;sender.attachViewer(p.connection);return}
  guard p===hostControl else{p.close();return};hostLastPing=Date()
  switch command {
  case "PING":p.send("PONG")
  case "ACK":if a.count==2,let id=UInt64(a[1]){sender?.acknowledge(id)}
  case "END":endHostSession()
  case "IDR":capture?.requestKeyframe();synthetic?.requestKeyframe()
  case "MOVE":if a.count==3,let x=Double(a[1]),let y=Double(a[2]){_ = input.move(x,y)}
  case "BUTTON":if (3...4).contains(a.count),let b=Int(a[1]),b>=0,b<=2,["0","1"].contains(a[2]){input.button(b,a[2]=="1",clickCount:a.count==4 ? Int(a[3]):nil)}
  case "KEY":if a.count==3,let code=UInt16(a[1]),code<=126,["0","1"].contains(a[2]){input.key("mac\(code)",code,a[2]=="1")}
  case "SCROLL":if a.count==3,let y=Int32(a[1]),let x=Int32(a[2]),abs(Int64(y))<=10000,abs(Int64(x))<=10000{input.scroll(y,x)}
  case "RELEASE":input.reset()
  default:break
  }
 }
 func reject(_ p:LinePeer,reason:String){
  p.connection.send(content:Data(("ERR "+reason+"\n").utf8),completion:.contentProcessed{_ in p.close()})
 }
 func createHostSession(_ p:LinePeer,width:Int,height:Int,fps:Int){
  trace("hostPreparing")
  guard !p.closed else{hostStarting=false;return}
  guard syntheticMode || CGPreflightScreenCaptureAccess() else{hostStarting=false;reject(p,reason:"请先在发送端允许映桥录屏，然后重新连接。");status.stringValue="收到 Air 请求；请点“录屏权限”，完成后在 Air 重新连接。";return}
  epoch+=1;let generation=epoch;hostControl=p;hostLastPing=Date()
  Task{@MainActor in do{
   let sender=try VideoSender(port:0,tcpMode:true,targetFPS:fps);self.sender=sender;sender.start();sender.setTargetBitrate(kbps:40000)
   let codec=StoreCapture.supports(kCMVideoCodecType_HEVC) ? "hevc":"avc"
   if syntheticMode{synthetic=try NativeCapture(width:width,height:height,fps:fps,sender:sender,codec:codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264)}
   else{
    let c=StoreCapture(width:width,height:height,fps:fps,codec:codec,sender:sender,displayName:"映桥 · Mac 接收屏",displayProduct:0x4d52,displaySerial:0x4d525031,showCursor:true);capture=c
    let id=try await c.start();guard generation==epoch,!p.closed else{_ = await c.stop();return};try input.configure(displayID:id,extended:false)
    c.onFailure={[weak self,weak c] reason in DispatchQueue.main.async{guard let self,let c,self.epoch==generation,self.capture===c else{return};self.status.stringValue=reason;self.trace("captureStopped");self.endHostSession()}}
   }
   sender.onReady={[weak self] in Task{@MainActor in guard let self,self.epoch==generation else{return};do{if let synthetic=self.synthetic{try synthetic.startSynthetic()}else{try await self.capture?.startMedia()};guard self.epoch==generation else{return};self.hostStarting=false;self.status.stringValue="正在向 Air 发送 \(width) × \(height) 独立桌面，\(fps) FPS 目标。"}catch{guard self.epoch==generation else{return};self.status.stringValue=error.localizedDescription;self.trace("captureStartFailed");self.endHostSession()}}}
   p.send(sender.handshake(width:width,height:height,fps:fps,desktop:nil)+" codec-\(codec)-v1")
   hostTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in guard let self else{return};if Date().timeIntervalSince(self.hostLastPing)>10{self.endHostSession()};self.writeHealth()}
  }catch{guard epoch==generation else{return};hostStarting=false;status.stringValue=error.localizedDescription;trace("hostSetupFailed");p.send("ERR "+error.localizedDescription);endHostSession()}}
 }
 func endHostSession(){
  epoch+=1;hostStarting=false;hostTimer?.invalidate();hostTimer=nil;input.reset();let c=capture,s=synthetic;c?.onFailure=nil;capture=nil;synthetic=nil;sender?.stop();sender=nil
  let peers=[hostControl,hostViewer];hostControl=nil;hostViewer=nil;for p in peers{p?.onClose=nil;p?.close()}
  hostStopping = c != nil || s != nil;Task{_ = await c?.stop();await s?.stop();self.hostStopping=false};writeHealth()
 }
 func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool){guard !services.contains(where:{$0==service}) else{return};services.append(service);service.delegate=self;service.resolve(withTimeout:4)}
 func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool){services.removeAll{$0==service};available.removeAll{$0==service};updateDevices()}
 func netServiceDidResolveAddress(_ sender:NetService){guard let txt=sender.txtRecordData(),let pin=NetService.dictionary(fromTXTRecord:txt)["sha256"],pin.count==64,sender.port>0,sender.port<65536,sender.hostName != nil else{return};if !available.contains(sender){available.append(sender)};if pendingTarget===sender{pendingTarget=nil;openReceiver(sender)};probeNearby();updateDevices()}
 func netService(_ sender:NetService,didNotResolve errorDict:[String:NSNumber]){if pendingTarget===sender{pendingTarget=nil;status.stringValue="电脑地址刷新失败，请确认两台 Mac 的局域网权限已开启。";trace("resolveFailed");updateDevices()}}
 func probeNearby(){
  guard role.selectedSegment==0,control==nil else{return}
  for service in available {
   let id=ObjectIdentifier(service)
   guard probes[id]==nil,let host=service.hostName,let port=NWEndpoint.Port(rawValue:UInt16(service.port)),let txt=service.txtRecordData(),let bytes=NetService.dictionary(fromTXTRecord:txt)["sha256"],let pin=String(data:bytes,encoding:.utf8) else{continue}
   let params=NWParameters(tls:Self.clientOptions(pin:pin),tcp:NWProtocolTCP.Options());params.includePeerToPeer=true
   let c=NWConnection(host:NWEndpoint.Host(host),port:port,using:params);probes[id]=c
   func finish(_ ready:Bool){
    guard self.probes[id]===c else{return}
    self.probes.removeValue(forKey:id);c.stateUpdateHandler=nil;c.cancel()
    if ready{self.readiness[id]=Date()}else{self.readiness.removeValue(forKey:id)}
    self.updateDevices()
   }
   c.stateUpdateHandler={state in DispatchQueue.main.async {
    switch state{
    case .ready:
     c.send(content:Data("PROBE\n".utf8),completion:.contentProcessed{error in
      guard error==nil else{DispatchQueue.main.async{finish(false)};return}
      c.receive(minimumIncompleteLength:6,maximumLength:64){data,_,_,error in DispatchQueue.main.async{finish(error==nil && data.map{String(decoding:$0,as:UTF8.self).hasPrefix("READY\n")}==true)}}
     })
    case .failed,.cancelled:finish(false)
    default:break
    }
   }}
   c.start(queue:.main)
   DispatchQueue.main.asyncAfter(deadline:.now()+2){finish(false)}
  }
  updateDevices()
 }
 func isReady(_ service:NetService)->Bool{readiness[ObjectIdentifier(service)].map{Date().timeIntervalSince($0)<4} ?? false}
 func updateDevices(){defer{refreshThemedState()};let previous=devices.titleOfSelectedItem;devices.removeAllItems();for s in available{devices.addItem(withTitle:s.name)};if let previous,available.contains(where:{$0.name==previous}){devices.selectItem(withTitle:previous)};if available.isEmpty{devices.addItem(withTitle:"尚未发现发送端")};connectButton.enabled(control==nil && available.indices.contains(devices.indexOfSelectedItem) && isReady(available[devices.indexOfSelectedItem]))
  if !automaticTestAttempted,role.selectedSegment==0,let i=CommandLine.arguments.firstIndex(of:"--mac-preview-connect-fingerprint"),CommandLine.arguments.indices.contains(i+1){
   let pin=CommandLine.arguments[i+1]
   if pin.count==64,let index=available.firstIndex(where:{service in guard self.isReady(service),let txt=service.txtRecordData(),let data=NetService.dictionary(fromTXTRecord:txt)["sha256"] else{return false};return String(data:data,encoding:.utf8)==pin}){automaticTestAttempted=true;devices.selectItem(at:index);DispatchQueue.main.async{[weak self] in self?.connectSelected()}}
  }
 }
 @objc func connectSelected(){guard role.selectedSegment==0,control==nil,videoWindow==nil,pendingTarget==nil,available.indices.contains(devices.indexOfSelectedItem) else{return};let service=available[devices.indexOfSelectedItem];guard isReady(service) else{probeNearby();return};pendingTarget=service;connectButton.enabled(false);status.stringValue="正在更新电脑地址…";service.stop();service.resolve(withTimeout:4)}
 func openReceiver(_ service:NetService){guard role.selectedSegment==0,control==nil,videoWindow==nil else{return};targetService=service
  guard let txt=service.txtRecordData(),let pinData=NetService.dictionary(fromTXTRecord:txt)["sha256"],let pin=String(data:pinData,encoding:.utf8),let host=service.hostName,let port=NWEndpoint.Port(rawValue:UInt16(service.port)) else{status.stringValue="电脑地址正在更新，请稍后重试。";trace("targetUnavailable");return};resolvedTarget=(host,port,pin);trace("selected")
  let video=MacPreviewDisplay(frame:NSScreen.main?.frame ?? NSRect(x:0,y:0,width:1280,height:832));display=video;video.send={[weak self] in self?.sendClient($0)};video.finish={[weak self] in self?.endCurrent()}
  let w=MacPreviewWindow(contentRect:video.frame,styleMask:[.borderless],backing:.buffered,defer:false);videoWindow=w;w.title="映桥 · 接收屏（Esc 结束）";w.isReleasedWhenClosed=false;w.delegate=self;w.contentView=video;w.acceptsMouseMovedEvents=true
  // A borderless viewport covers the physical panel, including the area next
  // to the camera. Native full-screen reserves the menu/safe-area strip.
  savedPresentation=NSApp.presentationOptions;NSApp.presentationOptions=[.hideDock,.hideMenuBar]
  w.setFrame(NSScreen.main?.frame ?? video.frame,display:true);w.makeKeyAndOrderFront(nil);w.makeFirstResponder(video);video.layoutSubtreeIfNeeded();trace("panelViewportReady");connectFullscreenWindow()
 }

 func windowDidEnterFullScreen(_ notification:Notification){guard let w=notification.object as? NSWindow,w===videoWindow else{return};trace("enteredFullscreen");connectFullscreenWindow()}
 func connectFullscreenWindow(){guard control==nil,let w=videoWindow,let video=display,let target=resolvedTarget else{trace("fullscreenTargetUnavailable");return}
  guard let d=MacPreviewWire.dimensions(width:video.bounds.width*w.backingScaleFactor,height:video.bounds.height*w.backingScaleFactor) else{status.stringValue="接收窗口尺寸尚未就绪，请按 Esc 后重试。";video.showMessage(status.stringValue);trace("viewportInvalid");return};requestedWidth=d.0;requestedHeight=d.1;trace("viewportReady");startClient(host:target.host,port:target.port,pin:target.pin)
 }
 func beginLoopback(port:NWEndpoint.Port,pin:String){requestedWidth=1280;requestedHeight=832;let d=MacPreviewDisplay(frame:NSRect(x:0,y:0,width:640,height:416));display=d
  let w=NSWindow(contentRect:d.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false);w.title="映桥 · 本机编解码对照";w.contentView=d;w.isReleasedWhenClosed=false;videoWindow=w;w.orderFront(nil);startClient(host:"127.0.0.1",port:port,pin:pin)
 }
 func startClient(host:String,port:NWEndpoint.Port,pin:String){
  connectEpoch+=1;let generation=connectEpoch;trace("clientConnecting")
  let params=NWParameters(tls:Self.clientOptions(pin:pin),tcp:NWProtocolTCP.Options());(params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay=true;params.includePeerToPeer=true
  let c=NWConnection(host:NWEndpoint.Host(host),port:port,using:params);control=c
  c.stateUpdateHandler={[weak self] state in DispatchQueue.main.async{guard let self,self.connectEpoch==generation,self.control===c else{return};switch state{
   case .ready:self.trace("controlReady");self.sendClient("HELLO \(self.requestedWidth) \(self.requestedHeight) 60 "+Data((Host.current().localizedName ?? "Mac 接收端").utf8.prefix(256)).base64EncodedString());self.readControl(c,generation:generation,host:host,port:port,pin:pin)
   case .waiting(let error):self.status.stringValue="等待网络连接："+error.localizedDescription+"。请检查局域网权限。";self.display?.showMessage(self.status.stringValue);self.trace("clientWaiting")
   case .failed(let error):self.status.stringValue=error.localizedDescription;self.trace("clientFailed");self.endClient()
   case .cancelled:self.endClient()
   default:break
  }}}
  c.start(queue:.main);status.stringValue="正在连接，并等待发送端允许…";display?.showMessage(status.stringValue);connectButton.enabled(false)
  DispatchQueue.main.asyncAfter(deadline:.now()+30){[weak self,weak c] in guard let self,let c,self.connectEpoch==generation,self.control===c,self.receivedFrames==0 else{return};self.status.stringValue="连接未完成，请检查两端局域网权限，并在发送端允许连接。按 Esc 可返回。";self.trace("firstFrameTimeout");self.endClient()}
 }
 func readControl(_ c:NWConnection,generation:Int,host:String,port:NWEndpoint.Port,pin:String){c.receive(minimumIncompleteLength:1,maximumLength:8192){[weak self] data,_,end,error in guard let self,self.connectEpoch==generation else{return};if let data{self.clientBuffer.append(data)};guard self.clientBuffer.count<=16384 else{self.endClient();return}
  while let i=self.clientBuffer.firstIndex(of:10){let line=String(decoding:self.clientBuffer.prefix(upTo:i),as:UTF8.self);self.clientBuffer.removeSubrange(...i);let a=line.split(separator:" ").map(String.init)
   if a.first=="OK",a.count>=9,self.viewer==nil,let sidData=MacPreviewWire.unhex(a[1]),sidData.count==4,let key=MacPreviewWire.unhex(a[2]),key.count==16,let prefix=MacPreviewWire.unhex(a[3]),prefix.count==4,Int(a[6])==self.requestedWidth,Int(a[7])==self.requestedHeight {
    self.clientSID=UInt32(sidData.uintBE(0,4));self.clientKey=SymmetricKey(data:key);self.clientPrefix=prefix;self.display?.playback.setCodec(hevc:a.contains("codec-hevc-v1"));self.trace("handshakeAccepted");self.openViewer(host:host,port:port,pin:pin,token:a[5],generation:generation)
    self.clientTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in self?.sendClient("PING");self?.writeHealth()}
   }else if a.first=="ERR"{self.status.stringValue=String(line.dropFirst(4));self.endClient();return}
  }
  if end || error != nil{self.status.stringValue=error?.localizedDescription ?? "发送端已结束连接，请返回后重试。";self.endClient()}else{self.readControl(c,generation:generation,host:host,port:port,pin:pin)}
 }}
 func openViewer(host:String,port:NWEndpoint.Port,pin:String,token:String,generation:Int){let tcp=NWProtocolTCP.Options();tcp.noDelay=true;let params=NWParameters(tls:Self.clientOptions(pin:pin),tcp:tcp);params.includePeerToPeer=true
  let v=NWConnection(host:NWEndpoint.Host(host),port:port,using:params);viewer=v;v.stateUpdateHandler={[weak self] state in DispatchQueue.main.async{guard let self,self.connectEpoch==generation else{return};if case .ready=state{self.trace("viewerReady");v.send(content:Data(("VIEW "+token+"\n").utf8),completion:.contentProcessed{_ in});self.readVideo(v,generation:generation)};if case .failed(let error)=state{self.status.stringValue=error.localizedDescription;self.endClient()}}};v.start(queue:.main)
 }
 func readVideo(_ v:NWConnection,generation:Int){v.receive(minimumIncompleteLength:1,maximumLength:65536){[weak self] data,_,end,error in
  guard let self,self.connectEpoch==generation,let key=self.clientKey,let playback=self.display?.playback else{return}
  guard let data,!data.isEmpty else{if end || error != nil{self.endClient()}else{self.readVideo(v,generation:generation)};return}
  playback.consume(data,sid:self.clientSID,key:key,prefix:self.clientPrefix){[weak self] result in DispatchQueue.main.async{
   guard let self,self.connectEpoch==generation else{return}
   switch result{
    case .success(let ids):for id in ids{self.receivedFrames+=1;self.sendClient("ACK \(id)")};if self.receivedFrames>0{self.display?.showMessage("");self.status.stringValue="已收到 \(self.requestedWidth) × \(self.requestedHeight) 画面。"};if end || error != nil{self.endClient()}else{self.readVideo(v,generation:generation)}
    case .failure(let error):self.status.stringValue=error.localizedDescription;self.endClient()
   }
  }}
 }}
 func sendClient(_ text:String){control?.send(content:Data((text+"\n").utf8),completion:.contentProcessed{_ in})}
 func endClient(){connectEpoch+=1;clientTimer?.invalidate();clientTimer=nil;control?.stateUpdateHandler=nil;viewer?.stateUpdateHandler=nil;control?.cancel();viewer?.cancel();control=nil;viewer=nil;clientBuffer=Data();parser=MacPreviewWire.Parser();clientKey=nil;receivedFrames=0;if let old=savedPresentation{NSApp.presentationOptions=old;savedPresentation=nil};display?.reset();display?.showMessage(status.stringValue);if role.selectedSegment==0{updateDevices()};writeHealth()}
 @objc func endCurrent(){sendClient("RELEASE");sendClient("END");endClient();endHostSession();if let w=videoWindow{videoWindow=nil;w.close()};display=nil}
 func windowWillClose(_ notification:Notification){if let w=notification.object as? NSWindow,w===videoWindow{videoWindow=nil;sendClient("END");endClient();display=nil}}
 func windowDidResignKey(_ notification:Notification){if let w=notification.object as? NSWindow,w===videoWindow{display?.restoreCursor();sendClient("RELEASE")}}
 func windowDidBecomeKey(_ notification:Notification){if let w=notification.object as? NSWindow,w===videoWindow{display?.updateCursor()}}
 func trace(_ event:String){lastEvent=event;writeHealth()}
 func writeHealth(){refreshThemedState();var values:[String:Any]=["event":lastEvent,"message":status.stringValue,"role":role?.selectedSegment ?? -1,"fullscreen":videoWindow != nil,"borderlessPanel":videoWindow?.styleMask.contains(.borderless) ?? false,"targetResolved":resolvedTarget != nil,"schema":"mac-preview-health-v1","synthetic":syntheticMode,"sending":sender != nil,"receiving":viewer != nil,"receivedFrames":receivedFrames,"submittedFrames":display?.frames ?? 0,"decoderState":display?.video.status.rawValue ?? 0,"width":requestedWidth,"height":requestedHeight,"viewportWidth":display?.bounds.width ?? 0,"viewportHeight":display?.bounds.height ?? 0,"screenPermission":CGPreflightScreenCaptureAccess(),"inputPermission":AXIsProcessTrusted(),"time":Date().timeIntervalSince1970];if let capture{values["capture"]=capture.stats()};if let sender{values["sender"]=sender.transportStats()};if let data=try? JSONSerialization.data(withJSONObject:values,options:[.sortedKeys]){try? FileManager.default.createDirectory(at:StoreIdentity.directory,withIntermediateDirectories:true);try? data.write(to:StoreIdentity.directory.appendingPathComponent("mac-preview-health.json"),options:.atomic)}}
 func applicationWillTerminate(_ notification:Notification){endCurrent();browser.stop();stopHostListener()}
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
private extension Character {var isASCIIControl:Bool{unicodeScalars.contains{$0.value<32 || $0.value==127}}}
#endif
