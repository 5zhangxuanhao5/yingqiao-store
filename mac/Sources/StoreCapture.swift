import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreGraphics
final class StoreCapture {
 let width:Int,height:Int,fps:Int,codec:String,sender:VideoSender,bitrate:Int
 let displayName:String,displayProduct:UInt32,displaySerial:UInt32
 let showCursor:Bool,displayScale:Int
 var virtual:CGVirtualDisplay?,media:NativeCapture?,mediaStarted=false
 private(set) var reusedDisplay=false
 var onFailure:((String)->Void)?
 var onStreamFailure:((Error)->Void)?
 var displayID:CGDirectDisplayID?{virtual?.displayID}
 init(width:Int,height:Int,fps:Int,codec:String,sender:VideoSender,bitrate:Int=40_000_000,displayName:String="映桥 · 平板扩展屏",displayProduct:UInt32=0x5354,displaySerial:UInt32=0x59515354,showCursor:Bool=false,displayScale:Int=2){self.displayScale=displayScale==1 ? 1:2;self.showCursor=showCursor;self.displayName=displayName;self.displayProduct=displayProduct;self.displaySerial=displaySerial;self.bitrate=bitrate;self.width=width;self.height=height;self.fps=fps;self.codec=codec;self.sender=sender}
 static func supports(_ codec:CMVideoCodecType,width:Int=1280,height:Int=720,fps:Int=60)->Bool{
  var encoder:VTCompressionSession?
  let result=VTCompressionSessionCreate(allocator:nil,width:Int32(width),height:Int32(height),codecType:codec,encoderSpecification:[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:nil,refcon:nil,compressionSessionOut:&encoder)
  guard result==noErr,let encoder else{return false}
  defer{VTCompressionSessionInvalidate(encoder)}
  let profile=codec==kCMVideoCodecType_HEVC ? kVTProfileLevel_HEVC_Main_AutoLevel:kVTProfileLevel_H264_High_AutoLevel
  return VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_RealTime,value:kCFBooleanTrue)==noErr && VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_AllowFrameReordering,value:kCFBooleanFalse)==noErr && VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_ProfileLevel,value:profile)==noErr && VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_ExpectedFrameRate,value:fps as CFNumber)==noErr
 }

 func start(adopting:CGVirtualDisplay?=nil)async throws->CGDirectDisplayID{
  // A route change does not change the panel. Reapplying a live mode causes a
  // WindowServer reconfiguration and two deliberate waits (600ms in total).
  // Match the accepted personal core: adopt the existing display unchanged.
  if let display=adopting,CGDisplayIsOnline(display.displayID) != 0,
     let mode=CGDisplayCopyDisplayMode(display.displayID),
     mode.pixelWidth==width,mode.pixelHeight==height {
   virtual=display;reusedDisplay=true;return display.displayID
  }
  let layout=ExtensionDisplayLayout.snapshot(excluding:adopting?.displayID)
  let d=CGVirtualDisplayDescriptor();d.name=displayName;d.maxPixelsWide=UInt32(width);d.maxPixelsHigh=UInt32(height);d.sizeInMillimeters=CGSize(width:300,height:300*Double(height)/Double(width));d.vendorID=0x5947;d.productID=displayProduct;d.serialNum=displaySerial;d.queue=DispatchQueue(label:"cn.edgelink.store.virtual")
  guard let display=adopting ?? CGVirtualDisplay(descriptor:d) else{throw NSError(domain:"Display",code:1)};virtual=display
  let settings=CGVirtualDisplaySettings();settings.hiDPI=displayScale==2 ? 1:0;settings.modes=[CGVirtualDisplayMode(width:UInt(width/displayScale),height:UInt(height/displayScale),refreshRate:Double(fps))]
  guard display.apply(settings) else{throw NSError(domain:"Display",code:2)}
  try await Task.sleep(nanoseconds:400_000_000);try layout?.placeExtension(display.displayID);try await Task.sleep(nanoseconds:200_000_000)
  return display.displayID
 }
 func startMedia()async throws{
  guard !mediaStarted,let displayID else{return};mediaStarted=true
  let capture=try NativeCapture(width:width,height:height,fps:fps,sender:sender,bitrate:bitrate,codec:codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264,onStopped:{[weak self] _,error in guard let self else{return};if let callback=self.onStreamFailure{callback(error)}else{self.onFailure?(error.localizedDescription)}},showCursor:showCursor)
  media=capture;try await capture.start(displayID:displayID)
 }
 /// Refresh the capture source after a display-list change, without tearing
 /// down the virtual desktop, transport, or receiver's window.
 func restartMedia()async throws{
  let owned=virtual,old=media;media=nil
  await old?.stop()
  guard let owned,virtual===owned else{throw CancellationError()}
  mediaStarted=false
  try await startMedia()
  requestKeyframe()
 }
 func requestKeyframe(){media?.requestKeyframe()}
 func stats()->[String:Any]{media?.stats() ?? [:]}
 func stop(keepingDisplay:Bool=false)async->CGVirtualDisplay?{let old=media;media=nil;await old?.stop();let retained=keepingDisplay ? virtual:nil;virtual=nil;sender.stop();return retained}
}
