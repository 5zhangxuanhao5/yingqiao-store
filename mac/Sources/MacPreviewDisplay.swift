#if MAC_RECEIVER_PREVIEW
import AppKit
import AVFoundation
import VideoToolbox
import CryptoKit

// Network decryption and sample construction stay off the AppKit thread.
// Only one receive is admitted until its decode submission completes, so a
// slow receiver cannot accumulate an unbounded application work queue.
final class MacPreviewPlayback {
 let video=AVSampleBufferDisplayLayer(),queue=DispatchQueue(label:"yingqiao.macpreview.decode",qos:.userInteractive)
 let lock=NSLock();private var retired=false,count=0
 var format:CMVideoFormatDescription?,parameters:[Int:Data]=[:],hevc=true,parser=MacPreviewWire.Parser()
 var frames:Int{lock.lock();defer{lock.unlock()};return count}
 func setCodec(hevc:Bool){queue.async{self.hevc=hevc}}
 func reset(){lock.lock();retired=true;lock.unlock();queue.async{self.video.flushAndRemoveImage();self.format=nil;self.parameters=[:];self.parser=MacPreviewWire.Parser()}}
 func consume(_ bytes:Data,sid:UInt32,key:SymmetricKey,prefix:Data,completion:@escaping(Result<[UInt64],Error>)->Void){
  queue.async{self.lock.lock();let active = !self.retired;self.lock.unlock();guard active else{return}
   do{var ids:[UInt64]=[];for (id,_,frame) in try self.parser.append(bytes,sid:sid,key:key,prefix:prefix){try self.enqueue(frame);ids.append(id)};completion(.success(ids))}catch{completion(.failure(error))}
  }
 }

