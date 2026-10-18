#ifdef _MSC_VER
#define __attribute__(value)
#endif
#include "../harmony/entry/src/main/cpp/probe.cpp"
#include <cassert>
#include <iostream>
void RegisterClient(napi_env,napi_value){}
void RegisterAvailability(napi_env,napi_value){}
int main(){
 Init(nullptr,nullptr);
 assert(FixtureExports().count("probe")==1);
 assert(FixtureExports().count("storeProfile")==1);
 FixtureValue w{3120,""},h{2080,""},codec{0,"avc,hevc"},refresh{120,""};
 std::vector<napi_value> args{&w,&h,&codec,&refresh};
 auto profile=FixtureExports().at("storeProfile")(nullptr,&args)->text;
 assert(profile.find("\"supported\":true")!=std::string::npos);
 assert(profile.find("\"width\":2400")!=std::string::npos);
 assert(profile.find("\"fps\":60")!=std::string::npos);
 assert(profile.find("\"codec\":\"hevc\"")!=std::string::npos);
 codec.text="avc";
 profile=FixtureExports().at("storeProfile")(nullptr,&args)->text;
 assert(profile.find("\"width\":1920")!=std::string::npos);
 assert(profile.find("\"fps\":30")!=std::string::npos);
 assert(profile.find("\"codec\":\"avc\"")!=std::string::npos);
 codec.text="invalid";
 profile=FixtureExports().at("storeProfile")(nullptr,&args)->text;
 assert(profile.find("\"supported\":false")!=std::string::npos);
 std::cout<<"PASS actual native module exports and profile callback with synthetic hardware capabilities; no real decoder or device tested.\n";
}
