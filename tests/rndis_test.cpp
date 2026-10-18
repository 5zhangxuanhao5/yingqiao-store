#include "../usb/RNDIS.hpp"
#include <cassert>
#include <iostream>
using namespace yingqiao::rndis;
int main(){auto init=Initialize(17);assert(Read(init.data(),init.size(),0)==2&&Read(init.data(),init.size(),8)==17);Bytes answer(52);Write(answer,0,0x80000002);Write(answer,4,52);Write(answer,8,17);assert(Complete(answer,2,17)&&!Complete(answer,2,18));Write(answer,12,1);assert(!Complete(answer,2,17));
 Bytes frame(1514,0xa5);auto packet=Packet(frame.data(),frame.size());auto both=packet;both.insert(both.end(),packet.begin(),packet.end());auto parsed=Parse(both.data(),both.size());assert(parsed.size()==2&&parsed[1]==frame);
 auto padded=packet;padded.push_back(0);assert(Parse(padded.data(),padded.size()).size()==1);padded.back()=1;bool tailRejected=false;try{Parse(padded.data(),padded.size());}catch(...){tailRejected=true;}assert(tailRejected);
 for(int mode=0;mode<4;mode++){auto bad=packet;if(mode==0)Write(bad,4,7);if(mode==1)Write(bad,8,0xffffffff);if(mode==2)Write(bad,12,65536);if(mode==3)bad.pop_back();bool failed=false;try{Parse(bad.data(),bad.size());}catch(...){failed=true;}assert(failed);}
 Bytes query(30);Write(query,0,0x80000004);Write(query,4,30);Write(query,8,2);Write(query,16,6);Write(query,20,16);auto mac=QueryData(query,2);assert(mac.size()==6);Write(query,20,0xfffffffc);bool failed=false;try{QueryData(query,2);}catch(...){failed=true;}assert(failed);
 std::cout<<"PASS RNDIS request IDs/status, Ethernet frame roundtrip, aggregated messages, truncated/oversized/overflow offsets. Protocol fixtures only.\n";
}
