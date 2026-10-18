#include "../harmony/entry/src/main/cpp/route_selector.h"
#include <cassert>
#include <iostream>
using namespace edgelinkroute;
Sample route(Kind kind,const char* endpoint,double rtt,double goodput){Sample s;s.kind=kind;s.endpoint=endpoint;s.epoch=1;s.verifiedAtMs=1000;s.measuredAtMs=1000;s.authenticated=true;s.reachable=true;s.localProof=true;s.probes=5;s.rttMedianMs=rtt;s.rttP95Ms=rtt+1;s.goodputMbps=goodput;return s;}
int main(){
 Selector selector;selector.record(route(Kind::USB,"127.0.0.1",40,20));selector.record(route(Kind::LAN,"192.168.1.2",3,400));
 auto p=selector.start(Mode::Extend,1100);assert(p.immediate&&p.immediate->kind==Kind::LAN);
 selector.record(route(Kind::USB,"127.0.0.1",1,1000));p=selector.start(Mode::Extend,1200);assert(p.immediate&&p.immediate->kind==Kind::USB);
 selector.failed(Kind::USB,1);p=selector.start(Mode::Extend,1300);assert(p.immediate&&p.immediate->kind==Kind::LAN);
 auto wan=route(Kind::Internet,"8.8.8.8",0.1,10000);selector.record(wan);assert(selector.start(Mode::Extend,1300).immediate->kind==Kind::LAN);
 assert(!selector.start(Mode::Extend,40000).immediate);std::cout<<"PASS measured local route selection, failed/stale exclusion, no WAN extension\n";
}
