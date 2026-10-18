#pragma once
#include <string>
struct OH_AVCapability {bool hevc;};
struct OH_AVRange {int minVal,maxVal;};
constexpr int HARDWARE=1,VIDEO_LOW_LATENCY=1;
inline OH_AVCapability *OH_AVCodec_GetCapabilityByCategory(const char *mime,bool,int){static OH_AVCapability h264{false},hevc{true};return std::string(mime)=="video/hevc"?&hevc:&h264;}
inline const char *OH_AVCapability_GetName(OH_AVCapability*){return "synthetic-hardware-fixture";}
inline bool OH_AVCapability_IsFeatureSupported(OH_AVCapability*,int){return true;}
inline int OH_AVCapability_GetVideoFrameRateRangeForSize(OH_AVCapability*,int,int,OH_AVRange *range){*range={1,60};return 0;}
inline bool OH_AVCapability_AreVideoSizeAndFrameRateSupported(OH_AVCapability *cap,int w,int h,int fps){return w<=(cap->hevc?2400:1920)&&h<=2400&&fps<=(cap->hevc?60:30);}
