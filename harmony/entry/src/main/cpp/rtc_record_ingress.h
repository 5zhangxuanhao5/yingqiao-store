#pragma once
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

// Additive NAPI-worker boundary candidate. submit() copies one complete opaque
// EDL1 record and never calls OpenSSL/decoder or waits for surface buffers.
// Consumer MUST use the current session's native AES-GCM verifier, and perform
// bounded UDP/RTC enqueue (not the existing unbounded TCP queue wait).
class RtcRecordIngress {
 public:
  using Bytes = std::vector<uint8_t>;
  using Consumer = std::function<void(uint64_t, const Bytes &, uint64_t)>;
  using Recovery = std::function<void(uint64_t)>;
  struct Counts { uint64_t accepted=0, expired=0, rejected=0, occupied=0; };
  ~RtcRecordIngress() { stop(); }
  void start(uint64_t epoch, uint32_t sid, Consumer consume, Recovery recover) {
    stop(); std::lock_guard<std::mutex> g(mutex_);
    epoch_=epoch;sid_=sid;consumer_=std::move(consume);recovery_=std::move(recover);
    active_=true; worker_=std::thread([this]{run();});
  }
  bool submit(uint64_t epoch,const uint8_t *record,size_t size,uint64_t receivedNs) {
    if(!record || size<44 || size>2*1024*1024)return reject();
    const uint32_t total=uint32_t(be(record+20,4));
    if(memcmp(record,"EDL1",4) || be(record+16,2)!=0 || be(record+18,2)!=1 || total!=size-28 ||
       record[25]!=0 || record[26]!=0 || record[27]!=0 || (record[24]&~3) || (record[8]&128) || !be(record+8,8))return reject();
    std::lock_guard<std::mutex> g(mutex_);
    if(!active_ || epoch!=epoch_ || be(record+4,4)!=sid_){++counts_.rejected;return false;}
    if(!pending_.empty()){++counts_.occupied;return false;}
    pending_.assign(record,record+size);receivedNs_=receivedNs;++counts_.accepted;changed_.notify_one();return true;
  }
  void stop() {
    {std::lock_guard<std::mutex>g(mutex_);active_=false;pending_.clear();changed_.notify_all();}
    if(worker_.joinable())worker_.join();
    std::lock_guard<std::mutex>g(mutex_);consumer_={};recovery_={};
  }
  Counts counts() { std::lock_guard<std::mutex>g(mutex_);return counts_; }
 private:
  static uint64_t be(const uint8_t*p,size_t n){uint64_t v=0;while(n--)v=v*256+*p++;return v;}
  static uint64_t now(){return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
  bool reject(){std::lock_guard<std::mutex>g(mutex_);++counts_.rejected;return false;}
  void run(){
    for(;;){
      Bytes record;uint64_t epoch=0,received=0;Consumer consume;Recovery recovery;
      {std::unique_lock<std::mutex>g(mutex_);changed_.wait(g,[this]{return !active_||!pending_.empty();});if(!active_)return;
       record.swap(pending_);epoch=epoch_;received=receivedNs_;consume=consumer_;recovery=recovery_;}
      const uint64_t at=now();
      if(at<received || at-received>100000000ULL){
       {std::lock_guard<std::mutex>g(mutex_);++counts_.expired;}if(recovery)recovery(epoch);continue;
      }
      // Session owner rechecks epoch immediately before native decrypt/enqueue.
      if(consume)consume(epoch,record,received);
    }
  }
  std::mutex mutex_;std::condition_variable changed_;std::thread worker_;bool active_=false;
  uint64_t epoch_=0,receivedNs_=0;uint32_t sid_=0;Bytes pending_;Consumer consumer_;Recovery recovery_;Counts counts_;
};
