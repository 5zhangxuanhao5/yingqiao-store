#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace edgelink::audio {
enum class Direction:uint8_t {MacOutput=1,PadMicrophone=2};
enum class Codec:uint8_t {PCM=1,Opus=2};
struct Chunk {uint64_t epoch=0,sequence=0,capturedNs=0;uint16_t frames=0;uint8_t channels=0;std::vector<uint8_t>pcm;Codec codec=Codec::PCM;};
// Owned by one authenticated session's non-real-time serial worker. Session
// key is supplied by the existing paired handshake, never a stored password.
class AudioCipher {
public:
 static constexpr size_t kHeaderBytes=44,kMaxFrames=480;
 AudioCipher(const uint8_t*mediaKey,size_t mediaKeyBytes,uint32_t sessionID,uint64_t epoch,Direction);
 ~AudioCipher(){retire();}
 AudioCipher(const AudioCipher&)=delete;AudioCipher&operator=(const AudioCipher&)=delete;
 bool valid()const{return valid_&&!retired_;}
 bool seal(const uint8_t*pcm,size_t bytes,uint8_t channels,uint64_t capturedNs,std::vector<uint8_t>&record);
 bool sealOpus(const uint8_t*packet,size_t bytes,uint8_t channels,uint64_t capturedNs,std::vector<uint8_t>&record);
 bool open(const uint8_t*record,size_t bytes,Chunk&out);
 void retire();
private:
 bool sealPayload(const uint8_t*,size_t bytes,uint8_t channels,uint16_t frames,Codec,uint64_t capturedNs,std::vector<uint8_t>&record);
 std::array<uint8_t,32>key_{};std::array<uint8_t,4>prefix_{};
 uint32_t sid_;uint64_t epoch_,next_=1,last_=0;Direction direction_;bool valid_=false,retired_=false;
};
}
