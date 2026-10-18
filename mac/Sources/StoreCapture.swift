import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreVideo

final class StoreCapture:NSObject,SCStreamOutput,SCStreamDelegate {
 let width:Int,height:Int,fps:Int,codec:String,sender:StoreFrameSender
 let queue=DispatchQueue(label:"cn.edgelink.store.capture",qos:.userInteractive)
 var stream:SCStream?,encoder:VTCompressionSession?,virtual:CGVirtualDisplay?
 private var alive=false,inFlight=false,needsIDR=true
 private var targetBitrate=24_000_000
 var onFailure:((String)->Void)?
 init(width:Int,height:Int,fps:Int,codec:String,sender:StoreFrameSender){self.width=width;self.height=height;self.fps=fps;self.codec=codec;self.sender=sender}
 static func supports(_ codec:CMVideoCodecType)->Bool {var encoder:VTCompressionSession?;let r=VTCompressionSessionCreate(allocator:nil,width:1280,height:720,codecType:codec,encoderSpecification:[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:nil,refcon:nil,compressionSessionOut:&encoder);if let encoder{VTCompressionSessionInvalidate(encoder)};return r==noErr}
 func start(adopting:CGVirtualDisplay?=nil)async throws->CGDirectDisplayID {
  guard NSClassFromString("CGVirtualDisplay") != nil else{throw failure("这台 Mac 当前系统没有可用的扩展显示接口")}
  let d=CGVirtualDisplayDescriptor();d.name="映桥 · 平板扩展屏";d.maxPixelsWide=UInt32(width);d.maxPixelsHigh=UInt32(height);d.sizeInMillimeters=CGSize(width:300,height:300*Double(height)/Double(width));d.vendorID=0x5947;d.productID=0x5354;d.serialNum=UInt32(randomBytes(4).uintBE(0,4));d.queue=queue
  guard let display=adopting ?? CGVirtualDisplay(descriptor:d) else{throw failure("无法创建独立扩展屏")};virtual=display
  let settings=CGVirtualDisplaySettings();settings.hiDPI=0;settings.modes=[CGVirtualDisplayMode(width:UInt(width),height:UInt(height),refreshRate:Double(fps))];guard display.apply(settings) else{throw failure("扩展屏不支持所选尺寸")}
  // Only place the display we own; do not rearrange existing Sidecar/monitors.
  let main=CGDisplayBounds(CGMainDisplayID());var ids=[CGDirectDisplayID](repeating:0,count:32),count:UInt32=0
  guard CGGetActiveDisplayList(32,&ids,&count) == .success else{throw failure("显示器列表暂不可用")}
  let left=ids.prefix(Int(count)).filter{$0 != display.displayID}.map{CGDisplayBounds($0).minX}.min() ?? main.minX
  var layout:CGDisplayConfigRef?;guard CGBeginDisplayConfiguration(&layout) == .success,let layout else{throw failure("无法准备扩展屏排列")}
  guard CGConfigureDisplayOrigin(layout,display.displayID,Int32(left)-Int32(width),Int32(main.minY)) == .success else{CGCancelDisplayConfiguration(layout);throw failure("扩展屏排列失败")}
  guard CGCompleteDisplayConfiguration(layout,.forSession) == .success else{throw failure("系统未接受扩展屏排列")}

  var target:SCDisplay?
  for _ in 0..<10{let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true);target=content.displays.first{$0.displayID==display.displayID};if target != nil{break};try await Task.sleep(nanoseconds:200_000_000)}
  guard let target else{throw failure("系统暂未返回扩展屏画面；不会改为镜像已有桌面")}
  let type=codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264
  let result=VTCompressionSessionCreate(allocator:nil,width:Int32(width),height:Int32(height),codecType:type,encoderSpecification:[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:{refcon,_,status,_,buffer in guard status==noErr,let refcon,let buffer else{return};Unmanaged<StoreCapture>.fromOpaque(refcon).takeUnretainedValue().encoded(buffer)},refcon:Unmanaged.passUnretained(self).toOpaque(),compressionSessionOut:&encoder)
  guard result==noErr,let encoder else{throw failure("这台 Mac 不支持所选硬件编码器，请改用 H.264")}
  _ = try StoreEncoderSettings.apply(fps:fps){key,value in VTSessionSetProperty(encoder,key:key,value:value)}
  let c=SCStreamConfiguration();c.width=width;c.height=height;c.minimumFrameInterval=CMTime(value:1,timescale:Int32(fps));c.queueDepth=3;c.pixelFormat=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;c.showsCursor=true;c.capturesAudio=false
  let s=SCStream(filter:SCContentFilter(display:target,excludingWindows:[]),configuration:c,delegate:self);stream=s;try s.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue);queue.sync{alive=true};try await s.startCapture();return display.displayID
 }
 func stream(_ stream:SCStream,didStopWithError error:Error){onFailure?(error.localizedDescription)}
 func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType){guard type == .screen,alive,!inFlight,sender.canEncode,let encoder,let pixel=sample.imageBuffer else{return};inFlight=true
  let properties=needsIDR ? [kVTEncodeFrameOptionKey_ForceKeyFrame:true] as CFDictionary:nil;needsIDR=false
  let r=VTCompressionSessionEncodeFrame(encoder,imageBuffer:pixel,presentationTimeStamp:sample.presentationTimeStamp,duration:CMTime(value:1,timescale:Int32(fps)),frameProperties:properties,sourceFrameRefcon:nil,infoFlagsOut:nil);if r != noErr{inFlight=false;needsIDR=true}
 }
 private func encoded(_ sample:CMSampleBuffer){queue.async{[weak self] in guard let self else{return};defer{self.inFlight=false};guard self.alive,let description=sample.formatDescription,let block=sample.dataBuffer else{return}
  let flags=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[CFString:Any]],keyframe=(flags?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true;var frame=Data()
  if keyframe {for i in 0..<(self.codec=="hevc" ? 3:2){var ptr:UnsafePointer<UInt8>?,size=0,count=0,header:Int32=0
   let result:OSStatus=self.codec=="hevc" ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(description,parameterSetIndex:i,parameterSetPointerOut:&ptr,parameterSetSizeOut:&size,parameterSetCountOut:&count,nalUnitHeaderLengthOut:&header):CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,parameterSetIndex:i,parameterSetPointerOut:&ptr,parameterSetSizeOut:&size,parameterSetCountOut:&count,nalUnitHeaderLengthOut:&header)
   if result==noErr,let ptr{frame.append(contentsOf:[0,0,0,1]);frame.append(ptr,count:size)}
  }}
  let length=CMBlockBufferGetDataLength(block);var bytes=Data(count:length);let result=bytes.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!)};guard result==noErr else{return};var offset=0
  while offset+4<=bytes.count{let count=Int(bytes.uintBE(offset,4));offset+=4;guard count>0,offset+count<=bytes.count else{return};frame.append(contentsOf:[0,0,0,1]);frame.append(bytes[offset..<offset+count]);offset+=count}
  guard offset==bytes.count,frame.count<4*1024*1024 else{return};self.sender.send(frame,keyframe:keyframe)
 }}
 func updateRate(ackP95ms:Double){queue.async{[weak self] in guard let self,self.alive,let encoder=self.encoder,ackP95ms>=0 else{return};var next=self.targetBitrate;if ackP95ms>120{next=max(6_000_000,next*4/5)}else if ackP95ms<45{next=min(48_000_000,next*11/10)};if next != self.targetBitrate,VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_AverageBitRate,value:next as CFNumber)==noErr{self.targetBitrate=next}}}
 func requestKeyframe(){queue.async{self.needsIDR=true}}
 func stop(keepingDisplay:Bool=false)async ->CGVirtualDisplay? {queue.sync{alive=false};if let stream{try? await stream.stopCapture();try? stream.removeStreamOutput(self,type:.screen)};stream=nil;queue.sync{if let encoder{VTCompressionSessionCompleteFrames(encoder,untilPresentationTimeStamp:.invalid);VTCompressionSessionInvalidate(encoder)};encoder=nil;inFlight=false};let kept=keepingDisplay ? virtual:nil;virtual=nil;sender.stop();return kept}
 private func failure(_ message:String)->NSError{NSError(domain:"StoreCapture",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
}
