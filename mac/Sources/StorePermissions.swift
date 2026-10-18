import AppKit
import CoreGraphics
import ApplicationServices

extension StoreHost {
 var mediaPermissionsReady:Bool{CGPreflightScreenCaptureAccess() && AXIsProcessTrusted()}
 func explainInitialPermissions(){
  guard !UserDefaults.standard.bool(forKey:"store.permissionExplanation.v1") else{prepare();return}
  let alert=NSAlert();permissionAlert=alert;alert.messageText="让平板成为 Mac 的扩展屏"
  alert.informativeText="录屏与辅助功能是画面显示和键鼠操作所必需的权限。本地网络用于寻找附近设备；录屏权限仅用于把扩展桌面的画面传到平板；辅助功能用于把你在平板上的键盘、鼠标和触控操作交给 Mac。\n\n接下来由 macOS 申请这些权限。你也可以稍后再开启；设备发现仍可使用。"
  alert.addButton(withTitle:"继续设置");alert.addButton(withTitle:"稍后")
  alert.beginSheetModal(for:window){[weak self] response in DispatchQueue.main.async{
   guard let self else{return};self.permissionAlert=nil;UserDefaults.standard.set(true,forKey:"store.permissionExplanation.v1");self.prepare()
   if response == .alertFirstButtonReturn{self.requestPermission(.screen,explained:true)}
  }}
 }
 enum StorePermissionKind:Equatable {case screen,input}
 func requestPermission(_ kind:StorePermissionKind,explained:Bool=false){
  if kind == .screen && CGPreflightScreenCaptureAccess(){if explained{requestPermission(.input,explained:true)};return}
  if kind == .input && AXIsProcessTrusted(){updateDashboard();return}
  if !explained {
   guard permissionAlert==nil else{return};let alert=NSAlert();permissionAlert=alert
   alert.messageText=kind == .screen ? "允许显示扩展桌面":"允许平板控制 Mac"
   alert.informativeText=kind == .screen ? "映桥需要录屏权限，把你选择的扩展桌面实时显示在平板上。画面只发送给已确认连接的平板，不会录制或保存。":"映桥需要辅助功能权限，把平板上的键盘、鼠标和触摸操作交给 Mac。结束会话后停止转发输入。"
   alert.addButton(withTitle:"继续");alert.addButton(withTitle:"稍后")
   alert.beginSheetModal(for:window){[weak self] response in DispatchQueue.main.async{guard let self else{return};self.permissionAlert=nil;if response == .alertFirstButtonReturn{self.requestPermission(kind,explained:true)}}};return
  }
  if kind == .screen{UserDefaults.standard.set(true,forKey:"store.screenPermissionRequested");_ = CGRequestScreenCaptureAccess();statusMessage="请完成 macOS 的录屏授权，设备发现会继续运行。";continueInputAfterScreen=true}
  else{UserDefaults.standard.set(true,forKey:"store.inputPermissionRequested");_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary);statusMessage="请完成 macOS 的辅助功能授权。"}
  beginPermissionObservation();updateDashboard()
 }
 func beginPermissionObservation(){
  permissionObservationUntil=ProcessInfo.processInfo.systemUptime+120;guard permissionTimer==nil else{return}
  permissionTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in DispatchQueue.main.async{
   guard let self else{return};if self.continueInputAfterScreen && CGPreflightScreenCaptureAccess(){self.continueInputAfterScreen=false;self.requestPermission(.input,explained:true)}
   self.updateDashboard()
   if self.mediaPermissionsReady{self.permissionTimer?.invalidate();self.permissionTimer=nil;if let id=self.pendingPermissionPadID{self.pendingPermissionPadID=nil;self.performStartExtension(id)};return}
   if ProcessInfo.processInfo.systemUptime>=self.permissionObservationUntil{self.permissionTimer?.invalidate();self.permissionTimer=nil;self.pendingPermissionPadID=nil}
  }}
 }
 @objc func screenPermission(){
  if UserDefaults.standard.bool(forKey:"store.screenPermissionRequested") || CGPreflightScreenCaptureAccess(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!);beginPermissionObservation()}
  else{requestPermission(.screen)}
 }
 @objc func accessPermission(){
  if UserDefaults.standard.bool(forKey:"store.inputPermissionRequested") || AXIsProcessTrusted(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!);beginPermissionObservation()}
  else{requestPermission(.input)}
 }
 @discardableResult func requireMediaPermissions()->Bool{
  guard !mediaPermissionsReady else{return true};statusMessage="需要录屏和辅助功能权限，才能开始扩展屏。"
  if !CGPreflightScreenCaptureAccess(){if !UserDefaults.standard.bool(forKey:"store.screenPermissionRequested"){requestPermission(.screen)}else{beginPermissionObservation()}}
  else if !AXIsProcessTrusted(){if !UserDefaults.standard.bool(forKey:"store.inputPermissionRequested"){requestPermission(.input)}else{beginPermissionObservation()}}
  return false
 }
}
