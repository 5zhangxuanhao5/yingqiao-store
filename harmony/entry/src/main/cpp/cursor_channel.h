#pragma once
#include <napi/native_api.h>
#include <cstdint>
#include <string>

struct CursorChannelSample {
    uint64_t cursorSequence = 0;
    uint64_t edgeInputAck = 0;
    uint32_t sourceOwner = 0;
    uint32_t visible = 0;
    uint64_t sampleTimeNs = 0;
    double x = 0;
    double y = 0;
};

// Each client run owns a distinct epoch. An old run cannot end or publish to a
// later session, including after a callback has been rebound in the same env.
uint64_t BeginCursorSession();
void EndCursorSession(uint64_t epoch);
void PublishCursorSample(uint64_t epoch, const CursorChannelSample& sample);
void RegisterCursorChannelAPI(napi_env env, napi_value exports);
std::string CursorChannelStats();
