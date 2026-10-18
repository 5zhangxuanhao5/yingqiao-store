#include "availability.h"
#include "../store_policy.h"
#include "../split_proof.h"
#include "../route_selector.h"
#include <openssl/ssl.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

// Independent availability connections. No Client socket, decoder, input,
// window, tsnet handle, password, DNS lookup, or disk state is touched here.
namespace edgelinkavailability {
namespace {
uint64_t NowMs(){return uint64_t(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
bool Hex(const std::string& s,size_t n){return s.size()==n&&std::all_of(s.begin(),s.end(),[](unsigned char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F');});}
std::string RandomID(){std::array<unsigned char,16> b{};if(RAND_bytes(b.data(),int(b.size()))!=1)return {};static const char h[]="0123456789abcdef";std::string s;s.reserve(32);for(auto c:b){s.push_back(h[c>>4]);s.push_back(h[c&15]);}return s;}
bool LocalAddress(const std::string& host){in_addr a{};if(inet_pton(AF_INET,host.c_str(),&a)!=1)return false;const uint32_t x=ntohl(a.s_addr);return (x>>24)==10||(x>>20)==0xac1||(x>>16)==0xc0a8||(x>>16)==0xa9fe;}
bool AvailabilityState(const std::string& s){return s=="idle"||s=="busy"||s=="backgroundUnsupported";}
struct Event{std::string type,route,request;uint64_t callbackEpoch=0,workerEpoch=0;};
struct Options{std::string host,route,token,certificate,processSession;int port=49562;uint64_t epoch=0;};
struct Path{bool ready=false;uint64_t epoch=0,verifiedAt=0,measuredAt=0;unsigned probes=0;double median=0,p95=0,goodput=0;std::string error;};
class Worker;
class Manager {
public:
 static Manager& Get(){static auto* manager=new Manager;return *manager;}
 bool Configure(const std::string& host,int port,const std::string& token,const std::string& certificate);
 bool USBNetwork(const std::string& host);
 void State(const std::string& state);
 bool Reply(const std::string& id,bool accepted);
 void Stop();
 void Refresh();
 std::string Status();
 std::string ProcessSession(){std::lock_guard<std::mutex>g(lock_);return session_;}
 std::string DeviceMetadata(){std::lock_guard<std::mutex>g(lock_);return deviceMetadata_;}
 void DeviceMetadata(std::string value){std::lock_guard<std::mutex>g(lock_);deviceMetadata_=std::move(value);}
 bool CanUsePath(const std::string& route,const std::string& host,int port,const std::string& token,const std::string& certificate);
 bool Ready(const std::shared_ptr<Worker>& worker);
 void Lost(const std::shared_ptr<Worker>& worker,const std::string& error);
 void Metric(const std::shared_ptr<Worker>& worker,unsigned probes,double median,double tail,double goodput);
 void Seen(const std::shared_ptr<Worker>& worker);
 bool StartRequest(const std::shared_ptr<Worker>& worker,const std::string& request);
 void CancelRequest(const std::shared_ptr<Worker>& worker,const std::string& request);
 void EndRequest(const std::shared_ptr<Worker>& worker,const std::string& session);
 void Tick();
 void HostHint(const std::string& host){std::lock_guard<std::mutex> g(lock_);hostHint_=host;}
 std::string hostHint_;
 uint64_t NextDeadline(uint64_t otherwise){std::lock_guard<std::mutex> g(lock_);return request_?std::min(otherwise,request_->deadline):otherwise;}
 std::string CurrentState(){std::lock_guard<std::mutex> g(lock_);return state_;}
 bool IsCurrent(const std::shared_ptr<Worker>& worker);
 bool CurrentEvent(const Event& event);
 bool Emit(Event event);
#ifndef EDGELINK_AVAILABILITY_TEST
 bool BindCallback(napi_env env,napi_value callback);
 void Unbind();
 static void CallJS(napi_env,napi_value,void*,void*);
#else
 void BindTest(std::function<void(TestEvent)> callback);
 void Unbind(){std::lock_guard<std::mutex> g(callbackLock_);testCallback_={};callbackEpoch_.fetch_add(1);}
#endif
private:
 struct Request{std::string id,route;std::weak_ptr<Worker> worker;uint64_t epoch=0,deadline=0;bool replied=false;};
 std::mutex lock_,callbackLock_;
 std::shared_ptr<Worker> usb_,lan_;
 std::string token_,certificate_,session_,host_,usbNetworkHost_,state_="idle",preferred_,deviceMetadata_;
 int port_=0;uint64_t nextEpoch_=1;
 Path usbPath_,lanPath_;
 std::unique_ptr<Request> request_;
 edgelinkroute::Selector selector_;
 std::atomic<uint64_t> callbackEpoch_{1};
#ifndef EDGELINK_AVAILABILITY_TEST
 napi_threadsafe_function callback_=nullptr;
#else
 std::function<void(TestEvent)> testCallback_;
#endif
 Path& PathFor(const std::string& route){return route=="usb"?usbPath_:lanPath_;}
 void PickLocked(uint64_t now);
};

class Worker:public std::enable_shared_from_this<Worker>{
public:
 explicit Worker(Options options):options_(std::move(options)){
  if(pipe(wake_)==0){for(int fd:wake_){int f=fcntl(fd,F_GETFL,0);if(f>=0)fcntl(fd,F_SETFL,f|O_NONBLOCK);fcntl(fd,F_SETFD,FD_CLOEXEC);}}
  else wake_[0]=wake_[1]=-1;
 }
 ~Worker(){Cancel();for(int fd:wake_)if(fd>=0)close(fd);if(!options_.token.empty())OPENSSL_cleanse(options_.token.data(),options_.token.size());}
 const Options& Config()const{return options_;}
 void Launch(){auto self=shared_from_this();std::thread([self]{self->Run();}).detach();}
 void Wake(){if(wake_[1]>=0){const char b=1;auto ignored=write(wake_[1],&b,1);(void)ignored;}}
 void Cancel(){stop_.store(true);{std::lock_guard<std::mutex> g(ioLock_);if(registeredFD_>=0)shutdown(registeredFD_,SHUT_RDWR);}Wake();}
 bool WaitDone(uint64_t until){std::unique_lock<std::mutex> g(doneLock_);return doneCV_.wait_for(g,std::chrono::milliseconds(until>NowMs()?until-NowMs():0),[this]{return done_;});}
 bool Queue(const std::string& value,bool priority=false){
  if(stop_.load()||value.size()>256||value.find('\n')!=std::string::npos)return false;
  {std::lock_guard<std::mutex> g(queueLock_);if(stop_.load()||outgoing_.size()>=16)return false;if(priority)outgoing_.push_front(value);else outgoing_.push_back(value);}
  Wake();return true;
 }
 void StateChanged(){Queue("ALIVE "+Manager::Get().CurrentState(),true);}
private:
 struct Socket {
  Worker& owner;int fd=-1;
  explicit Socket(Worker& w):owner(w){fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return;std::lock_guard<std::mutex> g(owner.ioLock_);if(owner.stop_.load()){close(fd);fd=-1;}else owner.registeredFD_=fd;}
  ~Socket(){if(fd>=0){std::lock_guard<std::mutex> g(owner.ioLock_);if(owner.registeredFD_==fd)owner.registeredFD_=-1;close(fd);fd=-1;}}
 };
 struct TLS{SSL_CTX* context=nullptr;SSL* ssl=nullptr;~TLS(){if(ssl)SSL_free(ssl);if(context)SSL_CTX_free(context);}};
 Options options_;std::atomic<bool> stop_{false};std::mutex ioLock_,queueLock_,doneLock_;int registeredFD_=-1,wake_[2]{-1,-1};
 std::condition_variable doneCV_;bool done_=false;std::deque<std::string> outgoing_;std::string input_;
 std::vector<double> rtts_;std::string probe_,burst_;uint64_t probeSent_=0,probeDeadline_=0,burstStart_=0,burstDeadline_=0;unsigned probeCount_=0,burstLines_=0;size_t burstBytes_=0;double goodput_=0;bool burstAttempted_=false,measurementPublished_=false;
 int Poll(int fd,short events,uint64_t until){
  if(stop_.load())return -1;pollfd p[2]{{fd,events,0},{wake_[0],POLLIN,0}};
  const int wait=int(std::min<uint64_t>(until>NowMs()?until-NowMs():0,20000));const int n=poll(p,2,wait);
  if(stop_.load())return -1;
  if(n<0){if(errno==EINTR)return 0;return -1;}
  if(p[1].revents&POLLIN){char data[128];while(read(wake_[0],data,sizeof(data))>0){}}
  if(p[0].revents&(POLLERR|POLLHUP|POLLNVAL))return -1;
  return p[0].revents&events?1:0;
 }
 bool WaitSSL(SSL* ssl,int result,uint64_t until){
  const int error=SSL_get_error(ssl,result);if(error!=SSL_ERROR_WANT_READ&&error!=SSL_ERROR_WANT_WRITE)return false;
  while(!stop_.load()&&NowMs()<until){const int p=Poll(SSL_get_fd(ssl),error==SSL_ERROR_WANT_READ?POLLIN:POLLOUT,until);if(p<0)return false;if(p>0)return true;}return false;
 }
 bool Send(SSL* ssl,const std::string& line,uint64_t deadline){
  std::string data=line+'\n';size_t offset=0;
  while(!stop_.load()&&offset<data.size()&&NowMs()<deadline){int n=SSL_write(ssl,data.data()+offset,int(data.size()-offset));if(n>0)offset+=size_t(n);else if(!WaitSSL(ssl,n,deadline))break;}
  const bool ok=offset==data.size();if(line.rfind("STANDBY ",0)==0)OPENSSL_cleanse(data.data(),data.size());return ok;
 }
 bool ReadLine(SSL* ssl,std::string& line,size_t limit,uint64_t deadline){
  for(;;){auto end=input_.find('\n');if(end!=std::string::npos){if(end>limit)return false;line=input_.substr(0,end);input_.erase(0,end+1);return !line.empty()&&line.find('\r')==std::string::npos;}
   if(input_.size()>limit)return false;if(stop_.load()||NowMs()>=deadline)return false;
   char data[2048];int n=SSL_read(ssl,data,sizeof(data));if(n>0){input_.append(data,size_t(n));continue;}if(!WaitSSL(ssl,n,deadline))return false;
  }
 }
 bool Connect(Socket& socket,TLS& tls,uint64_t deadline){
  if(socket.fd<0)return false;int flags=fcntl(socket.fd,F_GETFL,0);if(flags<0||fcntl(socket.fd,F_SETFL,flags|O_NONBLOCK)!=0)return false;
  fcntl(socket.fd,F_SETFD,FD_CLOEXEC);int yes=1;setsockopt(socket.fd,IPPROTO_TCP,TCP_NODELAY,&yes,sizeof(yes));
#ifdef SO_NOSIGPIPE
  setsockopt(socket.fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
#endif
  sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(uint16_t(options_.port));if(inet_pton(AF_INET,options_.host.c_str(),&address.sin_addr)!=1)return false;
  int connected=connect(socket.fd,reinterpret_cast<sockaddr*>(&address),sizeof(address));
  if(connected<0&&errno!=EINPROGRESS)return false;
  while(connected<0&&!stop_.load()&&NowMs()<deadline){int p=Poll(socket.fd,POLLOUT,deadline);if(p<0)return false;if(p==0)continue;int error=0;socklen_t size=sizeof(error);if(getsockopt(socket.fd,SOL_SOCKET,SO_ERROR,&error,&size)!=0||error!=0)return false;connected=0;}
  if(connected<0||stop_.load())return false;
  tls.context=SSL_CTX_new(TLS_client_method());if(!tls.context)return false;SSL_CTX_set_min_proto_version(tls.context,TLS1_2_VERSION);SSL_CTX_set_verify(tls.context,SSL_VERIFY_PEER,nullptr);
  BIO* bio=BIO_new_mem_buf(options_.certificate.data(),int(options_.certificate.size()));if(!bio)return false;X509* expected=PEM_read_bio_X509(bio,nullptr,nullptr,nullptr);BIO_free(bio);if(!expected)return false;
  const bool stored=X509_STORE_add_cert(SSL_CTX_get_cert_store(tls.context),expected)==1;
  tls.ssl=stored?SSL_new(tls.context):nullptr;if(!tls.ssl){X509_free(expected);return false;}
  SSL_set_mode(tls.ssl,SSL_MODE_ENABLE_PARTIAL_WRITE|SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);SSL_set_fd(tls.ssl,socket.fd);
  int result=0;while(!stop_.load()&&NowMs()<deadline){result=SSL_connect(tls.ssl);if(result==1)break;if(!WaitSSL(tls.ssl,result,deadline))break;}
  X509* actual=result==1?SSL_get_peer_certificate(tls.ssl):nullptr;
  const bool verified=result==1&&SSL_get_verify_result(tls.ssl)==X509_V_OK&&actual&&X509_cmp(expected,actual)==0;
  if(actual)X509_free(actual);X509_free(expected);return verified;
 }
 void StartProbe(SSL* ssl){if(probeCount_>=5||!probe_.empty()||stop_.load())return;probe_=RandomID();if(probe_.empty()){probeCount_=5;return;}probeSent_=NowMs();probeDeadline_=probeSent_+2000;if(!Send(ssl,"RTT "+probe_,NowMs()+200)){probe_.clear();probeCount_=5;}}
 void PublishMetric(){
  if(rtts_.empty())return;auto s=rtts_;std::sort(s.begin(),s.end());const double median=s[s.size()/2],tail=s.back();
  Manager::Get().Metric(shared_from_this(),unsigned(s.size()),median,tail,goodput_);
  std::ostringstream wire;wire<<std::fixed<<std::setprecision(3)<<"METRIC "<<median<<' '<<tail<<' '<<goodput_;Queue(wire.str());
 }
 bool Dispatch(const std::string& line){
  std::istringstream fields(line);std::string kind,a,b,c,extra;fields>>kind;
  if(kind=="ALIVE"){if(!(fields>>a)||a!="OK"||(fields>>extra))return false;Manager::Get().Seen(shared_from_this());return true;}
  if(kind=="RTT"){if(!(fields>>a)||!Hex(a,32)||(fields>>extra))return false;if(a==probe_){const auto now=NowMs();if(now>=probeSent_&&now<=probeDeadline_)rtts_.push_back(std::max(.001,double(now-probeSent_)));probe_.clear();++probeCount_;}return true;}
  if(kind=="HOST"){if(!(fields>>a)||(fields>>extra))return false;if(options_.route=="usb"&&LocalAddress(a))Manager::Get().HostHint(a);return true;}
  if(kind=="START"){if(!(fields>>a>>b>>c)||!Hex(a,32)||b!="extend"||c!=options_.route||(fields>>extra))return false;if(!Manager::Get().StartRequest(shared_from_this(),a))Queue("ACK "+a+" 0",true);return true;}
  if(kind=="END"){if(!(fields>>a)||(fields>>extra)||a.empty()||a.size()>10||!std::all_of(a.begin(),a.end(),[](char c){return c>='0'&&c<='9';}))return false;Manager::Get().EndRequest(shared_from_this(),a);return true;}
  if(kind=="CANCEL"){if(!(fields>>a)||!Hex(a,32)||(fields>>extra))return false;Manager::Get().CancelRequest(shared_from_this(),a);return true;}
  if(kind=="BURST_SKIP"){if(!(fields>>a)||!Hex(a,32)||(fields>>extra))return false;if(a==burst_){burst_.clear();PublishMetric();}return true;}
  if(kind=="BURST"){
   if(!(fields>>a>>b)||!Hex(a,32)||b.size()!=1024||!std::all_of(b.begin(),b.end(),[](char x){return x=='x';})||(fields>>extra))return false;
   if(a!=burst_)return true;if(NowMs()>burstDeadline_||Manager::Get().CurrentState()!="idle"){burst_.clear();PublishMetric();return true;}
   if(!burstStart_)burstStart_=NowMs();++burstLines_;burstBytes_+=line.size()+1;
   if(burstLines_==64){const auto duration=std::max<uint64_t>(1,NowMs()-burstStart_);goodput_=double(burstBytes_)*8/(double(duration)*1000);burst_.clear();PublishMetric();}return true;
  }
  return false;
 }
 bool Session(Socket& socket,TLS& tls){
  const uint64_t connectDeadline=NowMs()+2000;
  if(!Connect(socket,tls,connectDeadline))return false;
  std::string hello="STANDBY "+options_.token+' '+options_.processSession+' '+options_.route+' '+Manager::Get().CurrentState()+' '+Manager::Get().DeviceMetadata();
  const bool sent=Send(tls.ssl,hello,connectDeadline);OPENSSL_cleanse(hello.data(),hello.size());if(!sent)return false;
  std::string line;if(!ReadLine(tls.ssl,line,256,connectDeadline)||line!="READY OK standby-v1")return false;
  if(!Manager::Get().Ready(shared_from_this()))return false;
  if(options_.route=="usb")Queue("HOST",false);
  uint64_t lastAlive=NowMs(),lastReply=lastAlive,nextMeasurement=lastAlive;
  while(!stop_.load()){
   Manager::Get().Tick();
   std::deque<std::string> writes;{std::lock_guard<std::mutex> g(queueLock_);writes.swap(outgoing_);}
   for(const auto& write:writes)if(!Send(tls.ssl,write,NowMs()+200))return false;
   uint64_t now=NowMs();
   if(now-lastAlive>=20000){if(!Send(tls.ssl,"ALIVE "+Manager::Get().CurrentState(),NowMs()+200))return false;lastAlive=NowMs();if(options_.route=="usb")Queue("HOST",false);}
   if(now-lastReply>45000)return false;
   if(!probe_.empty()&&now>=probeDeadline_){probe_.clear();++probeCount_;}
   const bool idle=Manager::Get().CurrentState()=="idle";
   // Keep standby authenticated, but defer route measurements while video is active.
   if(idle&&probeCount_<5&&probe_.empty())StartProbe(tls.ssl);
   if(idle&&probeCount_>=5&&!measurementPublished_&&probe_.empty()){
    measurementPublished_=true;PublishMetric();
    if(!burstAttempted_&&Manager::Get().CurrentState()=="idle"){
     burst_=RandomID();burstDeadline_=NowMs()+1000;burstStart_=0;burstLines_=0;burstBytes_=0;
     if(!burst_.empty()&&!Send(tls.ssl,"BURST "+burst_,NowMs()+200))return false;
    }
    burstAttempted_=true;
    nextMeasurement=NowMs()+60000;
   }
   if(!burst_.empty()&&NowMs()>=burstDeadline_){burst_.clear();PublishMetric();}
   if(idle&&burstAttempted_&&now>=nextMeasurement&&probe_.empty()&&burst_.empty()){
    // Refresh only five tiny RTT probes; bulk is once per endpoint connection.
    probeCount_=0;rtts_.clear();measurementPublished_=false;nextMeasurement=now+60000;
   }
   size_t dispatched=0;
   while(dispatched<16){auto end=input_.find('\n');if(end==std::string::npos)break;if(end>1100)return false;line=input_.substr(0,end);input_.erase(0,end+1);if(line.empty()||line.find('\r')!=std::string::npos||!Dispatch(line))return false;lastReply=NowMs();++dispatched;}
   if(dispatched==16||(idle&&probe_.empty()&&(probeCount_<5||!measurementPublished_)))continue;
   char data[4096];const int n=SSL_read(tls.ssl,data,sizeof(data));
   if(n>0){input_.append(data,size_t(n));if(input_.size()>20000)return false;continue;}
   const int error=SSL_get_error(tls.ssl,n);if(error!=SSL_ERROR_WANT_READ&&error!=SSL_ERROR_WANT_WRITE)return false;
   uint64_t until=std::min(lastAlive+20000,lastReply+45000);
   if(!probe_.empty())until=std::min(until,probeDeadline_);
   if(!burst_.empty())until=std::min(until,burstDeadline_);
   until=Manager::Get().NextDeadline(until); // Idle wakes only for socket/pipe/heartbeat.
   if(Poll(socket.fd,error==SSL_ERROR_WANT_READ?POLLIN:POLLOUT,until)<0)return false;
  }
  return true;
 }
 void Run(){
  // OpenSSL's socket BIO may use write() on platforms without SO_NOSIGPIPE.
  // Block SIGPIPE only in this worker; never change the app-wide handler.
  sigset_t signals;sigemptyset(&signals);sigaddset(&signals,SIGPIPE);pthread_sigmask(SIG_BLOCK,&signals,nullptr);
  unsigned retry=0;
  while(!stop_.load()){
   input_.clear();rtts_.clear();probe_.clear();burst_.clear();probeCount_=0;burstAttempted_=false;measurementPublished_=false;goodput_=0;
   {Socket socket(*this);TLS tls;Session(socket,tls);}
   if(stop_.load())break;
   Manager::Get().Lost(shared_from_this(),"local_connection_unavailable");
   {std::lock_guard<std::mutex> g(queueLock_);outgoing_.clear();}
   const uint64_t delay=std::min<uint64_t>(20000,1000ULL<<std::min<unsigned>(retry++,5));Poll(-1,0,NowMs()+delay);
  }
  {std::lock_guard<std::mutex> g(doneLock_);done_=true;}doneCV_.notify_all();
 }
};

bool ValidConfiguration(const std::string& host,int port,const std::string& token,const std::string& certificate){
 if((!host.empty()&&!LocalAddress(host))||port<1||port>65535||!Hex(token,64)||certificate.empty()||certificate.size()>8192)return false;
 BIO* bio=BIO_new_mem_buf(certificate.data(),int(certificate.size()));if(!bio)return false;
 X509* cert=PEM_read_bio_X509(bio,nullptr,nullptr,nullptr);BIO_free(bio);if(!cert)return false;X509_free(cert);return true;
}

bool Manager::Configure(const std::string& host,int port,const std::string& token,const std::string& certificate){
 if(!ValidConfiguration(host,port,token,certificate))return false;
 std::shared_ptr<Worker> oldUSB,oldLAN,newUSB,newLAN;
 {
  std::lock_guard<std::mutex> g(lock_);
  const bool pairChanged=token_!=token||certificate_!=certificate||port_!=port||session_.empty();
  const std::string newSession=pairChanged?RandomID():session_;if(newSession.empty())return false;
  if(pairChanged){
   oldUSB=std::move(usb_);oldLAN=std::move(lan_);usbNetworkHost_.clear();request_.reset();selector_=edgelinkroute::Selector();preferred_.clear();
   if(!token_.empty())OPENSSL_cleanse(token_.data(),token_.size());token_=token;certificate_=certificate;session_=newSession;port_=port;
  }else if(host_!=host){oldLAN=std::move(lan_);if(request_&&request_->route=="lan")request_.reset();selector_.failed(edgelinkroute::Kind::LAN,lanPath_.epoch);}
  host_=host;
  if(edgelinkstore::DebugUSBAvailable()&&!usb_){Options o{"127.0.0.1","usb",token_,certificate_,session_,port_,nextEpoch_++};usb_=newUSB=std::make_shared<Worker>(std::move(o));usbPath_=Path();usbPath_.epoch=usb_->Config().epoch;}
  if(!host.empty()&&!lan_){Options o{host,"lan",token_,certificate_,session_,port_,nextEpoch_++};lan_=newLAN=std::make_shared<Worker>(std::move(o));lanPath_=Path();lanPath_.epoch=lan_->Config().epoch;}
  if(host.empty()){lanPath_=Path();}
 }
 // Cancellation owns each worker's registered descriptor; it never closes an
 // unregistered descriptor that the OS could already have reused elsewhere.
 if(oldUSB)oldUSB->Cancel();if(oldLAN)oldLAN->Cancel();
 if(newUSB)newUSB->Launch();if(newLAN)newLAN->Launch();Refresh();
 const uint64_t deadline=NowMs()+200;if(oldUSB)oldUSB->WaitDone(deadline);if(oldLAN)oldLAN->WaitDone(deadline);
 return true;
}

// A consumer USB-network endpoint is supplied only after the paired PATH
// probe identifies usb-net. It has its own pinned STANDBY; Wi-Fi stays warm.
bool Manager::USBNetwork(const std::string& host){
 if(!host.empty()&&!LocalAddress(host))return false;
 std::shared_ptr<Worker> old,newWorker;
 {
  std::lock_guard<std::mutex> g(lock_);if(session_.empty()||token_.empty())return false;
  if(host==usbNetworkHost_){if(usb_)usb_->Wake();return true;}
  usbNetworkHost_=host;old=std::move(usb_);selector_.failed(edgelinkroute::Kind::USB,usbPath_.epoch);usbPath_=Path();
  if(request_&&request_->route=="usb")request_.reset();
  const std::string endpoint=host.empty()?(edgelinkstore::DebugUSBAvailable()?"127.0.0.1":""):host;
  if(!endpoint.empty()){
   Options options{endpoint,"usb",token_,certificate_,session_,host.empty()?port_:49563,nextEpoch_++};
   usb_=newWorker=std::make_shared<Worker>(std::move(options));usbPath_.epoch=usb_->Config().epoch;
  }
  if(preferred_=="usb")preferred_.clear();PickLocked(NowMs());
 }
 if(old)old->Cancel();if(newWorker)newWorker->Launch();
 if(old)old->WaitDone(NowMs()+200);return true;
}

bool Manager::IsCurrent(const std::shared_ptr<Worker>& worker){
 std::lock_guard<std::mutex> g(lock_);return worker&&(worker->Config().route=="usb"?usb_:lan_)==worker;
}

void Manager::PickLocked(uint64_t now){
 auto record=[&](const std::shared_ptr<Worker>& worker,const Path& path,edgelinkroute::Kind kind){
  if(!worker)return;edgelinkroute::Sample sample;
  sample.kind=kind;sample.endpoint=worker->Config().host+":"+std::to_string(worker->Config().port);sample.epoch=path.epoch;
  sample.verifiedAtMs=path.verifiedAt;sample.measuredAtMs=path.measuredAt;sample.authenticated=path.ready;sample.reachable=path.ready;
  sample.probes=path.probes;sample.rttMedianMs=path.median;sample.rttP95Ms=path.p95;sample.goodputMbps=path.goodput;
  // READY is an authenticated protocol promise from the paired Mac on its
  // dedicated local-only ingress. Private IPs and a route label are not proof.
  sample.localProof=path.ready;selector_.record(std::move(sample));
 };
 record(usb_,usbPath_,edgelinkroute::Kind::USB);record(lan_,lanPath_,edgelinkroute::Kind::LAN);
 if(state_=="busy"&&((preferred_=="usb"&&usbPath_.ready)||(preferred_=="lan"&&lanPath_.ready)))return;
 const auto plan=selector_.start(edgelinkroute::Mode::Extend,now);
 preferred_=plan.immediate?(plan.immediate->kind==edgelinkroute::Kind::USB?"usb":"lan"):"";
}

bool Manager::Ready(const std::shared_ptr<Worker>& worker){
 {
  std::lock_guard<std::mutex> g(lock_);if((worker->Config().route=="usb"?usb_:lan_)!=worker)return false;
  auto& path=PathFor(worker->Config().route);path.ready=true;path.verifiedAt=NowMs();path.error.clear();PickLocked(path.verifiedAt);
 }
 // Foreground can start now. Five RTT probes and the optional local burst do
 // not delay this event, create a virtual display, or initiate media capture.
 Emit({"ready",worker->Config().route,"",callbackEpoch_.load(),worker->Config().epoch});return true;
}

void Manager::Lost(const std::shared_ptr<Worker>& worker,const std::string& error){
 std::string canceled;bool wasReady=false;
 {
  std::lock_guard<std::mutex> g(lock_);if((worker->Config().route=="usb"?usb_:lan_)!=worker)return;
  auto& path=PathFor(worker->Config().route);wasReady=path.ready;path.ready=false;path.error=error;
  selector_.failed(worker->Config().route=="usb"?edgelinkroute::Kind::USB:edgelinkroute::Kind::LAN,path.epoch);
  if(request_&&request_->epoch==worker->Config().epoch){canceled=request_->id;request_.reset();}
  PickLocked(NowMs());
 }
 if(!canceled.empty())Emit({"cancel",worker->Config().route,canceled,callbackEpoch_.load(),worker->Config().epoch});
 if(wasReady)Emit({"lost",worker->Config().route,"",callbackEpoch_.load(),worker->Config().epoch});
}

void Manager::Seen(const std::shared_ptr<Worker>& worker){
 std::lock_guard<std::mutex> g(lock_);if((worker->Config().route=="usb"?usb_:lan_)!=worker)return;
 auto& path=PathFor(worker->Config().route);if(path.ready){path.verifiedAt=NowMs();PickLocked(path.verifiedAt);}
}

void Manager::Metric(const std::shared_ptr<Worker>& worker,unsigned probes,double median,double tail,double goodput){
 if(!probes||probes>5||!std::isfinite(median)||!std::isfinite(tail)||!std::isfinite(goodput)||median<=0||tail<median||tail>10000||goodput<0||goodput>100000)return;
 std::lock_guard<std::mutex> g(lock_);if((worker->Config().route=="usb"?usb_:lan_)!=worker)return;
 auto& path=PathFor(worker->Config().route);if(!path.ready)return;
 path.probes=probes;path.median=median;path.p95=tail;path.goodput=goodput;path.measuredAt=NowMs();path.verifiedAt=path.measuredAt;PickLocked(path.measuredAt);
}

bool Manager::StartRequest(const std::shared_ptr<Worker>& worker,const std::string& id){
 {
  std::lock_guard<std::mutex> g(lock_);
  if((worker->Config().route=="usb"?usb_:lan_)!=worker||!PathFor(worker->Config().route).ready||state_!="idle"||!Hex(id,32))return false;
  if(request_){if(request_->id==id&&request_->epoch==worker->Config().epoch){if(request_->replied)worker->Queue("ACK "+id+" 1",true);return true;}return false;}
  request_=std::make_unique<Request>(Request{id,worker->Config().route,worker,worker->Config().epoch,NowMs()+10000,false});
 }
 if(Emit({"start",worker->Config().route,id,callbackEpoch_.load(),worker->Config().epoch}))return true;
 std::lock_guard<std::mutex> g(lock_);if(request_&&request_->id==id&&request_->epoch==worker->Config().epoch)request_.reset();return false;
}

void Manager::EndRequest(const std::shared_ptr<Worker>& worker,const std::string& session){
 {std::lock_guard<std::mutex> g(lock_);if((worker->Config().route=="usb"?usb_:lan_)!=worker||!PathFor(worker->Config().route).ready||state_!="busy")return;}
 Emit({"end",worker->Config().route,session,callbackEpoch_.load(),worker->Config().epoch});
}

void Manager::CancelRequest(const std::shared_ptr<Worker>& worker,const std::string& id){
 {
  std::lock_guard<std::mutex> g(lock_);if(!request_||request_->id!=id||request_->epoch!=worker->Config().epoch)return;request_.reset();
 }
 Emit({"cancel",worker->Config().route,id,callbackEpoch_.load(),worker->Config().epoch});
}

bool Manager::Reply(const std::string& id,bool accepted){
 if(!Hex(id,32))return false;
 std::lock_guard<std::mutex> g(lock_);
 if(!request_||request_->id!=id||request_->replied||NowMs()>=request_->deadline)return false;
 auto worker=request_->worker.lock();if(!worker||(worker->Config().route=="usb"?usb_:lan_)!=worker||!PathFor(worker->Config().route).ready)return false;
 const bool allow=accepted&&state_=="idle";
 if(!worker->Queue("ACK "+id+(allow?" 1":" 0"),true))return false;
 if(allow){request_->replied=true;request_->deadline=NowMs()+20000;}else request_.reset();
 return allow==accepted;
}

void Manager::State(const std::string& state){
 if(!AvailabilityState(state))return;
 std::shared_ptr<Worker> usb,lan,canceledWorker;std::string canceled;
 {
  std::lock_guard<std::mutex> g(lock_);if(state_==state)return;
  if(state!="idle"&&request_&&!request_->replied){canceledWorker=request_->worker.lock();canceled=request_->id;request_.reset();}
  if(state=="idle"&&state_=="busy"&&request_&&request_->replied)request_.reset();
  state_=state;usb=usb_;lan=lan_;PickLocked(NowMs());
 }
 if(canceledWorker){canceledWorker->Queue("ACK "+canceled+" 0",true);Emit({"cancel",canceledWorker->Config().route,canceled,callbackEpoch_.load(),canceledWorker->Config().epoch});}
 if(usb)usb->StateChanged();if(lan)lan->StateChanged();
}

void Manager::Tick(){
 std::shared_ptr<Worker> worker;std::string id;bool notify=false,ack=false;
 {
  std::lock_guard<std::mutex> g(lock_);if(!request_||NowMs()<request_->deadline)return;
  worker=request_->worker.lock();id=request_->id;ack=!request_->replied;notify=ack||state_!="busy";request_.reset();
 }
 if(worker){if(ack)worker->Queue("ACK "+id+" 0",true);if(notify)Emit({"cancel",worker->Config().route,id,callbackEpoch_.load(),worker->Config().epoch});}
}

bool Manager::CurrentEvent(const Event& event){
 if(event.callbackEpoch!=callbackEpoch_.load())return false;
 std::lock_guard<std::mutex> g(lock_);const auto worker=event.route=="usb"?usb_:lan_;
 if(!worker||worker->Config().epoch!=event.workerEpoch)return false;
 if(event.type=="start")return state_=="idle"&&request_&&request_->id==event.request&&request_->epoch==event.workerEpoch&&!request_->replied&&NowMs()<request_->deadline;
 if(event.type=="ready")return PathFor(event.route).ready;
 if(event.type=="lost")return !PathFor(event.route).ready;
 return event.type=="cancel"||(event.type=="end"&&state_=="busy"&&PathFor(event.route).ready);
}

void Manager::Stop(){
 Unbind();std::shared_ptr<Worker> usb,lan;
 {
  std::lock_guard<std::mutex> g(lock_);usb=std::move(usb_);lan=std::move(lan_);request_.reset();usbPath_=Path();lanPath_=Path();preferred_.clear();host_.clear();usbNetworkHost_.clear();hostHint_.clear();session_.clear();port_=0;state_="idle";selector_=edgelinkroute::Selector();
  if(!token_.empty())OPENSSL_cleanse(token_.data(),token_.size());token_.clear();certificate_.clear();
 }
 if(usb)usb->Cancel();if(lan)lan->Cancel();
 const uint64_t deadline=NowMs()+200;if(usb)usb->WaitDone(deadline);if(lan)lan->WaitDone(deadline);
 // Detached threads retain their own Worker. A slow OS teardown cannot leave
 // a UI-thread join or allow a worker to reference freed storage.
}

void Manager::Refresh(){
 std::shared_ptr<Worker> usb,lan;
 {std::lock_guard<std::mutex> g(lock_);usb=usb_;lan=lan_;}
 // User intent can interrupt exponential reconnect backoff without rebinding
 // the callback, changing its epoch, or replacing a live USB connection.
 if(usb){usb->StateChanged();usb->Wake();}if(lan){lan->StateChanged();lan->Wake();}
}

std::string Manager::Status(){
 Tick();std::lock_guard<std::mutex> g(lock_);PickLocked(NowMs());
 std::ostringstream json;json<<std::fixed<<std::setprecision(3)<<"{\"usbHost\":\""<<(usb_?usb_->Config().host:"")<<"\",\"usbPort\":"<<(usb_?usb_->Config().port:0)<<",\"hostHint\":\""<<hostHint_<<"\",\"paths\":[";
 auto emit=[&](const char* route,const Path& p){json<<"{\"route\":\""<<route<<"\",\"ready\":"<<(p.ready?"true":"false")<<",\"rttMedianMs\":"<<p.median<<",\"rttP95Ms\":"<<p.p95<<",\"goodputMbps\":"<<p.goodput<<'}';};
 emit("usb",usbPath_);json<<',';emit("lan",lanPath_);json<<"],\"preferredRoute\":\""<<preferred_<<"\",\"dualMediaSupported\":false}";return json.str();
}

bool Manager::CanUsePath(const std::string& route,const std::string& host,int port,const std::string& token,const std::string& certificate){
 if(route!="usb"&&route!="lan")return false;
 std::lock_guard<std::mutex> g(lock_);const auto worker=route=="usb"?usb_:lan_;
 const auto& path=PathFor(route);const auto now=NowMs();
 return worker&&path.ready&&path.epoch==worker->Config().epoch&&now>=path.verifiedAt&&now-path.verifiedAt<=30000&&
  worker->Config().host==host&&worker->Config().port==port&&certificate==certificate_&&token.size()==token_.size()&&!token.empty()&&CRYPTO_memcmp(token.data(),token_.data(),token.size())==0;
}

#ifndef EDGELINK_AVAILABILITY_TEST
bool Manager::BindCallback(napi_env env,napi_value callback){
 napi_valuetype type;if(napi_typeof(env,callback,&type)!=napi_ok||type!=napi_function)return false;
 napi_value name;if(napi_create_string_utf8(env,"EdgeLinkLocalAvailability",NAPI_AUTO_LENGTH,&name)!=napi_ok)return false;
 napi_threadsafe_function fresh=nullptr;
 if(napi_create_threadsafe_function(env,callback,nullptr,name,16,1,nullptr,nullptr,nullptr,CallJS,&fresh)!=napi_ok)return false;
 napi_unref_threadsafe_function(env,fresh);
 {std::lock_guard<std::mutex> g(callbackLock_);auto old=callback_;callbackEpoch_.fetch_add(1);callback_=fresh;if(old)napi_release_threadsafe_function(old,napi_tsfn_abort);}
 std::shared_ptr<Worker> worker;std::string id;
 {std::lock_guard<std::mutex> g(lock_);if(request_&&!request_->replied){worker=request_->worker.lock();id=request_->id;request_.reset();}}
 if(worker){worker->Queue("ACK "+id+" 0",true);Emit({"cancel",worker->Config().route,id,callbackEpoch_.load(),worker->Config().epoch});}
 return true;
}
void Manager::Unbind(){std::lock_guard<std::mutex> g(callbackLock_);callbackEpoch_.fetch_add(1);if(callback_){napi_release_threadsafe_function(callback_,napi_tsfn_abort);callback_=nullptr;}}
bool Manager::Emit(Event event){
 auto data=std::make_unique<Event>(std::move(event));std::lock_guard<std::mutex> g(callbackLock_);
 if(!callback_||data->callbackEpoch!=callbackEpoch_.load())return false;
 if(napi_call_threadsafe_function(callback_,data.get(),napi_tsfn_nonblocking)!=napi_ok)return false;data.release();return true;
}
void Manager::CallJS(napi_env env,napi_value callback,void*,void* raw){
 std::unique_ptr<Event> event(static_cast<Event*>(raw));if(!event||!env||!callback||!Get().CurrentEvent(*event))return;
 napi_value object,undefined,value;if(napi_create_object(env,&object)!=napi_ok)return;
 auto field=[&](const char* key,const std::string& s){return napi_create_string_utf8(env,s.data(),s.size(),&value)==napi_ok&&napi_set_named_property(env,object,key,value)==napi_ok;};
 if(!field("type",event->type)||!field("route",event->route)||(!event->request.empty()&&!field("requestId",event->request)))return;
 napi_get_undefined(env,&undefined);napi_value ignored;napi_call_function(env,undefined,callback,1,&object,&ignored);
}
#else
void Manager::BindTest(std::function<void(TestEvent)> callback){
 {std::lock_guard<std::mutex> g(callbackLock_);testCallback_=std::move(callback);callbackEpoch_.fetch_add(1);}
 std::shared_ptr<Worker> worker;std::string id;
 {std::lock_guard<std::mutex> g(lock_);if(request_&&!request_->replied){worker=request_->worker.lock();id=request_->id;request_.reset();}}
 if(worker){worker->Queue("ACK "+id+" 0",true);Emit({"cancel",worker->Config().route,id,callbackEpoch_.load(),worker->Config().epoch});}
}
bool Manager::Emit(Event event){
 std::function<void(TestEvent)> callback;{std::lock_guard<std::mutex> g(callbackLock_);if(event.callbackEpoch!=callbackEpoch_.load())return false;callback=testCallback_;}
 if(!callback||!CurrentEvent(event))return false;callback({event.type,event.route,event.request});return true;
}
#endif
} // anonymous namespace

std::string CurrentProcessSession(){return Manager::Get().ProcessSession();}
std::string CurrentDeviceMetadata(){return Manager::Get().DeviceMetadata();}
bool CanUseVerifiedLocalPath(const std::string& route,const std::string& host,int standbyPort,const std::string& token,const std::string& certificate){return Manager::Get().CanUsePath(route,host,standbyPort,token,certificate);}

#ifdef EDGELINK_AVAILABILITY_TEST
bool ConfigureForTest(const std::string& host,int port,const std::string& token,const std::string& certificate,std::function<void(TestEvent)> callback){
 if(!ValidConfiguration(host,port,token,certificate))return false;Manager::Get().BindTest(std::move(callback));return Manager::Get().Configure(host,port,token,certificate);
}
void StateForTest(const std::string& state){Manager::Get().State(state);}
bool ReplyForTest(const std::string& request,bool accepted){return Manager::Get().Reply(request,accepted);}
void StopForTest(){Manager::Get().Stop();}
void RefreshForTest(){Manager::Get().Refresh();}
std::string StatusForTest(){return Manager::Get().Status();}
#endif
} // edgelinkavailability

#ifndef EDGELINK_AVAILABILITY_TEST
namespace {
using edgelinkavailability::Manager;
bool StringArgument(napi_env env,napi_value value,size_t limit,std::string& result){
 napi_valuetype type;size_t size=0;if(napi_typeof(env,value,&type)!=napi_ok||type!=napi_string||napi_get_value_string_utf8(env,value,nullptr,0,&size)!=napi_ok||size>limit)return false;
 std::vector<char> buffer(size+1);size_t actual=0;const bool ok=napi_get_value_string_utf8(env,value,buffer.data(),buffer.size(),&actual)==napi_ok&&actual==size;
 if(ok)result.assign(buffer.data(),actual);OPENSSL_cleanse(buffer.data(),buffer.size());return ok;
}
napi_value Undefined(napi_env env){napi_value value=nullptr;napi_get_undefined(env,&value);return value;}
napi_value ConfigureJS(napi_env env,napi_callback_info info){
 napi_value args[5];size_t count=5;napi_get_cb_info(env,info,&count,args,nullptr,nullptr);
 std::string host,token,certificate;int32_t port=0;
 const bool valid=count==5&&StringArgument(env,args[0],15,host)&&napi_get_value_int32(env,args[1],&port)==napi_ok&&StringArgument(env,args[2],64,token)&&StringArgument(env,args[3],8192,certificate)&&edgelinkavailability::ValidConfiguration(host,port,token,certificate);
 const bool ok=valid&&Manager::Get().BindCallback(env,args[4])&&Manager::Get().Configure(host,port,token,certificate);
 if(!token.empty())OPENSSL_cleanse(token.data(),token.size());if(!ok)napi_throw_error(env,"availability_invalid_config","Local availability configuration is invalid");return Undefined(env);
}
napi_value USBNetworkJS(napi_env env,napi_callback_info info){napi_value args[1];size_t count=1;napi_get_cb_info(env,info,&count,args,nullptr,nullptr);std::string host;const bool ok=count==1&&StringArgument(env,args[0],64,host)&&Manager::Get().USBNetwork(host);napi_value result;napi_get_boolean(env,ok,&result);return result;}
napi_value StateJS(napi_env env,napi_callback_info info){napi_value args[1];size_t count=1;napi_get_cb_info(env,info,&count,args,nullptr,nullptr);std::string state;if(count==1&&StringArgument(env,args[0],32,state)&&edgelinkavailability::AvailabilityState(state))Manager::Get().State(state);else napi_throw_error(env,"availability_invalid_state","Availability state is invalid");return Undefined(env);}
napi_value ReplyJS(napi_env env,napi_callback_info info){napi_value args[2];size_t count=2;napi_get_cb_info(env,info,&count,args,nullptr,nullptr);std::string id;bool accepted=false;const bool ok=count==2&&StringArgument(env,args[0],32,id)&&napi_get_value_bool(env,args[1],&accepted)==napi_ok&&Manager::Get().Reply(id,accepted);napi_value value;napi_get_boolean(env,ok,&value);return value;}
napi_value StopJS(napi_env env,napi_callback_info){Manager::Get().Stop();return Undefined(env);}
napi_value RefreshJS(napi_env env,napi_callback_info){Manager::Get().Refresh();return Undefined(env);}
napi_value StatusJS(napi_env env,napi_callback_info){const auto json=Manager::Get().Status();napi_value value;napi_create_string_utf8(env,json.data(),json.size(),&value);return value;}
napi_value IdentityJS(napi_env env,napi_callback_info info){napi_value arg;size_t n=1;napi_get_cb_info(env,info,&n,&arg,nullptr,nullptr);std::string value;if(n==1&&StringArgument(env,arg,256,value)&&value.rfind("device-v1:",0)==0&&value.find_first_of(" \r\n")==std::string::npos)Manager::Get().DeviceMetadata(value);return Undefined(env);}
void Cleanup(void*){Manager::Get().Stop();}
}
void RegisterAvailability(napi_env env,napi_value exports){
 napi_property_descriptor methods[]={
  {"availabilityUSBNetwork",nullptr,USBNetworkJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityConfigure",nullptr,ConfigureJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityState",nullptr,StateJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityReply",nullptr,ReplyJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityStop",nullptr,StopJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityRefresh",nullptr,RefreshJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityIdentity",nullptr,IdentityJS,nullptr,nullptr,nullptr,napi_default,nullptr},
  {"availabilityStatus",nullptr,StatusJS,nullptr,nullptr,nullptr,napi_default,nullptr}
 };
 napi_define_properties(env,exports,sizeof(methods)/sizeof(methods[0]),methods);napi_add_env_cleanup_hook(env,Cleanup,nullptr);
}
#endif
