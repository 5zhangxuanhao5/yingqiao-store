#include "remote_audio.h"
#include <chrono>
#include <cstring>

namespace edgelink::audio {
uint64_t RemoteAudio::nowNs(){return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
bool RemoteAudio::startPlayback(uint64_t epoch){return startPlaybackMode(epoch,true);}
bool RemoteAudio::startPlaybackNormal(uint64_t epoch){return startPlaybackMode(epoch,false);}
bool RemoteAudio::startPlaybackMode(uint64_t epoch,bool tryFast){
 if(!epoch||epoch<=retiredSessionEpoch_.load()||cleanupPendingActive())return false;
 ProviderOperation operation(providerOperations_);std::lock_guard<std::mutex>guard(lifecycle_);if(!stopLocked()||epoch<=retiredSessionEpoch_.load())return false;
 epoch_=epoch;renderedFrames_=renderCallbacks_=lastRenderNs_=0;
 rendererObservedState_=rendererStateResult_=rendererInterruptType_=rendererInterruptHint_=rendererDeviceChangeReason_=-1;
 rendererInterruptMask_=0;rendererStateSamples_=rendererInterruptEvents_=rendererDeviceChanges_=rendererStateSampleNs_=0;output_.begin(epoch);input_.begin(epoch);
 if(tryFast&&openPlayback(epoch,true))return true;
 // Unsupported fast paths are retried once through the same system MEDIA
 // volume route. This records actual latency mode, rather than claiming FAST.
 if(openPlayback(epoch,false))return true;
 stopLocked();return false;
}
bool RemoteAudio::openPlayback(uint64_t epoch,bool fast){
 if(renderer_)return false;
 const auto generation=++playbackGeneration_;
 rendererContext_=std::make_unique<RenderContext>(this,epoch,generation);
 OH_AudioStreamBuilder*b=nullptr;
 auto result=OH_AudioStreamBuilder_Create(&b,AUDIOSTREAM_TYPE_RENDERER);
 if(result!=AUDIOSTREAM_SUCCESS){lastError_=playbackError_=result;return false;}
 auto set=[&](OH_AudioStream_Result r){if(result==AUDIOSTREAM_SUCCESS&&r!=AUDIOSTREAM_SUCCESS)result=r;};
 set(OH_AudioStreamBuilder_SetSamplingRate(b,48000));
 set(OH_AudioStreamBuilder_SetChannelCount(b,2));
 set(OH_AudioStreamBuilder_SetSampleFormat(b,AUDIOSTREAM_SAMPLE_S16LE));
 set(OH_AudioStreamBuilder_SetEncodingType(b,AUDIOSTREAM_ENCODING_TYPE_RAW));
 set(OH_AudioStreamBuilder_SetRendererInfo(b,AUDIOSTREAM_USAGE_MUSIC));
 set(OH_AudioStreamBuilder_SetVolumeMode(b,AUDIOSTREAM_VOLUMEMODE_SYSTEM_GLOBAL));
 set(OH_AudioStreamBuilder_SetLatencyMode(b,fast?AUDIOSTREAM_LATENCY_MODE_FAST:AUDIOSTREAM_LATENCY_MODE_NORMAL));
 // Callback size is a request; device output size is still honored exactly.
 (void)OH_AudioStreamBuilder_SetFrameSizeInCallback(b,480);
 set(OH_AudioStreamBuilder_SetRendererWriteDataCallback(b,write,rendererContext_.get()));
 set(OH_AudioStreamBuilder_SetRendererErrorCallback(b,renderError,rendererContext_.get()));
 set(OH_AudioStreamBuilder_SetRendererInterruptCallback(b,renderInterrupt,rendererContext_.get()));
 set(OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback(b,renderDeviceChange,rendererContext_.get()));
 if(result==AUDIOSTREAM_SUCCESS)result=OH_AudioStreamBuilder_GenerateRenderer(b,&renderer_);rendererOwned_=renderer_!=nullptr;
 (void)OH_AudioStreamBuilder_Destroy(b);
 if(result==AUDIOSTREAM_SUCCESS){rendererContext_->handle=renderer_;rendererContext_->active=true;playback_=true;result=OH_AudioRenderer_Start(renderer_);}
 if(result!=AUDIOSTREAM_SUCCESS){playback_=false;rendererContext_->active=false;lastError_=playbackError_=result;
  if(renderer_){(void)OH_AudioRenderer_Stop(renderer_);const auto released=OH_AudioRenderer_Release(renderer_);if(released==AUDIOSTREAM_SUCCESS){renderer_=nullptr;rendererOwned_=false;rendererContext_.reset();}else{lastError_=playbackError_=released;}}
  else{rendererContext_.reset();}return false;}
 if(epoch<=retiredSessionEpoch_.load()){stopLocked();return false;}
 epoch_=epoch;fastRequested_=fast;lastError_=playbackError_=0;cleanupPending_=false;
 OH_AudioStream_LatencyMode mode=AUDIOSTREAM_LATENCY_MODE_NORMAL;(void)OH_AudioRenderer_GetLatencyMode(renderer_,&mode);latencyMode_=mode;return true;
}
bool RemoteAudio::inspectPlayback(uint64_t epoch){
 ProviderOperation operation(providerOperations_);std::unique_lock<std::mutex>guard(lifecycle_,std::try_to_lock);
 if(!guard.owns_lock()||!renderer_||epoch!=epoch_.load()||!current(rendererContext_.get(),renderer_))return false;
 OH_AudioStream_State observed=AUDIOSTREAM_STATE_INVALID;const auto result=OH_AudioRenderer_GetCurrentState(renderer_,&observed);
 // End can retire atomics while the provider query is in flight. Its result
 // must not relabel a newer session or revive a retired renderer.
 if(epoch!=epoch_.load()||!current(rendererContext_.get(),renderer_))return false;
 rendererStateResult_=result;rendererObservedState_=result==AUDIOSTREAM_SUCCESS?int32_t(observed):-1;rendererStateSamples_++;rendererStateSampleNs_=nowNs();return result==AUDIOSTREAM_SUCCESS;
}
bool RemoteAudio::requestPlaybackObservation(uint64_t epoch){
 if(!epoch||epoch!=epoch_.load()||!playback_)return false;
 std::unique_lock<std::mutex>guard(observationLock_,std::try_to_lock);
 if(!guard.owns_lock()||observationInFlight_.load())return false;
 // The last finished worker performs no provider operations after this flag.
 if(observationThread_.joinable())observationThread_.join();
 observationInFlight_=true;observationStartedNs_=nowNs();
 try{observationThread_=std::thread([this,epoch]{(void)inspectPlayback(epoch);observationInFlight_=false;});}
 catch(...){observationInFlight_=false;return false;}return true;
}
bool RemoteAudio::startMicrophone(uint64_t epoch){
 ProviderOperation operation(providerOperations_);std::lock_guard<std::mutex>guard(lifecycle_);
 if(!epoch||epoch<=retiredSessionEpoch_.load()||epoch!=epoch_.load()||!playback_)return false;
 if(!stopMicrophoneLocked())return false;input_.begin(epoch);
 const auto generation=++microphoneGeneration_;
 capturerContext_=std::make_unique<CaptureContext>(this,epoch,generation);
 OH_AudioStreamBuilder*b=nullptr;auto result=OH_AudioStreamBuilder_Create(&b,AUDIOSTREAM_TYPE_CAPTURER);
 if(result!=AUDIOSTREAM_SUCCESS){lastError_=microphoneError_=result;return false;}
 auto set=[&](OH_AudioStream_Result r){if(result==AUDIOSTREAM_SUCCESS&&r!=AUDIOSTREAM_SUCCESS)result=r;};
 set(OH_AudioStreamBuilder_SetSamplingRate(b,48000));set(OH_AudioStreamBuilder_SetChannelCount(b,1));
 set(OH_AudioStreamBuilder_SetSampleFormat(b,AUDIOSTREAM_SAMPLE_S16LE));
 set(OH_AudioStreamBuilder_SetEncodingType(b,AUDIOSTREAM_ENCODING_TYPE_RAW));
 // Isolated source comparison: ordinary microphone routing, default latency.
 // No gain boost and no recording; compare with voice-communication processing.
 set(OH_AudioStreamBuilder_SetCapturerInfo(b,AUDIOSTREAM_SOURCE_TYPE_MIC));
 (void)OH_AudioStreamBuilder_SetFrameSizeInCallback(b,480);
 set(OH_AudioStreamBuilder_SetCapturerReadDataCallback(b,read,capturerContext_.get()));
 set(OH_AudioStreamBuilder_SetCapturerErrorCallback(b,captureError,capturerContext_.get()));
 if(result==AUDIOSTREAM_SUCCESS)result=OH_AudioStreamBuilder_GenerateCapturer(b,&capturer_);capturerOwned_=capturer_!=nullptr;
 (void)OH_AudioStreamBuilder_Destroy(b);
 if(result==AUDIOSTREAM_SUCCESS){capturerContext_->handle=capturer_;capturerContext_->active=true;microphone_=true;result=OH_AudioCapturer_Start(capturer_);}
 if(result!=AUDIOSTREAM_SUCCESS){lastError_=microphoneError_=result;stopMicrophoneLocked();return false;}
 if(epoch<=retiredSessionEpoch_.load()){stopMicrophoneLocked();return false;}lastError_=microphoneError_=0;return true;
}
bool RemoteAudio::enqueuePlayback(uint64_t epoch,const void*pcm,size_t size,uint64_t receivedNs){
 return playback_&&epoch==epoch_.load()&&size%4==0&&output_.push(epoch,pcm,size,receivedNs);
}
size_t RemoteAudio::drainMicrophone(uint64_t epoch,void*pcm,size_t capacity,uint64_t&capturedNs){
 if(!microphone_||epoch!=epoch_.load()||!pcm||capacity<960)return 0;
 std::lock_guard<std::mutex>guard(microphoneAssemblyLock_);
 const auto now=nowNs();if(microphoneAssemblyBytes_&&(now<microphoneAssemblyTime_||now-microphoneAssemblyTime_>30000000ULL)){microphoneAssemblyBytes_=0;microphoneAssemblyTime_=0;}
 while(microphoneAssemblyBytes_<960){std::array<uint8_t,1920>chunk{};uint64_t time=0;const auto bytes=input_.pop(epoch,chunk.data(),chunk.size(),time);
  if(!bytes)return 0;if(bytes>960||now<time||now-time>30000000ULL)continue;
  if(!microphoneAssemblyBytes_)microphoneAssemblyTime_=time;
  std::memcpy(microphoneAssembly_.data()+microphoneAssemblyBytes_,chunk.data(),bytes);microphoneAssemblyBytes_+=bytes;
 }
 std::memcpy(pcm,microphoneAssembly_.data(),960);capturedNs=microphoneAssemblyTime_;microphoneAssemblyBytes_-=960;
 if(microphoneAssemblyBytes_)std::memmove(microphoneAssembly_.data(),microphoneAssembly_.data()+960,microphoneAssemblyBytes_);else microphoneAssemblyTime_=0;
 return 960;
}
bool RemoteAudio::current(const RenderContext*ctx,OH_AudioRenderer*handle){return ctx&&ctx->active&&handle==ctx->handle&&ctx->owner->epoch_==ctx->epoch&&ctx->owner->playbackGeneration_==ctx->generation;}
bool RemoteAudio::current(const CaptureContext*ctx,OH_AudioCapturer*handle){return ctx&&ctx->active&&handle==ctx->handle&&ctx->owner->epoch_==ctx->epoch&&ctx->owner->microphoneGeneration_==ctx->generation;}
OH_AudioData_Callback_Result RemoteAudio::write(OH_AudioRenderer*handle,void*opaque,void*data,int32_t size){
 auto*ctx=static_cast<RenderContext*>(opaque);if(!ctx)return AUDIO_DATA_CALLBACK_RESULT_INVALID;auto*self=ctx->owner;
 if(!data||size<=0)return AUDIO_DATA_CALLBACK_RESULT_INVALID;
 if(!current(ctx,handle)||!self->playback_){std::memset(data,0,size);return AUDIO_DATA_CALLBACK_RESULT_VALID;}
 const auto now=nowNs();self->renderCallbacks_++;self->lastRenderNs_=now;
 const auto filled=self->output_.render(ctx->epoch,data,size,now);self->renderedFrames_+=filled/4;return AUDIO_DATA_CALLBACK_RESULT_VALID;
}
void RemoteAudio::read(OH_AudioCapturer*handle,void*opaque,void*data,int32_t size){
 auto*ctx=static_cast<CaptureContext*>(opaque);if(!ctx)return;auto*self=ctx->owner;
 if(!current(ctx,handle)||!self->microphone_||!data||size<=0||size%2)return;
 const auto epoch=ctx->epoch;const auto now=nowNs();
 // Some hardware callback buffers contain >10 ms. Split without allocation;
 // the bounded capture queue only retains the freshest three chunks.
 for(int32_t offset=0;offset<size;){const auto bytes=std::min<int32_t>(960,size-offset);
  self->input_.push(epoch,static_cast<uint8_t*>(data)+offset,bytes,now,true);offset+=bytes;}
}
void RemoteAudio::renderError(OH_AudioRenderer*handle,void*opaque,OH_AudioStream_Result error){auto*ctx=static_cast<RenderContext*>(opaque);if(!current(ctx,handle))return;ctx->owner->lastError_=ctx->owner->playbackError_=error;ctx->owner->playback_=false;}
void RemoteAudio::renderInterrupt(OH_AudioRenderer*handle,void*opaque,OH_AudioInterrupt_ForceType type,OH_AudioInterrupt_Hint hint){
 auto*ctx=static_cast<RenderContext*>(opaque);if(!current(ctx,handle))return;auto*self=ctx->owner;
 self->rendererInterruptEvents_++;self->rendererInterruptType_=int32_t(type);self->rendererInterruptHint_=int32_t(hint);
 switch(hint){
  case AUDIOSTREAM_INTERRUPT_HINT_PAUSE:self->rendererInterruptMask_.fetch_or(1);break;
  case AUDIOSTREAM_INTERRUPT_HINT_STOP:self->rendererInterruptMask_.fetch_or(2);break;
  case AUDIOSTREAM_INTERRUPT_HINT_MUTE:self->rendererInterruptMask_.fetch_or(4);break;
  case AUDIOSTREAM_INTERRUPT_HINT_RESUME:self->rendererInterruptMask_.fetch_and(~uint32_t(1));break;
  case AUDIOSTREAM_INTERRUPT_HINT_UNMUTE:self->rendererInterruptMask_.fetch_and(~uint32_t(4));break;
  default:break;
 }
}
void RemoteAudio::renderDeviceChange(OH_AudioRenderer*handle,void*opaque,OH_AudioStream_DeviceChangeReason reason){
 auto*ctx=static_cast<RenderContext*>(opaque);if(!current(ctx,handle))return;ctx->owner->rendererDeviceChanges_++;ctx->owner->rendererDeviceChangeReason_=int32_t(reason);
}
void RemoteAudio::captureError(OH_AudioCapturer*handle,void*opaque,OH_AudioStream_Result error){auto*ctx=static_cast<CaptureContext*>(opaque);if(!current(ctx,handle))return;ctx->owner->lastError_=ctx->owner->microphoneError_=error;ctx->owner->microphone_=false;}
bool RemoteAudio::stopMicrophoneLocked(){
 microphone_=false;++microphoneGeneration_;if(capturerContext_)capturerContext_->active=false;
 {std::lock_guard<std::mutex>guard(microphoneAssemblyLock_);microphoneAssemblyBytes_=0;microphoneAssemblyTime_=0;microphoneAssembly_.fill(0);}
 if(capturer_){(void)OH_AudioCapturer_Stop(capturer_);const auto r=OH_AudioCapturer_Release(capturer_);if(r==AUDIOSTREAM_SUCCESS){capturer_=nullptr;capturerOwned_=false;capturerContext_.reset();}else{lastError_=microphoneError_=r;}}
 else{capturerContext_.reset();}input_.end();cleanupPending_=(renderer_!=nullptr&&!playback_)||(capturer_!=nullptr&&!microphone_);return capturer_==nullptr;
}
bool RemoteAudio::stopMicrophone(){ProviderOperation operation(providerOperations_);std::lock_guard<std::mutex>guard(lifecycle_);return stopMicrophoneLocked();}
bool RemoteAudio::stopLocked(){
 epoch_=0;playback_=false;microphone_=false;stopMicrophoneLocked();
 ++playbackGeneration_;if(rendererContext_)rendererContext_->active=false;
 if(renderer_){(void)OH_AudioRenderer_Stop(renderer_);const auto r=OH_AudioRenderer_Release(renderer_);if(r==AUDIOSTREAM_SUCCESS){renderer_=nullptr;rendererOwned_=false;rendererContext_.reset();}else{lastError_=playbackError_=r;}}
 else{rendererContext_.reset();}
 output_.end();input_.end();fastRequested_=false;latencyMode_=AUDIOSTREAM_LATENCY_MODE_NORMAL;
 cleanupPending_=renderer_!=nullptr||capturer_!=nullptr;return !cleanupPending_;
}
bool RemoteAudio::stop(){ProviderOperation operation(providerOperations_);std::lock_guard<std::mutex>guard(lifecycle_);return stopLocked();}
void RemoteAudio::retireCallbacks(uint64_t sessionEpoch){auto previous=retiredSessionEpoch_.load();while(previous<sessionEpoch&&!retiredSessionEpoch_.compare_exchange_weak(previous,sessionEpoch)){}epoch_=0;playback_=false;microphone_=false;playbackGeneration_++;microphoneGeneration_++;cleanupPending_=true;}
RemoteAudio::Status RemoteAudio::status()const{
 // Never wait for a provider's Stop/Release lock from NAPI statistics/UI.
 Status result{epoch_,playback_,microphone_,fastRequested_,cleanupPendingActive(),latencyMode_.load(),lastError_,playbackError_,microphoneError_,renderedFrames_,renderCallbacks_,lastRenderNs_,output_.stats(),input_.stats()};
 result.rendererObservedState=rendererObservedState_;result.rendererStateResult=rendererStateResult_;result.rendererStateSamples=rendererStateSamples_;result.rendererStateSampleNs=rendererStateSampleNs_;
 result.rendererInterruptEvents=rendererInterruptEvents_;result.rendererInterruptType=rendererInterruptType_;result.rendererInterruptHint=rendererInterruptHint_;result.rendererInterruptMask=rendererInterruptMask_;
 result.rendererDeviceChanges=rendererDeviceChanges_;result.rendererDeviceChangeReason=rendererDeviceChangeReason_;result.rendererResourceOwned=rendererOwned_;result.capturerResourceOwned=capturerOwned_;result.providerOperations=providerOperations_;result.rendererProbeInFlight=observationInFlight_;result.rendererProbeStartedNs=observationStartedNs_;return result;
}
}
