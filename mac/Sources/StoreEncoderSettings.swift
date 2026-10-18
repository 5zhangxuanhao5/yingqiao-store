import Foundation
import VideoToolbox
struct StoreEncoderSettings {
 static func apply(fps:Int,set:(CFString,CFTypeRef)->OSStatus)throws->Bool {
  for (key,value):(CFString,CFTypeRef) in [(kVTCompressionPropertyKey_RealTime,kCFBooleanTrue),(kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse),(kVTCompressionPropertyKey_ExpectedFrameRate,fps as CFNumber),(kVTCompressionPropertyKey_AverageBitRate,24_000_000 as CFNumber),(kVTCompressionPropertyKey_MaxKeyFrameInterval,(fps*2) as CFNumber)]{
   let result=set(key,value);guard result==noErr else{throw NSError(domain:"StoreEncoder",code:Int(result),userInfo:[NSLocalizedDescriptionKey:"硬件编码参数不支持：\(key) (\(result))"])}
  }
  // HEVC hardware on the test Mac reports -12900 for this optional property.
  return set(kVTCompressionPropertyKey_MaxFrameDelayCount,0 as CFNumber)==noErr
 }
 static func selfTest(){
  var calls=0
  let supported=try! apply(fps:60){key,_ in calls+=1;return key==kVTCompressionPropertyKey_MaxFrameDelayCount ? -12900:noErr}
  precondition(!supported && calls==6)
  do{_ = try apply(fps:60){_,_ in -12900};preconditionFailure("required encoder error ignored")}catch{}
 }
}
