import AppKit

enum BridgeTheme {
 static let fog=color(0xF5F7F6),ink=color(0x172D2C),green=color(0x23796C),muted=color(0x748581),line=color(0xE2E9E5),mint=color(0xE8F2ED),amber=color(0x986727)
 static func color(_ hex:UInt32)->NSColor{NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)}
 static func label(_ text:String,size:CGFloat=14,weight:NSFont.Weight = .regular,color:NSColor=ink,wrap:Bool=false)->NSTextField{
  let view=wrap ? NSTextField(wrappingLabelWithString:text):NSTextField(labelWithString:text)
  view.font = .systemFont(ofSize:size,weight:weight);view.textColor=color;view.isSelectable=false;view.maximumNumberOfLines=wrap ? 3:1;return view
 }
 static func symbol(_ name:String,size:CGFloat=18)->NSImageView{let view=NSImageView();view.image=NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:size,weight:.medium));view.contentTintColor=green;view.imageScaling = .scaleProportionallyDown;return view}
 static func button(_ title:String,target:AnyObject?,action:Selector,primary:Bool=false)->BridgeActionButton{BridgeActionButton(title:title,target:target,action:action,primary:primary)}
 static func fitDiagnostics(_ view:NSTextView,minimumHeight:CGFloat){guard let container=view.textContainer,let manager=view.layoutManager else{return};manager.ensureLayout(for:container);let height=max(minimumHeight,ceil(manager.usedRect(for:container).height+view.textContainerInset.height*2));if view.frame.height != height{view.setFrameSize(NSSize(width:view.frame.width,height:height))}}
}

final class BridgeActionButton:NSButton {
 let primary:Bool
 init(title:String,target:AnyObject?,action:Selector,primary:Bool){self.primary=primary;super.init(frame:.zero);self.title=title;self.target=target;self.action=action;setButtonType(.momentaryPushIn);isBordered=false;wantsLayer=true;layer?.cornerRadius=11;layer?.cornerCurve = .continuous;layer?.backgroundColor=(primary ? BridgeTheme.green:BridgeTheme.mint).cgColor;refreshTitle()}
 required init?(coder:NSCoder){nil}
 func refreshTitle(){attributedTitle=NSAttributedString(string:title,attributes:[.font:NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:primary ? NSColor.white:BridgeTheme.green]);alphaValue=isEnabled ? 1:0.45}
 func enabled(_ value:Bool){isEnabled=value;refreshTitle()}
}

final class BridgeCard:NSView {
 override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.white.cgColor;layer?.cornerRadius=20;layer?.cornerCurve = .continuous;layer?.borderWidth=1;layer?.borderColor=BridgeTheme.line.cgColor}
 required init?(coder:NSCoder){nil}
 override var isFlipped:Bool{true}
}

final class BridgeBrandMark:NSView {
 override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.cornerRadius=15;layer?.cornerCurve = .continuous;layer?.backgroundColor=BridgeTheme.green.cgColor;setAccessibilityLabel("映桥")}
 required init?(coder:NSCoder){nil}
 override func draw(_ dirtyRect:NSRect){super.draw(dirtyRect);let p=NSBezierPath();p.lineWidth=2.3;p.lineCapStyle = .round;NSColor.white.setStroke();p.move(to:NSPoint(x:12,y:18));p.line(to:NSPoint(x:12,y:29));p.curve(to:NSPoint(x:40,y:29),controlPoint1:NSPoint(x:19,y:41),controlPoint2:NSPoint(x:33,y:41));p.line(to:NSPoint(x:40,y:18));p.stroke();let base=NSBezierPath();base.lineWidth=2.3;base.lineCapStyle = .round;base.move(to:NSPoint(x:18,y:17));base.line(to:NSPoint(x:34,y:17));base.stroke()}
}

final class BridgeStatusPill:NSView {
 let label=BridgeTheme.label("待命",size:12,weight:.semibold,color:BridgeTheme.green)
 var tone=BridgeTheme.green
 override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.cornerRadius=14;layer?.cornerCurve = .continuous;layer?.backgroundColor=BridgeTheme.mint.cgColor;addSubview(label)}
 required init?(coder:NSCoder){nil}
 override func layout(){super.layout();label.frame=NSRect(x:24,y:(bounds.height-18)/2,width:bounds.width-32,height:18)}
 func update(_ text:String,warning:Bool=false){guard label.stringValue != text || tone != (warning ? BridgeTheme.amber:BridgeTheme.green) else{return};label.stringValue=text;tone=warning ? BridgeTheme.amber:BridgeTheme.green;label.textColor=tone;layer?.backgroundColor=(warning ? BridgeTheme.color(0xF8EEDD):BridgeTheme.mint).cgColor;needsDisplay=true}
 override func draw(_ rect:NSRect){super.draw(rect);tone.setFill();NSBezierPath(ovalIn:NSRect(x:12,y:(bounds.height-6)/2,width:6,height:6)).fill()}
}

final class BridgeDeviceView:NSView {
 var peerIsMac=false {didSet{needsDisplay=true;setAccessibilityLabel(peerIsMac ? "两台 Mac 连接示意":"Mac 与 平板 连接示意")}}
 var active=false{didSet{if oldValue != active{needsDisplay=true}}}
 override init(frame:NSRect){super.init(frame:frame);setAccessibilityLabel("Mac 与 平板 连接示意")}
 required init?(coder:NSCoder){nil}
 override func draw(_ rect:NSRect){
  super.draw(rect);let x=(bounds.width-274)/2,y=(bounds.height-92)/2
  let mac=NSRect(x:x,y:y+26,width:106,height:64),pad=NSRect(x:x+164,y:y+20,width:110,height:73)
  func shape(_ r:NSRect,fill:NSColor,border:NSColor,radius:CGFloat){let path=NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius);fill.setFill();path.fill();border.setStroke();path.lineWidth=1.5;path.stroke()}
  shape(mac,fill:BridgeTheme.mint,border:BridgeTheme.green,radius:8);shape(mac.insetBy(dx:7,dy:7),fill:NSColor.white,border:BridgeTheme.line,radius:3)
  let stand=NSBezierPath();stand.lineWidth=2;stand.move(to:NSPoint(x:x+53,y:y+26));stand.line(to:NSPoint(x:x+53,y:y+12));stand.move(to:NSPoint(x:x+37,y:y+11));stand.line(to:NSPoint(x:x+69,y:y+11));BridgeTheme.green.setStroke();stand.stroke()
  shape(pad,fill:BridgeTheme.mint,border:BridgeTheme.green,radius:9);shape(pad.insetBy(dx:5,dy:5),fill:NSColor.white,border:BridgeTheme.line,radius:5)
  let connection=NSBezierPath();connection.lineWidth=1.5;connection.move(to:NSPoint(x:x+115,y:y+55));connection.line(to:NSPoint(x:x+155,y:y+55));BridgeTheme.line.setStroke();connection.stroke()
  (active ? BridgeTheme.green:BridgeTheme.muted).setFill();for dx in [118.0,133.0,148.0]{NSBezierPath(ovalIn:NSRect(x:x+dx,y:y+52,width:6,height:6)).fill()}
  let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:BridgeTheme.muted]
  "Mac".draw(at:NSPoint(x:x+40,y:y-10),withAttributes:attrs);(peerIsMac ? "Mac":"平板").draw(at:NSPoint(x:x+181,y:y-10),withAttributes:attrs)
 }
}
