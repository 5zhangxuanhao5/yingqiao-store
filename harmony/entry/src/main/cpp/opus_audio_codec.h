#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EDLAOpusEncoder EDLAOpusEncoder;
typedef struct EDLAOpusDecoder EDLAOpusDecoder;
EDLAOpusEncoder* EDLAOpusEncoderCreate(int channels,int bitrate);
void EDLAOpusEncoderDestroy(EDLAOpusEncoder*);
// Exactly 480 frames =10 ms. Work-thread calls only, not HAL/OHAudio callbacks.
int EDLAOpusEncode(EDLAOpusEncoder*,const int16_t*pcm,int frames,uint8_t*out,int capacity);
int EDLAOpusEncoderLookahead(EDLAOpusEncoder*);
EDLAOpusDecoder* EDLAOpusDecoderCreate(int channels);
void EDLAOpusDecoderDestroy(EDLAOpusDecoder*);
int EDLAOpusDecode(EDLAOpusDecoder*,const uint8_t*packet,int bytes,int16_t*out,int frames);
// Empty packet performs one 10 ms PLC step. No buffering or packet files.
int EDLAOpusConceal(EDLAOpusDecoder*,int16_t*out,int frames);
void EDLAOpusDecoderReset(EDLAOpusDecoder*);
#ifdef __cplusplus
}
#endif
