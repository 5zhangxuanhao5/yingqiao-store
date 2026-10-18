#include <stdio.h>
#include <multimedia/player_framework/native_avcapability.h>
int main(void) {
 const char *mimes[] = {"video/avc", "video/hevc"};
 int sizes[][2] = {{1920,1080},{2400,1600},{2880,1920},{3120,2080}};
 for (int i=0;i<2;i++) {
  OH_AVCapability *cap=OH_AVCodec_GetCapabilityByCategory(mimes[i],false,HARDWARE);
  printf("%s hardware=%s\n",mimes[i],cap ? OH_AVCapability_GetName(cap) : "unavailable");
  if (!cap) continue;
  printf("low_latency=%s\n",OH_AVCapability_IsFeatureSupported(cap,VIDEO_LOW_LATENCY)?"true":"false");
  for(int s=0;s<4;s++) {
   OH_AVRange range={0};
   OH_AVErrCode err=OH_AVCapability_GetVideoFrameRateRangeForSize(cap,sizes[s][0],sizes[s][1],&range);
   printf("%dx%d query=%d reported_fps=%d..%d supports60=%d supports120=%d\n",sizes[s][0],sizes[s][1],err,range.minVal,range.maxVal,OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap,sizes[s][0],sizes[s][1],60),OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap,sizes[s][0],sizes[s][1],120));
  }
 }
 return 0;
}
