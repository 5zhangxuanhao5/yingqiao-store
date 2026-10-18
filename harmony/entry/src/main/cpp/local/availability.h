#pragma once
#ifdef EDGELINK_AVAILABILITY_TEST
#include <functional>
#include <string>
#include <cstdint>
namespace edgelinkavailability {
struct TestEvent { std::string type, route, requestId; };
bool ConfigureForTest(const std::string& host,int port,const std::string& token,const std::string& certificate,std::function<void(TestEvent)> callback);
void StateForTest(const std::string& state);
bool ReplyForTest(const std::string& request,bool accepted);
void StopForTest();
void RefreshForTest();
std::string StatusForTest();
}
#else
#include <napi/native_api.h>
void RegisterAvailability(napi_env env,napi_value exports);
#endif
