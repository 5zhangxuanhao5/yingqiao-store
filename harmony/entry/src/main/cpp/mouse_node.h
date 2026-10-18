#pragma once

#include <napi/native_api.h>
#include <string>

void RegisterMouseNodeAPI(napi_env env, napi_value exports);
std::string NativeMouseNodeStats();
