#include "../../../../../shared/DisplayProfile.hpp"
#include <napi/native_api.h>
#include "local/availability.h"
#include <multimedia/player_framework/native_avcapability.h>
#include <hilog/log.h>
#include <sstream>
static napi_value Probe(napi_env env,napi_callback_info info) {
 std::ostringstream out;out << "{\"codecs\":[";
 const char *mimes[]={"video/avc","video/hevc"};
 int sizes[][2]={{1920,1280},{2400,1600},{2880,1920},{3120,2080}};
 for(int i=0;i<2;i++) {
  if(i)out<<",";
  OH_AVCapability *cap=OH_AVCodec_GetCapabilityByCategory(mimes[i],false,HARDWARE);
  out<<"{\"mime\":\""<<mimes[i]<<"\",\"hardware\":"<<(cap?"true":"false");
  if(cap) {
   out<<",\"name\":\""<<OH_AVCapability_GetName(cap)<<"\",\"lowLatency\":"<<(OH_AVCapability_IsFeatureSupported(cap,VIDEO_LOW_LATENCY)?"true":"false")<<",\"sizes\":[";
   for(int s=0;s<4;s++) {
    if(s)out<<",";
    OH_AVRange range={0};auto error=OH_AVCapability_GetVideoFrameRateRangeForSize(cap,sizes[s][0],sizes[s][1],&range);
    out<<"{\"width\":"<<sizes[s][0]<<",\"height\":"<<sizes[s][1]<<",\"queryStatus\":"<<error<<",\"maxFps\":"<<range.maxVal<<",\"supports60\":"<<(OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap,sizes[s][0],sizes[s][1],60)?"true":"false")<<",\"supports120\":"<<(OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap,sizes[s][0],sizes[s][1],120)?"true":"false")<<"}";
   }
   out<<"]";
  }
  out<<"}";
 }
 out<<"]}";auto s=out.str();OH_LOG_Print(LOG_APP,LOG_INFO,0xED01,"EdgeLinkLab","CAPABILITIES %{public}s",s.c_str());
 napi_value result;napi_create_string_utf8(env,s.c_str(),s.size(),&result);return result;
}
static napi_value StoreProfile(napi_env env,napi_callback_info info){size_t n=4;napi_value v[4];napi_get_cb_info(env,info,&n,v,nullptr,nullptr);int32_t w=0,h=0,refresh=60;if(n<3)return nullptr;if(n==4)napi_get_value_int32(env,v[3],&refresh);napi_get_value_int32(env,v[0],&w);napi_get_value_int32(env,v[1],&h);char codec[32]={};size_t copied=0;napi_get_value_string_utf8(env,v[2],codec,sizeof(codec),&copied);
 const std::string allowed(codec);auto selected=yingqiao::ChooseDisplayProfile(w,h,refresh,allowed.find("hevc")!=std::string::npos?"hevc":"avc",[allowed](const std::string&codec,int w,int h,int fps){if(allowed.find(codec)==std::string::npos)return false;auto cap=OH_AVCodec_GetCapabilityByCategory(codec=="hevc"?"video/hevc":"video/avc",false,HARDWARE);return cap&&OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap,w,h,fps);});std::ostringstream out;out<<"{\"supported\":"<<(selected.supported?"true":"false")<<",\"width\":"<<selected.width<<",\"height\":"<<selected.height<<",\"fps\":"<<selected.fps<<",\"codec\":\""<<selected.codec<<"\"}";napi_value result;napi_create_string_utf8(env,out.str().c_str(),NAPI_AUTO_LENGTH,&result);return result;}

void RegisterClient(napi_env env,napi_value exports);
static napi_value Init(napi_env env,napi_value exports) {
 napi_property_descriptor d[]={ {"probe",nullptr,Probe,nullptr,nullptr,nullptr,napi_default,nullptr},{"storeProfile",nullptr,StoreProfile,nullptr,nullptr,nullptr,napi_default,nullptr} };
 napi_define_properties(env,exports,1,d);RegisterClient(env,exports);RegisterAvailability(env,exports);return exports;
}
static napi_module module={1,0,nullptr,Init,"edgelink",nullptr,{0}};
extern "C" __attribute__((constructor)) void Register() {napi_module_register(&module);}
