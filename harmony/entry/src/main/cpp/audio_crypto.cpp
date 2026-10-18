#include "audio_crypto.h"
#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <openssl/crypto.h>
#include <cstring>
#include <limits>
#include <memory>

namespace edgelink::audio {
namespace {
void put(uint8_t*p,uint64_t value,size_t count){for(size_t i=0;i<count;i++)p[count-1-i]=uint8_t(value>>(i*8));}
uint64_t get(const uint8_t*p,size_t count){uint64_t value=0;for(size_t i=0;i<count;i++)value=(value<<8)|p[i];return value;}
bool derive(const uint8_t*input,size_t size,const uint8_t*salt,const std::string&info,uint8_t*out,size_t wanted){
 auto*ctx=EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF,nullptr);if(!ctx)return false;
 const bool ok=EVP_PKEY_derive_init(ctx)>0&&EVP_PKEY_CTX_set_hkdf_md(ctx,EVP_sha256())>0&&
  EVP_PKEY_CTX_set1_hkdf_salt(ctx,salt,12)>0&&EVP_PKEY_CTX_set1_hkdf_key(ctx,input,int(size))>0&&
  EVP_PKEY_CTX_add1_hkdf_info(ctx,reinterpret_cast<const uint8_t*>(info.data()),int(info.size()))>0&&
  EVP_PKEY_derive(ctx,out,&wanted)>0;
 EVP_PKEY_CTX_free(ctx);return ok;
}
using CipherPtr=std::unique_ptr<EVP_CIPHER_CTX,decltype(&EVP_CIPHER_CTX_free)>;
}
AudioCipher::AudioCipher(const uint8_t*mediaKey,size_t keyBytes,uint32_t sid,uint64_t epoch,Direction direction):sid_(sid),epoch_(epoch),direction_(direction){
 if(!mediaKey||(keyBytes!=16&&keyBytes!=32)||!epoch||
  (direction!=Direction::MacOutput&&direction!=Direction::PadMicrophone))return;
 uint8_t salt[12];put(salt,sid,4);put(salt+4,epoch,8);
 const auto domain="edgelink.audio.v1/"+std::to_string(unsigned(direction))+"/";
 valid_=derive(mediaKey,keyBytes,salt,domain+"key",key_.data(),key_.size())&&
  derive(mediaKey,keyBytes,salt,domain+"nonce",prefix_.data(),prefix_.size());
}
bool AudioCipher::seal(const uint8_t*pcm,size_t bytes,uint8_t channels,uint64_t capturedNs,std::vector<uint8_t>&record){
 if(!channels||bytes%(channels*2))return false;
 return sealPayload(pcm,bytes,channels,uint16_t(bytes/(channels*2)),Codec::PCM,capturedNs,record);
}
bool AudioCipher::sealOpus(const uint8_t*packet,size_t bytes,uint8_t channels,uint64_t capturedNs,std::vector<uint8_t>&record){return sealPayload(packet,bytes,channels,480,Codec::Opus,capturedNs,record);}
bool AudioCipher::sealPayload(const uint8_t*pcm,size_t bytes,uint8_t channels,uint16_t frames,Codec codec,uint64_t capturedNs,std::vector<uint8_t>&record){
 record.clear();const auto expected=direction_==Direction::MacOutput?2:1;
 if(!valid()||!pcm||!bytes||channels!=expected||!frames||frames>kMaxFrames||
  (codec==Codec::PCM ? bytes!=size_t(frames)*channels*2:(frames!=480||bytes>1275)))return false;
 if(next_==std::numeric_limits<uint64_t>::max()){retire();return false;}
 const auto sequence=next_++;record.resize(kHeaderBytes+bytes+16);
 auto*p=record.data();std::memcpy(p,"EAD1",4);p[4]=1;p[5]=uint8_t(direction_);p[6]=uint8_t(codec);p[7]=channels;
 put(p+8,sid_,4);put(p+12,epoch_,8);put(p+20,sequence,8);put(p+28,capturedNs,8);
 put(p+36,48000,4);put(p+40,frames,2);put(p+42,bytes,2);
 uint8_t nonce[12];std::memcpy(nonce,prefix_.data(),4);put(nonce+4,sequence,8);
 CipherPtr ctx(EVP_CIPHER_CTX_new(),EVP_CIPHER_CTX_free);int size=0,tail=0;
 const bool ok=ctx&&EVP_EncryptInit_ex(ctx.get(),EVP_aes_256_gcm(),nullptr,key_.data(),nonce)==1&&
  EVP_EncryptUpdate(ctx.get(),nullptr,&size,p,kHeaderBytes)==1&&
  EVP_EncryptUpdate(ctx.get(),p+kHeaderBytes,&size,pcm,int(bytes))==1&&size==int(bytes)&&
  EVP_EncryptFinal_ex(ctx.get(),p+kHeaderBytes+bytes,&tail)==1&&tail==0&&
  EVP_CIPHER_CTX_ctrl(ctx.get(),EVP_CTRL_GCM_GET_TAG,16,p+kHeaderBytes+bytes)==1;
 if(!ok){OPENSSL_cleanse(record.data(),record.size());record.clear();}return ok;
}
bool AudioCipher::open(const uint8_t*p,size_t bytes,Chunk&out){
 if(!valid()||!p||bytes<kHeaderBytes+16||std::memcmp(p,"EAD1",4)||p[4]!=1||p[5]!=uint8_t(direction_)||
  (p[6]!=1&&p[6]!=2)||get(p+8,4)!=sid_||get(p+12,8)!=epoch_||get(p+36,4)!=48000)return false;
 const auto codec=Codec(p[6]);
 const auto channels=p[7];const auto frames=get(p+40,2),size=get(p+42,2),sequence=get(p+20,8);
 if(channels!=(direction_==Direction::MacOutput?2:1)||!frames||frames>kMaxFrames||
  (codec==Codec::PCM ? size!=frames*channels*2:(frames!=480||!size||size>1275))||bytes!=kHeaderBytes+size+16||!sequence||sequence<=last_)return false;
 uint8_t nonce[12];std::memcpy(nonce,prefix_.data(),4);put(nonce+4,sequence,8);
 std::vector<uint8_t>plain(size);CipherPtr ctx(EVP_CIPHER_CTX_new(),EVP_CIPHER_CTX_free);int copied=0,tail=0;
 const bool ok=ctx&&EVP_DecryptInit_ex(ctx.get(),EVP_aes_256_gcm(),nullptr,key_.data(),nonce)==1&&
  EVP_DecryptUpdate(ctx.get(),nullptr,&copied,p,kHeaderBytes)==1&&
  EVP_DecryptUpdate(ctx.get(),plain.data(),&copied,p+kHeaderBytes,int(size))==1&&copied==int(size)&&
  EVP_CIPHER_CTX_ctrl(ctx.get(),EVP_CTRL_GCM_SET_TAG,16,const_cast<uint8_t*>(p+kHeaderBytes+size))==1&&
  EVP_DecryptFinal_ex(ctx.get(),plain.data()+copied,&tail)==1&&tail==0;
 if(!ok){OPENSSL_cleanse(plain.data(),plain.size());return false;}
 last_=sequence;out={epoch_,sequence,get(p+28,8),uint16_t(frames),channels,std::move(plain),codec};return true;
}
void AudioCipher::retire(){retired_=true;valid_=false;OPENSSL_cleanse(key_.data(),key_.size());OPENSSL_cleanse(prefix_.data(),prefix_.size());}
}
