import Foundation
// Capture admission is bounded by Pad render-submission ACKs, not socket-buffer writes.
struct StoreFrameWindow {
 var targetFPS=60
 var limit:Int{let base=samples.min() ?? 30;let jitter=min(30,max(0,p95-base));return min(12,max(4,Int(ceil((base+jitter)*Double(targetFPS)/1000))+2))}
 var nextID:UInt64=1,lastAck:UInt64=0
 var outstanding:[UInt64:TimeInterval]=[:],samples:[Double]=[]
 var canEncode:Bool{outstanding.count<limit}
 mutating func sent(now:TimeInterval)->UInt64{let id=nextID;nextID+=1;outstanding[id]=now;return id}
 mutating func acknowledge(_ id:UInt64,now:TimeInterval){
  guard id>lastAck,id<nextID,let sent=outstanding[id] else{return}
  samples.append(max(0,(now-sent)*1000));if samples.count>60{samples.removeFirst(samples.count-60)}
  lastAck=id;outstanding=outstanding.filter{$0.key>id}
 }
 var p95:Double{let sorted=samples.sorted();return sorted.isEmpty ? -1:sorted[min(sorted.count-1,Int(Double(sorted.count-1)*0.95))]}
 static func selfTest(){
  var w=StoreFrameWindow();precondition(w.limit==4)
  for i in 0..<4{precondition(w.sent(now:Double(i))==UInt64(i+1))};precondition(!w.canEncode)
  w.acknowledge(20,now:4);precondition(!w.canEncode)
  w.acknowledge(2,now:4);precondition(w.canEncode && w.outstanding.count==2 && w.limit<=12)
  w.acknowledge(1,now:5);precondition(w.lastAck==2)
  w.acknowledge(4,now:5);precondition(w.outstanding.isEmpty)
  w.samples=[20,20,150];precondition(w.limit>=4 && w.limit<=6)
  w.samples=[160,160,160];precondition(w.limit==12)
 }
}