 var send:((String)->Void)?,finish:(()->Void)?
 func enqueue(_ frame:Data)throws{
  var sampleNALs:[Data]=[]
  for nal in MacPreviewWire.nals(frame){
   guard let first=nal.first else{continue};let type=hevc ? Int((first>>1)&63):Int(first&31)
   if (hevc ? [32,33,34]:[7,8]).contains(type){if parameters[type] != nal{parameters[type]=nal;format=nil}}
   else if !(hevc ? [35,38]:[9,12]).contains(type){sampleNALs.append(nal)}
  }
  if format==nil {
   let keys=hevc ? [32,33,34]:[7,8];guard keys.allSatisfy({parameters[$0] != nil}) else{return}
   let blocks=keys.map{parameters[$0]! as NSData},ptrs=blocks.map{$0.bytes.assumingMemoryBound(to:UInt8.self)},sizes=blocks.map{$0.length}
   let result=ptrs.withUnsafeBufferPointer{p in sizes.withUnsafeBufferPointer{n in
    if hevc{return CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:3,parameterSetPointers:p.baseAddress!,parameterSetSizes:n.baseAddress!,nalUnitHeaderLength:4,extensions:nil,formatDescriptionOut:&format)}
    return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:2,parameterSetPointers:p.baseAddress!,parameterSetSizes:n.baseAddress!,nalUnitHeaderLength:4,formatDescriptionOut:&format)
   }}
   guard result==noErr else{throw MacPreviewWire.failure("视频格式初始化失败：\(result)")}
  }
  guard let format,!sampleNALs.isEmpty else{return};var bytes=Data()
  for nal in sampleNALs{bytes.appendBE(UInt32(nal.count));bytes.append(nal)}
  var block:CMBlockBuffer?
  guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:bytes.count,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:bytes.count,flags:0,blockBufferOut:&block)==kCMBlockBufferNoErr,let block else{throw MacPreviewWire.failure("视频缓冲分配失败")}
  let copied=bytes.withUnsafeBytes{CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block,offsetIntoDestination:0,dataLength:bytes.count)}
  guard copied==kCMBlockBufferNoErr else{throw MacPreviewWire.failure("视频缓冲复制失败")}
  var sample:CMSampleBuffer?,size=bytes.count
  guard CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:1,sampleTimingEntryCount:0,sampleTimingArray:nil,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample)==noErr,let sample else{throw MacPreviewWire.failure("视频样本生成失败")}
  if let rows=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true) as? [NSMutableDictionary],let row=rows.first{row[kCMSampleAttachmentKey_DisplayImmediately]=true}
  if video.status == .failed{throw video.error ?? MacPreviewWire.failure("系统解码器未能播放画面")}
  video.enqueue(sample);lock.lock();count+=1;lock.unlock()
 }
}
final class MacPreviewWindow:NSWindow {
 override var canBecomeKey:Bool{true}
 override var canBecomeMain:Bool{true}
}
final class MacPreviewDisplay:NSView {
 let playback=MacPreviewPlayback()
 let message=NSTextField(wrappingLabelWithString:"正在连接，请在发送端确认连接请求…")
 var video:AVSampleBufferDisplayLayer{playback.video}
 var frames:Int{playback.frames}
 var send:((String)->Void)?,finish:(()->Void)?
 private var cursorHidden=false
 override var acceptsFirstResponder:Bool{true}
 override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=NSColor.black.cgColor;video.videoGravity = .resizeAspect;layer?.addSublayer(video);message.textColor = .white;message.alignment = .center;message.font = .systemFont(ofSize:20);message.translatesAutoresizingMaskIntoConstraints=false;addSubview(message);NSLayoutConstraint.activate([message.centerXAnchor.constraint(equalTo:centerXAnchor),message.centerYAnchor.constraint(equalTo:centerYAnchor),message.widthAnchor.constraint(lessThanOrEqualTo:widthAnchor,multiplier:0.85)])}
 required init?(coder:NSCoder){nil}
 override func layout(){super.layout();CATransaction.begin();CATransaction.setDisableActions(true);video.frame=bounds;CATransaction.commit()}
 override func updateTrackingAreas(){super.updateTrackingAreas();for a in trackingAreas{removeTrackingArea(a)};addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil))}
 func updateCursor(){let inside=window.map{bounds.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil)) && $0.isKeyWindow} ?? false;if inside && !cursorHidden{NSCursor.hide();cursorHidden=true}else if !inside{restoreCursor()}}
 func restoreCursor(){if cursorHidden{NSCursor.unhide();cursorHidden=false}}
 override func mouseEntered(with event:NSEvent){updateCursor()}
 override func mouseExited(with event:NSEvent){restoreCursor()}
 func reset(){restoreCursor();playback.reset()}
 func showMessage(_ text:String){message.stringValue=text;message.isHidden=text.isEmpty}
 func move(_ event:NSEvent){updateCursor();let p=convert(event.locationInWindow,from:nil);guard bounds.width>0,bounds.height>0 else{return};send?("MOVE \(p.x/bounds.width) \(1-p.y/bounds.height)")}
 override func mouseMoved(with event:NSEvent){move(event)}
 override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);move(event);send?("BUTTON 0 1 \(max(1,min(3,event.clickCount)))")}
 override func mouseDragged(with event:NSEvent){move(event)}
 override func mouseUp(with event:NSEvent){move(event);send?("BUTTON 0 0")}
 override func rightMouseDown(with event:NSEvent){move(event);send?("BUTTON 1 1")}
 override func rightMouseDragged(with event:NSEvent){move(event)}
 override func rightMouseUp(with event:NSEvent){send?("BUTTON 1 0")}
 override func scrollWheel(with event:NSEvent){move(event);send?("SCROLL \(Int32(max(-10000,min(10000,event.scrollingDeltaY*3)))) \(Int32(max(-10000,min(10000,event.scrollingDeltaX*3))))")}
 override func keyDown(with event:NSEvent){if event.keyCode==53{finish?();return};send?("KEY \(event.keyCode) 1")}
 override func keyUp(with event:NSEvent){send?("KEY \(event.keyCode) 0")}
 override func flagsChanged(with event:NSEvent){let flags:[UInt16:NSEvent.ModifierFlags]=[55:.command,54:.command,56:.shift,60:.shift,58:.option,61:.option,59:.control,62:.control,57:.capsLock];if let flag=flags[event.keyCode]{send?("KEY \(event.keyCode) \(event.modifierFlags.contains(flag) ? 1:0)")}}
}
#endif
