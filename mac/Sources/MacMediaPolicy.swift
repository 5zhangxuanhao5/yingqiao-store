#if MAC_RECEIVER_PREVIEW || MAC_RECEIVER_ENABLED
import Foundation

/// Limits describe a bounded preview workload, not a list of certified Macs.
enum MacMediaPolicy {
 struct Capabilities:Equatable {
  let hevc:Bool,scale:Int
  var token:String { "media2-\(hevc ? "hevc" : "avc")-\(scale)" }
  init(hevc:Bool,scale:Int){self.hevc=hevc;self.scale=scale==1 ? 1:2}
  init?(token:String){
   let fields=token.split(separator:"-")
   guard fields.count==3,fields[0]=="media2",["avc","hevc"].contains(fields[1]),let scale=Int(fields[2]),[1,2].contains(scale) else{return nil}
   self.hevc=fields[1]=="hevc";self.scale=scale
  }
 }
 struct Plan:Equatable {
  let width:Int,height:Int,fps:Int,scale:Int,hevc:Bool
  var bitrate:Int { min(40_000_000,max(8_000_000,Int(Double(width)*Double(height)*Double(fps)*0.16))) }
 }
 static func candidates(width:Int,height:Int,fps:Int,capabilities:Capabilities)->[Plan]{
  guard width>=640,height>=480,width<=3840,height<=3200,width*height<=8_000_000,width%2==0,height%2==0,[30,60].contains(fps) else{return []}
  var result:[Plan]=[]
  for factor in [1.0,0.75,0.5] {
   let w=Int(Double(width)*factor)/2*2,h=Int(Double(height)*factor)/2*2
   guard w>=640,h>=480 else{continue}
   for rate in fps==60 ? [60,30]:[30] {
    for hevc in capabilities.hevc ? [true,false]:[false] { result.append(Plan(width:w,height:h,fps:rate,scale:capabilities.scale,hevc:hevc)) }
   }
  }
  return result
 }
 static func accepts(width:Int,height:Int,fps:Int,requestedWidth:Int,requestedHeight:Int,negotiated:Bool)->Bool {
  guard [30,60].contains(fps),width>=640,height>=480,width<=3840,height<=3200,width<=requestedWidth,height<=requestedHeight,width%2==0,height%2==0,width*height<=8_000_000 else{return false}
  if !negotiated{return width==requestedWidth && height==requestedHeight}
  return abs(Double(width)/Double(height)-Double(requestedWidth)/Double(requestedHeight))<0.006
 }
 static func selfTest(){
  // Screen geometry fixtures: non-Retina, Retina Air/Pro, ultrawide,
  // portrait and 4K/5K/6K/8K panels. They are not device certification.
  for (w,h) in [(1280.0,800.0),(1920,1080),(2560,1600),(2560,1664),(2880,1864),(3024,1964),(3456,2234),(3840,2160),(5120,2880),(6016,3384),(7680,4320),(3440,1440),(2160,3840)] {
   let d=MacPreviewWire.dimensions(width:w,height:h)!
   precondition(d.0%2==0 && d.1%2==0 && d.0*d.1<=8_000_000)
   precondition(abs(Double(d.0)/Double(d.1)-w/h)<0.006)
   for scale in [1,2] { for hevc in [false,true] {
    let c=Capabilities(hevc:hevc,scale:scale);precondition(Capabilities(token:c.token)==c)
    let plans=candidates(width:d.0,height:d.1,fps:60,capabilities:c)
    precondition(!plans.isEmpty && plans.allSatisfy{$0.scale==scale && (hevc || !$0.hevc)})
    precondition(plans.allSatisfy{accepts(width:$0.width,height:$0.height,fps:$0.fps,requestedWidth:d.0,requestedHeight:d.1,negotiated:true)})
    // A simulated older encoder can select a smaller 30-FPS AVC plan.
    let fallback=plans.first{$0.width<=1920 && $0.height<=1600 && $0.fps==30 && !$0.hevc}
    if min(d.0,d.1)>=960 && d.0<=3840 && d.1<=3200 { precondition(fallback != nil) }
   }}
  }
  for bad in ["media2-av1-2","media2-hevc-0","media2-hevc-3","media2-avc-1-extra"] {precondition(Capabilities(token:bad)==nil)}
  precondition(candidates(width:Int.max,height:10,fps:60,capabilities:Capabilities(hevc:true,scale:2)).isEmpty)
  precondition(!accepts(width:1280,height:720,fps:60,requestedWidth:2560,requestedHeight:1664,negotiated:true))
  precondition(!accepts(width:1280,height:832,fps:60,requestedWidth:2560,requestedHeight:1664,negotiated:false))
  print("PASS Mac media negotiation, 13 panel fixtures, Retina/non-Retina scale, AVC/HEVC intersection and bounded fallback")
 }
}
#endif
