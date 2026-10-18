#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace edgelinkrtc {
// Media policy is independent of its control route. A USB-controlled RTC
// session still carries WAN media. No control TIME RTT is accepted here.
inline uint64_t ReorderWaitNs(int recordBudgetMs,double mediaRTTms=0){
 if(recordBudgetMs!=100&&recordBudgetMs!=300&&recordBudgetMs!=500)recordBudgetMs=300;
 const double upperMs=std::min(200.0,std::max(60.0,recordBudgetMs*0.6));
 const double estimate=(std::isfinite(mediaRTTms)&&mediaRTTms>0&&mediaRTTms<=5000)?mediaRTTms*0.75+40.0:double(recordBudgetMs)/3.0;
 return uint64_t(std::ceil(std::clamp(estimate,60.0,upperMs)*1000000.0));
}
}
