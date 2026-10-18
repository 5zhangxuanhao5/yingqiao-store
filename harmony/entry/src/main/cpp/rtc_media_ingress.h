#pragma once
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>
class RtcMediaIngress {
public:
 using Bytes=std::vector<uint8_t>;using Consumer=std::function<void(uint64_t,const Bytes&,uint64_t)>;using Recovery=std::function<void(uint64_t)>;
 struct Counts{uint64_t accepted=0,expired=0,rejected=0,occupied=0,cursorCoalesced=0;};
 ~RtcMediaIngress(){stop();}
 void start(uint64_t epoch,uint32_t sid,Consumer consumer,Recovery recovery){stop();std::lock_guard<std::mutex>g(m_);epoch_=epoch;sid_=sid;consumer_=std::move(consumer);recovery_=std::move(recovery);counts_={};active_=true;worker_=std::thread([this]{run();});}
 bool submit(uint64_t epoch,const uint8_t*p,size_t n,uint64_t at){
  if(!p||n<44||n>2*1024*1024)return reject();uint32_t total=uint32_t(be(p+20,4));bool cursor=p[25]==2;
  if(memcmp(p,"EDL1",4)||be(p+16,2)||be(p+18,2)!=1||total!=n-28||p[26]||p[27]||!be(p+8,8)||(cursor?(n!=84||p[24]||!(p[8]&128)):(p[25]||(p[24]&~3)||(p[8]&128))))return reject();
  std::lock_guard<std::mutex>g(m_);if(!active_||epoch!=epoch_||be(p+4,4)!=sid_){++counts_.rejected;return false;}auto&slot=cursor?cursor_:video_;if(!slot.empty()){if(cursor)++counts_.cursorCoalesced;else{++counts_.occupied;return false;}}slot.assign(p,p+n);(cursor?cursorAt_:videoAt_)=at;++counts_.accepted;changed_.notify_one();return true;
 }
 void stop(){{std::lock_guard<std::mutex>g(m_);active_=false;video_.clear();cursor_.clear();changed_.notify_all();}if(worker_.joinable())worker_.join();std::lock_guard<std::mutex>g(m_);consumer_={};recovery_={};}
 Counts counts(){std::lock_guard<std::mutex>g(m_);return counts_;}
private:
 static uint64_t be(const uint8_t*p,size_t n){uint64_t v=0;while(n--)v=v*256+*p++;return v;}static uint64_t now(){return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
 bool reject(){std::lock_guard<std::mutex>g(m_);++counts_.rejected;return false;}
 void run(){for(;;){Bytes record;uint64_t epoch=0,at=0;Consumer consume;Recovery recover;
  {std::unique_lock<std::mutex>g(m_);changed_.wait(g,[this]{return !active_||!video_.empty()||!cursor_.empty();});if(!active_)return;bool cursor=video_.empty();record.swap(cursor?cursor_:video_);at=cursor?cursorAt_:videoAt_;epoch=epoch_;consume=consumer_;recover=recovery_;}
  auto time=now();if(time<at||time-at>100000000ULL){{std::lock_guard<std::mutex>g(m_);++counts_.expired;}if(record[25]==0&&recover)recover(epoch);continue;}if(consume)consume(epoch,record,at);
 }}
 std::mutex m_;std::condition_variable changed_;std::thread worker_;bool active_=false;uint64_t epoch_=0,videoAt_=0,cursorAt_=0;uint32_t sid_=0;Bytes video_,cursor_;Consumer consumer_;Recovery recovery_;Counts counts_;
};
