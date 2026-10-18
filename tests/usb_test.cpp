#include "../usb/AccessoryProtocol.hpp"
#include "../usb/StreamMux.hpp"
#include <cassert>
#include <iostream>
using namespace yingqiao::usb;
struct Fixture:ControlPipe{int calls=0,failAt=-1;std::vector<uint8_t>requests;bool transfer(uint8_t direction,uint8_t request,uint16_t index,std::vector<uint8_t>&bytes)override{++calls;requests.push_back(request);if(calls==failAt)return false;if(request==51){assert(direction==0xc0&&bytes.size()==2);bytes={2,0};}if(request==52){assert(direction==0x40&&index<6&&bytes.back()==0&&bytes.size()<=256);}if(request==53)assert(bytes.empty());return true;}};
int main(){Fixture f;assert(Start(f,false,"ephemeral-session")==StartResult::permissionRequired&&f.calls==0);assert(Start(f,true,"ephemeral-session")==StartResult::waitingForReenumeration);assert(f.calls==8&&f.requests.front()==51&&f.requests.back()==53);Fixture fail;fail.failAt=3;assert(Start(fail,true,"session")==StartResult::transferFailed&&fail.requests.back()!=53);assert(AccessoryID(0x18d1,0x2d00));assert(!AccessoryID(0x12d1,0x2d00));
 Decoder parser;Chunk a{1,{1,2,3}},b{2,std::vector<uint8_t>(16000,4)};auto one=Encode(a),two=Encode(b);one.insert(one.end(),two.begin(),two.end());std::vector<Chunk>got;
 for(size_t i=0;i<one.size();i+=7){auto out=parser.push(std::vector<uint8_t>(one.begin()+i,one.begin()+std::min(one.size(),i+7)));got.insert(got.end(),out.begin(),out.end());}assert(got.size()==2&&got[0].stream==1&&got[1].payload==b.payload);
 bool rejected=false;try{auto bad=Encode(a);bad[4]=9;parser.push(bad);}catch(...){rejected=true;}assert(rejected);parser.reset();FairWriter q;for(int i=0;i<10;++i)assert(q.enqueue(a));assert(q.enqueue(b));Chunk next;for(int i=0;i<8;++i){assert(q.pop(next)&&next.stream==1);}assert(q.pop(next)&&next.stream==2);q.reset();assert(!q.pop(next));
 std::cout<<"PASS accessory consent gate, control sequence/failure, fragmented stream mux, parser rejection and control/video fairness. No USB hardware accessed; Harmony AOA compatibility unproven.\n";
}
