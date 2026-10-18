#pragma once
#include "route_selector.h"
#include <arpa/inet.h>
#include <cmath>
#include <optional>
#include <string>
#include <vector>
namespace edgelinksplit {
enum class Role {Control,Video};
struct Endpoint {std::string host,route;int port=0;};
inline bool PrivateNumericIPv4(const std::string& host){in_addr a{};if(inet_pton(AF_INET,host.c_str(),&a)!=1)return false;const auto x=ntohl(a.s_addr);return (x>>24)==10||(x>>20)==0xac1||(x>>16)==0xc0a8||(x>>16)==0xa9fe;}
inline std::optional<Endpoint> LocalEndpoint(const std::string& host,int port){
 if(host=="127.0.0.1"&&port==48561)return Endpoint{host,"usb",port};
 if(PrivateNumericIPv4(host)&&port==48563)return Endpoint{host,"lan",port};
 return {};
}
inline bool ValidConfiguration(const std::string& mode,const std::string& transport,
                               const Endpoint& control,const Endpoint& video){
 const auto c=LocalEndpoint(control.host,control.port),v=LocalEndpoint(video.host,video.port);
 return (mode=="extend"||mode=="remote"||mode=="bench")&&transport=="tcp"&&
  c&&v&&c->route==control.route&&v->route==video.route&&control.route!=video.route;
}
inline Endpoint ForRole(Role role,bool requested,const Endpoint& control,const Endpoint& video){return requested&&role==Role::Video?video:control;}
struct Proposal {
 edgelinkroute::Kind control,video;
 double controlTailMs=0,videoScoreMs=0,bestSingleScoreMs=0;
 // A proposal is a controlled experiment. No amount of tiny RTT/burst results
 // can turn this on automatically without equivalent full-stream evidence.
 bool automaticAllowed=false;
};
inline std::optional<Proposal> Propose(const std::vector<edgelinkroute::Sample>& samples,uint64_t now,double bitrateMbps=40,double fps=60){
 edgelinkroute::Selector media(bitrateMbps,fps);std::optional<edgelinkroute::Sample> input;
 std::vector<edgelinkroute::Sample> usable;
 for(const auto& s:samples){
  if(s.kind==edgelinkroute::Kind::Internet||!s.authenticated||!s.reachable||!s.localProof||!s.epoch||
   now<s.verifiedAtMs||now-s.verifiedAtMs>30000||now<s.measuredAtMs||now-s.measuredAtMs>60000||s.probes<3||
   !std::isfinite(s.rttMedianMs)||!std::isfinite(s.rttP95Ms)||s.rttMedianMs<=0||s.rttP95Ms<s.rttMedianMs||s.rttP95Ms>10000||
   !std::isfinite(s.goodputMbps)||s.goodputMbps<=0)continue;
  usable.push_back(s);media.record(s);
  const double cost=s.rttP95Ms+(s.rttP95Ms-s.rttMedianMs);
  if(!input||cost<input->rttP95Ms+(input->rttP95Ms-input->rttMedianMs))input=s;
 }
 const auto choice=media.start(edgelinkroute::Mode::Extend,now).immediate;
 if(!input||!choice||input->kind==choice->kind||usable.size()<2)return {};
 // The media policy's score includes tail RTT, jitter and estimated per-frame
 // wire time. This avoids choosing a high-throughput path with enormous RTT.
 double controlSingle=0;
 for(const auto& s:usable)if(s.kind==input->kind){edgelinkroute::Selector one(bitrateMbps,fps);one.record(s);auto selected=one.start(edgelinkroute::Mode::Extend,now).immediate;if(selected)controlSingle=selected->scoreMs;}
 if(controlSingle-choice->scoreMs<1.0)return {}; // Tiny noise is not a trial justification.
 return Proposal{input->kind,choice->kind,input->rttP95Ms,choice->scoreMs,choice->scoreMs,false};
}
} // edgelinksplit
