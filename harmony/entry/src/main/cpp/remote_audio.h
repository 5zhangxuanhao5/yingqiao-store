#pragma once
#include <atomic>
#include <mutex>
#include <memory>
#include <thread>
#include <ohaudio/native_audiostreambuilder.h>
#include "audio_ring.h"

namespace edgelink::audio {
// Candidate-only audio adapter: no sockets, NAPI, permissions, or GUI changes.
// The authenticated media session owns one adapter and its nonzero epoch.
class RemoteAudio {
public:
 RemoteAudio()=default;~RemoteAudio(){retireCallbacks(epoch_.load());if(observationThread_.joinable())observationThread_.join();if(!stop()){(void)rendererContext_.release();(void)capturerContext_.release();}}
 RemoteAudio(const RemoteAudio&)=delete;RemoteAudio&operator=(const RemoteAudio&)=delete;
 bool startPlayback(uint64_t epoch);
 // Isolated recovery primitive. Caller must first retire the failed Mac audio
 // connection; this method does not grant a mute lease or start a microphone.
 bool startPlaybackNormal(uint64_t epoch);
 // Worker only: try-lock lifetime, query provider state without updating it.
 bool inspectPlayback(uint64_t epoch);
 // At most one provider query worker. Read deadlines/UI never await it.
 bool requestPlaybackObservation(uint64_t epoch);
 // Caller must have obtained ohos.permission.MICROPHONE interactively. Never
 // call this automatically on app startup or merely entering remote mode.
 bool startMicrophone(uint64_t epoch);
 bool stopMicrophone();bool stop();
 // Lock-free session retirement; provider cleanup remains on its worker.
 void retireCallbacks(uint64_t sessionEpoch);
 bool enqueuePlayback(uint64_t epoch,const void*pcm,size_t size,uint64_t receivedNs);
 size_t drainMicrophone(uint64_t epoch,void*pcm,size_t capacity,uint64_t&capturedNs);
 struct Status {uint64_t epoch=0;bool playback=false,microphone=false,fastRequested=false,cleanupPending=false;
  OH_AudioStream_LatencyMode latencyMode=AUDIOSTREAM_LATENCY_MODE_NORMAL;int32_t lastError=0;
  int32_t playbackError=0,microphoneError=0;
  uint64_t renderedAuthenticatedFrames=0,renderCallbacks=0,lastRenderNs=0;
  PCMQueue::Stats playbackQueue,microphoneQueue;
  int32_t rendererObservedState=-1,rendererStateResult=-1,rendererInterruptType=-1,rendererInterruptHint=-1,rendererDeviceChangeReason=-1;
  uint32_t rendererInterruptMask=0;uint64_t rendererStateSamples=0,rendererInterruptEvents=0,rendererDeviceChanges=0,rendererStateSampleNs=0;
  bool rendererResourceOwned=false,capturerResourceOwned=false,rendererProbeInFlight=false;uint64_t providerOperations=0,rendererProbeStartedNs=0;};
 Status status()const;
private:
 static uint64_t nowNs();
 static OH_AudioData_Callback_Result write(OH_AudioRenderer*,void*,void*,int32_t);
 static void read(OH_AudioCapturer*,void*,void*,int32_t);
 static void renderError(OH_AudioRenderer*,void*,OH_AudioStream_Result);
 static void renderInterrupt(OH_AudioRenderer*,void*,OH_AudioInterrupt_ForceType,OH_AudioInterrupt_Hint);
 static void renderDeviceChange(OH_AudioRenderer*,void*,OH_AudioStream_DeviceChangeReason);
 static void captureError(OH_AudioCapturer*,void*,OH_AudioStream_Result);
 bool startPlaybackMode(uint64_t epoch,bool tryFast);
 bool openPlayback(uint64_t epoch,bool fast);
 bool stopMicrophoneLocked();bool stopLocked();
 bool cleanupPendingActive()const{return cleanupPending_&&(rendererOwned_||capturerOwned_||providerOperations_.load()>0);}
 struct ProviderOperation{std::atomic<uint64_t>&count;explicit ProviderOperation(std::atomic<uint64_t>&c):count(c){count.fetch_add(1);}~ProviderOperation(){count.fetch_sub(1);}};
 struct RenderContext{RemoteAudio*owner;const uint64_t epoch,generation;OH_AudioRenderer*handle=nullptr;std::atomic<bool>active{false};RenderContext(RemoteAudio*o,uint64_t e,uint64_t g):owner(o),epoch(e),generation(g){}};
 struct CaptureContext{RemoteAudio*owner;const uint64_t epoch,generation;OH_AudioCapturer*handle=nullptr;std::atomic<bool>active{false};CaptureContext(RemoteAudio*o,uint64_t e,uint64_t g):owner(o),epoch(e),generation(g){}};
 static bool current(const RenderContext*,OH_AudioRenderer*);static bool current(const CaptureContext*,OH_AudioCapturer*);
 std::mutex observationLock_;std::thread observationThread_;
 std::atomic<bool>observationInFlight_{false};std::atomic<uint64_t>observationStartedNs_{0};
 mutable std::mutex lifecycle_;std::mutex microphoneAssemblyLock_;
 std::array<uint8_t,1920>microphoneAssembly_{};size_t microphoneAssemblyBytes_=0;uint64_t microphoneAssemblyTime_=0;
 std::atomic<bool>rendererOwned_{false},capturerOwned_{false};std::atomic<uint64_t>providerOperations_{0};
 std::atomic<uint64_t>retiredSessionEpoch_{0};std::atomic<bool>cleanupPending_{false};
 std::atomic<uint64_t>epoch_{0};std::atomic<bool>playback_{false},microphone_{false};
 std::atomic<uint64_t>playbackGeneration_{0},microphoneGeneration_{0},renderedFrames_{0},renderCallbacks_{0},lastRenderNs_{0};
 std::atomic<int32_t>lastError_{0},playbackError_{0},microphoneError_{0};OH_AudioRenderer*renderer_=nullptr;
 OH_AudioCapturer*capturer_=nullptr;PCMQueue output_,input_;
 std::unique_ptr<RenderContext>rendererContext_;std::unique_ptr<CaptureContext>capturerContext_;
 std::atomic<int32_t>rendererObservedState_{-1},rendererStateResult_{-1},rendererInterruptType_{-1},rendererInterruptHint_{-1},rendererDeviceChangeReason_{-1};
 std::atomic<uint32_t>rendererInterruptMask_{0};std::atomic<uint64_t>rendererStateSamples_{0},rendererInterruptEvents_{0},rendererDeviceChanges_{0},rendererStateSampleNs_{0};
 std::atomic<bool>fastRequested_{false};std::atomic<OH_AudioStream_LatencyMode>latencyMode_{AUDIOSTREAM_LATENCY_MODE_NORMAL};
};
}
