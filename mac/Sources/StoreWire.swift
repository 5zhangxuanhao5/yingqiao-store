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
 guard !value.contains("\0"),let part=value.lowercased().split(separator:"%").first else{return false};let s=String(part)
 var ipv4=in_addr();if inet_pton(AF_INET,s,&ipv4)==1 {let v=UInt32(bigEndian:ipv4.s_addr);return (v>>24)==10 || (v>>20)==0xac1 || (v>>16)==0xc0a8 || (v>>16)==0xa9fe}
 var ipv6=in6_addr();guard inet_pton(AF_INET6,s,&ipv6)==1 else{return false};let b=withUnsafeBytes(of:&ipv6){Array($0)}
 if b.prefix(10).allSatisfy({$0==0}) && b[10]==255 && b[11]==255{return privateLANAddress(b[12...15].map(String.init).joined(separator:"."))}
 return b[0]&0xfe==0xfc || (b[0]==0xfe && b[1]&0xc0==0x80)
}
final class LinePeer {
 let usb:Bool,standby:Bool;let connection:NWConnection;var buffer=Data();var closed=false;var probeReplied=false;var onLine:((String)->Void)?,onClose:(()->Void)?
 init(_ value:NWConnection,usb:Bool=false,standby:Bool=false){connection=value;self.usb=usb;self.standby=standby}
 func start(){connection.stateUpdateHandler={[weak self] state in guard let self else{return};switch state{case .ready:self.read();case .failed,.cancelled:self.close();default:break}};connection.start(queue:.main)}
 func read(){connection.receive(minimumIncompleteLength:1,maximumLength:4096){[weak self] data,_,end,error in guard let self,!self.closed else{return};if let data{self.buffer.append(data)};guard self.buffer.count<=8192 else{self.close();return};while let i=self.buffer.firstIndex(of:10){let line=String(decoding:self.buffer.prefix(upTo:i),as:UTF8.self);self.buffer.removeSubrange(...i);self.onLine?(line)};if end || error != nil{self.close()}else{self.read()}}}
 func send(_ value:String){guard !closed,value.utf8.count<8192 else{return};connection.send(content:Data((value+"\n").utf8),completion:.contentProcessed{[weak self] error in if error != nil{DispatchQueue.main.async{self?.close()}}})}
 func close(){guard !closed else{return};closed=true;connection.cancel();onClose?()}
}
