import Foundation
import Security
import Network
import VideoToolbox
import Darwin

struct StoreIdentity:Codable {
 let token:String,password:String,certificate:String
 static var directory:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("cn.edgelink.store.mac",isDirectory:true)}
 static func createOrRead()throws->StoreIdentity {
  let fm=FileManager.default,dir=directory;try fm.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);let config=dir.appendingPathComponent("identity.json")
  if fm.fileExists(atPath:config.path){return try JSONDecoder().decode(Self.self,from:Data(contentsOf:config))}
  let temp=dir.appendingPathComponent(UUID().uuidString,isDirectory:true);try fm.createDirectory(at:temp,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:temp)}
  let password=hex(randomBytes(32)),pass=temp.appendingPathComponent("password"),key=temp.appendingPathComponent("key.pem"),cert=temp.appendingPathComponent("certificate.pem"),p12=temp.appendingPathComponent("identity.p12")
  try Data(password.utf8).write(to:pass,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:pass.path)
  func run(_ arguments:[String])throws{let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/openssl");p.arguments=arguments;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice;try p.run();p.waitUntilExit();guard p.terminationStatus==0 else{throw NSError(domain:"StoreIdentity",code:Int(p.terminationStatus),userInfo:[NSLocalizedDescriptionKey:"无法生成本机配对身份，请检查系统 OpenSSL 是否可用"])} }
  try run(["req","-x509","-newkey","rsa:2048","-nodes","-keyout",key.path,"-out",cert.path,"-days","3650","-subj","/CN=Yingqiao-Store-Local"])
  try run(["pkcs12","-export","-inkey",key.path,"-in",cert.path,"-out",p12.path,"-passout","file:"+pass.path])
  let value=StoreIdentity(token:hex(randomBytes(32)),password:password,certificate:try String(contentsOf:cert,encoding:.utf8));let finalP12=dir.appendingPathComponent("identity.p12");try fm.moveItem(at:p12,to:finalP12);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:finalP12.path);try JSONEncoder().encode(value).write(to:config,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:config.path);return value
 }
 func tlsOptions()throws->NWProtocolTLS.Options {
  var items:CFArray?;var options:[String:Any]=[kSecImportExportPassphrase as String:password]
  if #available(macOS 15.0,*){options[kSecImportToMemoryOnly as String]=true}
  let result=SecPKCS12Import(try Data(contentsOf:Self.directory.appendingPathComponent("identity.p12")) as CFData,options as CFDictionary,&items)
  guard result==errSecSuccess,let list=items as? [[String:Any]],let identity=list.first?[kSecImportItemIdentity as String] else{throw NSError(domain:"StoreTLS",code:Int(result))}
  let tls=NWProtocolTLS.Options();sec_protocol_options_set_local_identity(tls.securityProtocolOptions,sec_identity_create(identity as! SecIdentity)!);sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12);return tls
 }
 func pairingJSON(host:String)throws->String {let codecs:[String]=[("avc",kCMVideoCodecType_H264),("hevc",kCMVideoCodecType_HEVC)].filter{StoreCapture.supports($0.1)}.map{$0.0};guard !codecs.isEmpty else{throw NSError(domain:"HardwareEncoder",code:1,userInfo:[NSLocalizedDescriptionKey:"未找到可用的硬件编码器"])};let d:[String:Any]=["schema":"yingqiao-pairing-v1","host":host,"token":token,"cert":certificate,"port":49563,"udpPort":49564,"codecs":codecs];return String(decoding:try JSONSerialization.data(withJSONObject:d,options:[.sortedKeys]),as:UTF8.self)}
 static func addresses()->[String]{var first:UnsafeMutablePointer<ifaddrs>?;guard getifaddrs(&first)==0 else{return []};defer{freeifaddrs(first)};var values:[String]=[],p=first
  while let item=p{defer{p=item.pointee.ifa_next};guard let address=item.pointee.ifa_addr,address.pointee.sa_family==AF_INET else{continue};var name=[CChar](repeating:0,count:Int(NI_MAXHOST));if getnameinfo(address,socklen_t(address.pointee.sa_len),&name,socklen_t(name.count),nil,0,NI_NUMERICHOST)==0{let ip=String(cString:name);if privateLANAddress(ip){values.append(ip)}}};return Array(Set(values)).sorted()
 }
}
