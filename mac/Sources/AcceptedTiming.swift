import Foundation
import CoreMedia
import Darwin

func monotonicNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

// SCStreamFrameInfo.displayTime is mach_absolute_time ticks (SCStream.h).
// Map a local tick delta into DispatchTime's nanosecond clock; do not assume
// their numeric epochs or that mach ticks are already nanoseconds.
struct CaptureClockAnchor {
 var callback:UInt64,machTicks:UInt64
 var numer:UInt32,denom:UInt32
 var hostSeconds:Double,alignmentUncertaintyNs:UInt64
 private static let timebase:(UInt32,UInt32) = {
  var info=mach_timebase_info_data_t()
  guard mach_timebase_info(&info)==KERN_SUCCESS else{return (0,0)}
  return (info.numer,info.denom)
 }()
 static func nanoseconds(ticks:UInt64,numer:UInt32,denom:UInt32)->UInt64? {
  guard numer>0,denom>0 else{return nil}
  let n=UInt64(numer),d=UInt64(denom)
  let (whole,overflow)=(ticks/d).multipliedReportingOverflow(by:n)
  guard !overflow else{return nil}
  // Remainder and numerator are each <2^32, so this product fits UInt64.
  let fraction=((ticks%d)*n)/d
  let (result,additionOverflow)=whole.addingReportingOverflow(fraction)
  return additionOverflow ? nil:result
 }
 static func now()->CaptureClockAnchor {
  let before=mach_absolute_time(),callback=monotonicNanoseconds(),after=mach_absolute_time()
  let span=after>=before ? after-before:0
  let midpoint=before+span/2
  let uncertainty=(nanoseconds(ticks:span,numer:timebase.0,denom:timebase.1) ?? 0)/2
  return CaptureClockAnchor(callback:callback,machTicks:midpoint,numer:timebase.0,denom:timebase.1,
   hostSeconds:CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())),alignmentUncertaintyNs:uncertainty)
 }
}

struct FrameTiming {
 var sourceCapture:UInt64
 var captureCallback:UInt64
 var encodeStart:UInt64=0
 var encodeDone:UInt64=0
 var sourcePTSValid:Bool
 // sourcePTSValid keeps its existing wire/API name; it also denotes a valid
 // WindowServer displayTime source. Provenance stays in local diagnostics.
 var sourceTimeKind:String="synthetic",sourceInvalidReason:String=""
 var sourceAlignmentUncertaintyNs:UInt64=0,sourceDisplayMachTime:UInt64=0

 static func captured(anchor:CaptureClockAnchor,presentationTime:CMTime,displayMachTime:UInt64?)->FrameTiming {
  func invalid(_ kind:String,_ reason:String)->FrameTiming {
   var f=FrameTiming(sourceCapture:anchor.callback,captureCallback:anchor.callback,sourcePTSValid:false)
   f.sourceTimeKind=kind;f.sourceInvalidReason=reason;f.sourceAlignmentUncertaintyNs=anchor.alignmentUncertaintyNs
   f.sourceDisplayMachTime=displayMachTime ?? 0;return f
  }
  if let displayMachTime {
   guard displayMachTime>0 else{return invalid("displayTimeMach","zeroDisplayTime")}
   guard displayMachTime<=anchor.machTicks else{return invalid("displayTimeMach","futureDisplayTime")}
   guard let age=CaptureClockAnchor.nanoseconds(ticks:anchor.machTicks-displayMachTime,numer:anchor.numer,denom:anchor.denom)
    else{return invalid("displayTimeMach","invalidTimebaseOrOverflow")}
   guard age<5_000_000_000 else{return invalid("displayTimeMach","staleDisplayTime")}
   guard age<=anchor.callback else{return invalid("displayTimeMach","clockUnderflow")}
   var f=FrameTiming(sourceCapture:anchor.callback-age,captureCallback:anchor.callback,sourcePTSValid:true)
   f.sourceTimeKind="displayTimeMach";f.sourceAlignmentUncertaintyNs=anchor.alignmentUncertaintyNs;f.sourceDisplayMachTime=displayMachTime;return f
  }
  // Retain the earlier PTS path only when displayTime metadata is missing.
  // A present but invalid/future displayTime is never hidden by another origin.
  let age=anchor.hostSeconds-CMTimeGetSeconds(presentationTime)
  guard age.isFinite else{return invalid("ptsFallback","invalidPTS")}
  guard age>=0 else{return invalid("ptsFallback","futurePTS")}
  guard age<5 else{return invalid("ptsFallback","stalePTS")}
  guard Double(anchor.callback)>=age*1e9 else{return invalid("ptsFallback","clockUnderflow")}
  var f=FrameTiming(sourceCapture:anchor.callback-UInt64(age*1e9),captureCallback:anchor.callback,sourcePTSValid:true)
  f.sourceTimeKind="ptsFallback";return f
 }

 static func captured(at callback:UInt64,presentationTime:CMTime)->FrameTiming {
  var anchor=CaptureClockAnchor.now();anchor.callback=callback
  return captured(anchor:anchor,presentationTime:presentationTime,displayMachTime:nil)
 }

 func payload(_ annexB:Data,sendStart:UInt64)->Data {
  var data=Data("EDT1".utf8)
  data.appendBE(UInt32(sourcePTSValid ? 1:0))
  for value in [sourcePTSValid ? sourceCapture:0,captureCallback,encodeStart,encodeDone,sendStart] { data.appendBE(value) }
  data.append(annexB)
  return data
 }
}
