#include "store_policy.h"
#include "session_end_policy.h"
#include <napi/native_api.h>
#include "axis_observer.h"
#include "desktop_shortcut.h"
#include "cursor_lock.h"
#include "mouse_node.h"
#include "cursor_channel.h"
#include "timing.h"
#include "clock_refresh.h"
#include "desktop_topology.h"
#include <arkui/ui_input_event.h>
#include "wan_rate_controller.h"
#include "rtc_reorder_policy.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_window/external_window.h>
#include <multimedia/player_framework/native_avcodec_videodecoder.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <openssl/ssl.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/err.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <cstring>
#include <memory>
#include <functional>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <map>
#include <set>
#include <sstream>
#include <vector>
#include <array>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include "network.h"
#include "control_stream_owner.h"
#include "remote_audio.h"
#include "audio_crypto.h"
#include "audio_read_liveness.h"
#include "opus_audio_codec.h"
#include "split_policy.h"
#include "split_proof.h"
#include "rtc_signaling.h"
#include "rtc_event_channel.h"
#include "rtc_media_ingress.h"
#include <pthread.h>
#include <signal.h>

using Bytes=std::vector<uint8_t>;
static uint64_t Now(){return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static uint64_t ReadBE(const uint8_t*p,int n){uint64_t x=0;while(n--)x=(x<<8)|*p++;return x;}
static void PutBE(Bytes&d,uint64_t x,int n){for(int i=n-1;i>=0;i--)d.push_back(uint8_t(x>>(i*8)));}
static Bytes Unhex(const std::string&s){Bytes d;if(s.size()%2)throw std::runtime_error("bad hex");for(size_t i=0;i<s.size();i+=2){char*e=nullptr;std::string part=s.substr(i,2);auto x=strtoul(part.c_str(),&e,16);if(!e||*e)throw std::runtime_error("bad hex");d.push_back(uint8_t(x));}return d;}
static std::string Quoted(const std::string&s){std::string out="\"";for(char c:s){if(c=='\"'||c=='\\')out+='\\';if(uint8_t(c)>=32)out+=c;}return out+'\"';}
struct TLS {
 SSL_CTX*ctx=nullptr;SSL*ssl=nullptr;int fd=-1;uint64_t streamEpoch=0;
 std::function<void(int,uint64_t)>onClosing;
 ~TLS(){if(ssl)SSL_free(ssl);if(ctx)SSL_CTX_free(ctx);if(fd>=0){if(onClosing)onClosing(fd,streamEpoch);close(fd);}}
};
struct Frame {uint64_t id=0,receivedAt=0,assembled=0,enqueuedAt=0;bool key=false;Bytes data;edgetiming::FrameTiming timing;};
struct DecodeTiming {uint64_t id=0,pushedAt=0;edgetiming::FrameTiming host;};
struct Assembly {uint64_t created=0;uint32_t total=0;uint16_t count=0;uint8_t flags=0;Bytes data;std::vector<bool>seen;int got=0;};
struct Options {std::string host,mode,transport,token,certificate;int port=48563,width=2400,height=1600,fps=60,bitrateKbps=0;bool splitPath=false;std::string videoHost;int videoPort=0;};
class Client {
 public:
 std::atomic<bool>running{false};std::thread worker;
 std::mutex lock,ioLock;std::recursive_mutex lifecycleLock;std::condition_variable changed;
 std::atomic<bool>stopRequested{false};
 bool controlWriterReady=false,stopControlWriteAttempted=false,stopControlWritten=false,stopControlWriteCompleted=false,stopControlTimedOut=false;
 bool stopProxyDrainAttempted=false,stopProxyDrainRequested=false;
 std::string status="idle",error,lastStopReason;Options options;
 std::deque<std::string>commands;std::deque<Frame>frames;
 std::map<uint64_t,DecodeTiming>times;
 edgetiming::ClockSync clockSync;bool timingNegotiated=false;DesktopTopology desktopTopology;uint64_t desktopTopologyRevision=0;
 uint64_t timingSessionEpoch=0,clockSyncRefreshes=0;
 std::atomic<uint64_t>clockRefreshProbes{0},clockRefreshAccepted{0},clockRefreshTimeouts{0},clockRefreshRejected{0},clockRefreshOverlong{0};
 bool localHandoverSupported=false,backgroundRetainSupported=false,backgroundRetentionArmed=false;
 bool cursorChannelSupported=false,cursorCapabilityKnown=false;uint64_t cursorAcceptedInputSeq=0,cursorSessionEpoch=0,cursorLastSequence=0;
 bool desktopOverviewCapabilityKnown=false,desktopOverviewSupported=false;
 bool rateV2Supported=false;int rateTargetKbps=0,rateAppliedKbps=0;std::string rateReason;uint64_t rateRequests=0,rateReplies=0,rateErrors=0;double rateGoodputKbps=0,rateAgeLowerBoundMs=-1;edgelinkwan::ControlReplyMux controlReplyMux;
 std::atomic<uint64_t>desktopOverviewQueued{0},desktopOverviewSent{0};
 std::atomic<uint64_t>cursorPackets{0},cursorRejectedPackets{0},cursorAuthenticatedPackets{0},cursorBytesReceived{0};
 edgetiming::Samples decodeMs,videoQueueMs,decoderBufferWaitMs,receiverBackpressureMs,videoReadyQueueMs,decryptMs;
 edgetiming::Samples encodeMs,hostCaptureCallbackDelayMs,preEncodeDelayMs,senderQueueMs;
 edgetiming::Samples captureAgeAtReceiveMs,sendToReceiveMs,captureToRenderSubmitMs,captureCallbackToRenderSubmitMs,renderSubmitCallMs;
 uint64_t timedFrames=0,legacyFrames=0,invalidTimingFrames=0,renderSubmitFailures=0;
 std::string decoderName;
 bool decoderLowLatencySupported=false,decoderDecodingOrderSupported=false;
 int32_t decoderReportedLowLatency=-1,decoderReportedInputBuffers=-1,decoderReportedOutputBuffers=-1;
 int32_t nativeWindowQueueSize=-1,nativeWindowRequestTimeoutMs=-1;
 uint64_t decoderPendingHighWater=0,tcpDecodeQueueTimeouts=0,decoderInputTimeouts=0;
 uint64_t captureAgeRejected=0,sendAgeRejected=0,renderAgeRejected=0,captureCallbackRenderAgeRejected=0;
 std::atomic<uint64_t>inputCalls{0},inputSent{0},nativeKeyEvents{0};
 bool localUI=false;std::map<std::string,int>heldKeys;std::set<int>heldButtons;
 uint64_t ignoredSystemKeys=0,ignoredModifierRepeats=0;
 std::atomic<uint64_t>received{0},decoded{0},rendered{0},lost{0},clockTicks{0},bytes{0};
 uint64_t lastStats=0,lastReceived=0,lastRendered=0,lastTicks=0;
 int ctrlFD=-1,videoFD=-1,audioFD=-1,micFD=-1,udpFD=-1,networkRequest=-1,audioNetworkRequest=-1,micNetworkRequest=-1;bool udpBridge=false;TLS *control=nullptr;edgelink::ControlStreamOwner controlStreamOwner;
 edgelink::audio::RemoteAudio remoteAudio;
 std::atomic<uint64_t>audioGeneration{0};std::atomic<unsigned>audioWorkers{0};
 std::atomic<uint64_t>audioPackets{0},audioRejected{0},audioGaps{0};
 std::string audioState="idle",audioError,audioStopReason,micState="idle",micError;
 std::atomic<int>audioLastSSLError{0};
 uint64_t audioPrepareStartedNs=0,audioReadySentNs=0,audioReadyAckNs=0;int audioReadinessPhase=0;
 std::atomic<uint64_t>audioHeartbeatsSent{0},audioLastHeartbeatNs{0},audioLastHeartbeatAck{0},audioLastHeartbeatRendered{0};
 std::atomic<uint64_t>micAttemptGeneration{0};std::atomic<bool>microphoneAllowed{false},microphoneSupported{false};std::atomic<uint64_t>micPackets{0},micDropped{0},micPeak{0},micRms{0},micPeakMax{0},micRmsMax{0};
 std::atomic<bool>surfaceAvailable{false};OH_AVCodec*decoder=nullptr;OHNativeWindow*window=nullptr;OH_NativeXComponent*component=nullptr;
 OH_NativeXComponent_Callback surfaceCallbacks{};
 uint32_t sid=0;Bytes key,serverPrefix,clientPrefix;std::string viewerToken;
 uint64_t nextFrame=1,helloID=1,lastIDR=0,udpGapStartedAt=0;bool awaitKey=true;std::map<uint64_t,Assembly>assemblies;std::map<uint64_t,Frame>complete;
 std::atomic<uint64_t>udpDatagrams{0},udpRejectedDatagrams{0},udpAssemblyTimeouts{0},udpRecoveries{0},idrRequests{0},udpHellos{0},udpHelloFailures{0};
 std::atomic<uint64_t>udpLargestDeclaredKeyframeBytes{0},udpCompletedKeyframes{0},udpAwaitKeyDrops{0};
 std::atomic<uint64_t>udpDecodeQueueWaits{0},udpDecodeQueueOverflows{0},udpDecodeQueueDiscardedFrames{0},udpSequenceGaps{0},udpGapTimeouts{0},udpGapOverflows{0};
 uint64_t rtcEpoch=0,rtcMessageID=0;std::string rtcControlLines;edgelinkrtc::SignalAssembler rtcSignals;RtcMediaIngress rtcIngress;std::atomic<bool>rtcActive{false};
 std::atomic<uint64_t>rtcAuthenticatedFrames{0},rtcIngressDropped{0},rtcRenderACKs{0},rtcIDRRequests{0},rtcLastIDR{0};
 static constexpr int rtcRecordBudgetMs=500;
 bool isRTC()const{return options.transport=="rtc"||options.transport=="tailnet-rtc";}
 bool unreliableMedia()const{return isUDP()||isRTC();}
 bool isUDP()const{return options.transport=="udp"||options.transport=="tailnet-udp";}
 bool isTailnet()const{return options.transport=="tailnet"||options.transport=="tailnet-udp"||options.transport=="tailnet-rtc";}
 edgelinksplit::Endpoint endpoint(bool video)const{
  edgelinksplit::Endpoint control{options.host,"",options.port},picture{options.videoHost,"",options.videoPort};
  if(options.splitPath){
   auto c=edgelinksplit::LocalEndpoint(options.host,options.port),v=edgelinksplit::LocalEndpoint(options.videoHost,options.videoPort);
   if(!c||!v||!edgelinksplit::ValidConfiguration(options.mode,options.transport,*c,*v))throw std::runtime_error("分流候选仅允许已配对的 USB 与实际局域网 TCP");
   control=*c;picture=*v;
  }
  return edgelinksplit::ForRole(video?edgelinksplit::Role::Video:edgelinksplit::Role::Control,options.splitPath,control,picture);
 }
 uint64_t assemblyTimeoutNs()const{return isUDP()&&isTailnet()?400000000ULL:50000000ULL;}
 uint64_t udpReorderTimeoutNs()const{return isRTC()?edgelinkrtc::ReorderWaitNs(rtcRecordBudgetMs):isTailnet()?60000000ULL:30000000ULL;}
 uint64_t idrRequestIntervalNs()const{return unreliableMedia()&&isTailnet()?500000000ULL:100000000ULL;}
 // Caller holds ioLock. Remove the bridge before its fd can ever be reused.
 void shutdownDatagramLocked(){if(udpFD>=0){if(udpBridge){NetworkCloseDatagram(udpFD);udpBridge=false;}shutdown(udpFD,SHUT_RDWR);}}
 void closeDatagramLocked(){shutdownDatagramLocked();if(udpFD>=0){close(udpFD);udpFD=-1;}}
 ~Client(){component=nullptr;stop();if(window)OH_NativeWindow_DestroyNativeWindow(window);}
 void setStatus(const std::string&s,const std::string&e=""){std::lock_guard<std::mutex>g(lock);status=s;error=e;}
 void abort(const std::string&message){setStatus("error",message);running=false;EndCursorSession(cursorSessionEpoch);StopAxisObservation();ReleaseCursorLock();changed.notify_all();std::lock_guard<std::mutex>g(ioLock);for(int request:{networkRequest,audioNetworkRequest,micNetworkRequest})NetworkCancel(request);for(int fd:{ctrlFD,videoFD,audioFD,micFD})if(fd>=0)shutdown(fd,SHUT_RDWR);shutdownDatagramLocked();}
 void send(const std::string&s){if(!running||stopRequested)return;std::lock_guard<std::mutex>g(lock);if(!running||stopRequested)return;if(!commands.empty() && s.rfind("MOVE ",0)==0 && commands.back().rfind("MOVE ",0)==0)commands.back()=s;else if(commands.size()<1024)commands.push_back(s);changed.notify_all();}
 // Called on the input service callback thread. Never start/stop observation here.
 void enqueueAxisCommand(const std::string&s){
  std::lock_guard<std::mutex>g(lock);if(!running||stopRequested||localUI)return;
  if(s=="BUTTON 0 0")heldButtons.erase(0);
  if(commands.size()<1024)commands.push_back(s);changed.notify_all();
 }
 void releaseLocked(){
  for(const auto&item:heldKeys)commands.push_back(item.first+" 0");heldKeys.clear();
  for(int b:heldButtons)commands.push_back("BUTTON "+std::to_string(b)+" 0");heldButtons.clear();
  commands.push_back("RELEASE");changed.notify_all();
 }
 bool input(const std::string&s){
  if(s=="BACKGROUND 1"||s=="BACKGROUND 0"){std::lock_guard<std::mutex>g(lock);backgroundRetentionArmed=s=="BACKGROUND 1"&&backgroundRetainSupported&&options.mode=="extend";return true;}
  if(s.rfind("CURSORINACTIVE ",0)==0){
   std::istringstream fields(s);std::string type,extra;int windowId=-1;
   if((fields>>type>>windowId)&&windowId>0&&!(fields>>extra))NotifyCursorWindowInactive(windowId);
   return false;
  }
  if(s.rfind("CURSORLOCK ",0)==0){std::istringstream fields(s);std::string type,extra;int windowId=-1,enabled=-1,follow=1;
   if(!(fields>>type>>windowId>>enabled)||(enabled!=0&&enabled!=1))return false;
   fields>>std::ws;if(!fields.eof() && (!(fields>>follow)||(fields>>extra)||(follow!=0&&follow!=1)))return false;
   if(!enabled){ReleaseCursorLock();return false;}if(windowId<0)return false;
   bool allowed;{std::lock_guard<std::mutex>g(lock);allowed=running&&!stopRequested&&!localUI;}if(!allowed)return false;
   RequestCursorLock(windowId,true,follow==1);
   {std::lock_guard<std::mutex>g(lock);allowed=running&&!stopRequested&&!localUI;}if(!allowed)ReleaseCursorLock();return false;
  }
  if(s.rfind("OBSERVE ",0)==0){int windowId=-1;try{windowId=std::stoi(s.substr(8));}catch(...){return false;}
   if(windowId<0){StopAxisObservation();return false;}if(!running||stopRequested)return false;
   {std::lock_guard<std::mutex>g(lock);if(!running||stopRequested||localUI)return false;}
   StartAxisObservation(windowId,[this](const std::string&command){enqueueAxisCommand(command);});
   bool allowed;{std::lock_guard<std::mutex>g(lock);allowed=running&&!stopRequested&&!localUI;}
   if(!allowed)StopAxisObservation();return false;}
  if(s=="LOCALUI 1"||s=="RELEASE"){StopAxisObservation();ReleaseCursorLock();}
  if(!running||stopRequested)return false;std::lock_guard<std::mutex>g(lock);if(!running||stopRequested)return false;inputCalls++;
  if(s=="LOCALUI 1"){localUI=true;releaseLocked();return true;}
  if(s=="LOCALUI 0"){localUI=false;return true;}
  if(s=="RELEASE"){releaseLocked();return true;}
  if(s.rfind("DESKTOP",0)==0){
   const bool accepted=EnqueueDesktopShortcut(commands,s,running,stopRequested,localUI,heldKeys.size(),heldButtons.size(),
    desktopOverviewCapabilityKnown&&desktopOverviewSupported,options.mode);
   if(accepted){++desktopOverviewQueued;changed.notify_all();}return accepted;
  }
  if(s.rfind("TOPOLOGYACK ",0)==0){
   if(s!="TOPOLOGYACK "+std::to_string(desktopTopologyRevision)||desktopTopologyRevision==0)return false;
   commands.push_back(s);changed.notify_all();return true;
  }
  if(localUI && s.rfind("TEXT ",0)!=0 && s.rfind("OPTION ",0)!=0)return false;
  if(AxisGestureInProgress()&&(s.rfind("BUTTON 0 1",0)==0||s.rfind("MOVE ",0)==0))return false;
  std::istringstream fields(s);std::string type;int code,down;fields>>type;
  if((type=="KEY"||type=="MACKEY") && fields>>code>>down){
   const std::string identity=type+" "+std::to_string(code);
   bool modifier=type=="KEY" ? (code>=2045&&code<=2048)||(code>=2072&&code<=2077) : code>=54&&code<=63;
   if(down){if(heldKeys.count(identity)&&modifier){ignoredModifierRepeats++;return false;}heldKeys[identity]=code;}
   else {if(!heldKeys.erase(identity))return false;}
  }else if(type=="BUTTON" && fields>>code>>down){if(down)heldButtons.insert(code);else heldButtons.erase(code);}
  uint64_t moveSequence=0;std::string wireCommand=s;
  if(type=="MOVE"){
   double x=0,y=0;std::string sequence,extra;
   if(!(fields>>x>>y)||!std::isfinite(x)||!std::isfinite(y))return false;
   if(fields>>sequence){
    if(!cursorCapabilityKnown || sequence.empty() || sequence.size()>16 || sequence.find_first_not_of("0123456789")!=std::string::npos || (fields>>extra))return false;
    try{moveSequence=std::stoull(sequence);}catch(...){return false;}
    if(!moveSequence || moveSequence>9007199254740991ULL || moveSequence<=cursorAcceptedInputSeq)return false;
    if(!cursorChannelSupported){std::ostringstream legacy;legacy.precision(17);legacy<<"MOVE "<<x<<' '<<y;wireCommand=legacy.str();}
   }
  }
  if(!commands.empty() && type=="MOVE" && commands.back().rfind("MOVE ",0)==0)commands.back()=wireCommand;
  else if(commands.size()<1024)commands.push_back(wireCommand);
  else return false;
  if(moveSequence)cursorAcceptedInputSeq=moveSequence;
  changed.notify_all();return true;
 }
 void requestIDR(){
  if(!running)return;const uint64_t now=Now();if(lastIDR&&now-lastIDR<idrRequestIntervalNs())return;
  lastIDR=now;idrRequests++;send("IDR");
 }
 void retryKeyframe(){
  if(!awaitKey)return;
  // Never replace an IDR which is still being assembled merely because a P
  // frame arrived behind it. Its normal assembly deadline controls recovery.
  for(const auto&item:assemblies)if(item.second.flags&1)return;
  requestIDR();
 }
 void recover(){udpRecoveries++;awaitKey=true;udpGapStartedAt=0;complete.clear();assemblies.clear();requestIDR();}
 void expireReorderGap(){
  if(udpGapStartedAt && Now()-udpGapStartedAt>=udpReorderTimeoutNs()){
   udpGapTimeouts++;udpSequenceGaps++;lost++;recover();
  }
 }
 int receiveDatagram(int fd,Bytes&packet){
  // A gap gets one fixed deadline, including when no more packets arrive.
  // The normal path retains its existing 200ms socket timeout and no new timer.
  expireReorderGap();
  if(!udpGapStartedAt)return int(recv(fd,packet.data(),packet.size(),0));
  while(running){
   expireReorderGap();
   if(!udpGapStartedAt){errno=EAGAIN;return -1;}
   const int n=int(recv(fd,packet.data(),packet.size(),MSG_DONTWAIT));
   if(n>=0 || (errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR))return n;
   if(errno==EINTR)continue;
   const uint64_t age=Now()-udpGapStartedAt,limit=udpReorderTimeoutNs();
   if(age>=limit)continue;
   pollfd descriptor{fd,POLLIN,0};
   const int timeoutMs=int((limit-age+999999ULL)/1000000ULL);
   if(poll(&descriptor,1,timeoutMs)<0 && errno!=EINTR)return -1;
  }
  // stop() writes STOP before clearing running and shutting down this socket;
  // stopRequested alone must not terminate the reader ahead of that write.
  errno=ECANCELED;return -1;
 }
 void expireAssemblies(){
  const uint64_t now=Now();for(const auto&item:assemblies)if(now-item.second.created>assemblyTimeoutNs()){
   udpAssemblyTimeouts++;lost++;recover();return;
  }
 }
 bool admitDatagram(uint8_t flags,uint32_t total){
  if(flags&1){if(total>udpLargestDeclaredKeyframeBytes)udpLargestDeclaredKeyframeBytes=total;return true;}
  if(!awaitKey)return true;
  udpAwaitKeyDrops++;expireAssemblies();retryKeyframe();return false;
 }
 static bool NativeKey(OH_NativeXComponent*component,void*){
  auto&client=Instance();if(!client.running||client.stopRequested)return false;
  OH_NativeXComponent_KeyEvent*event=nullptr;
  OH_NativeXComponent_KeyAction action=OH_NATIVEXCOMPONENT_KEY_ACTION_UNKNOWN;
  OH_NativeXComponent_KeyCode code;
  if(OH_NativeXComponent_GetKeyEvent(component,&event)!=OH_NATIVEXCOMPONENT_RESULT_SUCCESS||!event||
   OH_NativeXComponent_GetKeyEventAction(event,&action)!=OH_NATIVEXCOMPONENT_RESULT_SUCCESS||
   OH_NativeXComponent_GetKeyEventCode(event,&code)!=OH_NATIVEXCOMPONENT_RESULT_SUCCESS||
   (action!=OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN&&action!=OH_NATIVEXCOMPONENT_KEY_ACTION_UP))return false;
  if(int(code)<2000){std::lock_guard<std::mutex>g(client.lock);client.ignoredSystemKeys++;return false;}
  {std::lock_guard<std::mutex>g(client.lock);if(client.localUI)return false;}
  client.nativeKeyEvents++;
  client.input("KEY "+std::to_string(int(code))+" "+(action==OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN?"1":"0"));return true;
 }
 static void FrameClock(OH_NativeXComponent*c,uint64_t,uint64_t){auto&client=Instance();if(client.running && client.component==c)client.clockTicks++;}
 static void SurfaceCreated(OH_NativeXComponent*c,void*w){
  auto&client=Instance();std::lock_guard<std::recursive_mutex>lifecycle(client.lifecycleLock);client.component=c;
  // Surface recreation does not necessarily rerun ArkUI onLoad. Reacquire an
  // owned window from the new surface; never reuse the destroyed decoder target.
  if(!client.window&&w){uint64_t id=0;if(OH_NativeWindow_GetSurfaceId(static_cast<OHNativeWindow*>(w),&id)==0)OH_NativeWindow_CreateNativeWindowFromSurfaceId(id,&client.window);}
  client.surfaceAvailable=client.window!=nullptr;
 }
 static void SurfaceChanged(OH_NativeXComponent*,void*){}
 static void SurfaceDestroyed(OH_NativeXComponent*c,void*){
  auto&client=Instance();std::lock_guard<std::recursive_mutex>lifecycle(client.lifecycleLock);if(client.component!=c)return;client.surfaceAvailable=false;
  // The framework is removing this object: no subsequent stop may dereference it.
  bool park=false;{std::lock_guard<std::mutex>g(client.lock);park=client.backgroundRetentionArmed;}
  client.component=nullptr;client.stop(park?"background_suspend":"surface_destroyed");
  if(client.window){OH_NativeWindow_DestroyNativeWindow(client.window);client.window=nullptr;}
 }
 static void NativeTouch(OH_NativeXComponent*,void*){}
 static void NativeAxis(OH_NativeXComponent*c,ArkUI_UIInputEvent*event,ArkUI_UIInputEvent_Type type){
  auto&client=Instance();if(client.component!=c||!event||type!=ARKUI_UIINPUTEVENT_TYPE_AXIS)return;
  LocalAxisSample e;e.source=OH_ArkUI_UIInputEvent_GetSourceType(event);e.tool=OH_ArkUI_UIInputEvent_GetToolType(event);
  e.supportedSource=e.source!=UI_INPUT_EVENT_SOURCE_TYPE_TOUCH_SCREEN &&
   (e.source==UI_INPUT_EVENT_SOURCE_TYPE_MOUSE||e.tool==UI_INPUT_EVENT_TOOL_TYPE_MOUSE||e.tool==UI_INPUT_EVENT_TOOL_TYPE_TOUCHPAD);
  e.action=OH_ArkUI_AxisEvent_GetAxisAction(event);
  e.hasHorizontal=OH_ArkUI_AxisEvent_HasAxis(event,UI_AXIS_TYPE_HORIZONTAL_AXIS);
  e.hasVertical=OH_ArkUI_AxisEvent_HasAxis(event,UI_AXIS_TYPE_VERTICAL_AXIS);
  e.hasPinch=OH_ArkUI_AxisEvent_HasAxis(event,UI_AXIS_TYPE_PINCH_AXIS);
  e.x=OH_ArkUI_AxisEvent_GetHorizontalAxisValue(event);e.y=OH_ArkUI_AxisEvent_GetVerticalAxisValue(event);e.scale=OH_ArkUI_AxisEvent_GetPinchAxisScaleValue(event);
  HandleLocalAxisEvent(e);
 }

 void attachComponent(OH_NativeXComponent*c){
  component=c;surfaceCallbacks={SurfaceCreated,SurfaceChanged,SurfaceDestroyed,NativeTouch};
  OH_NativeXComponent_RegisterCallback(c,&surfaceCallbacks);
  OH_NativeXComponent_RegisterKeyEventCallbackWithResult(c,NativeKey);
  SetLocalAxisRegistrationResult(OH_NativeXComponent_RegisterUIInputEventCallback(c,NativeAxis,ARKUI_UIINPUTEVENT_TYPE_AXIS));
 }
 static Client&Instance(){static Client client;return client;}
 // Snapshot the owner under ioLock, then start its fixed drain deadline without
 // holding a Client lock. The Go ABI returns immediately and pins fd + epoch.
 void requestControlDrain(){
  edgelink::ControlStreamOwner::Snapshot owner;
  {std::lock_guard<std::mutex>g(ioLock);owner=controlStreamOwner.ForDescriptor(ctrlFD);}
  if(!owner)return;
  const bool accepted=NetworkDrainStream(owner.fd,owner.epoch,1000)==0;
  {std::lock_guard<std::mutex>g(lock);stopProxyDrainAttempted=true;stopProxyDrainRequested=stopProxyDrainRequested||accepted;}
 }
 void stop(const std::string&reason="internal"){
  // start() calls stop() while holding this recursive lifecycle lock. Neither
  // run() nor transmit() acquires it, so joining their threads cannot invert it.
  std::lock_guard<std::recursive_mutex>lifecycle(lifecycleLock);
  bool graceful=false;
  {std::lock_guard<std::mutex>g(lock);lastStopReason=reason;
   graceful=running&&controlWriterReady&&!stopControlWriteCompleted;}
  if(graceful)requestControlDrain(); // Start before publishing final STOP to the writer.
  {std::lock_guard<std::mutex>g(lock);stopRequested=true;commands.clear();}
  EndCursorSession(cursorSessionEpoch);EndRtcOwner(rtcEpoch);rtcActive=false;
  StopAxisObservation();
  ReleaseCursorLock();changed.notify_all();
  if(graceful){std::unique_lock<std::mutex>g(lock);
   if(!changed.wait_for(g,std::chrono::milliseconds(120),[this]{return stopControlWriteCompleted||!controlWriterReady||!running;}))stopControlTimedOut=true;}
  running=false;remoteAudio.retireCallbacks(audioGeneration.load());ReleaseCursorLock();changed.notify_all();
  if(component){OH_NativeXComponent_UnregisterOnFrameCallback(component);OH_NativeXComponent_ExpectedRateRange range={0,60,30};OH_NativeXComponent_SetExpectedFrameRateRange(component,&range);}
  {std::lock_guard<std::mutex>g(ioLock);for(int request:{networkRequest,audioNetworkRequest,micNetworkRequest})NetworkCancel(request);for(int fd:{ctrlFD,videoFD,audioFD,micFD})if(fd>=0)shutdown(fd,SHUT_RDWR);shutdownDatagramLocked();}
  if(worker.joinable() && worker.get_id()!=std::this_thread::get_id())worker.join();
  std::lock_guard<std::mutex>g(lock);frames.clear();commands.clear();times.clear();heldKeys.clear();heldButtons.clear();localUI=false;desktopTopology={};desktopTopologyRevision=0;desktopOverviewCapabilityKnown=false;desktopOverviewSupported=false;if(status!="error")status="idle";
 }
 void start(Options o){
  if(!edgelinkstore::Allowed(o.host,o.port,o.mode,o.transport)){stop("store_scope_rejected");setStatus("error","上架版仅允许已配对的局域网扩展屏");return;}
  std::lock_guard<std::recursive_mutex>lifecycle(lifecycleLock);
  stop();if(!window){setStatus("error","显示 Surface 尚未就绪");return;}
  rtcEpoch=BeginRtcOwner();rtcMessageID=0;rtcControlLines.clear();rtcSignals.reset();rtcActive=false;rtcAuthenticatedFrames=rtcIngressDropped=rtcRenderACKs=rtcIDRRequests=rtcLastIDR=0;
  audioGeneration++;{std::lock_guard<std::mutex>g(lock);audioStopReason.clear();audioPrepareStartedNs=audioReadySentNs=audioReadyAckNs=0;audioReadinessPhase=0;}audioLastSSLError=0;audioHeartbeatsSent=audioLastHeartbeatNs=audioLastHeartbeatAck=audioLastHeartbeatRendered=0;microphoneAllowed=false;microphoneSupported=false;micPackets=micDropped=micPeak=micRms=micPeakMax=micRmsMax=0;setMicStatus("idle");setAudioStatus("idle");audioPackets=audioRejected=audioGaps=0;
  options=std::move(o);backgroundRetentionArmed=false;backgroundRetainSupported=false;localHandoverSupported=false;rateV2Supported=false;rateTargetKbps=rateAppliedKbps=0;rateReason="waiting";rateRequests=rateReplies=rateErrors=0;rateGoodputKbps=0;rateAgeLowerBoundMs=-1;controlReplyMux.Reset();inputCalls=inputSent=nativeKeyEvents=0;lastStopReason="";received=decoded=rendered=lost=clockTicks=bytes=0;lastStats=Now();lastReceived=lastRendered=lastTicks=0;nextFrame=1;helloID=1;lastIDR=0;udpGapStartedAt=0;awaitKey=true;assemblies.clear();complete.clear();
  udpDatagrams=udpRejectedDatagrams=udpAssemblyTimeouts=udpRecoveries=idrRequests=udpHellos=udpHelloFailures=0;
  udpLargestDeclaredKeyframeBytes=udpCompletedKeyframes=udpAwaitKeyDrops=0;
  udpDecodeQueueWaits=udpDecodeQueueOverflows=udpDecodeQueueDiscardedFrames=udpSequenceGaps=udpGapTimeouts=udpGapOverflows=0;
  {std::lock_guard<std::mutex>g(lock);stopRequested=false;controlWriterReady=stopControlWriteAttempted=stopControlWritten=stopControlWriteCompleted=stopControlTimedOut=false;stopProxyDrainAttempted=stopProxyDrainRequested=false;clockSync={};timingNegotiated=false;decodeMs={};videoQueueMs={};decoderBufferWaitMs={};receiverBackpressureMs={};videoReadyQueueMs={};decryptMs={};encodeMs={};hostCaptureCallbackDelayMs={};preEncodeDelayMs={};senderQueueMs={};captureAgeAtReceiveMs={};sendToReceiveMs={};captureToRenderSubmitMs={};captureCallbackToRenderSubmitMs={};renderSubmitCallMs={};timedFrames=legacyFrames=invalidTimingFrames=renderSubmitFailures=captureAgeRejected=sendAgeRejected=renderAgeRejected=captureCallbackRenderAgeRejected=0;}
  {std::lock_guard<std::mutex>g(lock);decoderName.clear();decoderLowLatencySupported=decoderDecodingOrderSupported=false;decoderReportedLowLatency=decoderReportedInputBuffers=decoderReportedOutputBuffers=nativeWindowQueueSize=nativeWindowRequestTimeoutMs=-1;decoderPendingHighWater=tcpDecodeQueueTimeouts=decoderInputTimeouts=0;}
  {std::lock_guard<std::mutex>g(lock);++timingSessionEpoch;clockSyncRefreshes=0;}
  clockRefreshProbes=clockRefreshAccepted=clockRefreshTimeouts=clockRefreshRejected=clockRefreshOverlong=0;
  cursorPackets=cursorRejectedPackets=cursorAuthenticatedPackets=cursorBytesReceived=0;cursorLastSequence=0;
  {std::lock_guard<std::mutex>g(lock);cursorChannelSupported=false;cursorCapabilityKnown=false;cursorAcceptedInputSeq=0;
   desktopOverviewCapabilityKnown=false;desktopOverviewSupported=false;desktopOverviewQueued=desktopOverviewSent=0;}
  cursorSessionEpoch=BeginCursorSession();
  setStatus("connecting");running=true;
  if(component){OH_NativeXComponent_ExpectedRateRange range={options.fps,options.fps,options.fps};OH_NativeXComponent_SetExpectedFrameRateRange(component,&range);OH_NativeXComponent_RegisterOnFrameCallback(component,FrameClock);}
  worker=std::thread([this]{run();});
 }
 std::unique_ptr<TLS> connectTLS(bool video,int audio=0){
  const auto target=endpoint(video);
  if(options.splitPath&&!edgelinkavailability::CanUseVerifiedLocalPath(target.route,target.host,48562,options.token,options.certificate))throw std::runtime_error("本地分流路径认证已过期，请重新准备连接");
  auto c=std::make_unique<TLS>();
  c->onClosing=[this,video,audio](int fd,uint64_t epoch){std::lock_guard<std::mutex>g(ioLock);int&registered=audio==2?micFD:(audio==1?audioFD:(video?videoFD:ctrlFD));if(!video&&audio==0){if(controlStreamOwner.Release(fd,epoch)&&registered==fd)registered=-1;}else if(registered==fd)registered=-1;};
  if(isTailnet()){
   int request;{std::lock_guard<std::mutex>g(ioLock);if(!running)throw std::runtime_error("会话已取消");(audio==2?micNetworkRequest:(audio==1?audioNetworkRequest:networkRequest))=request=NetworkNewRequest();}
   if(request<0)throw std::runtime_error("请先登录互联网连接服务");
   int fd=NetworkDial(target.host,target.port,request);
   c->streamEpoch=fd>=0?NetworkStreamEpoch(fd):0;
   {std::lock_guard<std::mutex>g(ioLock);(audio==2?micNetworkRequest:(audio==1?audioNetworkRequest:networkRequest))=-1;if(!running){if(fd>=0)close(fd);throw std::runtime_error("会话已取消");}if(fd>=0){(audio==2?micFD:(audio==1?audioFD:(video?videoFD:ctrlFD)))=fd;if(!video&&audio==0)controlStreamOwner.Bind(fd,c->streamEpoch);}}
   if(fd<0)throw std::runtime_error("互联网连接超时或 Mac 离线");c->fd=fd;
  }else{
  addrinfo hints{};hints.ai_socktype=SOCK_STREAM;hints.ai_family=AF_UNSPEC;hints.ai_flags=options.splitPath?AI_NUMERICHOST:0;addrinfo*addresses=nullptr;
  if(getaddrinfo(target.host.c_str(),std::to_string(target.port).c_str(),&hints,&addresses)!=0)throw std::runtime_error("无法解析 Mac 地址");
  for(auto a=addresses;a&&running;a=a->ai_next){
   int fd=socket(a->ai_family,SOCK_STREAM,0);if(fd<0)continue;
   {std::lock_guard<std::mutex>g(ioLock);if(!running){close(fd);break;}(audio==2?micFD:(audio==1?audioFD:(video?videoFD:ctrlFD)))=fd;if(!video&&audio==0)controlStreamOwner.Bind(fd,0);}
   int flags=fcntl(fd,F_GETFL,0);fcntl(fd,F_SETFL,flags|O_NONBLOCK);
   int r=connect(fd,a->ai_addr,a->ai_addrlen);
   if(r<0 && errno==EINPROGRESS){pollfd p{fd,POLLOUT,0};r=poll(&p,1,5000);int e=0;socklen_t length=sizeof(e);if(r>0 && getsockopt(fd,SOL_SOCKET,SO_ERROR,&e,&length)==0 && e==0)r=0;else r=-1;}
   fcntl(fd,F_SETFL,flags);
   if(r==0){c->fd=fd;break;}
   {std::lock_guard<std::mutex>g(ioLock);(audio==2?micFD:(audio==1?audioFD:(video?videoFD:ctrlFD)))=-1;close(fd);}
  }
  freeaddrinfo(addresses);if(c->fd<0)throw std::runtime_error("Mac 连接失败：检查地址、同一局域网或 USB 转发");
  }
  timeval timeout{isTailnet()?15:5,0};setsockopt(c->fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(c->fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));int yes=1;setsockopt(c->fd,IPPROTO_TCP,TCP_NODELAY,&yes,sizeof(yes));
  c->ctx=SSL_CTX_new(TLS_client_method());if(!c->ctx)throw std::runtime_error("TLS 初始化失败");SSL_CTX_set_min_proto_version(c->ctx,TLS1_2_VERSION);SSL_CTX_set_verify(c->ctx,SSL_VERIFY_PEER,nullptr);
  BIO*bio=BIO_new_mem_buf(options.certificate.data(),int(options.certificate.size()));X509*trusted=PEM_read_bio_X509(bio,nullptr,nullptr,nullptr);BIO_free(bio);
  if(!trusted)throw std::runtime_error("配对证书无效");X509_STORE_add_cert(SSL_CTX_get_cert_store(c->ctx),trusted);
  c->ssl=SSL_new(c->ctx);SSL_set_fd(c->ssl,c->fd);
  const int handshake=SSL_connect(c->ssl);
  if(handshake!=1){const long verify=SSL_get_verify_result(c->ssl);const int sslError=SSL_get_error(c->ssl,handshake);const unsigned long detail=ERR_get_error();char reason[256]={};if(detail)ERR_error_string_n(detail,reason,sizeof(reason));X509_free(trusted);if(verify!=X509_V_OK)throw std::runtime_error("Mac 证书认证失败："+std::string(X509_verify_cert_error_string(verify)));throw std::runtime_error("TLS 握手未完成，请重试（"+std::to_string(sslError)+"/"+std::to_string(errno)+"）"+reason);}
  X509*actual=SSL_get1_peer_certificate(c->ssl);bool exact=actual && X509_cmp(trusted,actual)==0;X509_free(actual);X509_free(trusted);if(!exact)throw std::runtime_error("Mac 身份与本机配对证书不一致");
  return c;
 }
 static void Write(TLS*c,const std::string&s){const char*p=s.data();size_t left=s.size();while(left){int n=SSL_write(c->ssl,p,int(left));if(n<=0)throw std::runtime_error("控制连接已断开");p+=n;left-=n;}}
 std::unique_ptr<TLS> connectWithRetry(bool video,int audio=0){
  const int attempts=isTailnet()?3:1;
  for(int attempt=0;attempt<attempts;attempt++){
   try{return connectTLS(video,audio);}catch(const std::exception&e){
    const std::string message=e.what();
    if(!running||attempt+1==attempts||message.find("证书")!=std::string::npos||message.find("身份")!=std::string::npos)throw;
    std::unique_lock<std::mutex>g(lock);changed.wait_for(g,std::chrono::milliseconds(600),[this]{return !running;});
   }
  }
  throw std::runtime_error("互联网连接尚未就绪");
 }
 static bool Read(TLS*c,uint8_t*p,size_t length){while(length){int n=SSL_read(c->ssl,p,int(length));if(n<=0)return false;p+=n;length-=n;}return true;}
 // Used only during the serial control handshake, before transmit() exists.
 // A late/absent TIME reply must not hold startup for the regular 15 s timeout.
 static bool ReadLineUntil(TLS*c,std::string&line,uint64_t deadline){
  const int previous=fcntl(c->fd,F_GETFL,0);if(previous<0||fcntl(c->fd,F_SETFL,previous|O_NONBLOCK)<0)return false;
  struct RestoreFlags{int fd,flags;~RestoreFlags(){fcntl(fd,F_SETFL,flags);}}restore{c->fd,previous};
  line.clear();while(line.size()<256){
   const uint64_t now=Now();if(now>=deadline)return false;
   uint8_t ch=0;int n=SSL_read(c->ssl,&ch,1);if(n==1){if(ch=='\n')return true;line+=char(ch);continue;}
   int e=SSL_get_error(c->ssl,n);if(e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE)return false;
   pollfd p{c->fd,short(e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT),0};
   const uint64_t afterRead=Now();if(afterRead>=deadline)return false;
   const int timeout=int(std::min<uint64_t>(1000,(deadline-afterRead+999999)/1000000));
   int ready=poll(&p,1,timeout);if(ready<0&&errno==EINTR)continue;
   if(ready==0)continue;
   if(ready<0||(p.revents&(POLLERR|POLLHUP|POLLNVAL)))return false;
  }return false;
 }
 void calibrateClock(){
  edgetiming::ClockSync candidate;
  for(int sample=0;sample<5&&running;++sample){
   const uint64_t t0=Now();Write(control,"TIME "+std::to_string(t0)+"\n");
   std::string line;if(!ReadLineUntil(control,line,t0+1000000000ULL))break;
   const uint64_t t3=Now();uint64_t t1=0,t2=0;
   if(edgetiming::ParseTimeReply(line,t0,t1,t2))candidate.Add(t0,t1,t2,t3);
  }
  std::lock_guard<std::mutex>g(lock);clockSync=candidate;
 }
 // Only transmit() calls this after handshake: no concurrent SSL_read/write
 // against the same object. A bounded nonblocking pump cannot await a TIME
 // reply, even when a peer sends a partial line and then stops responding.
 bool pumpClockReplies(edgetiming::ClockRefresh&refresh){
  if(!running||stopRequested)return true;
  const int previous=fcntl(control->fd,F_GETFL,0);
  if(previous<0||fcntl(control->fd,F_SETFL,previous|O_NONBLOCK)<0)return false;
  struct RestoreFlags{int fd,flags;~RestoreFlags(){fcntl(fd,F_SETFL,flags);}}restore{control->fd,previous};
  char buffer[2048];size_t budget=isRTC()?16384:512;unsigned calls=0;
  while(budget && calls++<8 && running && !stopRequested){
   const int n=SSL_read(control->ssl,buffer,int(std::min(budget,sizeof(buffer))));
   if(n>0){const auto consumeLegacy=[&](const char*bytes,size_t length){controlReplyMux.Consume(bytes,length,[this](bool success,int kbps){
     std::lock_guard<std::mutex>g(lock);if(!rateV2Supported)return;
     if(success){rateAppliedKbps=kbps;++rateReplies;}
     else{++rateErrors;if(kbps==rateTargetKbps){rateV2Supported=false;rateReason="host_rate_update_failed";}}
    },[this,&refresh](const std::string&line){if(line=="SESSION ENDED\n"){{std::lock_guard<std::mutex>g(lock);lastStopReason="mac_end";}abort("Mac 已结束会话");return;}refresh.Consume(line.data(),line.size(),Now());});};
    if(isRTC()){
     rtcControlLines.append(buffer,size_t(n));size_t end;while((end=rtcControlLines.find('\n'))!=std::string::npos){auto line=rtcControlLines.substr(0,end);rtcControlLines.erase(0,end+1);
      if(line.rfind("RTC ERROR",0)==0)throw std::runtime_error("实时视频通道未建立");
      const auto accepted=rtcSignals.consume(line,viewerToken,Now(),[this](char kind,const std::string&body){if(!PublishRtcEvent(rtcEpoch,viewerToken,kind=='C'?"config":"signal",body))throw std::runtime_error("实时视频前台桥接不可用");});
      if(accepted<0)throw std::runtime_error("实时视频信令格式无效");if(!accepted){line+='\n';consumeLegacy(line.data(),line.size());}
     }if(rtcControlLines.size()>8191)throw std::runtime_error("实时视频控制行过长");rtcSignals.expire(Now());if(rtcSignals.expired)throw std::runtime_error("实时视频信令重组超时");
    }else consumeLegacy(buffer,size_t(n));budget-=size_t(n);continue;}
   const int e=SSL_get_error(control->ssl,n);
   if(e==SSL_ERROR_WANT_READ||e==SSL_ERROR_WANT_WRITE)return true;
   if(e==SSL_ERROR_SYSCALL&&errno==EINTR)continue;
   return false;
  }
  return true;
 }
 void applyClockRefresh(const edgetiming::ClockSync&candidate,uint64_t epoch){
  std::lock_guard<std::mutex>g(lock);
  if(!running||stopRequested||!timingNegotiated||epoch!=timingSessionEpoch)return;
  clockSync=candidate;++clockSyncRefreshes;
  // Samples calculated with different offsets must not share a percentile
  // window. Preserve the cumulative accepted counts but restart these windows.
  captureAgeAtReceiveMs.values.clear();sendToReceiveMs.values.clear();captureToRenderSubmitMs.values.clear();captureCallbackToRenderSubmitMs.values.clear();
 }
 Bytes header(uint64_t id,uint32_t total,uint8_t flags,uint8_t type){Bytes h={'E','D','L','1'};PutBE(h,sid,4);PutBE(h,id,8);PutBE(h,0,2);PutBE(h,1,2);PutBE(h,total,4);h.push_back(flags);h.push_back(type);PutBE(h,0,2);return h;}
 Bytes aad(const uint8_t*h){Bytes a(h+4,h+16);a.insert(a.end(),h+20,h+28);return a;}
 Bytes nonce(const Bytes&prefix,uint64_t id){Bytes n=prefix;PutBE(n,id,8);return n;}
 bool decrypt(const Bytes&body,const Bytes&h,Bytes&plain){
  if(body.size()<16)return false;auto iv=nonce(serverPrefix,ReadBE(h.data()+8,8));auto auth=aad(h.data());EVP_CIPHER_CTX*c=EVP_CIPHER_CTX_new();int n=0,total=0;plain.resize(body.size()-16);
  bool ok=EVP_DecryptInit_ex(c,EVP_aes_128_gcm(),nullptr,key.data(),iv.data())==1;
  ok=ok&&EVP_DecryptUpdate(c,nullptr,&n,auth.data(),int(auth.size()))==1;
  ok=ok&&EVP_DecryptUpdate(c,plain.data(),&n,body.data(),int(body.size()-16))==1;total=n;
  ok=ok&&EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_SET_TAG,16,const_cast<uint8_t*>(body.data()+body.size()-16))==1;
  ok=ok&&EVP_DecryptFinal_ex(c,plain.data()+total,&n)==1;total+=n;EVP_CIPHER_CTX_free(c);if(ok)plain.resize(total);return ok;
 }
 void hello(){auto h=header(helloID++,21,0,1);auto iv=nonce(clientPrefix,ReadBE(h.data()+8,8));auto auth=aad(h.data());EVP_CIPHER_CTX*c=EVP_CIPHER_CTX_new();int n=0,total=0;Bytes cipher(21);
  EVP_EncryptInit_ex(c,EVP_aes_128_gcm(),nullptr,key.data(),iv.data());EVP_EncryptUpdate(c,nullptr,&n,auth.data(),int(auth.size()));EVP_EncryptUpdate(c,cipher.data(),&n,reinterpret_cast<const uint8_t*>("hello"),5);total=n;EVP_EncryptFinal_ex(c,cipher.data()+total,&n);EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_GET_TAG,16,cipher.data()+5);EVP_CIPHER_CTX_free(c);h.insert(h.end(),cipher.begin(),cipher.end());if(::send(udpFD,h.data(),h.size(),0)==ssize_t(h.size()))udpHellos++;else udpHelloFailures++;
 }
 void readDecoderDescription(){
  int32_t low=-1,inputs=-1,outputs=-1,queue=-1,timeout=-1;
  auto format=OH_VideoDecoder_GetOutputDescription(decoder);
  if(format){OH_AVFormat_GetIntValue(format,OH_MD_KEY_VIDEO_ENABLE_LOW_LATENCY,&low);
   OH_AVFormat_GetIntValue(format,OH_MD_MAX_INPUT_BUFFER_COUNT,&inputs);
   OH_AVFormat_GetIntValue(format,OH_MD_MAX_OUTPUT_BUFFER_COUNT,&outputs);OH_AVFormat_Destroy(format);}
  OH_NativeWindow_NativeWindowHandleOpt(window,GET_BUFFERQUEUE_SIZE,&queue);OH_NativeWindow_NativeWindowHandleOpt(window,GET_TIMEOUT,&timeout);
  std::lock_guard<std::mutex>g(lock);decoderReportedLowLatency=low;decoderReportedInputBuffers=inputs;decoderReportedOutputBuffers=outputs;nativeWindowQueueSize=queue;nativeWindowRequestTimeoutMs=timeout;
 }
 std::string storeCodec="avc";
 void createDecoder(){
  auto cap=OH_AVCodec_GetCapabilityByCategory(storeCodec=="hevc"?"video/hevc":"video/avc",false,HARDWARE);if(!cap)throw std::runtime_error("硬件解码器不可用");decoder=OH_VideoDecoder_CreateByName(OH_AVCapability_GetName(cap));if(!decoder)throw std::runtime_error("解码器创建失败");
  const char*name=OH_AVCapability_GetName(cap);const bool low=OH_AVCapability_IsFeatureSupported(cap,VIDEO_LOW_LATENCY),ordered=OH_AVCapability_IsFeatureSupported(cap,VIDEO_DECODER_OUTPUT_IN_DECODING_ORDER);
  {std::lock_guard<std::mutex>g(lock);decoderName=name?name:"";decoderLowLatencySupported=low;decoderDecodingOrderSupported=ordered;}
  auto f=OH_AVFormat_Create();OH_AVFormat_SetIntValue(f,OH_MD_KEY_WIDTH,options.width);OH_AVFormat_SetIntValue(f,OH_MD_KEY_HEIGHT,options.height);OH_AVFormat_SetDoubleValue(f,OH_MD_KEY_FRAME_RATE,options.fps);OH_AVFormat_SetIntValue(f,OH_MD_KEY_VIDEO_ENABLE_LOW_LATENCY,1);OH_AVFormat_SetIntValue(f,OH_MD_KEY_ENABLE_SYNC_MODE,1);OH_AVFormat_SetIntValue(f,OH_MD_KEY_MAX_INPUT_SIZE,4*1024*1024);
  auto r=OH_VideoDecoder_Configure(decoder,f);OH_AVFormat_Destroy(f);if(r!=AV_ERR_OK)throw std::runtime_error("解码器配置失败 "+std::to_string(r));OH_NativeWindow_NativeWindowSetScalingModeV2(window,OH_SCALING_MODE_SCALE_TO_WINDOW_V2);if(OH_VideoDecoder_SetSurface(decoder,window)!=AV_ERR_OK)throw std::runtime_error("视频 Surface 设置失败");if(OH_VideoDecoder_Prepare(decoder)!=AV_ERR_OK || OH_VideoDecoder_Start(decoder)!=AV_ERR_OK)throw std::runtime_error("解码器启动失败");
  readDecoderDescription();
 }
 void enqueue(uint64_t id,uint8_t flags,Bytes body,uint64_t receivedAt){
  if(!running||stopRequested)return;
  Frame f;f.id=id;f.key=(flags&1)!=0;f.receivedAt=receivedAt;
  const uint64_t decryptedAt=Now();size_t payloadOffset=0;
  if(!edgetiming::ParseFrameTiming(body,flags,f.timing,payloadOffset)){
   {std::lock_guard<std::mutex>g(lock);++invalidTimingFrames;}
   if(unreliableMedia()){lost++;recover();}else abort("视频计时元数据无效");return;
  }
  if(payloadOffset)body.erase(body.begin(),body.begin()+payloadOffset);
  f.data=std::move(body);f.assembled=Now();
  {std::lock_guard<std::mutex>g(lock);decryptMs.Add(double(decryptedAt-receivedAt)/1e6);
   if(f.timing.timed){++timedFrames;const auto&t=f.timing;
    encodeMs.Add(double(t.encodeDone-t.encodeStart)/1e6);
    preEncodeDelayMs.Add(double(t.encodeStart-t.captureCallback)/1e6);
    senderQueueMs.Add(double(t.sendStart-t.encodeDone)/1e6);
    double age=0;if(clockSync.AgeMs(t.sendStart,receivedAt,age))sendToReceiveMs.Add(age);else ++sendAgeRejected;
    if(t.sourceValid){hostCaptureCallbackDelayMs.Add(double(t.captureCallback-t.sourceCapture)/1e6);
     if(clockSync.AgeMs(t.sourceCapture,receivedAt,age))captureAgeAtReceiveMs.Add(age);else ++captureAgeRejected;
    }
   }else ++legacyFrames;
  }
  // Preserve TCP's reference chain. A stalled decoder must not retain a receive
  // worker indefinitely; End cancels this wait before its graceful STOP write.
  if(!unreliableMedia()){
   std::unique_lock<std::mutex>g(lock);
   if(!changed.wait_for(g,std::chrono::milliseconds(500),[this]{return !running||stopRequested||frames.size()<1;})){
    ++tcpDecodeQueueTimeouts;g.unlock();abort("视频解码排队超时，请重新连接");return;
   }
   if(!running||stopRequested)return;f.enqueuedAt=Now();received++;frames.push_back(std::move(f));changed.notify_all();return;
  }
  expireReorderGap();
  if(awaitKey && !f.key)return;if(id<nextFrame)return;
  if(f.key){
   // enqueue is reached only after the complete frame passes GCM; timing has
   // also passed above. Unauthenticated fragment flags cannot advance the chain.
   udpCompletedKeyframes++;awaitKey=false;udpGapStartedAt=0;complete.clear();nextFrame=id;
   for(auto i=assemblies.begin();i!=assemblies.end()&&i->first<=id;)i=assemblies.erase(i);
  }
  bool immediate=id==nextFrame;
  if(!immediate){
   if(complete.count(id))return;
   size_t retainedBytes=0;for(const auto&item:complete)retainedBytes+=item.second.data.size();
   if(complete.size()>=4 || f.data.size()>4*1024*1024-retainedBytes){
    udpGapOverflows++;udpSequenceGaps++;lost++;recover();return;
   }
   complete.emplace(id,std::move(f));
   if(!udpGapStartedAt)udpGapStartedAt=Now();
  }
  // An expected frame bypasses the reorder map, so four retained successors
  // never transiently become five. The decoder queue still has its own limit.
  while(immediate || complete.count(nextFrame)){
   Frame ready;
   if(immediate){ready=std::move(f);immediate=false;}
   else {ready=std::move(complete[nextFrame]);complete.erase(nextFrame);}
   nextFrame++;received++;
   bool overflow=false;
   {std::unique_lock<std::mutex>g(lock);
    // A paced IDR can be followed by several complete P frames in a burst.
    // Preserve that reference chain while the feeder drains the same bounded
    // three-frame queue; a brief scheduling delay is not network packet loss.
    if(frames.size()>=3){udpDecodeQueueWaits++;
     if(!changed.wait_for(g,std::chrono::milliseconds(25),[this]{return !running||stopRequested||frames.size()<3;})){
      udpDecodeQueueOverflows++;udpDecodeQueueDiscardedFrames+=frames.size()+1;frames.clear();lost++;overflow=true;
     }
    }
    if(!running||stopRequested)return;
    if(!overflow){ready.enqueuedAt=Now();frames.push_back(std::move(ready));}changed.notify_all();}
   if(overflow){recover();return;}
  }
  // Keep the first gap's age while any successor remains held, even when
  // nextFrame advances or a newer/lower successor arrives during the wait.
  if(complete.empty())udpGapStartedAt=0;
  expireReorderGap();
 }
 void receiveCursor(const Bytes&h,const Bytes&body){
  cursorPackets++;cursorBytesReceived+=h.size()+body.size();
  if(h.size()!=28 || std::memcmp(h.data(),"EDL1",4)!=0 || ReadBE(h.data()+4,4)!=sid){cursorRejectedPackets++;return;}
  const uint64_t wireID=ReadBE(h.data()+8,8),sequence=wireID&0x7fffffffffffffffULL;
  if(h.size()!=28 || h[25]!=2 || h[24]!=0 || h[26]!=0 || h[27]!=0 ||
     ReadBE(h.data()+16,2)!=0 || ReadBE(h.data()+18,2)!=1 || ReadBE(h.data()+20,4)!=56 || body.size()!=56 ||
     !(wireID&0x8000000000000000ULL) || !sequence || sequence>9007199254740991ULL || sequence<=cursorLastSequence){cursorRejectedPackets++;return;}
  Bytes plain;if(!decrypt(body,h,plain) || plain.size()!=40 || std::memcmp(plain.data(),"EDC1",4)!=0 ||
     (plain[4]!=1&&plain[4]!=2) || plain[5]>1 || plain[6]!=0 || plain[7]!=0){cursorRejectedPackets++;return;}
  CursorChannelSample sample;sample.cursorSequence=sequence;sample.sourceOwner=plain[4];sample.visible=plain[5];
  sample.edgeInputAck=ReadBE(plain.data()+8,8);sample.sampleTimeNs=ReadBE(plain.data()+32,8);
  const uint64_t xBits=ReadBE(plain.data()+16,8),yBits=ReadBE(plain.data()+24,8);double globalX=0,globalY=0;
  std::memcpy(&globalX,&xBits,sizeof(globalX));std::memcpy(&globalY,&yBits,sizeof(globalY));
  if(sample.edgeInputAck>9007199254740991ULL || !std::isfinite(globalX) || !std::isfinite(globalY) ||
     std::abs(globalX)>1000000 || std::abs(globalY)>1000000){cursorRejectedPackets++;return;}
  DesktopRect capture;
  {std::lock_guard<std::mutex>g(lock);
   if(!running||stopRequested||!cursorChannelSupported||!desktopTopology.valid||sample.edgeInputAck>cursorAcceptedInputSeq){cursorRejectedPackets++;return;}
   capture=desktopTopology.capture;
  }
  sample.x=(globalX-capture.x)/capture.width;sample.y=(globalY-capture.y)/capture.height;
  cursorLastSequence=sequence;cursorAuthenticatedPackets++;
  PublishCursorSample(cursorSessionEpoch,sample);
 }
 void rtcRequestRecovery(){const auto now=Now();auto previous=rtcLastIDR.load();if(previous&&now>=previous&&now-previous<500000000ULL)return;if(rtcLastIDR.compare_exchange_strong(previous,now)){++rtcIDRRequests;send("IDR");}}
 void rtcReceive(uint64_t epoch,const Bytes&record,uint64_t at){
  if(epoch!=rtcEpoch||!rtcActive||!running||stopRequested)return;
  Bytes header(record.begin(),record.begin()+28),body(record.begin()+28,record.end()),plain;
  if(header[25]==2){receiveCursor(header,body);return;}
  if(!decrypt(body,header,plain)){abort("实时视频帧认证失败");return;}++rtcAuthenticatedFrames;bytes+=record.size();
  enqueue(ReadBE(header.data()+8,8),header[24],std::move(plain),at);
 }
 bool rtcPush(const std::string&session,const uint8_t*record,size_t size){
  if(!running||stopRequested||!rtcActive||session!=viewerToken)return false;
  if(rtcIngress.submit(rtcEpoch,record,size,Now()))return true;++rtcIngressDropped;if(record&&size>25&&record[25]==0){rtcRequestRecovery();}return false;
 }
 bool rtcSignal(const std::string&session,const std::string&body){
  if(!running||stopRequested||!rtcActive||session!=viewerToken)return false;
  std::lock_guard<std::mutex>g(lock);if(!running||stopRequested||!rtcActive)return false;
  auto lines=edgelinkrtc::Encode('S',viewerToken,++rtcMessageID,body);if(lines.empty()||commands.size()+lines.size()>1024)return false;for(auto&line:lines)commands.push_back(std::move(line));changed.notify_all();return true;
 }
 void tcpRead(TLS*c){
  while(running){
   Bytes h(28);if(!Read(c,h.data(),h.size()))break;
   const uint32_t size=uint32_t(ReadBE(h.data()+20,4));const uint64_t id=ReadBE(h.data()+8,8);
   if(std::memcmp(h.data(),"EDL1",4)!=0 || ReadBE(h.data()+4,4)!=sid || size<16 || size>4*1024*1024)break;
   if(h[25]==2 && size!=56)break;
   Bytes body(size),plain;if(!Read(c,body.data(),body.size()))break;
   if(h[25]==2){receiveCursor(h,body);continue;}
   if(h[25]==3){
    if(options.mode!="extend"||size>4096||h[24]!=0||h[26]!=0||h[27]!=0||ReadBE(h.data()+16,2)!=0||ReadBE(h.data()+18,2)!=1||!decrypt(body,h,plain)){abort("显示器布局认证失败");break;}
    std::istringstream fields(std::string(plain.begin(),plain.end()));uint64_t revision=0;fields>>revision;
    const auto next=ParseDesktopTopology(fields,true);std::string extra;
    if(!revision||revision>9007199254740991ULL||id!=((1ULL<<62)|revision)||!next.valid||(fields>>extra)){abort("显示器布局无效");break;}
    std::lock_guard<std::mutex>g(lock);if(revision<=desktopTopologyRevision)continue;
    commands.erase(std::remove_if(commands.begin(),commands.end(),[](const std::string&line){return line.rfind("MOVE ",0)==0||line.rfind("BUTTON ",0)==0;}),commands.end());
    releaseLocked();desktopTopology=next;desktopTopologyRevision=revision;continue;
   }
   if(h[25]!=0 || (id&0x8000000000000000ULL))break;
   const uint64_t receivedAt=Now();bytes+=body.size()+h.size();
   if(!decrypt(body,h,plain)){abort("视频帧认证失败");break;}
   enqueue(id,h[24],std::move(plain),receivedAt);
  }
 }
 int openDatagram(){
  if(isTailnet()){
   // Check optional exports before allocating a cancellable Go dial request.
   if(!NetworkSupportsUDP())throw std::runtime_error("当前网络运行库不支持实验 UDP 视频通道");
   int request;{std::lock_guard<std::mutex>g(ioLock);if(!running)throw std::runtime_error("会话已取消");networkRequest=request=NetworkNewRequest();}
   if(request<0)throw std::runtime_error("请先登录互联网连接服务");
   const int fd=NetworkDialUDP(options.host,48564,request);
   {std::lock_guard<std::mutex>g(ioLock);networkRequest=-1;
    if(!running){if(fd>=0){NetworkCloseDatagram(fd);close(fd);}throw std::runtime_error("会话已取消");}
    if(fd>=0){udpFD=fd;udpBridge=true;}
   }
   if(fd<0)throw std::runtime_error("互联网 UDP 视频连接失败");return fd;
  }
  addrinfo hints{};hints.ai_socktype=SOCK_DGRAM;hints.ai_family=AF_UNSPEC;addrinfo*a=nullptr;if(getaddrinfo(options.host.c_str(),"48564",&hints,&a)!=0)throw std::runtime_error("视频地址解析失败");
  int fd=socket(a->ai_family,SOCK_DGRAM,0);if(fd<0){freeaddrinfo(a);throw std::runtime_error("UDP 初始化失败");}
  {std::lock_guard<std::mutex>g(ioLock);if(!running){freeaddrinfo(a);close(fd);throw std::runtime_error("会话已取消");}udpFD=fd;udpBridge=false;}
  const int connected=connect(fd,a->ai_addr,a->ai_addrlen);freeaddrinfo(a);if(connected!=0)throw std::runtime_error("UDP 视频地址连接失败");return fd;
 }
 void udpRead(){
  const int fd=openDatagram();
  int size=4*1024*1024;setsockopt(fd,SOL_SOCKET,SO_RCVBUF,&size,sizeof(size));timeval timeout{0,200000};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));hello();uint64_t lastHello=Now();
  // EDL1's 28-byte header plus 1172-byte fragment fits one 1200-byte datagram.
  Bytes packet(1201); // One extra byte lets us reject oversize datagrams, not truncate them into valid fragments.
  while(running){
   int n=receiveDatagram(fd,packet);if(Now()-lastHello>4000000000ULL){hello();lastHello=Now();}
   if(n<28){if(n>=0)udpRejectedDatagrams++;expireAssemblies();retryKeyframe();if(n<0 && errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR && running)break;continue;}
   if(n>1200){udpRejectedDatagrams++;continue;}
   const auto*h=packet.data();
   if(h[25]==2){
    expireAssemblies();retryKeyframe(); // Cursor traffic never extends a video assembly deadline.
    if(std::memcmp(h,"EDL1",4)!=0 || ReadBE(h+4,4)!=sid || n!=84){cursorRejectedPackets++;continue;}
    receiveCursor(Bytes(h,h+28),Bytes(h+28,h+n));continue;
   }
   uint64_t id=ReadBE(h+8,8);uint32_t total=uint32_t(ReadBE(h+20,4));uint16_t index=uint16_t(ReadBE(h+16,2)),count=uint16_t(ReadBE(h+18,2));
   if(std::string(reinterpret_cast<const char*>(h),4)!="EDL1" || ReadBE(h+4,4)!=sid || h[25]!=0 || total<16 || total>4*1024*1024 || count!=(total+1171)/1172 || index>=count || id<nextFrame || (id&0x8000000000000000ULL)){udpRejectedDatagrams++;continue;}
   size_t offset=size_t(index)*1172,length=std::min<size_t>(1172,total-offset);if(size_t(n)!=28+length){udpRejectedDatagrams++;continue;}
   udpDatagrams++; // Cursor-only traffic cannot count as video watchdog progress.
   if(!admitDatagram(h[24],total))continue;
   auto it=assemblies.find(id);if(it==assemblies.end()){
    if(assemblies.size()>=4){lost++;recover();if(!(h[24]&1))continue;}
    Assembly value;value.created=Now();value.total=total;value.count=count;value.flags=h[24];value.data.resize(total);value.seen.resize(count);it=assemblies.emplace(id,std::move(value)).first;
   }
   auto&v=it->second;if(v.total!=total||v.count!=count||v.flags!=h[24]){udpRejectedDatagrams++;continue;}if(!v.seen[index]){std::copy(h+28,h+n,v.data.begin()+offset);v.seen[index]=true;v.got++;bytes+=n;}
   if(v.got==v.count){const uint64_t receivedAt=Now();Bytes plain;Bytes headerBytes(h,h+28);const uint8_t flags=v.flags;bool ok=decrypt(v.data,headerBytes,plain);assemblies.erase(it);if(ok)enqueue(id,flags,std::move(plain),receivedAt);else{lost++;recover();}}
   expireAssemblies();
  }
 }
 void feed(){while(running&&!stopRequested){
  Frame f;{std::unique_lock<std::mutex>g(lock);changed.wait(g,[this]{return !running||stopRequested||!frames.empty();});if(!running||stopRequested)break;f=std::move(frames.front());frames.pop_front();changed.notify_all();}
  const uint64_t dequeuedAt=Now();
  uint32_t index=0;auto r=OH_VideoDecoder_QueryInputBuffer(decoder,&index,10000);
  while(running&&!stopRequested&&r==AV_ERR_TRY_AGAIN_LATER&&Now()-dequeuedAt<500000000ULL)r=OH_VideoDecoder_QueryInputBuffer(decoder,&index,10000);
  if(!running||stopRequested)break;
  if(r==AV_ERR_TRY_AGAIN_LATER){{std::lock_guard<std::mutex>g(lock);++decoderInputTimeouts;}abort("视频硬件解码器长时间无响应，请重新连接");break;}
  if(r!=AV_ERR_OK){abort("解码输入缓冲获取失败 "+std::to_string(r));break;}
  const uint64_t bufferReadyAt=Now();
  auto buffer=OH_VideoDecoder_GetInputBuffer(decoder,index);auto address=buffer?OH_AVBuffer_GetAddr(buffer):nullptr;
  if(!buffer||!address||OH_AVBuffer_GetCapacity(buffer)<int(f.data.size())){abort("解码输入缓冲不可用或帧过大");break;}
  memcpy(address,f.data.data(),f.data.size());OH_AVCodecBufferAttr attr{};attr.pts=int64_t(f.id*1000000/options.fps);attr.size=int32_t(f.data.size());attr.flags=f.key?AVCODEC_BUFFER_FLAGS_SYNC_FRAME:AVCODEC_BUFFER_FLAGS_NONE;
  if(OH_AVBuffer_SetBufferAttr(buffer,&attr)!=AV_ERR_OK){abort("解码输入属性设置失败");break;}
  {std::lock_guard<std::mutex>g(lock);const uint64_t pushedAt=Now();
   times[uint64_t(attr.pts)]={f.id,pushedAt,f.timing};if(times.size()>128)times.erase(times.begin());
   decoderPendingHighWater=std::max<uint64_t>(decoderPendingHighWater,times.size());
   // The old inputQueue metric measured this entire pre-decoder interval.
   videoQueueMs.Add(double(pushedAt-f.assembled)/1e6);
   decoderBufferWaitMs.Add(double(bufferReadyAt-dequeuedAt)/1e6);
   receiverBackpressureMs.Add(double(f.enqueuedAt-f.assembled)/1e6);
   videoReadyQueueMs.Add(double(dequeuedAt-f.enqueuedAt)/1e6);
  }
  if(!running||stopRequested)break;
  if(OH_VideoDecoder_PushInputBuffer(decoder,index)!=AV_ERR_OK){abort("解码输入提交失败");break;}
 }}
 void recordRenderSubmission(const DecodeTiming&trace,bool successful,uint64_t submitStarted,uint64_t submitReturned){
  std::lock_guard<std::mutex>g(lock);renderSubmitCallMs.Add(double(submitReturned-submitStarted)/1e6);
  if(!successful){++renderSubmitFailures;return;}
  ++rendered;if(!trace.host.timed)return;
  double age=0;
  // Every valid timed frame has captureCallback, even when its source PTS is
  // unavailable or predicts a future display time. Keep this separate origin:
  // it excludes WindowServer -> capture callback and is not glass-to-glass.
  if(clockSync.AgeMs(trace.host.captureCallback,submitReturned,age))captureCallbackToRenderSubmitMs.Add(age);
  else ++captureCallbackRenderAgeRejected;
  if(trace.host.sourceValid){
   if(clockSync.AgeMs(trace.host.sourceCapture,submitReturned,age))captureToRenderSubmitMs.Add(age);
   else ++renderAgeRejected;
  }
 }
 void output(){while(running&&!stopRequested){
  uint32_t index=0;auto r=OH_VideoDecoder_QueryOutputBuffer(decoder,&index,20000);
  if(!running||stopRequested){if(r==AV_ERR_OK)OH_VideoDecoder_FreeOutputBuffer(decoder,index);break;}
  if(r==AV_ERR_STREAM_CHANGED){readDecoderDescription();continue;}
  if(r==AV_ERR_TRY_AGAIN_LATER)continue;if(r!=AV_ERR_OK){abort("解码输出获取失败 "+std::to_string(r));break;}
  auto b=OH_VideoDecoder_GetOutputBuffer(decoder,index);OH_AVCodecBufferAttr attr{};if(!b||OH_AVBuffer_GetBufferAttr(b,&attr)!=AV_ERR_OK){OH_VideoDecoder_FreeOutputBuffer(decoder,index);continue;}
  if(attr.flags&AVCODEC_BUFFER_FLAGS_CODEC_DATA){OH_VideoDecoder_FreeOutputBuffer(decoder,index);continue;}
  decoded++;uint64_t id=(uint64_t(attr.pts)*options.fps+500000)/1000000,now=Now();DecodeTiming trace;
  {std::lock_guard<std::mutex>g(lock);auto i=times.find(uint64_t(attr.pts));if(i!=times.end()){trace=i->second;id=trace.id;decodeMs.Add(double(now-trace.pushedAt)/1e6);times.erase(i);}}
  // Let the compositor present the newest decoded frame at each VSYNC.
  // Plain RenderOutputBuffer keeps every surface buffer, building visible lag.
  const uint64_t submitStarted=Now();const auto submitted=OH_VideoDecoder_RenderOutputBufferAtTime(decoder,index,int64_t(submitStarted));const uint64_t submitReturned=Now();
  recordRenderSubmission(trace,submitted==AV_ERR_OK,submitStarted,submitReturned);
  // A failed render did not prove that the frame was submitted. End this codec
  // lifetime, whose Stop owns releasing its remaining buffers, instead of
  // acknowledging it or retrying an index with uncertain ownership.
  if(submitted!=AV_ERR_OK){abort("视频显示提交失败 "+std::to_string(submitted));break;}
  // This is the existing ACK point: render submission, not actual display.
  if(isRTC()&&rtcActive&&PublishRtcEvent(rtcEpoch,viewerToken,"ack",std::to_string(sid)+" "+std::to_string(id)))++rtcRenderACKs;
  send("ACK "+std::to_string(id));if(running)setStatus("streaming");
 }}
 void transmit(){
  edgetiming::ClockSync initial;uint64_t epoch=0;bool timed=false;
  {std::lock_guard<std::mutex>g(lock);if(!running||stopRequested)return;controlWriterReady=true;initial=clockSync;epoch=timingSessionEpoch;timed=timingNegotiated;changed.notify_all();}
  edgetiming::ClockRefresh refresh(Now(),initial);
  uint64_t lastPing=0;edgelinkwan::RateController rateController;rateController.Reset(epoch);
  while(running){
   std::deque<std::string>batch;bool finalControl=false;
   {std::unique_lock<std::mutex>g(lock);changed.wait_for(g,std::chrono::nanoseconds(std::min<uint64_t>(timed?refresh.WaitNs(Now()):1000000000ULL,isRTC()?20000000ULL:((rateV2Supported&&isTailnet()&&!isUDP())?1000000000ULL:UINT64_MAX))),[this]{return !running||stopRequested||!commands.empty();});
    if(!running)break;
    if(stopRequested){commands.clear();stopControlWriteAttempted=true;finalControl=true;}
    else batch.swap(commands);}
   try{
    if(finalControl){
     refresh.Stop();
     requestControlDrain(); // Idempotent retry if End raced control registration.
     // This is the only post-handshake TLS writer. Success means SSL_write
     // accepted every byte, not an acknowledgement from the Mac.
     std::string finalCommand;{std::lock_guard<std::mutex>g(lock);finalCommand=edgelink::FinalSessionControl(lastStopReason,options.mode,localHandoverSupported,backgroundRetainSupported);}
     Write(control,finalCommand);
     {std::lock_guard<std::mutex>g(lock);stopControlWritten=true;stopControlWriteCompleted=true;controlWriterReady=false;changed.notify_all();}
     break;
    }
    if(stopRequested)continue;
    if(timed){
     if(!pumpClockReplies(refresh)){if(!stopRequested)throw std::runtime_error("控制连接已断开");continue;}
     const auto probe=refresh.NextRequest(Now(),[this,epoch](const edgetiming::ClockSync&s){applyClockRefresh(s,epoch);});
     if(!probe.empty()){batch.push_back(probe.substr(0,probe.size()-1));++clockRefreshProbes;}
     clockRefreshAccepted=refresh.accepted;clockRefreshTimeouts=refresh.timeouts;clockRefreshRejected=refresh.rejected;clockRefreshOverlong=refresh.overlong;
    }
    if(isTailnet()&&!unreliableMedia()&&rateController.Due(Now()/1000000ULL)){
     edgelinkwan::Observation observation;observation.nowMs=Now()/1000000ULL;observation.generation=epoch;
     {std::lock_guard<std::mutex>g(lock);observation.active=observation.running=running&&!stopRequested;observation.writerReady=controlWriterReady;observation.capability=rateV2Supported;observation.appliedKbps=rateAppliedKbps;observation.bytesReceived=bytes.load();observation.receivedFrames=received.load();observation.clockValid=timingNegotiated&&clockSync.Valid(Now());observation.uncertaintyMs=clockSync.uncertaintyNs/1e6;observation.ageSamples=sendToReceiveMs.values.size();observation.ageP50ms=sendToReceiveMs.Percentile(0.50);observation.ageP95ms=sendToReceiveMs.Percentile(0.95);}
     const auto decision=rateController.Observe(observation);
     {std::lock_guard<std::mutex>g(lock);rateTargetKbps=decision.targetKbps;rateGoodputKbps=decision.goodputKbps;rateAgeLowerBoundMs=decision.ageLowerBoundMs;rateReason=decision.reason;if(decision.requestKbps>0){++rateRequests;}}
     if(decision.requestKbps>0){batch.erase(std::remove_if(batch.begin(),batch.end(),[](const std::string&line){return line.rfind("RATE ",0)==0;}),batch.end());batch.push_back("RATE "+std::to_string(decision.requestKbps));}
    }
    if(Now()-lastPing>4000000000ULL){batch.push_back("PING");lastPing=Now();}
    std::string data;for(auto&s:batch)data+=s+'\n';
    if(!data.empty()){if(stopRequested)continue;Write(control,data);
     for(const auto&s:batch){
      if(s=="DESKTOP overview"){++desktopOverviewSent;++inputSent;}
      else if(s.rfind("MOVE ",0)==0||s.rfind("BUTTON ",0)==0||s.rfind("KEY ",0)==0||s.rfind("MACKEY ",0)==0||s.rfind("WHEEL ",0)==0||s.rfind("SCROLL ",0)==0||s.rfind("ZOOM ",0)==0||s.rfind("TEXT ",0)==0)inputSent++;
     }}
   }catch(const std::exception&e){
    {std::lock_guard<std::mutex>g(lock);if(finalControl)stopControlWriteCompleted=true;controlWriterReady=false;changed.notify_all();}
    if(!stopRequested)abort(e.what());break;
   }
  }
  refresh.Stop();
  {std::lock_guard<std::mutex>g(lock);controlWriterReady=false;changed.notify_all();}
 }
 void setAudioStatus(const std::string&state,const std::string&message="",uint64_t generation=0){
  std::lock_guard<std::mutex>g(lock);if(generation&&generation!=audioGeneration)return;audioState=state;audioError=message;
 }
 void setAudioReadiness(int phase,uint64_t generation){
  std::lock_guard<std::mutex>g(lock);if(generation!=audioGeneration)return;audioReadinessPhase=phase;
  if(phase==1)audioPrepareStartedNs=Now();else if(phase==3)audioReadySentNs=Now();else if(phase==4)audioReadyAckNs=Now();
 }
 void setAudioStopReason(const std::string&reason,uint64_t generation){
  std::lock_guard<std::mutex>g(lock);if(generation!=audioGeneration)return;if(audioStopReason.empty())audioStopReason=reason;
 }
 void audioOutput(uint64_t generation,unsigned currentWorkers,bool normalPlayback=false){
  // This thread inherits the run() thread's SIGPIPE mask. All SSL operations
  // on this third object stay here: no parallel read/write against one SSL.
  std::unique_ptr<TLS>channel;EDLAOpusDecoder*opus=nullptr;
  uint64_t epoch=0,lastSequence=0,lastSourceTime=0;bool ownsPlayback=false;
  try{
   setAudioStatus("connecting","",generation);setAudioReadiness(1,generation);channel=connectWithRetry(true,true);setAudioReadiness(2,generation);
   // Prepare the system MEDIA stream before granting Mac permission to mute
   // its local playback. A local epoch fences all renderer input.
   const uint64_t rendererEpoch=generation;
   const auto priorDeadline=Now()+3000000000ULL;
   while(audioWorkers.load()>currentWorkers&&running&&!stopRequested&&audioGeneration==generation&&Now()<priorDeadline){poll(nullptr,0,10);}
   if(audioWorkers.load()>currentWorkers)throw std::runtime_error("上一次声音设备释放尚未完成");
   if(remoteAudio.status().cleanupPending&&!remoteAudio.stop())throw std::runtime_error("上一次声音设备恢复尚未完成");
   if(!running||stopRequested||audioGeneration!=generation||!(normalPlayback?remoteAudio.startPlaybackNormal(rendererEpoch):remoteAudio.startPlayback(rendererEpoch)))throw std::runtime_error("平板声音播放尚未就绪");ownsPlayback=true;
   const auto rendererDeadline=Now()+1000000000ULL;
   while(running&&!stopRequested&&audioGeneration==generation&&Now()<rendererDeadline&&remoteAudio.status().renderCallbacks==0){poll(nullptr,0,5);}
   auto rendererHealth=remoteAudio.status();if(!rendererHealth.playback||rendererHealth.playbackError!=0||rendererHealth.renderCallbacks==0)throw std::runtime_error("平板声音设备没有响应");
   (void)remoteAudio.requestPlaybackObservation(rendererEpoch);
   Write(channel.get(),"AUDIO READY "+viewerToken+"\n");setAudioReadiness(3,generation);
   std::string answer;if(!ReadLineUntil(channel.get(),answer,Now()+3000000000ULL))throw std::runtime_error("声音连接确认超时");
   std::istringstream fields(answer);std::string tag,ok,extra;fields>>tag>>ok>>epoch;
   if(tag!="AUDIO"||ok!="OK"||!epoch||(fields>>extra))throw std::runtime_error("Mac 声音连接未确认");setAudioReadiness(4,generation);
   edgelink::audio::AudioCipher cipher(key.data(),key.size(),sid,epoch,edgelink::audio::Direction::MacOutput);
   if(!cipher.valid()||!(opus=EDLAOpusDecoderCreate(2)))throw std::runtime_error("声音解码初始化失败");
   int flags=fcntl(channel->fd,F_GETFL,0);if(flags<0||fcntl(channel->fd,F_SETFL,flags|O_NONBLOCK)<0)throw std::runtime_error("声音通道配置失败");
   uint64_t lastPing=0,lastProbedCallback=0;edgelink::audio::AudioReadLiveness readHealth(Now());std::string readStopReason;
   auto failRead=[&](const char*reason){if(readStopReason.empty())readStopReason=reason;return false;};
   auto exact=[&](uint8_t*out,size_t wanted){
    size_t copied=0;
    while(copied<wanted&&running&&!stopRequested&&audioGeneration==generation){
     const auto health=remoteAudio.status();
     // Sample time after the callback snapshot: a newly published callback
     // must never appear to come from the future and trigger a false timeout.
     const uint64_t now=Now();
     // Diagnose one callback stall in a separate capped provider worker. The
     // 1 s watchdog and APING continue even if GetCurrentState blocks forever.
     if(health.lastRenderNs&&now>=health.lastRenderNs+500000000ULL&&lastProbedCallback!=health.lastRenderNs){
      if(remoteAudio.requestPlaybackObservation(rendererEpoch))lastProbedCallback=health.lastRenderNs;
     }
     if(const auto reason=readHealth.failure(now,health.playback,health.playbackError,health.lastRenderNs))return failRead(reason);
     if(now-lastPing>50000000ULL){
      const auto pulse="APING "+std::to_string(epoch)+" "+std::to_string(lastSequence)+" "+std::to_string(health.renderedAuthenticatedFrames)+" 1\n";
      // Tiny heartbeat has its own 200ms bound and never waits on video.
      size_t sent=0;const auto deadline=now+200000000ULL;
      while(sent<pulse.size()&&running&&!stopRequested&&audioGeneration==generation&&Now()<deadline){
       int n=SSL_write(channel->ssl,pulse.data()+sent,int(pulse.size()-sent));
       if(n>0){sent+=size_t(n);continue;}const int e=SSL_get_error(channel->ssl,n);
       if(e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE){audioLastSSLError=e;return failRead("audio_heartbeat_write_failed");}
       pollfd p{channel->fd,short(e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT),0};
       int r=poll(&p,1,20);if(r<0&&errno!=EINTR)return failRead("audio_heartbeat_poll_failed");
      }
      if(sent!=pulse.size()){if(!running||stopRequested||audioGeneration!=generation)return false;return failRead("audio_heartbeat_write_timeout");}lastPing=Now();audioHeartbeatsSent++;audioLastHeartbeatNs=lastPing;audioLastHeartbeatAck=lastSequence;audioLastHeartbeatRendered=health.renderedAuthenticatedFrames;
     }
     int n=SSL_read(channel->ssl,out+copied,int(wanted-copied));
     if(n>0){copied+=size_t(n);readHealth.received(Now());continue;}
     if(!running||stopRequested||audioGeneration!=generation)return false;
     const int e=SSL_get_error(channel->ssl,n);
     if(e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE){if(e==SSL_ERROR_SYSCALL&&errno==EINTR)continue;audioLastSSLError=e;return failRead(e==SSL_ERROR_ZERO_RETURN?"audio_peer_eof":"audio_tls_read_failed");}
     pollfd p{channel->fd,short(e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT),0};
     int r=poll(&p,1,100);if(r<0&&errno!=EINTR)return failRead("audio_read_poll_failed");
     if(r>0&&(p.revents&(POLLERR|POLLNVAL)))return failRead("audio_read_socket_failed");
    }
    return copied==wanted;
   };
   setAudioStatus("playing","",generation);std::array<int16_t,960>pcm{};
   while(running&&!stopRequested&&audioGeneration==generation){
    readHealth.beginRecord();Bytes record(44);if(!exact(record.data(),record.size()))break;
    const auto bytes=ReadBE(record.data()+42,2);
    if(std::memcmp(record.data(),"EAD1",4)||record[6]!=2||bytes<1||bytes>1275){audioRejected++;failRead("audio_invalid_record_header");break;}
    record.resize(44+bytes+16);if(!exact(record.data()+44,bytes+16))break;
    edgelink::audio::Chunk chunk;if(!cipher.open(record.data(),record.size(),chunk)||chunk.codec!=edgelink::audio::Codec::Opus||chunk.frames!=480){audioRejected++;failRead("audio_record_authentication_failed");break;}
    if(lastSequence&&chunk.sequence>lastSequence+1){audioGaps+=chunk.sequence-lastSequence-1;EDLAOpusDecoderReset(opus);}
    lastSequence=chunk.sequence;
    if(lastSourceTime&&(chunk.capturedNs<=lastSourceTime||chunk.capturedNs-lastSourceTime>20000000ULL))EDLAOpusDecoderReset(opus);
    lastSourceTime=chunk.capturedNs;
    // Only a reasonably certain clock may drop audio by Mac source age.
    // This is a stale-packet bound, not a promised end-to-end 30 ms latency.
    bool stale=false;{std::lock_guard<std::mutex>g(lock);double age=0;
     if(clockSync.Valid(Now())&&clockSync.uncertaintyNs<30000000ULL&&clockSync.AgeMs(chunk.capturedNs,Now(),age))stale=age>250.0+double(clockSync.uncertaintyNs)/1e6;
    }
    if(stale){audioRejected++;EDLAOpusDecoderReset(opus);continue;}
    // Decode only after authentication. No untrusted codec payload enters the
    // renderer, and no raw mic is started by output playback.
    if(EDLAOpusDecode(opus,chunk.pcm.data(),int(chunk.pcm.size()),pcm.data(),480)!=480){audioRejected++;failRead("audio_decode_failed");break;}
    if(!remoteAudio.enqueuePlayback(rendererEpoch,pcm.data(),pcm.size()*sizeof(int16_t),Now())){
     const auto health=remoteAudio.status();if(!health.playback||health.playbackError!=0)throw std::runtime_error("平板声音播放已停止");continue;
    }
    audioPackets++;
   }
   cipher.retire();
   setAudioStopReason(readStopReason.empty()?"session_end":readStopReason,generation);
   setAudioStatus(running&&!stopRequested&&audioGeneration==generation?"stopped":"idle",readStopReason,generation);
  }catch(const std::exception&e){if(running&&!stopRequested&&audioGeneration==generation){setAudioReadiness(5,generation);setAudioStopReason("audio_setup_or_playback_error",generation);setAudioStatus("error",e.what(),generation);}}
  // Closing the independent TLS peer causes Mac to stop the private tap and
  // restore local playback. Failure here never aborts the video/control pair.
  channel.reset();if(ownsPlayback)remoteAudio.stop();if(opus)EDLAOpusDecoderDestroy(opus);
 }
 bool allowMicrophone(bool allowed){
  if(allowed){std::lock_guard<std::mutex>g(lock);if(!running||stopRequested||options.mode!="remote"||!microphoneSupported||audioState!="playing")return false;}
  microphoneAllowed=allowed;changed.notify_all();
  if(!allowed){std::lock_guard<std::mutex>g(ioLock);NetworkCancel(micNetworkRequest);if(micFD>=0)shutdown(micFD,SHUT_RDWR);}
  return true;
 }
 void setMicStatus(const std::string&state,const std::string&message="",uint64_t generation=0){std::lock_guard<std::mutex>g(lock);if(generation&&generation!=audioGeneration)return;micState=state;micError=message;}
 void microphoneLoop(uint64_t generation){
  while(running&&!stopRequested&&audioGeneration==generation){
   {std::unique_lock<std::mutex>g(lock);changed.wait(g,[this,generation]{return !running||stopRequested||audioGeneration!=generation||microphoneAllowed.load();});}
   if(!running||stopRequested||audioGeneration!=generation)break;
   micAttemptGeneration=generation;
   std::unique_ptr<TLS>channel;EDLAOpusEncoder*opus=nullptr;bool ownsMicrophone=false;
   try{
    setMicStatus("connecting","",generation);channel=connectWithRetry(true,2);if(!microphoneAllowed||!running||stopRequested||audioGeneration!=generation)throw std::runtime_error("麦克风已关闭");
    Write(channel.get(),"MIC READY "+viewerToken+" 1\n");std::string answer;
    if(!ReadLineUntil(channel.get(),answer,Now()+3000000000ULL))throw std::runtime_error("麦克风确认超时");
    std::istringstream fields(answer);std::string tag,ok,extra;uint64_t epoch=0;fields>>tag>>ok>>epoch;
    if(tag!="MIC"||ok!="OK"||!epoch||(fields>>extra))throw std::runtime_error("Mac 虚拟麦克风未准备好");
    edgelink::audio::AudioCipher cipher(key.data(),key.size(),sid,epoch,edgelink::audio::Direction::PadMicrophone);
    if(!cipher.valid()||!(opus=EDLAOpusEncoderCreate(1,32000)))throw std::runtime_error("麦克风编码初始化失败");
    int flags=fcntl(channel->fd,F_GETFL,0);if(flags<0||fcntl(channel->fd,F_SETFL,flags|O_NONBLOCK)<0)throw std::runtime_error("麦克风通道配置失败");
    const uint64_t rendererEpoch=generation;
    bool capture=false;uint64_t lastPulse=0,lastHost=Now(),captureID=0,lastSent=0,lastAck=0;std::string lines;
    auto boundedWrite=[&](const Bytes&data){size_t sent=0;const auto deadline=Now()+200000000ULL;
     while(sent<data.size()&&running&&!stopRequested&&audioGeneration==generation&&microphoneAllowed&&Now()<deadline){int n=SSL_write(channel->ssl,data.data()+sent,int(data.size()-sent));if(n>0){sent+=size_t(n);continue;}int e=SSL_get_error(channel->ssl,n);if(e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE)return false;pollfd p{channel->fd,short(e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT),0};int r=poll(&p,1,10);if(r<0&&errno!=EINTR)return false;}
     return sent==data.size();
    };
    auto frame=[&](const Bytes&payload){Bytes wire;PutBE(wire,payload.size(),4);wire.insert(wire.end(),payload.begin(),payload.end());return boundedWrite(wire);};
    setMicStatus("ready","",generation);std::array<int16_t,480>pcm{};std::array<uint8_t,1275>encoded{};
    while(running&&!stopRequested&&audioGeneration==generation&&microphoneAllowed){
     if(!remoteAudio.status().playback)throw std::runtime_error("声音会话已停止");
     char incoming[1024];int n=SSL_read(channel->ssl,incoming,sizeof(incoming));
     if(n>0){lines.append(incoming,size_t(n));lastHost=Now();if(lines.size()>4096)throw std::runtime_error("麦克风控制格式异常");size_t end;
      while((end=lines.find('\n'))!=std::string::npos){const auto line=lines.substr(0,end);lines.erase(0,end+1);std::istringstream fields(line);std::string one,two,extra;uint64_t receivedEpoch=0,id=0;int wanted=0;
       fields>>one;
       if(one=="MIC"){fields>>two>>receivedEpoch>>wanted>>id;if(two!="CAPTURE"||receivedEpoch!=epoch||(wanted!=0&&wanted!=1)||!id||(fields>>extra))throw std::runtime_error("麦克风请求异常");
        if(id<=captureID)continue;captureID=id;capture=wanted==1;
        if(capture){ownsMicrophone=true;if(!remoteAudio.startMicrophone(rendererEpoch))throw std::runtime_error("平板麦克风无法开启");setMicStatus("capturing","",generation);}
        else{if(!remoteAudio.stopMicrophone())throw std::runtime_error("平板麦克风释放仍在处理中");ownsMicrophone=false;setMicStatus("ready","",generation);}
       }else if(one=="MACK"){fields>>receivedEpoch>>id;if(receivedEpoch!=epoch||id>lastSent||id<lastAck||(fields>>extra))throw std::runtime_error("麦克风确认异常");lastAck=id;}
       else throw std::runtime_error("麦克风控制未识别");
      }
     }else{int e=SSL_get_error(channel->ssl,n);if(e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE)throw std::runtime_error("麦克风连接已断开");}
     const auto now=Now();if(now-lastHost>3000000000ULL)throw std::runtime_error("麦克风连接超时");
     if(now-lastPulse>1000000000ULL){Bytes ping={'M','P','N','G'};PutBE(ping,epoch,8);if(!frame(ping))throw std::runtime_error("麦克风心跳发送失败");lastPulse=Now();}
     if(capture){const auto health=remoteAudio.status();if(!health.microphone||health.microphoneError!=0)throw std::runtime_error("平板麦克风已停止");uint64_t time=0;
      while(remoteAudio.drainMicrophone(rendererEpoch,pcm.data(),960,time)==960){
       if(Now()<time||Now()-time>30000000ULL||lastSent-lastAck>=24){micDropped++;continue;}
       uint64_t energy=0,peak=0;for(size_t i=0;i<480;++i){const auto v=int64_t(pcm[i]);energy+=uint64_t(v*v);peak=std::max(peak,uint64_t(v<0?-v:v));}
       micPeak=peak;micRms=uint64_t(std::sqrt(double(energy)/480.0));auto previous=micPeakMax.load();while(peak>previous&&!micPeakMax.compare_exchange_weak(previous,peak)){}
       auto rms=micRms.load();auto priorRms=micRmsMax.load();while(rms>priorRms&&!micRmsMax.compare_exchange_weak(priorRms,rms)){}
       const int bytes=EDLAOpusEncode(opus,pcm.data(),480,encoded.data(),1275);if(bytes<=0)throw std::runtime_error("麦克风编码失败");
       Bytes encrypted;if(!cipher.sealOpus(encoded.data(),size_t(bytes),1,time,encrypted))throw std::runtime_error("麦克风加密失败");
       Bytes payload={'M','C','F','1'};PutBE(payload,captureID,8);payload.insert(payload.end(),encrypted.begin(),encrypted.end());
       if(!frame(payload))throw std::runtime_error("麦克风发送超时");lastSent++;micPackets++;
      }
     }
     pollfd p{channel->fd,POLLIN,0};int r=poll(&p,1,capture?5:100);if(r<0&&errno!=EINTR)throw std::runtime_error("麦克风等待失败");
    }
    cipher.retire();setMicStatus("idle","",generation);
   }catch(const std::exception&e){if(running&&!stopRequested&&audioGeneration==generation&&microphoneAllowed)setMicStatus("error",e.what(),generation);else setMicStatus("idle","",generation);}
   if(audioGeneration==generation)microphoneAllowed=false;if(ownsMicrophone)remoteAudio.stopMicrophone();channel.reset();if(opus)EDLAOpusEncoderDestroy(opus);
   uint64_t completedGeneration=generation;micAttemptGeneration.compare_exchange_strong(completedGeneration,0);
  }
 }
 void run(){
  // Candidate-only: socket BIO writes cannot terminate the app after peer loss.
  // The transmit thread created here inherits this thread-local signal mask.
  sigset_t blocked;sigemptyset(&blocked);sigaddset(&blocked,SIGPIPE);pthread_sigmask(SIG_BLOCK,&blocked,nullptr);
  std::unique_ptr<TLS>ctrl,video;std::thread tx,feeder,outputs,audioThread,micThread;const uint64_t audioGen=audioGeneration.load();
  auto audioDone=std::make_shared<std::atomic<bool>>(true),micDone=std::make_shared<std::atomic<bool>>(true);
  try{
   int authKbps=isTailnet()?4000:(options.bitrateKbps>0?options.bitrateKbps:(!options.splitPath&&options.host=="127.0.0.1"&&options.port==49561?80000:40000));
   auto authenticate=[&](){Write(control,"AUTH "+options.token+" "+options.mode+" "+std::to_string(options.width)+" "+std::to_string(options.height)+" "+std::to_string(options.fps)+" "+(isUDP()?"udp":"tcp")+" "+std::to_string(authKbps)+" store-v1 codec-"+(options.transport=="store-hevc"?"hevc":"avc")+"-v1 edge-session-"+edgelinkavailability::CurrentProcessSession()+"\n");std::string line;uint8_t ch;while(line.size()<1024&&Read(control,&ch,1)){if(ch=='\n')break;line+=char(ch);}return line;};
   ctrl=connectWithRetry(false);control=ctrl.get();std::string answer=authenticate();
   // One exact legacy bitrate rejection permits one same-pinned TLS retry.
   // No retry weakens certificates or hides an unrelated AUTH/network failure.
   if(isTailnet()&&answer=="ERR bitrate_configuration"&&running&&!stopRequested){control=nullptr;ctrl.reset();authKbps=8000;ctrl=connectWithRetry(false);control=ctrl.get();answer=authenticate();}
   if(answer=="ERR permissions_required")throw std::runtime_error("请先在 Mac 的映桥中完成屏幕共享和键鼠权限设置，再重新连接");
   if(answer=="ERR remote_local_authorization_required")throw std::runtime_error("请先在 Mac 的映桥中开启“远控待机”，再重新连接");
   std::istringstream input(answer);std::string tag,sidHex,keyHex,sp,cp;int w=0,h=0,fps=0;input>>tag>>sidHex>>keyHex>>sp>>cp>>viewerToken>>w>>h>>fps;
   if(tag!="OK")throw std::runtime_error("Mac 拒绝会话，可能已有连接或配对不一致");key=Unhex(keyHex);serverPrefix=Unhex(sp);clientPrefix=Unhex(cp);auto sb=Unhex(sidHex);if(sb.size()!=4||key.size()!=16||serverPrefix.size()!=4||clientPrefix.size()!=4||w!=options.width||h!=options.height||fps!=options.fps)throw std::runtime_error("会话参数无效");sid=uint32_t(ReadBE(sb.data(),4));
   std::string capability;input>>capability;const bool timed=capability=="timing-v1";
   std::string extensionFields;std::getline(input,extensionFields);
   std::istringstream topologyFields(extensionFields),capabilities(extensionFields);
   const auto topology=ParseDesktopTopology(topologyFields,options.mode=="extend");
   const auto controlCapabilities=ParseControlCapabilities(capabilities);
   const bool cursorSupported=controlCapabilities.cursor;
   {std::lock_guard<std::mutex>g(lock);timingNegotiated=timed;localHandoverSupported=extensionFields.find(" local-handover-v1")!=std::string::npos;backgroundRetainSupported=extensionFields.find(" background-retain-v1")!=std::string::npos;desktopTopology=topology;cursorChannelSupported=cursorSupported;cursorCapabilityKnown=true;
    desktopOverviewCapabilityKnown=true;desktopOverviewSupported=controlCapabilities.desktopOverview;rateV2Supported=edgelinkwan::HasRateV2(extensionFields);rateTargetKbps=isTailnet()?4000:authKbps;rateAppliedKbps=authKbps;
    if(cursorSupported&&options.mode=="extend"&&topology.valid)commands.push_front("CURSOR 1");}
   if(options.mode=="extend"&&!isRTC()&&!isUDP()&&extensionFields.find(" desktop-live-v1")!=std::string::npos)send("TOPOLOGY 1");
   storeCodec=extensionFields.find("codec-hevc-v1")!=std::string::npos?"hevc":"avc";if(timed)calibrateClock();if(!running)throw std::runtime_error("会话已取消");createDecoder();setStatus("ready");
   if(isRTC()){if(extensionFields.find(" rtc-v1")==std::string::npos)throw std::runtime_error("Mac 尚未启用实时候选通道");
    rtcActive=true;rtcIngress.start(rtcEpoch,sid,[this](uint64_t epoch,const Bytes&record,uint64_t at){rtcReceive(epoch,record,at);},[this](uint64_t epoch){if(epoch==rtcEpoch&&running&&!stopRequested){rtcRequestRecovery();}});send("RTC START "+viewerToken+" "+std::to_string(rtcRecordBudgetMs));}
   else if(!isUDP()){video=connectWithRetry(true);timeval unlimited{0,0};setsockopt(video->fd,SOL_SOCKET,SO_RCVTIMEO,&unlimited,sizeof(unlimited));Write(video.get(),"VIEW "+viewerToken+"\n");}
   tx=std::thread([this]{transmit();});feeder=std::thread([this]{feed();});outputs=std::thread([this]{output();});
   bool audioSupported=false;{std::istringstream audioFields(extensionFields);std::string field;while(audioFields>>field)if(field=="audio-v1")audioSupported=true;}
   {std::istringstream fields(extensionFields);std::string field;while(fields>>field)if(field=="mic-v1")microphoneSupported=true;}
   if(audioSupported&&options.mode=="remote"){
    const unsigned currentWorkers=microphoneSupported ? 2:1;audioWorkers+=currentWorkers;*audioDone=false;audioThread=std::thread([this,audioGen,audioDone,currentWorkers]{for(unsigned attempt=0;attempt<3&&running&&!stopRequested&&audioGeneration==audioGen;++attempt){
     if(attempt){
      setAudioStatus("connecting","正在重新连接声音",audioGen);
      const auto retryAt=Now()+uint64_t(attempt)*1000000000ULL;
      while(running&&!stopRequested&&audioGeneration==audioGen&&Now()<retryAt)poll(nullptr,0,20);
      if(!running||stopRequested||audioGeneration!=audioGen)break;
     }
     audioOutput(audioGen,currentWorkers,attempt>0);
     if(!running||stopRequested||audioGeneration!=audioGen)break;
     // Output teardown retires the shared provider. Cancel any old mic peer
     // before retrying; only a new explicit Pad action can resume capture.
     microphoneAllowed=false;changed.notify_all();
     {std::lock_guard<std::mutex>g(ioLock);NetworkCancel(micNetworkRequest);if(micFD>=0)shutdown(micFD,SHUT_RDWR);}
     const auto micDeadline=Now()+2000000000ULL;
     while(running&&!stopRequested&&audioGeneration==audioGen&&micAttemptGeneration==audioGen&&Now()<micDeadline)poll(nullptr,0,20);
     if(micAttemptGeneration==audioGen||remoteAudio.status().capturerResourceOwned)break;
    }audioWorkers--;*audioDone=true;});
    if(microphoneSupported){*micDone=false;micThread=std::thread([this,audioGen,micDone]{microphoneLoop(audioGen);audioWorkers--;*micDone=true;});}
   }
   if(isRTC()){std::unique_lock<std::mutex>g(lock);changed.wait(g,[this]{return !running||stopRequested;});}
   else if(!isUDP())tcpRead(video.get());else udpRead();
   if(running&&!stopRequested)setStatus("error","视频连接已断开");
  }catch(const std::exception&e){if(running&&!stopRequested)setStatus("error",e.what());}
  running=false;EndCursorSession(cursorSessionEpoch);StopAxisObservation();ReleaseCursorLock();changed.notify_all();if(component){OH_NativeXComponent_UnregisterOnFrameCallback(component);OH_NativeXComponent_ExpectedRateRange range={0,60,30};OH_NativeXComponent_SetExpectedFrameRateRange(component,&range);}
  {std::lock_guard<std::mutex>g(ioLock);for(int request:{networkRequest,audioNetworkRequest,micNetworkRequest})NetworkCancel(request);if(ctrlFD>=0)shutdown(ctrlFD,SHUT_RDWR);if(audioFD>=0)shutdown(audioFD,SHUT_RDWR);if(micFD>=0)shutdown(micFD,SHUT_RDWR);shutdownDatagramLocked();}
  rtcActive=false;EndRtcOwner(rtcEpoch);changed.notify_all();rtcIngress.stop();
  microphoneAllowed=false;remoteAudio.retireCallbacks(audioGen);changed.notify_all();
  // The OS audio provider has no Stop/Release deadline API. Keep its callback
  // context and old owner alive, while bounding the foreground End wait.
  const auto audioDeadline=Now()+200000000ULL;
  while((!*audioDone||!*micDone)&&Now()<audioDeadline){poll(nullptr,0,5);}
  if(micThread.joinable()){if(*micDone)micThread.join();else micThread.detach();}
  if(audioThread.joinable()){if(*audioDone)audioThread.join();else audioThread.detach();}if(tx.joinable())tx.join();if(feeder.joinable())feeder.join();if(outputs.joinable())outputs.join();
  {std::lock_guard<std::mutex>g(lock);desktopOverviewCapabilityKnown=false;desktopOverviewSupported=false;}
  if(decoder){OH_VideoDecoder_Stop(decoder);OH_VideoDecoder_Destroy(decoder);decoder=nullptr;}
  {std::lock_guard<std::mutex>g(ioLock);ctrlFD=videoFD=-1;controlStreamOwner.Reset();closeDatagramLocked();control=nullptr;}
  video.reset();ctrl.reset();
 }
 // Small, nonblocking lifecycle snapshot. Unlike stats(), this does not reset
 // FPS samples, allocate diagnostic JSON, or query input/audio subsystems.
 int storeSessionFlags(){std::unique_lock<std::mutex>g(lock,std::try_to_lock);if(!g.owns_lock())return -1;
  return (running?1:0)|(localHandoverSupported?2:0)|(rendered.load()>0?4:0)|(lastStopReason=="mac_end"?8:0);
 }
 std::string stats(){std::lock_guard<std::mutex>g(lock);uint64_t now=Now();double seconds=std::max(0.001,double(now-lastStats)/1e9);std::ostringstream out;
  const auto sound=remoteAudio.status();
  out<<"{\"audioHeartbeatsSent\":"<<audioHeartbeatsSent<<",\"audioLastHeartbeatAck\":"<<audioLastHeartbeatAck<<",\"audioLastHeartbeatRendered\":"<<audioLastHeartbeatRendered<<",\"audioLastHeartbeatAgeMs\":"<<(audioLastHeartbeatNs&&now>=audioLastHeartbeatNs?double(now-audioLastHeartbeatNs)/1e6:-1)<<",\"audioStopReason\":"<<Quoted(audioStopReason)<<",\"audioLastSSLError\":"<<audioLastSSLError<<",\"audioStreamCleanupPending\":"<<(sound.cleanupPending?"true":"false")<<",\"audioRendererCallbacks\":"<<sound.renderCallbacks<<",\"audioRenderedAuthenticatedFrames\":"<<sound.renderedAuthenticatedFrames<<",\"audioRendererCallbackAgeMs\":"<<(sound.lastRenderNs&&now>=sound.lastRenderNs?double(now-sound.lastRenderNs)/1e6:-1)<<",\"audioPlaybackError\":"<<sound.playbackError<<",";
  out<<"\"audioRendererObservedState\":"<<sound.rendererObservedState<<",\"audioRendererStateResult\":"<<sound.rendererStateResult<<",\"audioRendererStateSamples\":"<<sound.rendererStateSamples<<",\"audioRendererStateAgeMs\":"<<(sound.rendererStateSampleNs&&now>=sound.rendererStateSampleNs?double(now-sound.rendererStateSampleNs)/1e6:-1)
     <<",\"audioRendererInterruptEvents\":"<<sound.rendererInterruptEvents<<",\"audioRendererInterruptType\":"<<sound.rendererInterruptType<<",\"audioRendererInterruptHint\":"<<sound.rendererInterruptHint<<",\"audioRendererInterruptMask\":"<<sound.rendererInterruptMask
     <<",\"audioRendererDeviceChanges\":"<<sound.rendererDeviceChanges<<",\"audioRendererDeviceChangeReason\":"<<sound.rendererDeviceChangeReason<<",\"audioRendererResourceOwned\":"<<(sound.rendererResourceOwned?"true":"false")<<",\"audioCapturerResourceOwned\":"<<(sound.capturerResourceOwned?"true":"false")<<",\"audioProviderOperations\":"<<sound.providerOperations<<",";
  out<<"\"audioReadinessPhase\":"<<audioReadinessPhase<<",\"audioPrepareAgeMs\":"<<(audioPrepareStartedNs&&now>=audioPrepareStartedNs?double(now-audioPrepareStartedNs)/1e6:-1)<<",\"audioReadyWaitMs\":"<<(audioReadySentNs?double((audioReadyAckNs?audioReadyAckNs:now)-audioReadySentNs)/1e6:-1)<<",\"audioReadyAcknowledged\":"<<(audioReadyAckNs?"true":"false")<<",";
  out<<"\"audioRendererProbeInFlight\":"<<(sound.rendererProbeInFlight?"true":"false")<<",\"audioRendererProbeAgeMs\":"<<(sound.rendererProbeStartedNs&&now>=sound.rendererProbeStartedNs?double(now-sound.rendererProbeStartedNs)/1e6:-1)<<",";
  out<<"\"surfaceAvailable\":"<<(surfaceAvailable?"true":"false")<<",\"backgroundRetainSupported\":"<<(backgroundRetainSupported?"true":"false")<<",\"sessionID\":"<<sid<<",\"localHandoverSupported\":"<<(localHandoverSupported?"true":"false")<<",\"audioCleanupWorkers\":"<<audioWorkers<<",\"microphoneSupported\":"<<(microphoneSupported?"true":"false")<<",\"microphoneAllowed\":"<<(microphoneAllowed?"true":"false")<<",\"microphoneState\":"<<Quoted(micState)<<",\"microphoneError\":"<<Quoted(micError)<<",\"microphonePackets\":"<<micPackets<<",\"microphonePeakS16\":"<<micPeak<<",\"microphoneRmsS16\":"<<micRms<<",\"microphonePeakMaxS16\":"<<micPeakMax<<",\"microphoneRmsMaxS16\":"<<micRmsMax<<",\"microphoneSourceMode\":0,\"microphoneDropped\":"<<micDropped<<",\"audioState\":"<<Quoted(audioState)<<",\"audioError\":"<<Quoted(audioError)<<",\"audioPackets\":"<<audioPackets<<",\"audioRejected\":"<<audioRejected<<",\"audioGaps\":"<<audioGaps<<",\"audioSystemVolume\":true,\"audioPlaybackActive\":"<<(sound.playback?"true":"false")<<",\"audioMicActive\":"<<(sound.microphone?"true":"false")<<",\"audioFastRequested\":"<<(sound.fastRequested?"true":"false")<<",\"audioLatencyMode\":"<<int(sound.latencyMode)<<",\"audioQueueDropped\":"<<sound.playbackQueue.dropped<<",\"audioUnderflows\":"<<sound.playbackQueue.underflow<<","<<AxisObservationStats()<<","<<CursorLockStats()<<","<<NativeMouseNodeStats()<<","<<CursorChannelStats()<<",\"heldKeys\":"<<heldKeys.size()<<",\"heldButtons\":"<<heldButtons.size()<<",\"localUI\":"<<(localUI?"true":"false")<<",\"ignoredSystemKeys\":"<<ignoredSystemKeys<<",\"ignoredModifierRepeats\":"<<ignoredModifierRepeats<<",\"stopReason\":"<<Quoted(lastStopReason)<<",\"inputCalls\":"<<inputCalls<<",\"nativeKeyEvents\":"<<nativeKeyEvents<<",\"inputSent\":"<<inputSent<<",\"state\":"<<Quoted(status)<<",\"error\":"<<Quoted(error)<<",\"receivedFrames\":"<<received<<",\"decodedFrames\":"<<decoded<<",\"renderSubmittedFrames\":"<<rendered<<",\"lostFrames\":"<<lost<<",\"receivedFPS\":"<<double(received-lastReceived)/seconds<<",\"renderSubmittedFPS\":"<<double(rendered-lastRendered)/seconds<<",\"displayClockFPS\":"<<double(clockTicks-lastTicks)/seconds<<",\"inputQueueP95ms\":"<<videoQueueMs.Percentile(0.95)<<",\"bytesReceived\":"<<bytes<<",\"running\":"<<(running?"true":"false");
  WriteDesktopTopologyStats(out,desktopTopology);out<<",\"desktopTopologyRevision\":"<<desktopTopologyRevision;
  const auto rtc=rtcIngress.counts();out<<","<<RtcEventStats()<<",\"rtcMode\":"<<(isRTC()?"true":"false")<<",\"rtcActive\":"<<(rtcActive?"true":"false")<<",\"rtcAuthenticatedFrames\":"<<rtcAuthenticatedFrames<<",\"rtcIngressDropped\":"<<rtcIngressDropped<<",\"rtcQueueExpired\":"<<rtc.expired<<",\"rtcRenderACKs\":"<<rtcRenderACKs;
  out<<",\"decoderName\":"<<Quoted(decoderName)<<",\"decoderHardwareRequested\":true,\"decoderLowLatencyRequested\":true"
   <<",\"decoderLowLatencySupported\":"<<(decoderLowLatencySupported?"true":"false")<<",\"decoderDecodingOrderSupported\":"<<(decoderDecodingOrderSupported?"true":"false")
   <<",\"decoderReportedLowLatency\":"<<decoderReportedLowLatency<<",\"decoderReportedInputBufferCount\":"<<decoderReportedInputBuffers<<",\"decoderReportedOutputBufferCount\":"<<decoderReportedOutputBuffers
   <<",\"nativeWindowQueueSize\":"<<nativeWindowQueueSize<<",\"nativeWindowRequestTimeoutMs\":"<<nativeWindowRequestTimeoutMs
   <<",\"decoderPendingTraces\":"<<times.size()<<",\"decoderPendingTraceHighWater\":"<<decoderPendingHighWater
   <<",\"tcpDecodeQueueTimeouts\":"<<tcpDecodeQueueTimeouts<<",\"decoderInputTimeouts\":"<<decoderInputTimeouts<<",\"decoderStallWaitLimitMs\":500,\"decoderOutputQueryTimeoutUs\":20000";
  out<<",\"desktopOverviewCapabilityKnown\":"<<(desktopOverviewCapabilityKnown?"true":"false")<<",\"desktopOverviewSupported\":"<<(desktopOverviewSupported?"true":"false")
   <<",\"desktopOverviewQueued\":"<<desktopOverviewQueued<<",\"desktopOverviewSent\":"<<desktopOverviewSent;
  out<<",\"cursorCapabilityKnown\":"<<(cursorCapabilityKnown?"true":"false")<<",\"cursorChannelSupported\":"<<(cursorChannelSupported?"true":"false")<<",\"cursorAcceptedInputSeq\":"<<cursorAcceptedInputSeq
   <<",\"cursorPackets\":"<<cursorPackets<<",\"cursorRejectedPackets\":"<<cursorRejectedPackets
   <<",\"cursorAuthenticatedPackets\":"<<cursorAuthenticatedPackets<<",\"cursorBytesReceived\":"<<cursorBytesReceived;
  out<<",\"rateV2Supported\":"<<(rateV2Supported?"true":"false")<<",\"rateTargetKbps\":"<<rateTargetKbps<<",\"rateAppliedKbps\":"<<rateAppliedKbps<<",\"rateRequests\":"<<rateRequests<<",\"rateReplies\":"<<rateReplies<<",\"rateErrors\":"<<rateErrors<<",\"rateGoodputKbps\":"<<rateGoodputKbps<<",\"rateAgeLowerBoundMs\":"<<rateAgeLowerBoundMs<<",\"rateReason\":"<<Quoted(rateReason);
  const bool syncValid=timingNegotiated&&clockSync.Valid(now);
  out<<",\"timingNegotiated\":"<<(timingNegotiated?"true":"false")<<",\"clockSyncValid\":"<<(syncValid?"true":"false")
   <<",\"clockSyncSampleCount\":"<<clockSync.validSamples<<",\"clockSyncUncertaintyMs\":";
  if(syncValid)out<<clockSync.uncertaintyNs/1e6;else out<<"null";
  out<<",\"clockSyncRttMs\":";if(syncValid)out<<double(clockSync.bestRttNs)/1e6;else out<<"null";
  out<<",\"clockSyncAgeMs\":";if(clockSync.calibratedAt&&now>=clockSync.calibratedAt)out<<double(now-clockSync.calibratedAt)/1e6;else out<<"null";
  out<<",\"clockSyncRefreshes\":"<<clockSyncRefreshes<<",\"clockRefreshProbes\":"<<clockRefreshProbes<<",\"clockRefreshAccepted\":"<<clockRefreshAccepted
   <<",\"clockRefreshTimeouts\":"<<clockRefreshTimeouts<<",\"clockRefreshRejected\":"<<clockRefreshRejected<<",\"clockRefreshOverlong\":"<<clockRefreshOverlong;
  out<<",\"timingAgeIsEstimate\":true,\"renderTimingEndpoint\":\"successfulRenderSubmissionReturn\",\"timingWindowCapacity\":"<<edgetiming::kMetricWindow
   <<",\"timedFrames\":"<<timedFrames<<",\"legacyFrames\":"<<legacyFrames<<",\"invalidTimingFrames\":"<<invalidTimingFrames
   <<",\"renderSubmitFailures\":"<<renderSubmitFailures<<",\"captureAgeRejected\":"<<captureAgeRejected<<",\"sendAgeRejected\":"<<sendAgeRejected<<",\"renderAgeRejected\":"<<renderAgeRejected
   <<",\"captureCallbackRenderAgeRejected\":"<<captureCallbackRenderAgeRejected<<",\"captureCallbackTimingOrigin\":\"MacCaptureCallbackEntry\"";
  out<<",\"transport\":"<<Quoted(options.transport)<<",\"mediaTransport\":"<<Quoted(isRTC()?"rtc":isUDP()?"udp":"tcp")
   <<",\"sessionWidthPx\":"<<options.width<<",\"sessionHeightPx\":"<<options.height<<",\"sessionTargetFPS\":"<<options.fps
   <<",\"udpDatagrams\":"<<udpDatagrams<<",\"udpRejectedDatagrams\":"<<udpRejectedDatagrams<<",\"udpAssemblyTimeouts\":"<<udpAssemblyTimeouts
   <<",\"udpRecoveries\":"<<udpRecoveries<<",\"idrRequests\":"<<idrRequests<<",\"udpHellos\":"<<udpHellos<<",\"udpHelloFailures\":"<<udpHelloFailures;
  out<<",\"splitPathRequested\":"<<(options.splitPath?"true":"false")<<",\"splitPathActive\":"<<(options.splitPath&&running?"true":"false");
  if(options.splitPath){auto c=edgelinksplit::LocalEndpoint(options.host,options.port),v=edgelinksplit::LocalEndpoint(options.videoHost,options.videoPort);out<<",\"controlRoute\":"<<Quoted(c?c->route:"")<<",\"videoRoute\":"<<Quoted(v?v->route:"");}
  out<<",\"udpAssemblyTimeoutMs\":"<<assemblyTimeoutNs()/1000000;
  out<<",\"udpDecodeQueueWaits\":"<<udpDecodeQueueWaits<<",\"udpDecodeQueueOverflows\":"<<udpDecodeQueueOverflows
   <<",\"udpDecodeQueueDiscardedFrames\":"<<udpDecodeQueueDiscardedFrames<<",\"udpSequenceGaps\":"<<udpSequenceGaps
   <<",\"udpGapTimeouts\":"<<udpGapTimeouts<<",\"udpGapOverflows\":"<<udpGapOverflows
   <<",\"udpReorderWaitLimitMs\":"<<udpReorderTimeoutNs()/1000000
   <<",\"udpReorderLimitFrames\":4,\"udpReorderLimitBytes\":4194304"
   <<",\"udpDecodeQueueLimitFrames\":3,\"udpDecodeQueueWaitLimitMs\":25";
  out<<",\"stopRequested\":"<<(stopRequested?"true":"false")<<",\"controlWriterReady\":"<<(controlWriterReady?"true":"false")
   <<",\"stopControlWriteAttempted\":"<<(stopControlWriteAttempted?"true":"false")<<",\"stopControlWritten\":"<<(stopControlWritten?"true":"false")
   <<",\"stopControlWriteCompleted\":"<<(stopControlWriteCompleted?"true":"false")<<",\"stopControlTimedOut\":"<<(stopControlTimedOut?"true":"false")
   <<",\"stopProxyDrainAttempted\":"<<(stopProxyDrainAttempted?"true":"false")<<",\"stopProxyDrainRequested\":"<<(stopProxyDrainRequested?"true":"false")
   <<",\"stopControlPeerAcknowledged\":false";
  out<<",\"idrRequestIntervalMs\":"<<idrRequestIntervalNs()/1000000<<",\"udpLargestDeclaredKeyframeBytes\":"<<udpLargestDeclaredKeyframeBytes
   <<",\"udpCompletedKeyframes\":"<<udpCompletedKeyframes<<",\"udpAwaitKeyDrops\":"<<udpAwaitKeyDrops;
  // Existing UI calls toFixed() on decodeP95ms; keep zero until its first sample.
  decodeMs.Json(out,"decode",true,true);videoQueueMs.Json(out,"videoQueue",true,true);
  decoderBufferWaitMs.Json(out,"decoderBufferWait");receiverBackpressureMs.Json(out,"receiverBackpressure");videoReadyQueueMs.Json(out,"videoReadyQueue");decryptMs.Json(out,"decrypt");
  encodeMs.Json(out,"encode");hostCaptureCallbackDelayMs.Json(out,"hostCaptureCallbackDelay");preEncodeDelayMs.Json(out,"preEncodeDelay");senderQueueMs.Json(out,"senderQueue");
  captureAgeAtReceiveMs.Json(out,"captureAgeAtReceive",syncValid);sendToReceiveMs.Json(out,"sendToReceive",syncValid);captureToRenderSubmitMs.Json(out,"captureToRenderSubmit",syncValid);captureCallbackToRenderSubmitMs.Json(out,"captureCallbackToRenderSubmit",syncValid);renderSubmitCallMs.Json(out,"renderSubmitCall");out<<"}";
  lastStats=now;lastReceived=received;lastRendered=rendered;lastTicks=clockTicks;return out.str();
 }
};
static std::string String(napi_env env,napi_value value){size_t length=0;napi_get_value_string_utf8(env,value,nullptr,0,&length);std::string s(length,'\0');napi_get_value_string_utf8(env,value,s.data(),length+1,&length);return s;}
static int Integer(napi_env env,napi_value value){int32_t x=0;napi_get_value_int32(env,value,&x);return x;}
static napi_value Void(napi_env env){napi_value v;napi_get_undefined(env,&v);return v;}
static napi_value Connect(napi_env env,napi_callback_info info){size_t n=10;napi_value v[10];napi_get_cb_info(env,info,&n,v,nullptr,nullptr);if(n<9||n>10)return Void(env);Options o;if(n==10)o.bitrateKbps=Integer(env,v[9]);o.host=String(env,v[0]);o.port=Integer(env,v[1]);o.mode=String(env,v[2]);o.width=Integer(env,v[3]);o.height=Integer(env,v[4]);o.fps=Integer(env,v[5]);o.transport=String(env,v[6]);o.token=String(env,v[7]);o.certificate=String(env,v[8]);if(o.host.empty()||o.host.size()>255||o.port<1||o.port>65535||o.token.size()!=64||o.certificate.size()>8192||o.width<640||o.width>3840||o.height<480||o.height>3200||o.fps<30||o.fps>120||o.bitrateKbps<0||o.bitrateKbps>240000)return Void(env);Client::Instance().start(std::move(o));return Void(env);}
static napi_value ConnectSplit(napi_env env,napi_callback_info info){
 size_t n=11;napi_value v[11];napi_get_cb_info(env,info,&n,v,nullptr,nullptr);if(n!=11){napi_throw_error(env,"split_invalid_config","Split configuration requires eleven arguments");return Void(env);}
 Options o;o.host=String(env,v[0]);o.port=Integer(env,v[1]);o.mode=String(env,v[2]);o.width=Integer(env,v[3]);o.height=Integer(env,v[4]);o.fps=Integer(env,v[5]);o.transport=String(env,v[6]);o.token=String(env,v[7]);o.certificate=String(env,v[8]);o.videoHost=String(env,v[9]);o.videoPort=Integer(env,v[10]);o.splitPath=true;
 auto c=edgelinksplit::LocalEndpoint(o.host,o.port),p=edgelinksplit::LocalEndpoint(o.videoHost,o.videoPort);
 const bool settings=o.token.size()==64&&o.token.find_first_not_of("0123456789abcdefABCDEF")==std::string::npos&&!o.certificate.empty()&&o.certificate.size()<=8192&&
  o.width>=640&&o.width<=3120&&o.height>=480&&o.height<=2080&&o.fps>=30&&o.fps<=120;
 const bool routes=c&&p&&edgelinksplit::ValidConfiguration(o.mode,o.transport,*c,*p);
 const bool proofs=routes&&edgelinkavailability::CanUseVerifiedLocalPath(c->route,c->host,48562,o.token,o.certificate)&&edgelinkavailability::CanUseVerifiedLocalPath(p->route,p->host,48562,o.token,o.certificate);
 if(!settings||!proofs){napi_throw_error(env,"split_local_ready_required","Two current paired USB/LAN READY paths are required");return Void(env);}
 Client::Instance().start(std::move(o));return Void(env);
}
static napi_value Disconnect(napi_env env,napi_callback_info info){size_t n=1;napi_value v;napi_get_cb_info(env,info,&n,&v,nullptr,nullptr);auto&c=Client::Instance();c.stop(n==1?String(env,v):"requested");return Void(env);}
static napi_value Input(napi_env env,napi_callback_info info){size_t n=1;napi_value v;napi_get_cb_info(env,info,&n,&v,nullptr,nullptr);auto s=n==1?String(env,v):std::string();const bool accepted=n==1 && s.size()<=4096 && s.find('\n')==std::string::npos && Client::Instance().input(s);napi_value result;napi_get_boolean(env,accepted,&result);return result;}
static napi_value MicAllowed(napi_env env,napi_callback_info info){size_t n=1;napi_value value;napi_get_cb_info(env,info,&n,&value,nullptr,nullptr);bool allowed=false;if(n==1)napi_get_value_bool(env,value,&allowed);const bool accepted=n==1&&Client::Instance().allowMicrophone(allowed);napi_value result;napi_get_boolean(env,accepted,&result);return result;}
static napi_value StoreSessionFlags(napi_env env,napi_callback_info){napi_value v;napi_create_int32(env,Client::Instance().storeSessionFlags(),&v);return v;}
static napi_value Stats(napi_env env,napi_callback_info){auto s=Client::Instance().stats();napi_value v;napi_create_string_utf8(env,s.c_str(),s.size(),&v);return v;}
static napi_value Network(napi_env env,napi_callback_info info){size_t n=2;napi_value v[2];napi_get_cb_info(env,info,&n,v,nullptr,nullptr);if(n==2){auto dir=String(env,v[0]);auto config=String(env,v[1]);if(!dir.empty()&&dir.size()<1024&&config.size()<8192)NetworkStart(dir,config);}auto s=NetworkStatus();napi_value result;napi_create_string_utf8(env,s.c_str(),s.size(),&result);return result;}
static napi_value Surface(napi_env env,napi_callback_info info){size_t n=1;napi_value v;napi_get_cb_info(env,info,&n,&v,nullptr,nullptr);auto&c=Client::Instance();std::lock_guard<std::recursive_mutex>lifecycle(c.lifecycleLock);c.surfaceAvailable=false;c.stop();if(c.window)OH_NativeWindow_DestroyNativeWindow(c.window);c.window=nullptr;try{uint64_t id=std::stoull(String(env,v));if(OH_NativeWindow_CreateNativeWindowFromSurfaceId(id,&c.window)!=0)c.setStatus("error","创建 NativeWindow 失败");}catch(...){c.setStatus("error","Surface ID 无效");}c.surfaceAvailable=c.window!=nullptr;return Void(env);}
static napi_value RtcPush(napi_env env,napi_callback_info info){size_t n=2;napi_value values[2];napi_get_cb_info(env,info,&n,values,nullptr,nullptr);void*bytes=nullptr;size_t size=0;bool accepted=false;if(n==2&&napi_get_arraybuffer_info(env,values[1],&bytes,&size)==napi_ok&&size<=2*1024*1024)accepted=Client::Instance().rtcPush(String(env,values[0]),(const uint8_t*)bytes,size);napi_value result;napi_get_boolean(env,accepted,&result);return result;}
static napi_value RtcSignal(napi_env env,napi_callback_info info){size_t n=2;napi_value values[2];napi_get_cb_info(env,info,&n,values,nullptr,nullptr);bool accepted=false;if(n==2){auto session=String(env,values[0]),body=String(env,values[1]);if(body.size()<=65536)accepted=Client::Instance().rtcSignal(session,body);}napi_value result;napi_get_boolean(env,accepted,&result);return result;}
void RegisterStoreLinkAPI(napi_env,napi_value);
void RegisterStorePathsAPI(napi_env,napi_value);
void RegisterClient(napi_env env,napi_value exports){
 RegisterStoreLinkAPI(env,exports);RegisterStorePathsAPI(env,exports);
 RegisterRtcEventAPI(env,exports);napi_property_descriptor rtcMethods[]={{"rtcPush",nullptr,RtcPush,nullptr,nullptr,nullptr,napi_default,nullptr},{"rtcSignal",nullptr,RtcSignal,nullptr,nullptr,nullptr,napi_default,nullptr}};napi_define_properties(env,exports,2,rtcMethods);
 RegisterMouseNodeAPI(env,exports);RegisterCursorChannelAPI(env,exports);
 napi_property_descriptor functions[]={{"storeSessionFlags",nullptr,StoreSessionFlags,nullptr,nullptr,nullptr,napi_default,nullptr},{"setMicrophoneAllowed",nullptr,MicAllowed,nullptr,nullptr,nullptr,napi_default,nullptr},{"network",nullptr,Network,nullptr,nullptr,nullptr,napi_default,nullptr},{"connect",nullptr,Connect,nullptr,nullptr,nullptr,napi_default,nullptr},{"disconnect",nullptr,Disconnect,nullptr,nullptr,nullptr,napi_default,nullptr},{"input",nullptr,Input,nullptr,nullptr,nullptr,napi_default,nullptr},{"stats",nullptr,Stats,nullptr,nullptr,nullptr,napi_default,nullptr},{"setSurface",nullptr,Surface,nullptr,nullptr,nullptr,napi_default,nullptr},{"connectSplit",nullptr,ConnectSplit,nullptr,nullptr,nullptr,napi_default,nullptr}};napi_define_properties(env,exports,9,functions);
 napi_value object;if(napi_get_named_property(env,exports,OH_NATIVE_XCOMPONENT_OBJ,&object)==napi_ok){OH_NativeXComponent*component=nullptr;if(napi_unwrap(env,object,reinterpret_cast<void**>(&component))==napi_ok && component){Client::Instance().attachComponent(component);}}
}
