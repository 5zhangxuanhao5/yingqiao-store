#include "remote_audio.h"
// Store prototype has no microphone/audio provider. Full personal-edition source
// is kept separately; it must not acquire a provider or a system mute lease here.
namespace edgelink::audio {
bool RemoteAudio::startPlayback(uint64_t){return false;}
bool RemoteAudio::startPlaybackNormal(uint64_t){return false;}
bool RemoteAudio::inspectPlayback(uint64_t){return false;}
bool RemoteAudio::requestPlaybackObservation(uint64_t){return false;}
bool RemoteAudio::startMicrophone(uint64_t){return false;}
bool RemoteAudio::stopMicrophone(){return true;}
bool RemoteAudio::stop(){return true;}
void RemoteAudio::retireCallbacks(uint64_t){}
bool RemoteAudio::enqueuePlayback(uint64_t,const void*,size_t,uint64_t){return false;}
size_t RemoteAudio::drainMicrophone(uint64_t,void*,size_t,uint64_t&time){time=0;return 0;}
RemoteAudio::Status RemoteAudio::status()const{return {};}
}
