#include "opus_audio_codec.h"
#include <opus.h>
#include <stdlib.h>
struct EDLAOpusEncoder {OpusEncoder*handle;int channels;};
struct EDLAOpusDecoder {OpusDecoder*handle;int channels;};
EDLAOpusEncoder*EDLAOpusEncoderCreate(int channels,int bitrate){
 if((channels!=1&&channels!=2)||bitrate<16000||bitrate>192000)return NULL;
 int error=0;OpusEncoder*encoder=opus_encoder_create(48000,channels,OPUS_APPLICATION_RESTRICTED_LOWDELAY,&error);
 if(!encoder||error!=OPUS_OK)return NULL;
 if(opus_encoder_ctl(encoder,OPUS_SET_BITRATE(bitrate))!=OPUS_OK||
  opus_encoder_ctl(encoder,OPUS_SET_COMPLEXITY(4))!=OPUS_OK||
  opus_encoder_ctl(encoder,OPUS_SET_VBR(1))!=OPUS_OK||
  opus_encoder_ctl(encoder,OPUS_SET_VBR_CONSTRAINT(1))!=OPUS_OK){opus_encoder_destroy(encoder);return NULL;}
 EDLAOpusEncoder*out=malloc(sizeof(*out));if(!out){opus_encoder_destroy(encoder);return NULL;}
 out->handle=encoder;out->channels=channels;return out;
}
void EDLAOpusEncoderDestroy(EDLAOpusEncoder*encoder){if(encoder){opus_encoder_destroy(encoder->handle);free(encoder);}}
int EDLAOpusEncode(EDLAOpusEncoder*encoder,const int16_t*pcm,int frames,uint8_t*out,int capacity){
 if(!encoder||!pcm||!out||frames!=480||capacity<1||capacity>1275)return OPUS_BAD_ARG;
 return opus_encode(encoder->handle,pcm,frames,out,capacity);
}
int EDLAOpusEncoderLookahead(EDLAOpusEncoder*encoder){int frames=0;return encoder&&opus_encoder_ctl(encoder->handle,OPUS_GET_LOOKAHEAD(&frames))==OPUS_OK?frames:-1;}
EDLAOpusDecoder*EDLAOpusDecoderCreate(int channels){
 if(channels!=1&&channels!=2)return NULL;int error=0;OpusDecoder*decoder=opus_decoder_create(48000,channels,&error);
 if(!decoder||error!=OPUS_OK)return NULL;
 EDLAOpusDecoder*out=malloc(sizeof(*out));if(!out){opus_decoder_destroy(decoder);return NULL;}
 out->handle=decoder;out->channels=channels;return out;
}
void EDLAOpusDecoderDestroy(EDLAOpusDecoder*decoder){if(decoder){opus_decoder_destroy(decoder->handle);free(decoder);}}
int EDLAOpusDecode(EDLAOpusDecoder*decoder,const uint8_t*packet,int bytes,int16_t*out,int frames){
 if(!decoder||!packet||bytes<1||bytes>1275||!out||frames!=480||opus_packet_get_nb_samples(packet,bytes,48000)!=480)return OPUS_BAD_ARG;
 return opus_decode(decoder->handle,packet,bytes,out,frames,0);
}
int EDLAOpusConceal(EDLAOpusDecoder*decoder,int16_t*out,int frames){if(!decoder||!out||frames!=480)return OPUS_BAD_ARG;return opus_decode(decoder->handle,NULL,0,out,frames,0);}
void EDLAOpusDecoderReset(EDLAOpusDecoder*decoder){if(decoder)(void)opus_decoder_ctl(decoder->handle,OPUS_RESET_STATE);}
