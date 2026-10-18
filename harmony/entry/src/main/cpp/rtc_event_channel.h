#pragma once
#include <napi/native_api.h>
#include <cstdint>
#include <string>
uint64_t BeginRtcOwner();
void EndRtcOwner(uint64_t epoch);
bool PublishRtcEvent(uint64_t epoch,const std::string&session,const std::string&kind,const std::string&body);
void RegisterRtcEventAPI(napi_env env,napi_value exports);
std::string RtcEventStats();
