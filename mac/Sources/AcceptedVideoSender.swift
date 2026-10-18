import Foundation
import Network
import CryptoKit
import Darwin

final class VideoSender {
 struct EncodePermit:Sendable{
  let id:UUID,requiresKeyframe:Bool
  init(id:UUID,requiresKeyframe:Bool=false){self.id=id;self.requiresKeyframe=requiresKeyframe}
 }
 private struct PermitState{let bytePermit:WANByteAdmissionBudget.Permit?}
 private var encodePermits:[UUID:PermitState]=[:]
 private var wireBudget:WANByteAdmissionBudget
 private var wanFlowEnabled=false
 private var stopped=false
 var onRecovery:(()->Void)?
 let sid:UInt32,key:SymmetricKey,serverPrefix:Data,clientPrefix:Data,viewerToken:String
 let queue=DispatchQueue(label:"edgelink.video.send",qos:.userInteractive)
 let socketFD:Int32;var peerAddress=sockaddr_storage(),peerLength:socklen_t=0
 var source:DispatchSourceRead?,viewer:NWConnection?,onReady:(()->Void)?
 var nextID:UInt64=1,lastHello:UInt64=0;var pendingSends=0;var closed=false
 var cursorEnabled=false,cursorWritePending=false,pendingCursor:CursorSample?
 var nextCursorSequence:UInt64=1,cursorRecords=0,cursorCoalesced=0,cursorWriteFailures=0
 var acked:UInt64=0;let tcpMode:Bool,timedFrames:Bool
 let targetFPS:Int;var roundTrip=0.03,sentAt:[UInt64:UInt64]=[:],recentRoundTrips:[Double]=[]
 init(port:UInt16,tcpMode:Bool,targetFPS:Int=60,timedFrames:Bool=false)throws{
  wireBudget=WANByteAdmissionBudget(kbps:40000,targetFPS:targetFPS)
  self.targetFPS=targetFPS
  self.tcpMode=tcpMode;self.timedFrames=timedFrames;sid=UInt32(randomBytes(4).uintBE(0,4));key=SymmetricKey(data:randomBytes(16));serverPrefix=randomBytes(4);clientPrefix=randomBytes(4);viewerToken=hex(randomBytes(32))
  socketFD=Darwin.socket(AF_INET6,SOCK_DGRAM,0);guard socketFD>=0 else{throw NSError(domain:"UDP",code:Int(errno))}
  var off:Int32=0;setsockopt(socketFD,IPPROTO_IPV6,IPV6_V6ONLY,&off,socklen_t(MemoryLayout<Int32>.size))
  var on:Int32=1;setsockopt(socketFD,SOL_SOCKET,SO_REUSEADDR,&on,socklen_t(MemoryLayout<Int32>.size))
  var address=sockaddr_in6();address.sin6_family=sa_family_t(AF_INET6);address.sin6_port=port.bigEndian
  let r=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(socketFD,$0,socklen_t(MemoryLayout<sockaddr_in6>.size))}}
  if r != 0{Darwin.close(socketFD);throw NSError(domain:"UDP",code:Int(errno))}
  fcntl(socketFD,F_SETFL,O_NONBLOCK)
 }
 func start(){let s=DispatchSource.makeReadSource(fileDescriptor:socketFD,queue:queue);source=s;s.setEventHandler{[weak self] in self?.readHello()};s.resume()}
 var keyHex:String {key.withUnsafeBytes{hex(Data($0))}}
 func handshake(width:Int,height:Int,fps:Int,desktop:DesktopInputTopology?)->String{
  var session=Data();session.appendBE(sid)
  return "OK \(hex(session)) \(keyHex) \(hex(serverPrefix)) \(hex(clientPrefix)) \(viewerToken) \(width) \(height) \(fps)"+(timedFrames ? " timing-v1":"")+(desktop?.wireFields() ?? "")+" cursor-v1 overview-v1"
 }
 func header(frame:UInt64,total:Int,flags:UInt8,type:UInt8,index:Int=0,count:Int=1)->Data {
  var d=Data("EDL1".utf8);d.appendBE(sid);d.appendBE(frame);d.appendBE(UInt16(index));d.appendBE(UInt16(count));d.appendBE(UInt32(total));d.append(flags);d.append(type);d.appendBE(UInt16(0));return d
 }
 func aad(_ header:Data)->Data {var d=Data(header[4..<16]);d.append(header[20..<28]);return d}
 func nonce(prefix:Data,id:UInt64)throws->AES.GCM.Nonce {var d=prefix;d.appendBE(id);return try AES.GCM.Nonce(data:d)}
 func readHello(){
  
  var buffer=[UInt8](repeating:0,count:1500)
  while true{
   var address=sockaddr_storage();var length=socklen_t(MemoryLayout<sockaddr_storage>.size)
   let count=withUnsafeMutablePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.recvfrom(socketFD,&buffer,buffer.count,0,$0,&length)}}
   if count<0{return};let d=Data(buffer.prefix(count));guard d.count>=44,d.prefix(4)==Data("EDL1".utf8),d.uintBE(4,4)==UInt64(sid),d[25]==1,d.uintBE(16,2)==0,d.uintBE(18,2)==1 else{continue}
   let id=d.uintBE(8,8);guard id>lastHello else{continue}
   let body=d.dropFirst(28);guard body.count==Int(d.uintBE(20,4)),body.count>=16 else{continue}
   do{
    let box=try AES.GCM.SealedBox(nonce:nonce(prefix:clientPrefix,id:id),ciphertext:body.dropLast(16),tag:body.suffix(16))
    let plain=try AES.GCM.open(box,using:key,authenticating:aad(d));guard plain==Data("hello".utf8) else{continue}
    lastHello=id;let wasReady=peerLength>0;peerAddress=address;peerLength=length;if !wasReady{flushCursor();onReady?()}
   }catch{continue}
  }
 }
 func attachViewer(_ connection:NWConnection){queue.async{guard !self.closed else{connection.cancel();return};self.viewer=connection;self.flushCursor();self.onReady?()}}
 func acknowledge(_ id:UInt64){queue.async{
  
  guard id<(UInt64(1)<<63) else{return}
  let received=min(id,self.nextID-1)
  if let sent=self.sentAt[received]{let now=monotonicNanoseconds();let elapsed=now>=sent ? Double(now-sent)/1e9:0;if elapsed>0 && elapsed<15{self.roundTrip=self.roundTrip*0.8+elapsed*0.2;self.recentRoundTrips.append(elapsed);if self.recentRoundTrips.count>120{self.recentRoundTrips.removeFirst()}}}
  self.acked=max(self.acked,received);self.sentAt=self.sentAt.filter{$0.key>self.acked}
  if self.tcpMode{_ = self.wireBudget.acknowledge(through:self.acked)}
 }}
 // Call after AUTH and after an actually applied RATE. Existing 8Mbps initial
 // WAN is conservatively gated; normal 40Mbps USB/LAN enforcement stays off.
 func setTargetBitrate(kbps:Int){queue.async{guard kbps>=1500,kbps<=240000 else{return};self.wireBudget.updateTarget(kbps:kbps);self.wanFlowEnabled=self.tcpMode && kbps<=8000}}
 private var baseACKRTTms:Double{(recentRoundTrips.min() ?? min(roundTrip,0.15))*1000}
 func reserveEncodeBudget()->EncodePermit?{queue.sync{
  
  guard !closed,!tcpMode || (pendingSends<2 && nextID+UInt64(encodePermits.count)<=acked+UInt64(frameWindow)) else{return nil}
  let bytePermit:WANByteAdmissionBudget.Permit?
  if wanFlowEnabled{guard let value=wireBudget.reserve(nowNs:monotonicNanoseconds(),baseRTTms:baseACKRTTms) else{return nil};bytePermit=value}else{bytePermit=nil}
  let value=EncodePermit(id:UUID());encodePermits[value.id]=PermitState(bytePermit:bytePermit);return value
 }}
 func cancelEncodePermit(_ permit:EncodePermit){queue.async{if let state=self.encodePermits.removeValue(forKey:permit.id){if let byte=state.bytePermit{self.wireBudget.cancel(byte)}}}}
 func send(_ annexB:Data,keyframe:Bool,timing:FrameTiming,permit:EncodePermit?=nil){queue.async{
  let admission=permit.flatMap{self.encodePermits.removeValue(forKey:$0.id)}
  
  // Even a stop race releases the reservation. Actual already-encoded frames
  // are accounted below, never dropped for exceeding a freshly lowered budget.
  if self.closed{if let byte=admission?.bytePermit{self.wireBudget.cancel(byte)};return}
  guard (self.tcpMode ? self.viewer != nil:self.peerLength>0) else{if let byte=admission?.bytePermit{self.wireBudget.cancel(byte)};return}
  if permit != nil && admission == nil{self.closed=true;self.viewer?.cancel();return}
  guard self.nextID<(UInt64(1)<<62) else{if let byte=admission?.bytePermit{self.wireBudget.cancel(byte)};self.closed=true;self.viewer?.cancel();return}
  // A slow receiver is handled before encoding by the capture engine. Never discard arbitrary P frames here.
  let id=self.nextID;self.nextID += 1
  let sendStart=monotonicNanoseconds()
  if self.tcpMode{self.sentAt[id]=sendStart}
  do{
   let plain=self.timedFrames ? timing.payload(annexB,sendStart:sendStart):annexB
   let total=plain.count+16;let flags:UInt8=(keyframe ? 1:0) | (self.timedFrames ? 2:0)
   let base=self.header(frame:id,total:total,flags:flags,type:0)
   let box=try AES.GCM.seal(plain,using:self.key,nonce:self.nonce(prefix:self.serverPrefix,id:id),authenticating:self.aad(base))
   var encrypted=box.ciphertext;encrypted.append(box.tag)
   if self.tcpMode,let viewer=self.viewer{
    self.pendingSends += 1;var record=base;record.append(encrypted)
    let accounted:Bool
    if let byte=admission?.bytePermit{accounted=self.wireBudget.commit(byte,frameID:id,wireBytes:record.count,nowNs:sendStart,baseRTTms:self.baseACKRTTms,keyframe:keyframe)}
    else{accounted=self.wireBudget.accountAlreadyEncoded(frameID:id,wireBytes:record.count,nowNs:sendStart,baseRTTms:self.baseACKRTTms,keyframe:keyframe)}
    guard accounted else{self.closed=true;viewer.cancel();return}
    viewer.send(content:record,completion:.contentProcessed{[weak self] error in self?.queue.async{self?.pendingSends=max(0,(self?.pendingSends ?? 1)-1);if error != nil{self?.closed=true}}})
   }else{
    let chunk=1172;let fragments=(encrypted.count+chunk-1)/chunk
    for i in 0..<fragments{
     let start=encrypted.startIndex+i*chunk,end=encrypted.startIndex+min(encrypted.count,(i+1)*chunk)
     var packet=self.header(frame:id,total:total,flags:flags,type:0,index:i,count:fragments);packet.append(encrypted[start..<end])
     packet.withUnsafeBytes{ bytes in withUnsafePointer(to:&self.peerAddress){$0.withMemoryRebound(to:sockaddr.self,capacity:1){_ = Darwin.sendto(self.socketFD,bytes.baseAddress,bytes.count,0,$0,self.peerLength)}}}
    }
   }
  }catch{if let byte=admission?.bytePermit{self.wireBudget.cancel(byte)};self.closed=true}
 }}
 func enableCursor(_ enabled:Bool){queue.async{self.cursorEnabled=enabled;if !enabled{self.pendingCursor=nil}else{self.flushCursor()}}}
 func cursorRecord(_ sample:CursorSample,sequence:UInt64)throws->Data{
  guard sample.valid(),sequence>0,sequence<=RemoteInput.maximumCursorSequence else{throw NSError(domain:"Cursor",code:1)}
  let id=(UInt64(1)<<63)|sequence,plain=sample.payload(),base=header(frame:id,total:plain.count+16,flags:0,type:2)
  let box=try AES.GCM.seal(plain,using:key,nonce:nonce(prefix:serverPrefix,id:id),authenticating:aad(base))
  var record=base;record.append(box.ciphertext);record.append(box.tag);return record
 }
 // Revision occupies a nonce domain disjoint from video and cursor records.
 func sendTopology(_ topology:DesktopInputTopology,revision:UInt64){queue.async{
  guard !self.closed,self.tcpMode,let viewer=self.viewer,topology.valid(),revision>0,revision<=RemoteInput.maximumCursorSequence else{return}
  do{
   let plain=Data((String(revision)+topology.wireFields()).utf8),id=(UInt64(1)<<62)|revision
   let base=self.header(frame:id,total:plain.count+16,flags:0,type:3)
   let box=try AES.GCM.seal(plain,using:self.key,nonce:self.nonce(prefix:self.serverPrefix,id:id),authenticating:self.aad(base))
   var record=base;record.append(box.ciphertext);record.append(box.tag)
   viewer.send(content:record,completion:.contentProcessed{_ in})
  }catch{self.closed=true;viewer.cancel()}
 }}
 func sendCursor(_ sample:CursorSample){queue.async{
  guard !self.closed,self.cursorEnabled,sample.valid() else{return}
  if self.pendingCursor != nil{self.cursorCoalesced += 1};self.pendingCursor=sample;self.flushCursor()
 }}
 // At most one small cursor write and one latest position are retained. They
 // never advance the video frame sequence, ACK window or encoding budget.
 private func flushCursor(){
  guard !closed,cursorEnabled,!cursorWritePending,(tcpMode ? viewer != nil:peerLength>0),let sample=pendingCursor else{return}
  pendingCursor=nil
  do{
   let record=try cursorRecord(sample,sequence:nextCursorSequence);nextCursorSequence += 1
   if tcpMode,let viewer{
    cursorWritePending=true
    viewer.send(content:record,completion:.contentProcessed{[weak self] error in self?.queue.async{guard let self else{return};self.cursorWritePending=false;if error != nil{self.cursorWriteFailures += 1;self.closed=true}else{self.cursorRecords += 1;self.flushCursor()}}})
   }else if peerLength>0{
    let sent=record.withUnsafeBytes{bytes in withUnsafePointer(to:&peerAddress){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.sendto(socketFD,bytes.baseAddress,bytes.count,0,$0,peerLength)}}}
    if sent==record.count{cursorRecords += 1}else{cursorWriteFailures += 1}
   }
  }catch{cursorWriteFailures += 1;closed=true}
 }
 // Only current authenticated owner can select this branch before VIEW/capture.





 // Only the current authenticated control owner calls this. Queue ordering
 // invalidates the lost reference chain before asking capture for its new IDR.


 // Allow packets to fill the measured path, while limiting queued media to that path's flight time.
 var frameWindow:Int {let baseline=recentRoundTrips.min() ?? roundTrip;let jitterBudget=min(0.03,max(0,roundTrip-baseline));return min(24,max(4,Int(ceil((baseline+jitterBudget)*Double(targetFPS)))+2))}
 func canAcceptFrame()->Bool {queue.sync{return !closed && (!tcpMode || (pendingSends<2 && nextID+UInt64(encodePermits.count)<=acked+UInt64(frameWindow) && (!wanFlowEnabled || wireBudget.canReserve(nowNs:monotonicNanoseconds(),baseRTTms:baseACKRTTms))))}}
 func transportStats()->[String:Any]{queue.sync{return ["wanFlowEnabled":wanFlowEnabled,"wireBudget":wireBudget.stats(baseRTTms:baseACKRTTms,nowNs:monotonicNanoseconds()),"pendingEncodePermits":encodePermits.count,"ackRoundTripMs":roundTrip*1000,"frameWindow":frameWindow,"unacknowledgedFrames":Int(nextID-1-acked),"pendingWrites":pendingSends,"cursorEnabled":cursorEnabled,"cursorRecords":cursorRecords,"cursorCoalesced":cursorCoalesced,"cursorWritePending":cursorWritePending,"cursorWriteFailures":cursorWriteFailures]}}
 func stop(){queue.sync{guard !stopped else{return};stopped=true;closed=true;onRecovery=nil;onReady=nil;wireBudget.stop();encodePermits.removeAll();cursorEnabled=false;pendingCursor=nil;viewer?.cancel();viewer=nil;source?.cancel();source=nil;Darwin.close(socketFD)}}
}
