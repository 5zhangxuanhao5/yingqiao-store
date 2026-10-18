#include "../shared/DisplayProfile.hpp"
#include "../shared/TransportPolicy.hpp"
#include "../harmony/entry/src/main/cpp/store_policy.h"
#include <cassert>
#include <iostream>
int main(){using namespace yingqiao;int cases=0;
 for(auto size:std::vector<std::pair<int,int>>{{3120,2080},{2880,1920},{2800,1840},{2560,1600},{2456,1600},{1920,1200},{1600,2560},{2048,2048},{3840,2160}}){auto p=ChooseDisplayProfile(size.first,size.second,120,"hevc",[](auto,int w,int h,int fps){return w<=2400&&h<=2400&&fps<=60;});assert(p.supported&&p.width%2==0&&p.height%2==0);assert(std::abs(double(p.width)/p.height-double(size.first)/size.second)<.005);++cases;}
 auto p=ChooseDisplayProfile(2800,1840,60,"hevc",[](auto codec,int,int,int fps){return codec=="avc"&&fps<=30;});assert(p.supported&&p.codec=="avc"&&p.fps==30);assert(!ChooseDisplayProfile(1,1,60,"avc",[](auto,int,int,int){return true;}).supported);
 std::vector<Path>paths={{"wifi","paired",true,false,true,100,20,100},{"usb","paired",true,true,true,100,3,500}};assert(PreferredPath(paths,"paired","wifi",101,90,false)=="usb");assert(PreferredPath(paths,"paired","wifi",101,90,true)=="wifi");assert(PreferredPath(paths,"paired","wifi",101,100,false)=="wifi");// A just-failed USB stream can still have a fresh cached probe. It must not
 // win recovery, even when it was faster, the dwell time is short, or a drag
 // was held when the cable disappeared.
 assert(PreferredPath(paths,"paired","usb",101,100,true,false)=="wifi");
 assert(PreferredPath(std::vector<Path>{paths[1]},"paired","usb",101,100,false,false).empty());
 paths[1].consumerSupported=false;assert(PreferredPath(paths,"paired","wifi",101,90,false)=="wifi");paths[1].consumerSupported=true;paths[1].peer="other";assert(PreferredPath(paths,"paired","wifi",101,90,false)=="wifi");paths[1].peer="paired";paths[0].authenticated=false;assert(PreferredPath(paths,"paired","wifi",101,100,true)=="usb");assert(PreferredPath(paths,"paired","usb",120,90,false).empty());paths[0].authenticated=true;StablePathChoice stable;
 assert(stable.choose(paths,"paired","wifi",101,90,false,true)=="wifi");
 assert(stable.choose(paths,"paired","wifi",101.1,90,false,true)=="wifi"); // Same probe is not another win.
 paths[0].measuredAt=paths[1].measuredAt=101;
 assert(stable.choose(paths,"paired","wifi",101.2,90,false,true)=="wifi");
 paths[0].measuredAt=paths[1].measuredAt=102;
 assert(stable.choose(paths,"paired","wifi",102,90,false,true)=="usb");
 assert(stable.choose(paths,"paired","usb",102,102,true,false)=="wifi"); // No debounce on failure.
 DisplayLease l;l.retain("paired",100);assert(!l.adopt("other",101));assert(l.adopt("paired",105));l.retain("paired",110);l.explicitEnd();assert(!l.adopt("paired",111));
 #ifdef ORIGINAL_USB_TEST
 assert(edgelinkstore::DebugUSBAvailable());
 assert(edgelinkstore::Allowed("127.0.0.1",49561,"extend","store-hevc"));
 assert(!edgelinkstore::Allowed("127.0.0.1",49562,"extend","store-hevc"));
 assert(!edgelinkstore::Allowed("127.0.0.1",49561,"remote","store-hevc"));
#else
 assert(!edgelinkstore::DebugUSBAvailable());
 assert(!edgelinkstore::Allowed("127.0.0.1",49561,"extend","store-hevc"));
#endif
 assert(edgelinkstore::Allowed("192.168.1.10",49563,"extend","store-avc"));for(auto ip:{"127.0.0.1","8.8.8.8","100.64.1.1","example.com","192.168.1.5.evil","::1"})assert(!edgelinkstore::Allowed(ip,49563,"extend","store-avc"));assert(!edgelinkstore::Allowed("10.0.0.5",49563,"remote","store-avc"));assert(!edgelinkstore::Allowed("10.0.0.5",48561,"extend","tcp"));std::cout<<"PASS "<<cases<<" panel ratios, codec/FPS fallback, authenticated route hysteresis/failure, display lease, local-only gate. Policy simulation, not USB integration proof.\n";
}
