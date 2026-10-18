#include "axis_observer.h"
#include <atomic>
#include <algorithm>
#include <cmath>
#include <mutex>
#include <sstream>
namespace {
std::mutex callbackLock;
std::atomic<bool> enabled{false},gestureActive{false};
std::atomic<int> result{-1},lastSource{0},lastTool{0};
std::atomic<uint64_t> scrollEvents{0},pinchEvents{0},callbacks{0},rejectedSource{0};
std::function<void(const std::string&)> forward;
int ownWindow=-1;
double remainderX=0,remainderY=0,pinchScale=1;
bool scrolling=false,pinching=false;
// Caller holds callbackLock. The forwarding function must only enqueue commands,
// never re-enter this module. Client stats and gesture gates read atomics only.
void finishGestures(){
 if(forward){if(scrolling)forward("SCROLL 0 0 4");if(pinching)forward("ZOOM 0 4");}
 scrolling=pinching=false;gestureActive=false;remainderX=remainderY=0;pinchScale=1;
}
}
void SetLocalAxisRegistrationResult(int registrationResult){result=registrationResult;}
void HandleLocalAxisEvent(const LocalAxisSample& e){
 callbacks++;
 if(!enabled)return;
 if(!e.supportedSource){rejectedSource++;return;}
 if(e.action<1||e.action>4)return;
 std::lock_guard<std::mutex>g(callbackLock);if(!enabled||!forward)return;
 // ArkUI axis actions: BEGIN=1, UPDATE=2, END=3, CANCEL=4.
 const bool ending=e.action==3||e.action==4;
 lastSource=e.source;lastTool=e.tool;
 if(ending){
  if(scrolling)scrollEvents++;if(pinching)pinchEvents++;
  finishGestures();return;
 }
 const bool isPinch=e.hasPinch;
 if(!isPinch){
  if((!e.hasHorizontal&&!e.hasVertical)||!std::isfinite(e.x)||!std::isfinite(e.y))return;
  const bool beginning=e.action==1||!scrolling;
  if(beginning){finishGestures();scrolling=true;gestureActive=true;forward("BUTTON 0 0");}
  remainderX-=std::clamp(e.x,-2000.0,2000.0);remainderY-=std::clamp(e.y,-2000.0,2000.0);
  const int dx=int(std::round(remainderX)),dy=int(std::round(remainderY));remainderX-=dx;remainderY-=dy;
  if(beginning&&e.action!=1)forward("SCROLL 0 0 1");
  if(e.action==1||dx||dy)forward("SCROLL "+std::to_string(dy)+" "+std::to_string(dx)+" "+std::to_string(e.action==1?1:2));
  scrollEvents++;
 }else{
  if(!std::isfinite(e.scale)||e.scale<=0)return;
  if(e.action==1||!pinching){finishGestures();pinching=true;gestureActive=true;forward("BUTTON 0 0");forward("ZOOM 0 1");}
  forward("ZOOM "+std::to_string(std::clamp(e.scale/pinchScale-1,-0.5,0.5))+" 2");pinchScale=e.scale;pinchEvents++;
 }
 gestureActive=scrolling||pinching;
}
void StopAxisObservation(){
 std::lock_guard<std::mutex>g(callbackLock);enabled=false;finishGestures();forward=nullptr;ownWindow=-1;
}
void StartAxisObservation(int windowId,std::function<void(const std::string&)> send){
 if(windowId<0)return;
 std::lock_guard<std::mutex>g(callbackLock);
 if(result!=0)return;
 if(ownWindow!=windowId)finishGestures();ownWindow=windowId;forward=std::move(send);enabled=true;
}
bool AxisObservationIsActive(){return enabled&&result==0;}
bool AxisGestureInProgress(){return enabled&&gestureActive;}
std::string AxisObservationStats(){std::ostringstream s;s<<"\"axisInputEnabled\":"<<(enabled?"true":"false")<<",\"localAxisEnabled\":"<<(enabled?"true":"false")<<",\"localAxisRegistrationResult\":"<<result<<",\"localAxisEvents\":"<<callbacks<<",\"localScrollEvents\":"<<scrollEvents<<",\"localPinchEvents\":"<<pinchEvents<<",\"localAxisSource\":"<<lastSource<<",\"localAxisTool\":"<<lastTool<<",\"localAxisRejectedSource\":"<<rejectedSource
 <<",\"axisMonitorEnabled\":false,\"axisMonitorResult\":-1,\"monitorScrollEvents\":0,\"monitorPinchEvents\":0,\"monitorSource\":0,\"monitorCallbacks\":0,\"monitorRejectedWindow\":0,\"monitorRejectedSource\":0";return s.str();}
