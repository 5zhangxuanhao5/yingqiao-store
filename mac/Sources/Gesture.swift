import Foundation
import CoreGraphics

// Personal-use gesture bridge. The serialized HID envelope follows the
// calftrail/Touch format also used by Hammerspoon. Keep this isolated: Apple
// does not publish the CGEvent gesture envelope as a supported API.
func makeMagnifyEvent(source:CGEventSource?,delta:Double,phase:UInt32)->CGEvent? {
 guard delta.isFinite,[1,2,4,8].contains(phase),let prototype=CGEvent(source:source) else{return nil}
 prototype.type=CGEventType(rawValue:29)!;prototype.flags=CGEventFlags(rawValue:0x100)
 let stamp=DispatchTime.now().uptimeNanoseconds;prototype.timestamp=stamp
 guard let serialized=prototype.data else{return nil};var data=serialized as Data
 guard data.count>=24 else{return nil};data.removeLast(24)
 func little<T:FixedWidthInteger>(_ value:T,_ target:inout Data){var v=value.littleEndian;Swift.withUnsafeBytes(of:&v){target.append(contentsOf:$0)}}
 data.appendBE(UInt16(192));data.append(contentsOf:[0x10,0x6D])
 // IOHIDSystemQueueElement: parent hand and vendor token.
 little(stamp,&data);little(UInt64(0),&data);little(UInt32(2),&data);little(UInt32(2),&data)
 little(UInt32(96),&data);little(UInt32(11),&data);little(stamp,&data)
 for value:UInt32 in [2,0,0,0,0,0x23,0,0,0,0,0,0,0,2,0,0,0,0,0,0]{little(value,&data)}
 little(UInt32(72),&data);little(UInt32(1),&data);little(stamp,&data);little(UInt32(0),&data)
 little(UInt16(0xFF00),&data);little(UInt16(0x1777),&data);little(UInt32(1),&data);little(UInt32(40),&data);data.append(Data(count:40))
 func field(_ id:UInt8,_ value:UInt32,_ float:Bool=false){data.appendBE(UInt16(1));data.append(float ? 0xC0:0x40);data.append(id);data.appendBE(value)}
 field(0x6E,8);field(0x6F,0);field(0x70,0);field(0x84,phase);field(0x85,0)
 field(0x71,Float(delta).bitPattern,true);field(0x8B,0,true);field(0x8C,0,true)
 return CGEvent(withDataAllocator:nil,data:data as CFData)
}
