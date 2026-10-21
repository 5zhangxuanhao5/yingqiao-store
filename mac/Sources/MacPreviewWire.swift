#if MAC_RECEIVER_PREVIEW || MAC_RECEIVER_ENABLED
import Foundation
import CryptoKit
import CoreGraphics

enum MacPreviewWire {
 static let service="_yqmacpreview._tcp."
 static let maximumFrame=12*1024*1024
 static func unhex(_ s:String)->Data? {
  guard !s.isEmpty,s.count%2==0,s.count<=8192 else{return nil}
  var data=Data(),i=s.startIndex
  while i<s.endIndex {let j=s.index(i,offsetBy:2);guard let b=UInt8(s[i..<j],radix:16) else{return nil};data.append(b);i=j}
  return data
 }
 static func dimensions(width:Double,height:Double)->(Int,Int)? {
  guard width.isFinite,height.isFinite,width>=640,height>=480 else{return nil}
  let scale=min(1,3840/width,3200/height,sqrt(8_000_000/(width*height)))
  return (Int(width*scale)/2*2,Int(height*scale)/2*2)
 }
 static func nals(_ data:Data)->[Data] {
  let a=Array(data);var ranges:[(Int,Int)]=[],i=0
  while i+3<=a.count {
   if i+4<=a.count,a[i]==0,a[i+1]==0,a[i+2]==0,a[i+3]==1{ranges.append((i,4));i+=4}
   else if a[i]==0,a[i+1]==0,a[i+2]==1{ranges.append((i,3));i+=3}else{i+=1}
  }
  return ranges.enumerated().compactMap {n,r in let end=n+1<ranges.count ? ranges[n+1].0:a.count;return end>r.0+r.1 ? Data(a[(r.0+r.1)..<end]):nil}
 }
 struct Parser {
  var buffer=Data(),lastVideo:UInt64=0
  mutating func append(_ data:Data,sid:UInt32,key:SymmetricKey,prefix:Data)throws->[(UInt64,UInt8,Data)] {
   guard buffer.count+data.count<=maximumFrame+65564,prefix.count==4 else{throw failure("接收缓冲超限")}
   buffer.append(data);var frames:[(UInt64,UInt8,Data)]=[]
   while buffer.count>=28 {
    let h=Data(buffer.prefix(28)),size=Int(h.uintBE(20,4)),id=h.uintBE(8,8)
    guard h.prefix(4)==Data("EDL1".utf8),h.uintBE(4,4)==UInt64(sid),h.uintBE(16,2)==0,h.uintBE(18,2)==1,
     h[25]==0,size>=16,size<=maximumFrame,id>lastVideo,id<(UInt64(1)<<62),h[24]&2==0 else{throw failure("画面记录不符合协议")}
    guard buffer.count>=28+size else{break}
    let body=Data(buffer[28..<(28+size)]);var nonce=prefix;nonce.appendBE(id)
    var aad=Data(h[4..<16]);aad.append(h[20..<28])
    let box=try AES.GCM.SealedBox(nonce:AES.GCM.Nonce(data:nonce),ciphertext:body.dropLast(16),tag:body.suffix(16))
    let plain=try AES.GCM.open(box,using:key,authenticating:aad)
    lastVideo=id;frames.append((id,h[24],plain));buffer=Data(buffer.dropFirst(28+size))
   }
   return frames
  }
 }
 static func failure(_ message:String)->NSError{NSError(domain:"MacReceiverPreview",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
 static func selfTest(){
  MacMediaPolicy.selfTest()
  let d=dimensions(width:2560,height:1664)!;precondition(d.0==2560 && d.1==1664)
  precondition(dimensions(width:0,height:100)==nil && dimensions(width:.infinity,height:100)==nil)
  let h=dimensions(width:6000,height:4000)!;precondition(h.0*h.1<=8_000_000 && abs(Double(h.0)/Double(h.1)-1.5)<0.003)
  precondition(nals(Data([0,0,0,1,0x40,1,0,0,1,0x42,2])).map{Array($0)}==[[0x40,1],[0x42,2]])
  let key=SymmetricKey(data:Data(repeating:7,count:16)),prefix=Data([1,2,3,4]);var head=Data("EDL1".utf8)
  head.appendBE(UInt32(123));head.appendBE(UInt64(1));head.appendBE(UInt16(0));head.appendBE(UInt16(1));head.appendBE(UInt32(21));head.append(contentsOf:[1,0,0,0])
  var nonce=prefix;nonce.appendBE(UInt64(1));var aad=Data(head[4..<16]);aad.append(head[20..<28]);let plain=Data("frame".utf8)
  let box=try! AES.GCM.seal(plain,using:key,nonce:AES.GCM.Nonce(data:nonce),authenticating:aad);let packet=head+box.ciphertext+box.tag
  var parser=Parser();precondition(try! parser.append(Data(packet.prefix(17)),sid:123,key:key,prefix:prefix).isEmpty)
  let rows=try! parser.append(Data(packet.dropFirst(17)),sid:123,key:key,prefix:prefix);precondition(rows.count==1 && rows[0].2==plain)
  do{_ = try parser.append(packet,sid:123,key:key,prefix:prefix);preconditionFailure("replay accepted")}catch{}
  // Reusing a Data slice must not retain a nonzero base index between records.
  var head2=head;var id2=Data();id2.appendBE(UInt64(2));head2.replaceSubrange(8..<16,with:id2)
  var nonce2=prefix;nonce2.appendBE(UInt64(2));var aad2=Data(head2[4..<16]);aad2.append(head2[20..<28])
  let box2=try! AES.GCM.seal(plain,using:key,nonce:AES.GCM.Nonce(data:nonce2),authenticating:aad2)
  let packet2=head2+box2.ciphertext+box2.tag
  var sequence=Parser();_ = try! sequence.append(packet,sid:123,key:key,prefix:prefix)
  precondition(try! sequence.append(packet2,sid:123,key:key,prefix:prefix).count==1)
  var joined=Parser();precondition(try! joined.append(packet+packet2,sid:123,key:key,prefix:prefix).count==2)
  var bad=packet;bad[bad.count-1]^=1
  do{var parser=Parser();_ = try parser.append(bad,sid:123,key:key,prefix:prefix);preconditionFailure("bad tag accepted")}catch{}
  var huge=head;huge.replaceSubrange(20..<24,with:[255,255,255,255])
  do{var parser=Parser();_ = try parser.append(huge,sid:123,key:key,prefix:prefix);preconditionFailure("oversized record accepted")}catch{}
  print("PASS Mac receiver geometry, Annex-B, fragmented AES-GCM records, replay/tag/size rejection")
 }
}
#endif
