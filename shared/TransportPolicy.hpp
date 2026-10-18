#pragma once
#include <string>
#include <vector>
#include <algorithm>
namespace yingqiao {
struct Path {std::string id,peer;bool authenticated=false,wired=false,consumerSupported=false;double measuredAt=0,p95ms=0,goodputMbps=0;};
// Policy shared by future USB network adapters. A cable's presence never proves a usable or fast media channel.
inline std::string PreferredPath(const std::vector<Path>&paths,const std::string&pairedPeer,const std::string&active,double now,double lastSwitch,bool dragging){
 std::vector<Path>ready;for(auto&p:paths)if(p.authenticated&&p.consumerSupported&&p.peer==pairedPeer&&p.measuredAt<=now&&now-p.measuredAt<=10&&p.p95ms>0&&p.goodputMbps>0)ready.push_back(p);
 if(ready.empty())return "";
 auto score=[](const Path&p){return p.p95ms+200.0/std::max(1.0,p.goodputMbps);};std::sort(ready.begin(),ready.end(),[&](auto&a,auto&b){return score(a)<score(b);});auto current=std::find_if(ready.begin(),ready.end(),[&](auto&p){return p.id==active;});
 if(current==ready.end())return ready.front().id;
 if(dragging||now-lastSwitch<5)return active;
 const auto&best=ready.front();if(best.id==active)return active;
 return score(best)<score(*current)*0.8 ? best.id:active;
}
struct DisplayLease {unsigned generation=0;double deadline=0;bool retained=false;std::string pairedPeer;
 void retain(const std::string&peer,double now){++generation;pairedPeer=peer;deadline=now+10;retained=true;}
 bool adopt(const std::string&peer,double now){if(!retained||peer!=pairedPeer||now>deadline)return false;retained=false;return true;}
 void explicitEnd(){++generation;retained=false;deadline=0;pairedPeer.clear();}
};
}
