#pragma once
#include <cstdint>

namespace edgelink::audio {
// Preserve the deployed safety deadlines while making their distinct failure
// reasons observable. A future idle policy needs authenticated server liveness.
class AudioReadLiveness {
public:
 explicit AudioReadLiveness(uint64_t now):lastReceive_(now){}
 void beginRecord(){}
 void received(uint64_t now){lastReceive_=now;}
 const char* failure(uint64_t now,bool playback,int32_t error,uint64_t lastRender)const{
  if(!playback||error)return "audio_renderer_unavailable";
  if(now<lastRender||now-lastRender>1'000'000'000ULL)return "audio_renderer_callback_timeout";
  if(now<lastReceive_||now-lastReceive_>8'000'000'000ULL)return "audio_no_bytes_timeout";
  return nullptr;
 }
private:
 uint64_t lastReceive_=0;
};
}
