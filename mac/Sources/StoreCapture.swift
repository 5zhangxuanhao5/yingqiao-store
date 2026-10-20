import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreGraphics
final class StoreCapture {
 let width:Int,height:Int,fps:Int,codec:String,sender:VideoSender,bitrate:Int
 let displayName:String,displayProduct:UInt32,displaySerial:UInt32
 let showCursor:Bool
 var virtual:CGVirtualDisplay?,media:NativeCapture?,mediaStarted=false
 private(set) var reusedDisplay=false
 var onFailure:((String)->Void)?
 var displayID:CGDirectDisplayID?{virtual?.displayID}
 init(width:Int,height:Int,fps:Int,codec:String,sender:VideoSender,bitrate:Int=40_000_000,displayName:String="映桥 · 平板扩展屏",displayProduct:UInt32=0x5354,displaySerial:UInt32=0x59515354,showCursor:Bool=false){self.showCursor=showCursor;self.displayName=displayName;self.displayProduct=displayProduct;self.displaySerial=displaySerial;self.bitrate=bitrate;self.width=width;self.height=height;self.fps=fps;self.codec=codec;self.sender=sender}
 static func supports(_ codec:CMVideoCodecType)->Bool{var encoder:VTCompressionSession?;let r=VTCompressionSessionCreate(allocator:nil,width:1280,height:720,codecType:codec,encoderSpecification:[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:nil,refcon:nil,compressionSessionOut:&encoder);if let encoder{VTCompressionSessionInvalidate(encoder)};return r==noErr}
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
  let settings=CGVirtualDisplaySettings();settings.hiDPI=1;settings.modes=[CGVirtualDisplayMode(width:UInt(width/2),height:UInt(height/2),refreshRate:Double(fps))]
  guard display.apply(settings) else{throw NSError(domain:"Display",code:2)}
  try await Task.sleep(nanoseconds:400_000_000);try layout?.placeExtension(display.displayID);try await Task.sleep(nanoseconds:200_000_000)
  return display.displayID
 }
 func startMedia()async throws{
  guard !mediaStarted,let displayID else{return};mediaStarted=true
  let capture=try NativeCapture(width:width,height:height,fps:fps,sender:sender,bitrate:bitrate,codec:codec=="hevc" ? kCMVideoCodecType_HEVC:kCMVideoCodecType_H264,onStopped:{[weak self] _,error in self?.onFailure?(error.localizedDescription)},showCursor:showCursor)
  media=capture;try await capture.start(displayID:displayID)
 }
 func requestKeyframe(){media?.requestKeyframe()}
 func stats()->[String:Any]{media?.stats() ?? [:]}
 func stop(keepingDisplay:Bool=false)async->CGVirtualDisplay?{let old=media;media=nil;await old?.stop();let retained=keepingDisplay ? virtual:nil;virtual=nil;sender.stop();return retained}
}
