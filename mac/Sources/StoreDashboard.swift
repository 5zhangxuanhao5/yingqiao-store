import AppKit

final class StoreDashboard:NSView {
 let scroll=NSScrollView(),document=StoreDashboardDocument()
 var diagnostics:NSTextView{document.diagnostics}
 init(target:AnyObject,stop:Selector,screen:Selector,access:Selector,network:Selector,relayConfig:Selector,start:Selector,power:Selector,powerSettings:Selector,remoteAccess:Selector){super.init(frame:NSRect(x:0,y:0,width:880,height:660));autoresizingMask=[.width,.height];wantsLayer=true;layer?.backgroundColor=BridgeTheme.fog.cgColor;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.borderType = .noBorder;scroll.documentView=document;addSubview(scroll);document.configure(target:target,stop:stop,screen:screen,access:access,network:network,relayConfig:relayConfig,start:start,power:power,powerSettings:powerSettings,remoteAccess:remoteAccess);document.onSizeChange={[weak self] in self?.needsLayout=true}}
 required init?(coder:NSCoder){nil}
 override func layout(){super.layout();scroll.frame=bounds;document.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(scroll.contentSize.height,document.desiredHeight));document.arrange()}
 func render(_ values:[String:Any]){document.render(values)}
 func startupFailed(_ message:String){document.render(["state":"error","lastError":message,"screenPermission":false,"inputPermission":false,"networkHelperRunning":false])}
}

