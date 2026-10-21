import AppKit

final class StoreDashboard:NSView {
 let scroll=NSScrollView(),document=StoreDashboardDocument()
 var diagnostics:NSTextView{document.diagnostics}
 init(target:AnyObject,stop:Selector,screen:Selector,access:Selector,network:Selector,relayConfig:Selector,start:Selector,power:Selector,powerSettings:Selector,remoteAccess:Selector){super.init(frame:NSRect(x:0,y:0,width:880,height:660));autoresizingMask=[.width,.height];wantsLayer=true;layer?.backgroundColor=BridgeTheme.fog.cgColor;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.borderType = .noBorder;scroll.documentView=document;addSubview(scroll);document.configure(target:target,stop:stop,screen:screen,access:access,network:network,start:start)}
 required init?(coder:NSCoder){nil}
 override func layout(){super.layout();scroll.frame=bounds;document.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(scroll.contentSize.height,document.desiredHeight));document.arrange()}
 func render(_ values:[String:Any]){document.render(values)}
 func startupFailed(_ message:String){document.render(["state":"error","statusMessage":message,"screenPermission":false,"inputPermission":false])}
}
final class StoreDashboardDocument:NSView {
 override var isFlipped:Bool{true}
 let brand=BridgeBrandMark(frame:.zero),name=BridgeTheme.label("映桥",size:28,weight:.semibold),tagline=BridgeTheme.label("让 Mac 与平板自然相连",size:13,color:BridgeTheme.muted),pill=BridgeStatusPill(frame:.zero)
 let hero=BridgeCard(frame:.zero),devices=BridgeDeviceView(frame:.zero),heading=BridgeTheme.label("扩展屏",size:25,weight:.semibold),explanation=BridgeTheme.label("把平板变成 Mac 的另一块屏幕。",size:14,color:BridgeTheme.muted,wrap:true),footnote=BridgeTheme.label("结束后停止传屏，保留附近设备发现。",size:12,color:BridgeTheme.muted,wrap:true)
 let permissions=BridgeCard(frame:.zero),permissionIcon=BridgeTheme.symbol("checkmark.shield"),permissionTitle=BridgeTheme.label("操作权限",size:16,weight:.semibold),screenTitle=BridgeTheme.label("屏幕共享",size:13,weight:.medium),inputTitle=BridgeTheme.label("键盘与触控板",size:13,weight:.medium),screenState=BridgeTheme.label("尚未申请",size:11,color:BridgeTheme.muted),inputState=BridgeTheme.label("尚未申请",size:11,color:BridgeTheme.muted)
 let nearby=BridgeCard(frame:.zero),nearbyIcon=BridgeTheme.symbol("ipad.landscape"),nearbyTitle=BridgeTheme.label("附近的 Pad",size:16,weight:.semibold),nearbyState=BridgeTheme.label("正在寻找平板…",size:13,weight:.medium),nearbyHint=BridgeTheme.label("两端打开映桥后，自动寻找附近设备。",size:12,color:BridgeTheme.muted,wrap:true),nearbySelector=NSPopUpButton(frame:.zero,pullsDown:false)
 // Detached compatibility sink; operational diagnostics remain in local log files.
 let diagnostics=NSTextView()
 var startButton:BridgeActionButton!,stopButton:BridgeActionButton!,screenButton:BridgeActionButton!,inputButton:BridgeActionButton!,networkButton:BridgeActionButton!
 var desiredHeight:CGFloat{570}
 func configure(target:AnyObject,stop:Selector,screen:Selector,access:Selector,network:Selector,start:Selector){
  for view in [brand,name,tagline,pill,hero,permissions,nearby]{addSubview(view)}
  for view in [heading,explanation,footnote,devices]{hero.addSubview(view)}
  for view in [permissionIcon,permissionTitle,screenTitle,inputTitle,screenState,inputState]{permissions.addSubview(view)}
  for view in [nearbyIcon,nearbyTitle,nearbyState,nearbyHint,nearbySelector]{nearby.addSubview(view)}
  startButton=BridgeTheme.button("开启扩展屏",target:target,action:start,primary:true);hero.addSubview(startButton)
  stopButton=BridgeTheme.button("结束会话",target:target,action:stop);hero.addSubview(stopButton)
  screenButton=BridgeTheme.button("允许录屏",target:target,action:screen);permissions.addSubview(screenButton)
  inputButton=BridgeTheme.button("允许控制",target:target,action:access);permissions.addSubview(inputButton)
  screenButton.setAccessibilityLabel("屏幕共享权限");inputButton.setAccessibilityLabel("键盘与触控板权限")
  nearbySelector.target=target;nearbySelector.action=#selector(StoreHost.selectNearbyPad(_:));nearbySelector.font = .systemFont(ofSize:13);nearbySelector.bezelStyle = .rounded;nearbySelector.setAccessibilityLabel("选择附近的平板")
  networkButton=BridgeTheme.button("刷新附近设备",target:target,action:network);nearby.addSubview(networkButton)
 }
 func arrange(){
  let pad:CGFloat=28,w=bounds.width-56,half=(w-18)/2
  brand.frame=NSRect(x:pad,y:26,width:52,height:52);name.frame=NSRect(x:pad+67,y:25,width:230,height:36);tagline.frame=NSRect(x:pad+68,y:63,width:300,height:19);pill.frame=NSRect(x:bounds.width-pad-108,y:36,width:108,height:29)
  hero.frame=NSRect(x:pad,y:102,width:w,height:226);devices.frame=NSRect(x:18,y:35,width:w*0.43,height:142)
  let hx=w*0.45;heading.frame=NSRect(x:hx,y:38,width:w-hx-22,height:34);explanation.frame=NSRect(x:hx,y:82,width:w-hx-32,height:70)
  startButton.frame=NSRect(x:24,y:178,width:142,height:34);footnote.frame=NSRect(x:183,y:177,width:w-346,height:40);stopButton.frame=NSRect(x:w-143,y:178,width:119,height:34)
  permissions.frame=NSRect(x:pad,y:346,width:half,height:196);nearby.frame=NSRect(x:pad+half+18,y:346,width:half,height:196)
  permissionIcon.frame=NSRect(x:22,y:24,width:22,height:22);permissionTitle.frame=NSRect(x:54,y:24,width:half-76,height:23)
  screenTitle.frame=NSRect(x:23,y:75,width:142,height:19);screenState.frame=NSRect(x:23,y:98,width:142,height:17);screenButton.frame=NSRect(x:half-129,y:78,width:106,height:32)
  inputTitle.frame=NSRect(x:23,y:139,width:142,height:19);inputState.frame=NSRect(x:23,y:162,width:142,height:17);inputButton.frame=NSRect(x:half-129,y:142,width:106,height:32)
  nearbyIcon.frame=NSRect(x:22,y:24,width:22,height:22);nearbyTitle.frame=NSRect(x:54,y:24,width:half-76,height:23);nearbyState.frame=NSRect(x:23,y:63,width:half-46,height:20);nearbySelector.frame=NSRect(x:20,y:89,width:half-40,height:28);nearbyHint.frame=NSRect(x:23,y:121,width:half-46,height:29);networkButton.frame=NSRect(x:23,y:155,width:half-46,height:28)
 }
 func render(_ values:[String:Any]){
  let state=values["state"] as? String ?? "idle",active=state=="streaming",connecting=state=="connecting" || state=="stopping"
  let screen=values["screenPermission"] as? Bool ?? false,input=values["inputPermission"] as? Bool ?? false,screenRequested=values["screenPermissionRequested"] as? Bool ?? false,inputRequested=values["inputPermissionRequested"] as? Bool ?? false
  let local=values["localConnection"] as? [String:Any] ?? [:],pending=(local["pending"] as? Bool ?? false)||(values["invitationPending"] as? Bool ?? false)
  let serviceReady=values["localServiceReady"] as? Bool ?? false
  let rows=values["nearbyPads"] as? [[String:Any]] ?? [],selected=values["selectedPadID"] as? String ?? ""
  heading.stringValue=active ? "扩展屏已连接":"扩展屏";devices.active=active
  explanation.stringValue=values["statusMessage"] as? String ?? "把平板变成 Mac 的另一块屏幕。"
  pill.update(active ? "扩展屏中":state=="parked" ? "桌面已保留":pending || connecting ? "正在连接":!screen || !input ? "需要权限":!serviceReady ? "连接未就绪":rows.isEmpty ? "寻找平板":"已准备好",warning:!active && (!screen || !input || !serviceReady))
  startButton.enabled(StoreConnectionReadiness.canStart(service:serviceReady,permissions:screen && input,device:rows.contains(where:{$0["ready"] as? Bool ?? false}),busy:(values["preparing"] as? Bool ?? false) || active || connecting || pending || state=="parked"))
  startButton.title=pending ? "正在连接平板…":"开启扩展屏";startButton.refreshTitle();stopButton.enabled(active || connecting || pending || state=="parked")
  screenState.stringValue=screen ? "已允许":screenRequested ? "等待系统授权":"首次使用时申请";screenState.textColor=screen ? BridgeTheme.green:BridgeTheme.muted
  inputState.stringValue=input ? "已允许":inputRequested ? "等待系统授权":"首次使用时申请";inputState.textColor=input ? BridgeTheme.green:BridgeTheme.muted
  screenButton.title=screen || screenRequested ? "查看设置":"允许录屏";inputButton.title=input || inputRequested ? "查看设置":"允许控制";screenButton.refreshTitle();inputButton.refreshTitle()
  let previous=nearbySelector.selectedItem?.representedObject as? String
  nearbySelector.removeAllItems()
  if rows.isEmpty{nearbySelector.addItem(withTitle:"尚未发现平板");nearbyState.stringValue="正在寻找平板…";nearbyHint.stringValue="请在平板上打开映桥。"}
  else{
   if rows.count>1 && selected.isEmpty{nearbySelector.addItem(withTitle:"选择一台平板")}
   let names=rows.compactMap{$0["name"] as? String}
   for row in rows{guard let id=row["id"] as? String,let name=row["name"] as? String else{continue};let label=names.filter{$0==name}.count>1 ? name+" · "+String(id.prefix(4)).uppercased():name;nearbySelector.addItem(withTitle:label);nearbySelector.lastItem?.representedObject=id}
   let desired=selected.isEmpty ? previous:selected;if let item=nearbySelector.itemArray.first(where:{($0.representedObject as? String)==desired}){nearbySelector.select(item)}
   nearbyState.stringValue="发现 \(rows.count) 台平板";nearbyHint.stringValue=rows.count==1 ? "点击开启扩展屏，首次连接需确认。":"先选择平板，再开启扩展屏。"
  }
  nearbySelector.isEnabled=rows.count>1 && !active && !pending;networkButton.enabled(!(values["preparing"] as? Bool ?? false))
  footnote.stringValue="结束后停止传屏，保留附近设备发现。"
 }
}
