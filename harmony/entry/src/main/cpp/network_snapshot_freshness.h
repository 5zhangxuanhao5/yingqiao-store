#pragma once
#include <algorithm>
#include <cstdint>
#include <string>

// Node owns the mutex. No sockets, probing, wall-clock trust or new timers.
class NetworkSnapshotFreshness {
public:
 uint64_t configure(const std::string& signature){
  if(signature!=signature_||generation_==0){signature_=signature;generation_++;configured_=false;sampleGeneration_=0;}
  return generation_;
 }
 void configured(uint64_t generation){if(generation==generation_)configured_=true;}
 void invalidated(uint64_t generation){if(generation==generation_){configured_=false;sampleGeneration_=0;}}
 uint64_t observationGeneration()const{return configured_?generation_:0;}
 bool observed(uint64_t generation,uint64_t steadyNs,int64_t wallMs){
  if(!generation||!configured_||generation!=generation_||!steadyNs||wallMs<=0)return false;
  sampleGeneration_=generation;steadyNs_=steadyNs;wallMs_=wallMs;sequence_++;return true;
 }
 bool ready(bool runtimeReady)const{return runtimeReady&&configured_&&sampleGeneration_==generation_&&sampleGeneration_!=0;}
 double ageMs(bool runtimeReady,uint64_t steadyNs,int64_t wallMs)const{
  if(!ready(runtimeReady)||steadyNs<steadyNs_||wallMs<wallMs_)return -1;
  return std::max(double(steadyNs-steadyNs_)/1e6,double(wallMs-wallMs_));
 }
 uint64_t sequence()const{return sequence_;}
private:
 std::string signature_;uint64_t generation_=0,sampleGeneration_=0,steadyNs_=0,sequence_=0;int64_t wallMs_=0;bool configured_=false;
};
