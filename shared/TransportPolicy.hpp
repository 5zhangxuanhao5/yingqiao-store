#pragma once
#include <string>
#include <vector>
#include <algorithm>
namespace yingqiao {
struct Path {std::string id,peer;bool authenticated=false,wired=false,consumerSupported=false;double measuredAt=0,p95ms=0,goodputMbps=0;};
// Policy shared by future USB network adapters. A cable's presence never proves a usable or fast media channel.
inline std::string PreferredPath(const std::vector<Path>&paths,const std::string&pairedPeer,const std::string&active,double now,double lastSwitch,bool dragging,bool activeAlive=true){
 std::vector<Path>ready;for(auto&p:paths)if((activeAlive||p.id!=active)&&p.authenticated&&p.consumerSupported&&p.peer==pairedPeer&&p.measuredAt<=now&&now-p.measuredAt<=10&&p.p95ms>0&&p.goodputMbps>0)ready.push_back(p);
 if(ready.empty())return "";
 auto score=[](const Path&p){return p.p95ms+200.0/std::max(1.0,p.goodputMbps);};std::sort(ready.begin(),ready.end(),[&](auto&a,auto&b){return score(a)<score(b);});auto current=std::find_if(ready.begin(),ready.end(),[&](auto&p){return p.id==active;});
 if(current==ready.end())return ready.front().id;
 if(dragging||now-lastSwitch<5)return active;
 const auto&best=ready.front();if(best.id==active)return active;
 return score(best)<score(*current)*0.8 ? best.id:active;
}
// A single short probe can prefer the other route under transient load.
// Improvement switches need three distinct, fresh paired measurements. Failure
// recovery bypasses this debounce; it never waits for a dead active route.
struct StablePathChoice {
 std::string active,candidate;double stamp=-1;unsigned wins=0;
 void reset(){active.clear();candidate.clear();stamp=-1;wins=0;}
 std::string choose(const std::vector<Path>&paths,const std::string&peer,const std::string&current,double now,double lastSwitch,bool dragging,bool alive){
  auto next=PreferredPath(paths,peer,current,now,lastSwitch,dragging,alive);
  if(!alive||next.empty()||next==current){reset();return next;}
  const auto a=std::find_if(paths.begin(),paths.end(),[&](auto&p){return p.id==current&&p.authenticated&&p.consumerSupported&&p.peer==peer&&now-p.measuredAt<=10;});
  const auto b=std::find_if(paths.begin(),paths.end(),[&](auto&p){return p.id==next;});
  if(a==paths.end()||b==paths.end()){reset();return next;}
  if(active!=current||candidate!=next){reset();active=current;candidate=next;}
  const double measured=std::min(a->measuredAt,b->measuredAt);
  if(measured>stamp){stamp=measured;if(wins<3)++wins;}
  return wins>=3?next:current;
 }
};
struct DisplayLease {unsigned generation=0;double deadline=0;bool retained=false;std::string pairedPeer;
 void retain(const std::string&peer,double now){++generation;pairedPeer=peer;deadline=now+10;retained=true;}
 bool adopt(const std::string&peer,double now){if(!retained||peer!=pairedPeer||now>deadline)return false;retained=false;return true;}
 void explicitEnd(){++generation;retained=false;deadline=0;pairedPeer.clear();}
};
}
