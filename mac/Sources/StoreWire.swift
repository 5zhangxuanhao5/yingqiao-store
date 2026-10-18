import Foundation
import Network
import Security
import CryptoKit
import Darwin

func randomBytes(_ n:Int)->Data {var d=Data(count:n);let status=d.withUnsafeMutableBytes{SecRandomCopyBytes(kSecRandomDefault,n,$0.baseAddress!)};precondition(status==errSecSuccess);return d}
func hex(_ d:Data)->String{d.map{String(format:"%02x",$0)}.joined()}
func constantEqual(_ a:String,_ b:String)->Bool{zip(SHA256.hash(data:Data(a.utf8)),SHA256.hash(data:Data(b.utf8))).reduce(UInt8(0)){$0|($1.0 ^ $1.1)}==0}
extension Data {
 mutating func appendBE<T:FixedWidthInteger>(_ value:T){var v=value.bigEndian;Swift.withUnsafeBytes(of:&v){append(contentsOf:$0)}}
 func uintBE(_ start:Int,_ count:Int)->UInt64{guard start>=0,count>0,start+count<=self.count else{return 0};return self[start..<start+count].reduce(0){($0<<8)|UInt64($1)}}
}
func privateLANAddress(_ value:String)->Bool {
 let s=value.lowercased().split(separator:"%")[0].description
 var ipv4=in_addr();if inet_pton(AF_INET,s,&ipv4)==1 {let v=UInt32(bigEndian:ipv4.s_addr);return (v>>24)==10 || (v>>20)==0xac1 || (v>>16)==0xc0a8 || (v>>16)==0xa9fe}
 var ipv6=in6_addr();guard inet_pton(AF_INET6,s,&ipv6)==1 else{return false};let b=withUnsafeBytes(of:&ipv6){Array($0)}
 if b.prefix(10).allSatisfy({$0==0}) && b[10]==255 && b[11]==255{return privateLANAddress(b[12...15].map(String.init).joined(separator:"."))}
 return b[0]&0xfe==0xfc || (b[0]==0xfe && b[1]&0xc0==0x80)
}
final class LinePeer {
 let connection:NWConnection;var buffer=Data();var closed=false;var onLine:((String)->Void)?,onClose:(()->Void)?
 init(_ value:NWConnection){connection=value}
 func start(){connection.stateUpdateHandler={[weak self] state in guard let self else{return};switch state{case .ready:self.read();case .failed,.cancelled:self.close();default:break}};connection.start(queue:.main)}
 func read(){connection.receive(minimumIncompleteLength:1,maximumLength:4096){[weak self] data,_,end,error in guard let self,!self.closed else{return};if let data{self.buffer.append(data)};guard self.buffer.count<=8192 else{self.close();return};while let i=self.buffer.firstIndex(of:10){let line=String(decoding:self.buffer.prefix(upTo:i),as:UTF8.self);self.buffer.removeSubrange(...i);self.onLine?(line)};if end || error != nil{self.close()}else{self.read()}}}
 func send(_ value:String){guard !closed,value.utf8.count<8192 else{return};connection.send(content:Data((value+"\n").utf8),completion:.contentProcessed{[weak self] error in if error != nil{DispatchQueue.main.async{self?.close()}}})}
 func close(){guard !closed else{return};closed=true;connection.cancel();onClose?()}
}
final class StoreFrameSender {
 let sid:UInt32,key:SymmetricKey,serverPrefix:Data,clientPrefix:Data,viewerToken:String
 let queue=DispatchQueue(label:"cn.edgelink.store.video",qos:.userInteractive)
 private let lock=NSLock();private var pending=0,alive=true;private var frameWindow=StoreFrameWindow();private var sentFrames:UInt64=0,sentBytes:UInt64=0
 var connection:NWConnection?
 init(fps:Int=60){frameWindow.targetFPS=fps;sid=UInt32(randomBytes(4).uintBE(0,4));key=SymmetricKey(data:randomBytes(16));serverPrefix=randomBytes(4);clientPrefix=randomBytes(4);viewerToken=hex(randomBytes(32))}
 var canEncode:Bool{lock.lock();defer{lock.unlock()};return alive && connection != nil && pending<2 && frameWindow.canEncode}
 func handshake(width:Int,height:Int,fps:Int,topology:DesktopInputTopology,codec:String)->String {var s=Data();s.appendBE(sid);return "OK \(hex(s)) \(key.withUnsafeBytes{hex(Data($0))}) \(hex(serverPrefix)) \(hex(clientPrefix)) \(viewerToken) \(width) \(height) \(fps)"+topology.wireFields()+" local-handover-v1 codec-\(codec)-v1"}
 func attach(_ value:NWConnection){lock.lock();connection=value;lock.unlock()}
 func send(_ frame:Data,keyframe:Bool){lock.lock();guard alive,let connection else{lock.unlock();return};pending+=1;let id=frameWindow.sent(now:ProcessInfo.processInfo.systemUptime);sentFrames+=1;sentBytes+=UInt64(frame.count);lock.unlock();queue.async{[weak self] in guard let self else{return}
  do {var h=Data("EDL1".utf8);h.appendBE(self.sid);h.appendBE(id);h.appendBE(UInt16(0));h.appendBE(UInt16(1));h.appendBE(UInt32(frame.count+16));h.append(keyframe ? 1:0);h.append(0);h.appendBE(UInt16(0));var aad=Data(h[4..<16]);aad.append(h[20..<28]);var n=self.serverPrefix;n.appendBE(id);let box=try AES.GCM.seal(frame,using:self.key,nonce:AES.GCM.Nonce(data:n),authenticating:aad);h.append(box.ciphertext);h.append(box.tag)
   connection.send(content:h,completion:.contentProcessed{[weak self] error in guard let self else{return};self.lock.lock();self.pending=max(0,self.pending-1);if error != nil{self.alive=false};self.lock.unlock()})
  }catch{self.stop()}
 }}
 func acknowledge(_ id:UInt64){lock.lock();frameWindow.acknowledge(id,now:ProcessInfo.processInfo.systemUptime);lock.unlock()}
 func health()->[String:Any]{lock.lock();defer{lock.unlock()};return ["framesSent":sentFrames,"bytesSent":sentBytes,"renderSubmissionAck":frameWindow.lastAck,"outstanding":frameWindow.outstanding.count,"frameWindow":frameWindow.limit,"ackMinMs":frameWindow.samples.min() ?? -1,"ackP95ms":frameWindow.p95,"pendingSocketWrites":pending]}
 func stop(){lock.lock();alive=false;let c=connection;connection=nil;lock.unlock();c?.cancel()}
}
