#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstddef>
#include <sstream>
#include <string>

namespace edgelinkwan {
struct Observation {
 uint64_t nowMs=0,generation=0,bytesReceived=0,receivedFrames=0;
 bool active=false,running=false,writerReady=false,capability=false,clockValid=false;
 int appliedKbps=0;double ageP50ms=0,ageP95ms=0,uncertaintyMs=0;size_t ageSamples=0;
};
struct Decision {
 int requestKbps=0,targetKbps=4000,appliedKbps=0;bool supported=false;
 double goodputKbps=0,ageLowerBoundMs=-1;std::string reason="waiting";
};
class RateController {
 uint64_t generation_=UINT64_MAX,lastMs_=0,lastBytes_=0,lastFrames_=0,lastRequest_=0,lastDecrease_=0;
 uint64_t lastPoll_=0;bool havePoll_=false;
 bool haveSample_=false,haveRequest_=false,supported_=false;
 int target_=4000,applied_=0;double goodput_=0,healthy_=0;std::string reason_="waiting";
 Decision result(int request,double age)const{return{request,target_,applied_,supported_,goodput_,age,reason_};}
 bool requestDue(uint64_t now,uint64_t delay=1000)const{return !haveRequest_||(now>=lastRequest_&&now-lastRequest_>=delay);}
public:
 void Reset(uint64_t generation){*this=RateController();generation_=generation;}
 bool Due(uint64_t now)const{return !havePoll_||now<lastPoll_||now-lastPoll_>=800;}
 Decision Observe(const Observation&s){
  if(s.generation!=generation_)Reset(s.generation);
  lastPoll_=s.nowMs;havePoll_=true;
  supported_=s.capability;if(s.appliedKbps>=1500&&s.appliedKbps<=80000)applied_=s.appliedKbps;
  bool ageValid=s.clockValid&&std::isfinite(s.uncertaintyMs)&&s.uncertaintyMs>=0&&s.uncertaintyMs<=1000&&s.ageSamples>=12&&
   std::isfinite(s.ageP50ms)&&std::isfinite(s.ageP95ms)&&s.ageP50ms>=0&&s.ageP95ms>=0;
  double lower=ageValid?std::max(0.0,s.ageP95ms-s.uncertaintyMs):-1;
  if(!s.active||!s.running||!s.writerReady||!supported_){haveSample_=false;healthy_=0;reason_=!supported_?"host_rate_v2_required":"inactive_or_writer_unready";return result(0,lower);}
  if(!haveSample_||s.nowMs<=lastMs_||s.bytesReceived<lastBytes_||s.receivedFrames<lastFrames_){
   haveSample_=true;lastMs_=s.nowMs;lastBytes_=s.bytesReceived;lastFrames_=s.receivedFrames;healthy_=goodput_=0;reason_="session_start";
   int request=applied_!=target_&&requestDue(s.nowMs)?target_:0;if(request){lastRequest_=s.nowMs;haveRequest_=true;}return result(request,lower);
  }
  uint64_t elapsed=s.nowMs-lastMs_;if(elapsed<800)return result(0,lower);
  uint64_t deltaBytes=s.bytesReceived-lastBytes_,deltaFrames=s.receivedFrames-lastFrames_;
  lastMs_=s.nowMs;lastBytes_=s.bytesReceived;lastFrames_=s.receivedFrames;
  if(elapsed>3000){healthy_=goodput_=0;reason_="sampling_gap";return result(0,lower);}
  double current=double(deltaBytes)*8/double(elapsed);goodput_=goodput_==0?current:goodput_*0.7+current*0.3;
  // Offset uncertainty does not erase multi-second tails. A conservative
  // absolute lower bound and a within-window spread provide separate evidence.
  // P95-P50 cancels the common clock offset; the native owner clears this
  // window on clock refresh. We still require a current valid clock/window.
  const double spread=ageValid?std::max(0.0,s.ageP95ms-s.ageP50ms):0;
  const bool spreadCongested=spread>600,spreadSevere=spread>1200;
  bool congested=ageValid&&(lower>std::max(350.0,s.ageP50ms+250)||spreadCongested);
  bool severe=ageValid&&(lower>std::max(750.0,s.ageP50ms+600)||spreadSevere);
  int request=0;
  if(congested){
   healthy_=0;if(requestDue(s.nowMs)){
    int next=int(std::floor(target_*(severe?0.55:0.75)/250))*250;
    if(deltaFrames>=4&&goodput_>=500)next=std::min(next,int(std::floor(goodput_*0.8/250))*250);
    next=std::clamp(next,1500,4000);if(next<target_){target_=next;lastDecrease_=s.nowMs;request=next;reason_=s.uncertaintyMs>150?(severe?"severe_network_age_spread":"network_age_spread"):(severe?"severe_network_age":"network_age");}
   }
  }else{
   bool healthy=ageValid&&s.uncertaintyMs<=150&&lower<std::max(220.0,s.ageP50ms+120)&&deltaFrames>=4&&current>=target_*0.65&&applied_==target_;
   healthy_=healthy?healthy_+double(elapsed)/1000:0;
   if(healthy_>=8&&s.nowMs>=lastDecrease_&&s.nowMs-lastDecrease_>=10000&&requestDue(s.nowMs)&&target_<4000){
    target_=std::min(4000,target_+250);request=target_;healthy_=0;reason_="slow_recovery";
   }
  }
  // Static desktop/low FPS alone never means low path capacity. The control
  // owner requests only 1.5...4Mbps and requires explicit server RATE_ACK.
  if(!request&&applied_!=target_&&requestDue(s.nowMs,3000)){request=target_;reason_="await_rate_ack_retry";}
  if(request){lastRequest_=s.nowMs;haveRequest_=true;}return result(request,lower);
 }
};
inline bool HasRateV2(const std::string&fields){std::istringstream in(fields);std::string t;while(in>>t)if(t=="rate-v2")return true;return false;}
inline bool ParseRateReply(const std::string&line,bool&success,int&kbps){
 size_t p;if(line.rfind("RATE_ACK ",0)==0){success=true;p=9;}else if(line.rfind("RATE_ERR ",0)==0){success=false;p=9;}else return false;
 if(line.size()<=p||line.size()-p>5)return false;int value=0;
 for(size_t i=p;i<line.size();++i){char c=line[i];if(c<'0'||c>'9')return false;value=value*10+c-'0';}
 if(value<1500||value>80000)return false;kbps=value;return true;
}
// The SAME unique TLS owner demultiplexes bounded whole lines before feeding
// TIME lines to ClockRefresh. Partial/coalesced RATE and TIME cannot corrupt it.
class ControlReplyMux {
 std::string line_;bool discarding_=false;
public:
 uint64_t overlong=0;
 void Reset(){line_.clear();discarding_=false;overlong=0;}
 template<class RateCallback,class ClockCallback>void Consume(const char*data,size_t size,RateCallback rate,ClockCallback clock){
  for(size_t i=0;i<size;++i){char c=data[i];
   if(discarding_){if(c=='\n')discarding_=false;continue;}
   if(c=='\n'){bool ok=false;int kbps=0;if(ParseRateReply(line_,ok,kbps))rate(ok,kbps);else{line_+='\n';clock(line_);}line_.clear();continue;}
   if(line_.size()>=255){line_.clear();discarding_=true;++overlong;continue;}line_+=c;
  }
 }
};
} // namespace edgelinkwan
