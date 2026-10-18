import Foundation
import ScreenCaptureKit
import CoreVideo
import VideoToolbox

private final class CaptureContentBox: @unchecked Sendable {
 let value:SCShareableContent
 init(_ value:SCShareableContent){self.value=value}
}
private final class CaptureEncoderBox: @unchecked Sendable {
 let value:VTCompressionSession?
 init(_ value:VTCompressionSession?){self.value=value}
}

// SCStream retains output/delegate objects while the server is finishing. A
// weak proxy prevents a missing completion from retaining NativeCapture.
private final class CaptureOutputProxy:NSObject,SCStreamOutput,SCStreamDelegate {
 weak var owner:NativeCapture?
 init(_ owner:NativeCapture){self.owner=owner}
 func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType){owner?.stream(stream,didOutputSampleBuffer:sample,of:type)}
 func stream(_ stream:SCStream,didStopWithError error:Error){owner?.stream(stream,didStopWithError:error)}
}

private final class CaptureEncodeDiagnosticToken {var completed=false}

final class NativeCapture:NSObject,SCStreamOutput,SCStreamDelegate {
 let width:Int,height:Int,fps:Int;let sender:VideoSender;let codec:CMVideoCodecType
 let queue=DispatchQueue(label:"edgelink.capture",qos:.userInteractive),lock=NSLock()
 var syntheticTimer:DispatchSourceTimer?;var pixelPool:CVPixelBufferPool?;var syntheticIndex=0
 var encoder:VTCompressionSession?,stream:SCStream?,latest:CVPixelBuffer?,latestTiming:FrameTiming?
 var inFlight=0,needsIDR=true,running=false,captureCount=0,encodeCount=0,skipped=0
 var encodeTimes:[Double]=[],captureCallbackTimes:[Double]=[],packetPreparationTimes:[Double]=[],started=Date()
 var screenCallbacks=0,invalidScreenSamples=0,missingFrameStatus=0,unknownFrameStatus=0,missingCompletePixels=0
 var frameStatusCounts:[String:Int]=[:],sourceTimeKinds:[String:Int]=[:],sourceInvalidReasons:[String:Int]=[:]
 var displayTimeMetadataFrames=0,validDisplayTimeFrames=0,missingDisplayTimeFrames=0,uniqueDisplayTimeFrames=0,duplicateDisplayTimeFrames=0,regressedDisplayTimeFrames=0
 var lastDisplayMachTime:UInt64=0,recentCaptureCallbacks:[UInt64]=[],recentDisplaySources:[UInt64]=[],sourceAlignmentUncertainties:[Double]=[]
 var lowLatencyRateControl=false
 private var activeBitrateKbps=0,dataRateClampActive=false,lastBitrateStatus:OSStatus=noErr
 private var encodeAttempts=0,encodeOutcomeCounts:[String:Int]=[:]
 private let lifecycle=BoundedCaptureLifecycle(),diagnostics=CaptureLifecycleDiagnostics()
 private let firstComplete=CaptureOneShotEvent<Void>()
 private var generation:UInt64=0,didBegin=false,didStop=false
 private var outputProxy:CaptureOutputProxy?,stopTask:Task<Void,Never>?
 // Policy values are candidate defaults, not hardware guarantees.
 private let contentDeadline=4.0,startDeadline=6.0,firstFrameDeadline=4.0,stopDeadline=2.0
 let onStopped:((NativeCapture,Error)->Void)?
 init(width:Int,height:Int,fps:Int,sender:VideoSender,bitrate:Int=40_000_000,codec:CMVideoCodecType=kCMVideoCodecType_HEVC,onStopped:((NativeCapture,Error)->Void)?=nil)throws {
  self.width=width;self.height=height;self.fps=fps;self.sender=sender;self.codec=codec;self.onStopped=onStopped;super.init()
  // On this M4, the AVE hardware encoder measured 5.6 ms P95 versus
  // 9.5 ms for the RTVC "low latency" mode. Select by measurement.
  let specification=[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:true] as CFDictionary
  let r=VTCompressionSessionCreate(allocator:nil,width:Int32(width),height:Int32(height),codecType:codec,encoderSpecification:specification,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:nil,refcon:nil,compressionSessionOut:&encoder)
  guard r==noErr,let encoder else{throw NSError(domain:"Encoder",code:Int(r),userInfo:[NSLocalizedDescriptionKey:"HEVC 硬件编码器不可用"])}
  let settings:[(CFString,CFTypeRef)]=[
   (kVTCompressionPropertyKey_RealTime,kCFBooleanTrue),
   (kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse),
   (kVTCompressionPropertyKey_ProfileLevel,codec==kCMVideoCodecType_HEVC ? kVTProfileLevel_HEVC_Main_AutoLevel:kVTProfileLevel_H264_High_AutoLevel),
   (kVTCompressionPropertyKey_ExpectedFrameRate,fps as CFNumber),
   (kVTCompressionPropertyKey_AverageBitRate,bitrate as CFNumber),
   (kVTCompressionPropertyKey_MaxKeyFrameInterval,(fps*2) as CFNumber)]
  for (key,value) in settings{let status=VTSessionSetProperty(encoder,key:key,value:value);if status != noErr{throw NSError(domain:"Encoder",code:Int(status),userInfo:[NSLocalizedDescriptionKey:"编码参数不支持：\(key)，\(status)"])} }
  if !lowLatencyRateControl{_=VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality,value:kCFBooleanTrue)}
  activeBitrateKbps=bitrate/1000
  if bitrate<=4_000_000{dataRateClampActive=Self.applyDataRateClamp(encoder,kbps:activeBitrateKbps)==noErr}
  _=VTCompressionSessionPrepareToEncodeFrames(encoder)
 }
 func startSynthetic()throws {
  let attrs:[CFString:Any]=[kCVPixelBufferWidthKey:width,kCVPixelBufferHeightKey:height,kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelBufferIOSurfacePropertiesKey:[:]]
  guard CVPixelBufferPoolCreate(nil,nil,attrs as CFDictionary,&pixelPool)==kCVReturnSuccess else{throw NSError(domain:"Pixels",code:1)}
  lock.lock();running=true;started=Date();lock.unlock()
  let timer=DispatchSource.makeTimerSource(queue:queue);syntheticTimer=timer
  timer.schedule(deadline:.now(),repeating:1.0/Double(fps),leeway:.milliseconds(1))
  timer.setEventHandler{[weak self] in
   guard let self,let pool=self.pixelPool else{return};var pixel:CVPixelBuffer?
   guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel)==kCVReturnSuccess,let pixel else{return}
   CVPixelBufferLockBaseAddress(pixel,[])
   for p in 0..<2{memset(CVPixelBufferGetBaseAddressOfPlane(pixel,p),p==0 ? 40:128,CVPixelBufferGetBytesPerRowOfPlane(pixel,p)*CVPixelBufferGetHeightOfPlane(pixel,p))}
   let x=(self.syntheticIndex*19)%max(1,self.width-220),y=(self.syntheticIndex*7)%max(1,self.height-220)
   let base=CVPixelBufferGetBaseAddressOfPlane(pixel,0)!.assumingMemoryBound(to:UInt8.self),stride=CVPixelBufferGetBytesPerRowOfPlane(pixel,0)
   for row in y..<y+200{memset(base.advanced(by:row*stride+x),220,200)}
   CVPixelBufferUnlockBaseAddress(pixel,[]);self.syntheticIndex += 1
   let now=monotonicNanoseconds(),timing=FrameTiming(sourceCapture:now,captureCallback:now,sourcePTSValid:true)
   self.lock.lock();self.captureCount += 1;self.latest=pixel;self.latestTiming=timing;self.lock.unlock()
   self.encode(pixel,time:CMClockGetTime(CMClockGetHostTimeClock()),timing:timing)
  };timer.resume()
 }
 func start(displayID:CGDirectDisplayID)async throws {
  let token=try beginCapture()
  diagnostics.setState("enumerating");diagnostics.record("contentRequested",detail:["targetDisplayID":String(displayID),"captureGeneration":String(token)])
  do{
   let contentDiagnostic=diagnostics
   let boxed:CaptureContentBox=try await lifecycle.run(generation:token,phase:"shareableContent",timeout:contentDeadline){reply in
    SCShareableContent.getExcludingDesktopWindows(false,onScreenWindowsOnly:true){content,error in
     contentDiagnostic.record("contentCompletion",detail:["displayIDs":content?.displays.map{String($0.displayID)}.joined(separator:",") ?? ""],error:error)
     if let error{reply(.failure(error))}
     else if let content{reply(.success(CaptureContentBox(content)))}
     else{reply(.failure(NSError(domain:"Capture",code:2,userInfo:[NSLocalizedDescriptionKey:"可捕获内容查询未返回结果"])))}
    }
   }
   try checkCapture(token)
   let content=boxed.value
   diagnostics.record("contentReturned",detail:["displayIDs":content.displays.map{String($0.displayID)}.joined(separator:",")])
   guard let display=content.displays.first(where:{$0.displayID==displayID}) else{throw NSError(domain:"Capture",code:1,userInfo:[NSLocalizedDescriptionKey:"目标屏幕不可捕获"])}
   let configuration=SCStreamConfiguration();configuration.width=width;configuration.height=height;configuration.pixelFormat=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;configuration.minimumFrameInterval=CMTime(value:1,timescale:Int32(fps));configuration.queueDepth=3;configuration.capturesAudio=false;configuration.showsCursor=false
   let proxy=CaptureOutputProxy(self)
   let s=SCStream(filter:SCContentFilter(display:display,excludingWindows:[]),configuration:configuration,delegate:proxy)
   try s.addStreamOutput(proxy,type:.screen,sampleHandlerQueue:queue)
   diagnostics.record("outputAdded")
   do{try installCapture(s,proxy:proxy,generation:token)}catch{try? s.removeStreamOutput(proxy,type:.screen);throw error}
   diagnostics.setState("starting");diagnostics.record("startRequested")
   let diagnostic=diagnostics
   let _:Void=try await lifecycle.run(generation:token,phase:"startCapture",timeout:startDeadline,
     onLateSuccess:{[weak s] in
      diagnostic.record("lateStartSuccessCleanupRequested")
      // No new Task or app-owned resource: this public API is a fire-and-forget
      // cleanup of only the old, weakly referenced stream after its late ACK.
      s?.stopCapture{error in diagnostic.record("lateStartCleanupCompletion",error:error)}
     }){[weak s] reply in
      guard let s else{reply(.failure(CaptureLifecycleError.superseded));return}
      s.startCapture{error in
       diagnostic.record("startCompletion",error:error)
       if let error{reply(.failure(error))}else{reply(.success(()))}
      }
     }
   try checkCapture(token);diagnostics.startCompleted();diagnostics.setState("awaitingFirstComplete")
   diagnostics.record("firstCompleteWaitRequested")
   let event=firstComplete
   let _:Void=try await lifecycle.run(generation:token,phase:"firstCompleteFrame",timeout:firstFrameDeadline){reply in event.subscribe(reply)}
   event.clearSubscriber();try checkCapture(token)
   diagnostics.setState("streaming");diagnostics.record("startupReady")
  }catch{
   firstComplete.clearSubscriber();diagnostics.record("startupFailed",error:error)
   await stop();throw error
  }
 }
 private func beginCapture()throws->UInt64{
  lock.lock();defer{lock.unlock()}
  guard !didBegin,!didStop else{throw CaptureLifecycleError.alreadyStopped}
  didBegin=true;running=true;started=Date();generation=lifecycle.nextGeneration();return generation
 }
 private func checkCapture(_ token:UInt64)throws{
  try Task.checkCancellation();lock.lock();let valid=running && !didStop && generation==token;lock.unlock()
  guard valid,lifecycle.isCurrent(token) else{throw CaptureLifecycleError.superseded}
 }
 private func installCapture(_ value:SCStream,proxy:CaptureOutputProxy,generation token:UInt64)throws{
  lock.lock();defer{lock.unlock()}
  guard running,!didStop,generation==token,lifecycle.isCurrent(token) else{throw CaptureLifecycleError.superseded}
  stream=value;outputProxy=proxy
 }
 func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType){
  guard type == .screen else{return};let anchor=CaptureClockAnchor.now()
  lock.lock();guard running,!didStop,self.stream===stream else{lock.unlock();return};screenCallbacks += 1;lock.unlock()
  diagnostics.recordFirst("firstScreenCallback",detail:["sampleValid":String(sample.isValid),"imageBufferPresent":String(sample.isValid && sample.imageBuffer != nil)])
  guard sample.isValid else{lock.lock();invalidScreenSamples += 1;lock.unlock();return}
  guard let array=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
    let attachments=array.first,let raw=attachments[.status] as? Int
    else{lock.lock();missingFrameStatus += 1;lock.unlock();return}
  guard let status=SCFrameStatus(rawValue:raw) else{lock.lock();unknownFrameStatus += 1;lock.unlock();return}
  let name:String
  switch status{case .complete:name="complete";case .idle:name="idle";case .blank:name="blank";case .suspended:name="suspended";case .started:name="started";case .stopped:name="stopped";@unknown default:name="unknown"}
  lock.lock();frameStatusCounts[name,default:0] += 1;lock.unlock()
  diagnostics.recordFirst("firstFrameStatus",detail:["status":name])
  guard status == .complete else{return}
  guard let pixel=sample.imageBuffer else{lock.lock();missingCompletePixels += 1;lock.unlock();return}
  guard CVPixelBufferGetWidth(pixel)>0,CVPixelBufferGetHeight(pixel)>0 else{lock.lock();missingCompletePixels += 1;lock.unlock();return}
  diagnostics.recordFirst("firstCompleteFrame",detail:["width":String(CVPixelBufferGetWidth(pixel)),"height":String(CVPixelBufferGetHeight(pixel))])
  let displayMachTime=attachments[.displayTime] as? UInt64
  let timing=FrameTiming.captured(anchor:anchor,presentationTime:sample.presentationTimeStamp,displayMachTime:displayMachTime)
  lock.lock();captureCount += 1;latest=pixel;latestTiming=timing
  recentCaptureCallbacks.append(anchor.callback);if recentCaptureCallbacks.count>120{recentCaptureCallbacks.removeFirst()}
  sourceTimeKinds[timing.sourceTimeKind,default:0] += 1
  if !timing.sourceInvalidReason.isEmpty{sourceInvalidReasons[timing.sourceInvalidReason,default:0] += 1}
  if let displayMachTime{
   displayTimeMetadataFrames += 1
   if timing.sourcePTSValid{
    validDisplayTimeFrames += 1
    sourceAlignmentUncertainties.append(Double(timing.sourceAlignmentUncertaintyNs)/1e6);if sourceAlignmentUncertainties.count>120{sourceAlignmentUncertainties.removeFirst()}
    if displayMachTime==lastDisplayMachTime{duplicateDisplayTimeFrames += 1}
    else{
     if lastDisplayMachTime>displayMachTime{regressedDisplayTimeFrames += 1}
     uniqueDisplayTimeFrames += 1;lastDisplayMachTime=displayMachTime
     recentDisplaySources.append(anchor.callback);if recentDisplaySources.count>120{recentDisplaySources.removeFirst()}
    }
   }
  }else{missingDisplayTimeFrames += 1}
  if timing.sourcePTSValid {captureCallbackTimes.append(Double(timing.captureCallback-timing.sourceCapture)/1e6);if captureCallbackTimes.count>120{captureCallbackTimes.removeFirst()}}
  lock.unlock();firstComplete.complete(.success(()));encode(pixel,time:sample.presentationTimeStamp,timing:timing)
 }
 func stream(_ stream:SCStream,didStopWithError error:Error){lock.lock();let active=running && !didStop && self.stream===stream;lock.unlock();guard active else{return};diagnostics.record("streamDidStop",error:error);firstComplete.complete(.failure(error));onStopped?(self,error)}
 // Diagnostic only. Called with lock held; one terminal reason per attempt.
 private func recordEncodeOutcomeLocked(_ token:CaptureEncodeDiagnosticToken,_ reason:String){
  guard !token.completed else{return};token.completed=true;encodeOutcomeCounts[reason,default:0] += 1
 }
 func encode(_ pixel:CVPixelBuffer,time:CMTime,timing:FrameTiming){
  let outcome=CaptureEncodeDiagnosticToken();lock.lock();encodeAttempts += 1;lock.unlock()
  guard let permit=sender.reserveEncodeBudget() else{lock.lock();skipped += 1;recordEncodeOutcomeLocked(outcome,"senderAdmissionRejected");lock.unlock();return}
  lock.lock();guard running,inFlight<2,let encoder else{skipped += 1;recordEncodeOutcomeLocked(outcome,!running ? "encoderInactiveRejected":(inFlight>=2 ? "encoderInFlightRejected":"encoderUnavailableRejected"));lock.unlock();sender.cancelEncodePermit(permit);return};inFlight += 1;let force=needsIDR || permit.requiresKeyframe;needsIDR=false;lock.unlock()
  let properties=force ? [kVTEncodeFrameOptionKey_ForceKeyFrame:true] as CFDictionary:nil
  let begin=monotonicNanoseconds();var frameTiming=timing;frameTiming.encodeStart=begin
  let status=VTCompressionSessionEncodeFrame(encoder,imageBuffer:pixel,presentationTimeStamp:time,duration:CMTime(value:1,timescale:Int32(fps)),frameProperties:properties,infoFlagsOut:nil){[weak self,weak upload=sender] status,flags,sample in
   guard let self else{upload?.cancelEncodePermit(permit);return};var sent=false;defer{if !sent{self.sender.cancelEncodePermit(permit)}};let done=monotonicNanoseconds()
   self.lock.lock();self.inFlight -= 1;let active=self.running;self.lock.unlock()
   guard active,status==noErr,!flags.contains(.frameDropped),let sample,let block=sample.dataBuffer,let format=sample.formatDescription else{self.lock.lock();self.recordEncodeOutcomeLocked(outcome,!active ? "vtRetiredCallback":(status != noErr ? "vtCallbackError":(flags.contains(.frameDropped) ? "vtFrameDropped":"vtMissingOutput")));self.needsIDR=true;self.lock.unlock();return}
   let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[CFString:Any]]
   let isKey=(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true
   var output=Data()
   if isKey {
    var count=0
    for index in 0..<(self.codec==kCMVideoCodecType_HEVC ? 3:2){
     var pointer:UnsafePointer<UInt8>?,length=0,headerLength:Int32=0
     let r:OSStatus=self.codec==kCMVideoCodecType_HEVC ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format,parameterSetIndex:index,parameterSetPointerOut:&pointer,parameterSetSizeOut:&length,parameterSetCountOut:&count,nalUnitHeaderLengthOut:&headerLength):CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,parameterSetIndex:index,parameterSetPointerOut:&pointer,parameterSetSizeOut:&length,parameterSetCountOut:&count,nalUnitHeaderLengthOut:&headerLength)
     if r==noErr,let pointer{output.append(contentsOf:[0,0,0,1]);output.append(pointer,count:length)}
    }
   }
   let length=CMBlockBufferGetDataLength(block);var buffer=Data(count:length)
   let copied=buffer.withUnsafeMutableBytes{CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!)}
   guard copied==noErr else{self.lock.lock();self.recordEncodeOutcomeLocked(outcome,"packetPreparationRejected");self.lock.unlock();return};var offset=0
   while offset+4<=buffer.count{let size=Int(buffer.uintBE(offset,4));offset += 4;guard size>0,offset+size<=buffer.count else{self.lock.lock();self.recordEncodeOutcomeLocked(outcome,"packetPreparationRejected");self.lock.unlock();return};output.append(contentsOf:[0,0,0,1]);output.append(buffer[offset..<offset+size]);offset += size}
   let prepared=monotonicNanoseconds()
   self.lock.lock();guard self.running,!self.didStop else{self.recordEncodeOutcomeLocked(outcome,"vtRetiredBeforeSend");self.lock.unlock();return};self.recordEncodeOutcomeLocked(outcome,"encoded");self.encodeCount += 1;self.encodeTimes.append(Double(done-begin)/1e6);self.packetPreparationTimes.append(Double(prepared-done)/1e6);if self.encodeTimes.count>120{self.encodeTimes.removeFirst();self.packetPreparationTimes.removeFirst()};self.lock.unlock()
   self.diagnostics.recordFirst("firstEncodedFrame")
   var completed=frameTiming;completed.encodeDone=done
   self.sender.send(output,keyframe:isKey,timing:completed,permit:permit);sent=true
  }
  if status != noErr{lock.lock();inFlight -= 1;recordEncodeOutcomeLocked(outcome,"vtSubmitError");needsIDR=true;lock.unlock();sender.cancelEncodePermit(permit)}
 }
 private static func applyDataRateClamp(_ encoder:VTCompressionSession,kbps:Int)->OSStatus{
  let bytesPerSecond=Int(ceil(Double(kbps)*1000/8*1.25))
  return VTSessionSetProperty(encoder,key:kVTCompressionPropertyKey_DataRateLimits,value:[bytesPerSecond as NSNumber,1.0 as NSNumber] as CFArray)
 }
 func updateBitrate(kbps:Int,completion:@escaping(OSStatus)->Void){
  queue.async{
   self.lock.lock();let value=self.encoder,active=self.running && !self.didStop;self.lock.unlock()
   guard active,let value else{completion(kVTInvalidSessionErr);return}
   let status=VTSessionSetProperty(value,key:kVTCompressionPropertyKey_AverageBitRate,value:(kbps*1000) as CFNumber)
   let clampStatus=status==noErr ? Self.applyDataRateClamp(value,kbps:kbps):status
   self.lock.lock();if status==noErr{self.activeBitrateKbps=kbps;self.dataRateClampActive=clampStatus==noErr};self.lastBitrateStatus=status;self.lock.unlock()
   completion(status)
  }
 }
 func requestKeyframe(){queue.async{self.lock.lock();self.needsIDR=true;let pixel=self.latest,timing=self.latestTiming;self.lock.unlock();if let pixel,let timing{self.encode(pixel,time:CMClockGetTime(CMClockGetHostTimeClock()),timing:timing)}}}
 func lifecycleStats()->[String:Any]{diagnostics.snapshot()}
 var startupReady:Bool{diagnostics.isReady}
 func stats()->[String:Any]{lock.lock();defer{lock.unlock()};let seconds=max(0.001,Date().timeIntervalSince(started));func p95(_ values:[Double])->Double{let s=values.sorted();return s.isEmpty ? 0:s[min(s.count-1,Int(Double(s.count-1)*0.95))]}
  func recentFPS(_ times:[UInt64])->Double{guard times.count>1,let first=times.first,let last=times.last,last>first else{return 0};return Double(times.count-1)*1e9/Double(last-first)}
  return ["activeBitrateKbps":activeBitrateKbps,"dataRateClampActive":dataRateClampActive,"lastBitrateStatus":lastBitrateStatus,"captureLifecycle":diagnostics.snapshot(),"lowLatencyRateControl":lowLatencyRateControl,"captureFrames":captureCount,"encodedFrames":encodeCount,"skippedRawFrames":skipped,"averageCaptureFPS":Double(captureCount)/seconds,"averageEncodeFPS":Double(encodeCount)/seconds,"recentEncodeP95ms":p95(encodeTimes),"captureCallbackP95ms":p95(captureCallbackTimes),"packetPreparationP95ms":p95(packetPreparationTimes),"encodingFramesInFlight":inFlight,"encodeAttempts":encodeAttempts,"encodeOutcomeCounts":encodeOutcomeCounts,
   "senderAdmissionRejected":encodeOutcomeCounts["senderAdmissionRejected",default:0],"encoderInFlightRejected":encodeOutcomeCounts["encoderInFlightRejected",default:0],"encoderInactiveRejected":encodeOutcomeCounts["encoderInactiveRejected",default:0],"encoderUnavailableRejected":encodeOutcomeCounts["encoderUnavailableRejected",default:0],
   "vtFrameDropped":encodeOutcomeCounts["vtFrameDropped",default:0],"vtCallbackError":encodeOutcomeCounts["vtCallbackError",default:0],"vtSubmitError":encodeOutcomeCounts["vtSubmitError",default:0],"vtMissingOutput":encodeOutcomeCounts["vtMissingOutput",default:0],"vtRetiredCallback":encodeOutcomeCounts["vtRetiredCallback",default:0],"vtRetiredBeforeSend":encodeOutcomeCounts["vtRetiredBeforeSend",default:0],"packetPreparationRejected":encodeOutcomeCounts["packetPreparationRejected",default:0],
   "screenCallbacks":screenCallbacks,"invalidScreenSamples":invalidScreenSamples,"missingFrameStatus":missingFrameStatus,"unknownFrameStatus":unknownFrameStatus,"missingCompletePixels":missingCompletePixels,"frameStatusCounts":frameStatusCounts,
   "sourceTimeKinds":sourceTimeKinds,"sourceInvalidReasons":sourceInvalidReasons,"displayTimeMetadataFrames":displayTimeMetadataFrames,"validDisplayTimeFrames":validDisplayTimeFrames,"missingDisplayTimeFrames":missingDisplayTimeFrames,
   "uniqueDisplayTimeFrames":uniqueDisplayTimeFrames,"duplicateDisplayTimeFrames":duplicateDisplayTimeFrames,"regressedDisplayTimeFrames":regressedDisplayTimeFrames,
   "recentCompleteCaptureFPS":recentFPS(recentCaptureCallbacks),"recentUniqueCapturedDisplayFPS":recentFPS(recentDisplaySources),"sourceClockAlignmentP95ms":p95(sourceAlignmentUncertainties),"sourceTimeOrigin":"WindowServer displayTime mach ticks; PTS only when metadata missing"]
 }
 func stop()async {let cleanup=beginStop();await cleanup.value}
 private func detachEncoder()->CaptureEncoderBox{
  lock.lock();defer{lock.unlock()};let result=CaptureEncoderBox(encoder)
  encoder=nil;latest=nil;latestTiming=nil;pixelPool=nil;return result
 }
 private func beginStop()->Task<Void,Never>{
  lock.lock();defer{lock.unlock()}
  if let stopTask{return stopTask}
  running=false;didStop=true;let oldStream=stream,oldProxy=outputProxy
  stream=nil;outputProxy=nil;syntheticTimer?.cancel();syntheticTimer=nil
  let token=lifecycle.nextGeneration();generation=token
  firstComplete.clearSubscriber();diagnostics.setState("stopping");diagnostics.record("stopRequested")
  let task=Task{[self] in
   if let oldStream{
    let diagnostic=diagnostics
    do{
     let _:Void=try await lifecycle.run(generation:token,phase:"stopCapture",timeout:stopDeadline){[weak oldStream] reply in
      guard let oldStream else{reply(.success(()));return}
      oldStream.stopCapture{error in diagnostic.record("stopCompletion",error:error);if let error{reply(.failure(error))}else{reply(.success(()))}}
     }
    }catch{diagnostics.record("stopWaitEnded",error:error)}
    if let oldProxy{do{try oldStream.removeStreamOutput(oldProxy,type:.screen)}catch{diagnostics.record("removeOutputFailed",error:error)}}
   }
   // Do not hold the virtual-display caller's stop wait behind encoder draining.
   // Pending encoder callbacks see running=false; no old frame is transmitted.
   let releasedEncoder=detachEncoder(),diagnostic=diagnostics
   queue.async{
    if let oldEncoder=releasedEncoder.value{VTCompressionSessionInvalidate(oldEncoder)}
    diagnostic.record("encoderInvalidated")
   }
   diagnostics.setState("stopped");diagnostics.record("stopWaitReleased")
  }
  stopTask=task;return task
 }
}
