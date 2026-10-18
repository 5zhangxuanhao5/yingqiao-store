#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// This policy has no sockets or timers. The caller owns authenticated probes,
// cancellation, and session boundaries. RTT is a route comparison, not a claim
// about glass-to-glass latency. Never use IP subnet strings as LAN proof.
namespace edgelinkroute {
enum class Kind { USB, LAN, Internet };
enum class Mode { Extend, Remote };
struct Sample {
 Kind kind=Kind::LAN;
 std::string endpoint;
 uint64_t epoch=0,verifiedAtMs=0,measuredAtMs=0;
 bool authenticated=false,reachable=false;
 unsigned probes=0;
 double rttMedianMs=0,rttP95Ms=0,goodputMbps=0;
 // Goodput must be measured on this authenticated local path, never guessed
 // from Wi-Fi link speed. Internet paths do not receive background bulk probes.
 bool localProof=false;
};
struct Choice {
 Kind kind;
 std::string endpoint;
 uint64_t epoch;
 double scoreMs;
 bool hasGoodput;
 bool hasRTT;
};
struct StartPlan {
 std::optional<Choice> immediate;
 std::vector<Kind> backgroundProbes;
 bool raceIfUnknown=false;
};
class Selector {
public:
 static constexpr uint64_t FreshVerificationMs=30000;
 static constexpr uint64_t FreshMeasurementMs=60000;
 explicit Selector(double bitrateMbps=40,double fps=60):bitrateMbps_(std::isfinite(bitrateMbps)&&bitrateMbps>=8&&bitrateMbps<=80?bitrateMbps:40),fps_(std::isfinite(fps)&&fps>=30&&fps<=120?fps:60){}
 void record(Sample sample){
  if(sample.endpoint.empty()||sample.endpoint.size()>255||!sample.epoch)return;
  auto it=std::find_if(samples_.begin(),samples_.end(),[&](const auto&v){return v.kind==sample.kind;});
  if(it!=samples_.end()){
   if(sample.epoch<it->epoch)return; // Late probe from a disconnected route.
   if(sample.epoch==it->epoch&&sample.verifiedAtMs<it->verifiedAtMs)return;
   *it=std::move(sample);
  }else samples_.push_back(std::move(sample));
 }
 void failed(Kind kind,uint64_t epoch){
  for(auto&v:samples_)if(v.kind==kind&&v.epoch==epoch){v.reachable=false;v.authenticated=false;}
 }
 StartPlan start(Mode mode,uint64_t now)const{
  StartPlan p;
  std::optional<Choice> usb;
  for(const auto&v:samples_){
   if(!eligible(v,mode,now))continue;
   auto candidate=choice(v,now);
   if(v.kind==Kind::USB)usb=candidate;
   if(!p.immediate||candidate.scoreMs<p.immediate->scoreMs)p.immediate=std::move(candidate);
  }
  // Available paired USB wins until an end-to-end video trial proves a better
  // path. Tiny startup probes are noisy and cannot justify silently using Wi-Fi.
  if(mode==Mode::Extend&&usb)p.immediate=usb;
  // No synchronously waiting for a better measurement if a verified path is
  // available. Both local probes are independently cancellable background work.
  p.backgroundProbes={Kind::USB,Kind::LAN};
  if(mode==Mode::Remote)p.backgroundProbes.push_back(Kind::Internet);
  p.raceIfUnknown=!p.immediate.has_value();
  return p;
 }
 std::optional<Choice> forRunning(Mode mode,uint64_t now,const Choice&current)const{
  const auto it=std::find_if(samples_.begin(),samples_.end(),[&](const auto&v){return v.kind==current.kind&&v.epoch==current.epoch&&v.endpoint==current.endpoint;});
  // A successful session must not be bounced for a microbenchmark. Media
  // migration requires a separately negotiated, tested protocol. Refresh age
  // does not interrupt already flowing video; explicit route failure does.
  if(it!=samples_.end()&&it->authenticated&&it->reachable&&allowed(*it,mode))return current;
  return start(mode,now).immediate;
 }
 // Two available paths alone are not a dual-channel implementation. Keep this
 // false until an actual negotiated scheduler and controlled stream comparison
 // exist. This prevents an optimistic UI from silently enabling TCP striping.
 static constexpr bool dualMediaSupported(){return false;}
private:
 static bool elapsed(uint64_t now,uint64_t past,uint64_t limit){return now>=past&&now-past<=limit;}
 static bool allowed(const Sample&s,Mode mode){
  if(s.kind==Kind::Internet)return mode==Mode::Remote;
  return s.localProof;
 }
 static bool eligible(const Sample&s,Mode mode,uint64_t now){
  return allowed(s,mode)&&s.authenticated&&s.reachable&&elapsed(now,s.verifiedAtMs,FreshVerificationMs)&&
   (s.probes<3 || (std::isfinite(s.rttMedianMs)&&std::isfinite(s.rttP95Ms)&&s.rttMedianMs>0&&s.rttP95Ms>=s.rttMedianMs&&s.rttP95Ms<=10000));
 }
 Choice choice(const Sample&s,uint64_t now)const{
  const bool measured=elapsed(now,s.measuredAtMs,FreshMeasurementMs)&&std::isfinite(s.goodputMbps)&&s.goodputMbps>0&&s.kind!=Kind::Internet;
  const bool hasRTT=s.probes>=3&&elapsed(now,s.measuredAtMs,FreshMeasurementMs);
  const double jitter=hasRTT?s.rttP95Ms-s.rttMedianMs:0;
  // One frame's wire time at the requested budget, plus tail RTT and jitter.
  // This is a conservative policy score, not measured video/render latency.
  double score=hasRTT?s.rttP95Ms+jitter:1000;
  if(measured){score+=1000*bitrateMbps_/(fps_*s.goodputMbps);if(s.goodputMbps<bitrateMbps_*1.25)score+=50*(bitrateMbps_*1.25/s.goodputMbps-1);}
  else score+=25; // Unknown throughput should not beat a well-measured route.
  return {s.kind,s.endpoint,s.epoch,score,measured,hasRTT};
 }
 double bitrateMbps_,fps_;
 std::vector<Sample> samples_;
};
}
