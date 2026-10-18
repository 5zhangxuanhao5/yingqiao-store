#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <mutex>

namespace edgelink::audio {
// Fixed 30 ms PCM queue. Network callers may take the mutex; real-time audio
// callbacks only try_lock, never wait, allocate, or perform network operations.
// All methods reject retired epochs; Start/End are serialized by their owner.
class PCMQueue {
public:
 static constexpr size_t kPacketBytes = 1920; // 48 kHz stereo S16, 10 ms.
 static constexpr size_t kSlots = 3;
 struct Stats { uint64_t enqueued=0, dropped=0, stale=0, underflow=0, contention=0; };
 void begin(uint64_t epoch) {
  std::lock_guard<std::mutex> guard(lock_);
  epoch_=epoch; active_=epoch!=0; head_=count_=offset_=0; stats_={};
  for(auto&slot:slots_)slot={};
 }
 void end() {
  std::lock_guard<std::mutex> guard(lock_);
  active_=false;epoch_=0;head_=count_=offset_=0;
  for(auto&slot:slots_)slot={};
 }
 bool push(uint64_t epoch,const void*bytes,size_t size,uint64_t receivedNs,bool realtime=false) {
  if(!bytes||!size||size>kPacketBytes||size%2)return false;
  std::unique_lock<std::mutex> guard(lock_,std::defer_lock);
  if(realtime){if(!guard.try_lock())return false;}else{guard.lock();}
  if(!active_||epoch!=epoch_){stats_.stale++;return false;}
  if(count_==kSlots){head_=(head_+1)%kSlots;count_--;offset_=0;stats_.dropped++;}
  auto&slot=slots_[(head_+count_)%kSlots];
  std::memcpy(slot.bytes.data(),bytes,size);slot.size=size;slot.receivedNs=receivedNs;
  count_++;stats_.enqueued++;return true;
 }
 // Renderer output is always filled, with silence on loss. No old session data
 // can reach a new stream. Packets delayed >30 ms locally are discarded.
 size_t render(uint64_t epoch,void*out,size_t wanted,uint64_t nowNs) {
  if(!out||!wanted)return 0;
  std::memset(out,0,wanted);
  std::unique_lock<std::mutex> guard(lock_,std::try_to_lock);
  if(!guard.owns_lock())return 0;
  if(!active_||epoch!=epoch_)return 0;
  size_t filled=0;
  while(count_&&filled<wanted){
   auto&slot=slots_[head_];
   if(nowNs>=slot.receivedNs&&nowNs-slot.receivedNs>30'000'000ULL){
    head_=(head_+1)%kSlots;count_--;offset_=0;stats_.dropped++;continue;
   }
   const auto copied=std::min(wanted-filled,slot.size-offset_);
   std::memcpy(static_cast<uint8_t*>(out)+filled,slot.bytes.data()+offset_,copied);
   offset_+=copied;filled+=copied;
   if(offset_==slot.size){head_=(head_+1)%kSlots;count_--;offset_=0;}
  }
  if(filled<wanted)stats_.underflow++;
  return filled;
 }
 // A normal-priority worker drains captured microphone data. It must not call
 // this concurrently from more than one producer/consumer pipeline.
 size_t pop(uint64_t epoch,void*out,size_t capacity,uint64_t&capturedNs) {
  std::lock_guard<std::mutex>guard(lock_);
  if(!active_||epoch!=epoch_||!count_||!out)return 0;
  auto&slot=slots_[head_];if(capacity<slot.size)return 0;
  const auto size=slot.size;std::memcpy(out,slot.bytes.data(),size);capturedNs=slot.receivedNs;
  slot={};head_=(head_+1)%kSlots;count_--;offset_=0;return size;
 }
 Stats stats()const{std::lock_guard<std::mutex>guard(lock_);return stats_;}
private:
 struct Slot {std::array<uint8_t,kPacketBytes>bytes{};size_t size=0;uint64_t receivedNs=0;};
 mutable std::mutex lock_;std::array<Slot,kSlots>slots_{};uint64_t epoch_=0;
 bool active_=false;size_t head_=0,count_=0,offset_=0;Stats stats_{};
};
}