final class StoreDashboardDocument:NSView {
 override var isFlipped:Bool{true}
 let brand=BridgeBrandMark(frame:.zero),name=BridgeTheme.label("映桥测试版",size:28,weight:.semibold),tagline=BridgeTheme.label("让 Mac 与平板自然相连",size:13,color:BridgeTheme.muted),pill=BridgeStatusPill(frame:.zero)
 let hero=BridgeCard(frame:.zero),devices=BridgeDeviceView(frame:.zero),heading=BridgeTheme.label("Mac 已准备好",size:25,weight:.semibold),explanation=BridgeTheme.label("在平板上选择这台 Mac，即可开始。",size:14,color:BridgeTheme.muted,wrap:true),mode=BridgeTheme.label("低功耗待命",size:12,weight:.medium,color:BridgeTheme.green),footnote=BridgeTheme.label("结束会话后自动停止传屏，保留随时连接的能力。",size:12,color:BridgeTheme.muted,wrap:true)
 let permissions=BridgeCard(frame:.zero),permissionIcon=BridgeTheme.symbol("checkmark.shield"),permissionTitle=BridgeTheme.label("操作权限",size:16,weight:.semibold),screenTitle=BridgeTheme.label("屏幕共享",size:13,weight:.medium),inputTitle=BridgeTheme.label("键盘与触控板",size:13,weight:.medium),screenState=BridgeTheme.label("待确认",size:11,color:BridgeTheme.muted),inputState=BridgeTheme.label("待确认",size:11,color:BridgeTheme.muted)
 let internet=BridgeCard(frame:.zero),networkIcon=BridgeTheme.symbol("network"),networkTitle=BridgeTheme.label("自动发现",size:16,weight:.semibold),networkState=BridgeTheme.label("正在准备",size:13,weight:.medium),networkHint=BridgeTheme.label("两台设备分别上网，也能在 Edge 上发起远控。",size:12,color:BridgeTheme.muted,wrap:true)
 let disclosure=NSButton(),diagScroll=NSScrollView(),diagnostics=NSTextView()
 let powerCard=BridgeCard(frame:.zero),powerIcon=BridgeTheme.symbol("laptopcomputer"),powerTitle=BridgeTheme.label("合盖远控待命",size:16,weight:.semibold),powerState=BridgeTheme.label("尚未开启联动",size:13,weight:.medium),powerHint=BridgeTheme.label("结束远控只停传屏，后台任务继续运行。",size:12,color:BridgeTheme.muted,wrap:true)
 var remoteAccessButton:BridgeActionButton!
 var startButton:BridgeActionButton!,stopButton:BridgeActionButton!,screenButton:BridgeActionButton!,inputButton:BridgeActionButton!,networkButton:BridgeActionButton!,relayConfigButton:BridgeActionButton!,powerButton:BridgeActionButton!,powerSettingsButton:BridgeActionButton!
 var diagnosticsOpen=false,onSizeChange:(()->Void)?
 var desiredHeight:CGFloat{diagnosticsOpen ? 810:590}
 func configure(target:AnyObject,stop:Selector,screen:Selector,access:Selector,network:Selector,relayConfig:Selector,start:Selector,power:Selector,powerSettings:Selector,remoteAccess:Selector){
  for view in [brand,name,tagline,pill,hero,permissions,internet,disclosure,diagScroll]{addSubview(view)}
  for view in [heading,explanation,mode,footnote,devices]{hero.addSubview(view)}
  for view in [permissionIcon,permissionTitle,screenTitle,inputTitle,screenState,inputState]{permissions.addSubview(view)}
  for view in [networkIcon,networkTitle,networkState,networkHint]{internet.addSubview(view)}
  startButton=BridgeTheme.button("连接扩展屏",target:target,action:start,primary:true);hero.addSubview(startButton)
  stopButton=BridgeTheme.button("结束会话",target:target,action:stop);hero.addSubview(stopButton)
  screenButton=BridgeTheme.button("查看设置",target:target,action:screen);permissions.addSubview(screenButton)
  inputButton=BridgeTheme.button("查看设置",target:target,action:access);permissions.addSubview(inputButton)
  screenButton.setAccessibilityLabel("屏幕共享权限设置");inputButton.setAccessibilityLabel("键盘与触控板权限设置")
  networkButton=BridgeTheme.button("刷新连接",target:target,action:network,primary:true);internet.addSubview(networkButton)
  relayConfigButton=BridgeTheme.button("远控配置",target:target,action:relayConfig);relayConfigButton.isHidden=true;relayConfigButton.setAccessibilityLabel("远控连接配置")
  for view in [powerIcon,powerTitle,powerState,powerHint]{powerCard.addSubview(view)}
  powerButton=BridgeTheme.button("开启合盖待命",target:target,action:power,primary:true);powerCard.addSubview(powerButton)
  powerSettingsButton=BridgeTheme.button("合盖设置",target:target,action:powerSettings);powerCard.addSubview(powerSettingsButton)
  remoteAccessButton=BridgeTheme.button("开启远控待机",target:target,action:remoteAccess,primary:true);remoteAccessButton.isHidden=true
  disclosure.title="连接诊断";disclosure.isBordered=false;disclosure.font = .systemFont(ofSize:12,weight:.medium);disclosure.contentTintColor=BridgeTheme.muted;disclosure.image=NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil);disclosure.imagePosition = .imageLeading;disclosure.target=self;disclosure.action=#selector(toggleDiagnostics)
  diagScroll.isHidden=true;diagScroll.drawsBackground=true;diagScroll.backgroundColor=NSColor.white;diagScroll.hasVerticalScroller=true;diagScroll.borderType = .noBorder;diagScroll.wantsLayer=true;diagScroll.layer?.cornerRadius=14;diagScroll.layer?.borderWidth=1;diagScroll.layer?.borderColor=BridgeTheme.line.cgColor
  diagnostics.isEditable=false;diagnostics.isSelectable=true;diagnostics.font = .monospacedSystemFont(ofSize:11,weight:.regular);diagnostics.textColor=BridgeTheme.muted;diagnostics.backgroundColor=NSColor.white;diagnostics.textContainerInset=NSSize(width:12,height:12);diagnostics.isVerticallyResizable=true;diagnostics.isHorizontallyResizable=false;diagnostics.maxSize=NSSize(width:1_000_000,height:10_000_000);diagnostics.textContainer?.widthTracksTextView=true;diagnostics.autoresizingMask=[.width];diagScroll.documentView=diagnostics
 }
 @objc func toggleDiagnostics(){diagnosticsOpen.toggle();diagScroll.isHidden = !diagnosticsOpen;disclosure.image=NSImage(systemSymbolName:diagnosticsOpen ? "chevron.down":"chevron.right",accessibilityDescription:nil);onSizeChange?();needsLayout=true}
 func arrange(){
  let pad:CGFloat=28,w=bounds.width-56,half=(w-18)/2
  brand.frame=NSRect(x:pad,y:26,width:52,height:52);name.frame=NSRect(x:pad+67,y:25,width:230,height:36);tagline.frame=NSRect(x:pad+68,y:63,width:300,height:19);pill.frame=NSRect(x:bounds.width-pad-108,y:36,width:108,height:29)
  hero.frame=NSRect(x:pad,y:102,width:w,height:226)
  devices.frame=NSRect(x:18,y:35,width:w*0.43,height:142)
  let hx=w*0.45;heading.frame=NSRect(x:hx,y:38,width:w-hx-22,height:34);explanation.frame=NSRect(x:hx,y:82,width:w-hx-32,height:54);mode.frame=NSRect(x:hx,y:147,width:w-hx-28,height:18)
  startButton.frame=NSRect(x:24,y:178,width:142,height:34);footnote.frame=NSRect(x:183,y:177,width:w-346,height:40);stopButton.frame=NSRect(x:w-143,y:178,width:119,height:34)
  permissions.frame=NSRect(x:pad,y:346,width:half,height:196);internet.frame=NSRect(x:pad+half+18,y:346,width:half,height:196)
  permissionIcon.frame=NSRect(x:22,y:24,width:22,height:22);permissionTitle.frame=NSRect(x:54,y:24,width:half-76,height:23)
  screenTitle.frame=NSRect(x:23,y:75,width:142,height:19);screenState.frame=NSRect(x:23,y:98,width:142,height:17);screenButton.frame=NSRect(x:half-129,y:78,width:106,height:32)
  inputTitle.frame=NSRect(x:23,y:139,width:142,height:19);inputState.frame=NSRect(x:23,y:162,width:142,height:17);inputButton.frame=NSRect(x:half-129,y:142,width:106,height:32)
  networkIcon.frame=NSRect(x:22,y:24,width:22,height:22);networkTitle.frame=NSRect(x:54,y:24,width:half-76,height:23);networkState.frame=NSRect(x:23,y:76,width:half-46,height:20);networkHint.frame=NSRect(x:23,y:104,width:half-46,height:36);networkButton.frame=NSRect(x:23,y:150,width:half-46,height:32);relayConfigButton.frame=NSRect(x:half-131,y:150,width:108,height:32)
  powerCard.frame=NSRect(x:pad,y:560,width:w,height:136)
  powerIcon.frame=NSRect(x:22,y:23,width:22,height:22);powerTitle.frame=NSRect(x:54,y:22,width:250,height:24)
  powerState.frame=NSRect(x:23,y:62,width:w-325,height:20);powerHint.frame=NSRect(x:23,y:90,width:w-325,height:34)
  powerButton.frame=NSRect(x:w-276,y:25,width:145,height:34);powerSettingsButton.frame=NSRect(x:w-119,y:25,width:96,height:34)
  remoteAccessButton.frame=NSRect(x:hx,y:138,width:180,height:32);mode.isHidden=true
  disclosure.frame=NSRect(x:pad+2,y:556,width:110,height:28);diagScroll.frame=NSRect(x:pad,y:596,width:w,height:226);diagnostics.frame=NSRect(x:0,y:0,width:w,height:max(226,diagnostics.frame.height));BridgeTheme.fitDiagnostics(diagnostics,minimumHeight:226)
 }
 func render(_ values:[String:Any]){
  let state=values["state"] as? String ?? "idle",error=values["lastError"] as? String ?? "",active=state=="streaming",connecting=state=="connecting" || state=="stopping",failed=state=="error" || (!error.isEmpty && !active && !connecting)
  let screen=values["screenPermission"] as? Bool ?? false,input=values["inputPermission"] as? Bool ?? false,needsPermission = !active && !connecting && !failed && (!screen || !input)
  let extended=(values["mode"] as? String)=="extend"
  pill.update(failed ? "需要处理":active ? "正在传屏":connecting ? "正在连接":needsPermission ? "需要权限":"待命",warning:failed || needsPermission)
  heading.stringValue=failed ? "连接需要处理":active ? (extended ? "扩展屏已连接":"正在远控 Mac"):connecting ? "正在连接 Edge":needsPermission ? "完成权限设置即可连接":"Mac 已准备好"
  explanation.stringValue=failed ? error:active ? (extended ? "Edge 已成为 Mac 的另一块屏幕，两端都能操作。":"你可以在 Edge 上操作这台 Mac，结束后自动停止传屏。"):connecting ? "正在准备画面，请稍候。":needsPermission ? "请在下方允许屏幕共享与键鼠操作，再从 Edge 开启会话。":"在平板上选择这台 Mac，即可开始。"
  if state=="stopping"{heading.stringValue="正在结束会话";explanation.stringValue="正在释放画面，随后继续待命。"}
  explanation.textColor=failed ? BridgeTheme.amber:BridgeTheme.muted;devices.active=active
  mode.stringValue=failed ? "可查看权限或连接设置":active ? (extended ? "扩展屏会话":"远控会话"):connecting ? "连接中":needsPermission ? "在下方开启需要的权限":"低功耗待命"
  let local=values["localConnection"] as? [String:Any] ?? [:],pending=local["pending"] as? Bool ?? false
  startButton.enabled(values["localExtensionAvailable"] as? Bool ?? false && !pending);startButton.title=pending ? "正在请求 Edge…":"连接扩展屏";startButton.refreshTitle()
  stopButton.enabled(active || connecting || pending)
  let lid=values["lidReadiness"] as? [String:Any] ?? [:]
  footnote.stringValue=(lid["sleepDisabled"] as? Bool)==true ? "已检测到防休眠设置；合盖连接仍需实测。":"合盖待命前，请开启映桥的“合盖待命”。"
  let link=values["clamshellLink"] as? [String:Any] ?? [:],linkPhase=link["phase"] as? String ?? "off",linkEnabled=link["enabled"] as? Bool ?? false
  powerState.stringValue=linkPhase=="ready" ? "合盖保护已确认":linkPhase=="preparing" ? "正在准备":linkPhase=="needsSetup" ? "需要完成联动设置":(lid["sleepDisabled"] as? Bool)==true ? "已检测到现有防休眠设置":"尚未开启联动"
  powerState.textColor=linkPhase=="ready" ? BridgeTheme.green:linkPhase=="needsSetup" ? BridgeTheme.amber:BridgeTheme.ink
  powerHint.stringValue=link["detail"] as? String ?? "结束远控只停传屏，后台任务继续运行。"
  powerButton.title=linkEnabled ? "关闭自动联动":"开启合盖待命";powerButton.refreshTitle()
  if values["headlessRemoteDisplay"] as? Bool==true{mode.stringValue="合盖远控工作台";footnote.stringValue="正在使用远控工作台；结束后释放画面与工作台。"}
  if !active && !connecting && !needsPermission && !failed{explanation.stringValue=pending ? "已向 Edge 发出请求，正在准备扩展屏。":"可在 Edge 开始会话，也可在这里连接扩展屏。"}
  if let error=local["lastError"] as? String,!error.isEmpty,!active,!connecting{explanation.stringValue=error}
  screenState.stringValue=screen ? "已允许":"需要允许";screenState.textColor=screen ? BridgeTheme.green:BridgeTheme.amber;screenButton.title=screen ? "查看设置":"开启权限";screenButton.refreshTitle()
  inputState.stringValue=input ? "已允许":"需要允许";inputState.textColor=input ? BridgeTheme.green:BridgeTheme.amber;inputButton.title=input ? "查看设置":"开启权限";inputButton.refreshTitle()
  remoteAccessButton.enabled(!(values["remoteAudioPermissionRevoking"] as? Bool ?? false) && !(values["remoteEnablePending"] as? Bool ?? false) && state != "stopping");remoteAccessButton.title=values["remoteAccessState"] as? String ?? "开启远控待机";remoteAccessButton.refreshTitle()
  let ready=values["networkHelperRunning"] as? Bool ?? false,networkError=values["networkHelperError"] as? String ?? ""
  networkState.stringValue=networkError.isEmpty ? (ready ? "已在后台待命":"正在准备连接"):"连接需要处理";networkState.textColor=networkError.isEmpty ? BridgeTheme.ink:BridgeTheme.amber
  networkHint.stringValue=networkError.isEmpty ? "两台设备分别上网，也能在 Edge 上发起远控。":networkError
  name.stringValue="映桥测试版";tagline.stringValue="让 Mac 与平板自然相连"
  explanation.stringValue=values["statusMessage"] as? String ?? "打开平板上的映桥测试版，自动发现后点击连接。"
  heading.stringValue=values["connected"] as? Bool == true ? "工作空间，已延展":(values["discoveryReady"] as? Bool == true ? "Mac 已准备好":"正在准备连接")
  networkState.stringValue=values["discoveryReady"] as? Bool == true ? "局域网可发现":"等待连接准备"
  networkHint.stringValue="两端打开后自动寻找设备，无需扫码、复制信息或输入地址。"
  footnote.stringValue="结束会话后停止采集和编码，保留设备自动发现。"
  startButton.enabled(!(values["preparing"] as? Bool ?? false));startButton.title=values["discoveryReady"] as? Bool == true ? "检查连接":"准备扩展屏";startButton.refreshTitle()
  pill.update(values["connected"] as? Bool == true ? "扩展屏中":(values["discoveryReady"] as? Bool == true ? "等待平板":"需要准备"))
  if diagnosticsOpen{BridgeTheme.fitDiagnostics(diagnostics,minimumHeight:226)}
 }
}
