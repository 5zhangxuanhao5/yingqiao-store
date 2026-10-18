#include "store_policy.h"
#include "../../../../../shared/TransportPolicy.hpp"
#include <napi/native_api.h>
#include <openssl/ssl.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <pthread.h>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <sstream>
#include <chrono>
#include <cmath>
#include <cctype>
#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <map>
#include <algorithm>
namespace {
double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
std::mutex lock;std::condition_variable changed;std::thread worker;std::atomic<bool>cancelled{true};int activeFD=-1;
struct Sample {yingqiao::Path path;int successes=0,failures=0;};
std::vector<Sample> samples;std::string configuration;yingqiao::StablePathChoice selection;
std::string str(napi_env e,napi_value v){size_t n=0;napi_get_value_string_utf8(e,v,nullptr,0,&n);if(n>12288)return {};std::string s(n+1,'\0');napi_get_value_string_utf8(e,v,s.data(),s.size(),&n);s.resize(n);return s;}
bool waitIO(int fd,int events,double deadline){while(!cancelled&&now()<deadline){pollfd p{fd,short(events),0};const int n=poll(&p,1,std::min(50,std::max(1,int((deadline-now())*1000))));if(n>0)return (p.revents&events)!=0;if(n<0&&errno!=EINTR)return false;}return false;}
bool tlsIO(SSL*s,int fd,unsigned char*bytes,size_t count,bool writing,double deadline){while(count&&!cancelled&&now()<deadline){int n=writing?SSL_write(s,bytes,int(count)):SSL_read(s,bytes,int(count));if(n>0){bytes+=n;count-=size_t(n);continue;}int e=SSL_get_error(s,n);if((e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE)||!waitIO(fd,e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT,deadline))return false;}return count==0;}
struct Channel{int fd=-1;SSL_CTX*ctx=nullptr;SSL*ssl=nullptr;~Channel(){if(ssl)SSL_free(ssl);if(ctx)SSL_CTX_free(ctx);std::lock_guard<std::mutex>g(lock);if(activeFD==fd)activeFD=-1;if(fd>=0)close(fd);}};
bool probe(Sample&sample,const std::string&token,const std::string&cert){
 Channel c;const double deadline=now()+1.2;c.fd=socket(AF_INET,SOCK_STREAM,0);if(c.fd<0)return false;
 {std::lock_guard<std::mutex>g(lock);if(cancelled)return false;activeFD=c.fd;}
 int yes=1;setsockopt(c.fd,IPPROTO_TCP,TCP_NODELAY,&yes,sizeof(yes));fcntl(c.fd,F_SETFL,fcntl(c.fd,F_GETFL,0)|O_NONBLOCK);
 sockaddr_in a{};a.sin_family=AF_INET;a.sin_port=htons(49563);if(inet_pton(AF_INET,sample.path.id.c_str(),&a.sin_addr)!=1)return false;
 int rc=connect(c.fd,reinterpret_cast<sockaddr*>(&a),sizeof(a));if(rc<0){if(errno!=EINPROGRESS||!waitIO(c.fd,POLLOUT,deadline))return false;int error=0;socklen_t n=sizeof(error);if(getsockopt(c.fd,SOL_SOCKET,SO_ERROR,&error,&n)<0||error)return false;}
 c.ctx=SSL_CTX_new(TLS_client_method());if(!c.ctx)return false;SSL_CTX_set_min_proto_version(c.ctx,TLS1_2_VERSION);SSL_CTX_set_verify(c.ctx,SSL_VERIFY_PEER,nullptr);
 BIO*b=BIO_new_mem_buf(cert.data(),int(cert.size()));X509*expected=b?PEM_read_bio_X509(b,nullptr,nullptr,nullptr):nullptr;if(b)BIO_free(b);if(!expected)return false;
 struct Certificate {X509*value;~Certificate(){X509_free(value);}} expectedOwner{expected};
 X509_STORE_add_cert(SSL_CTX_get_cert_store(c.ctx),expected);c.ssl=SSL_new(c.ctx);if(!c.ssl)return false;SSL_set_fd(c.ssl,c.fd);
 while(!cancelled){int n=SSL_connect(c.ssl);if(n==1)break;int e=SSL_get_error(c.ssl,n);if((e!=SSL_ERROR_WANT_READ&&e!=SSL_ERROR_WANT_WRITE)||!waitIO(c.fd,e==SSL_ERROR_WANT_READ?POLLIN:POLLOUT,deadline))return false;}
 if(cancelled)return false;X509*actual=SSL_get1_peer_certificate(c.ssl);bool same=actual&&X509_cmp(expected,actual)==0;X509_free(actual);if(!same)return false;
 unsigned char nonce[16];if(RAND_bytes(nonce,sizeof(nonce))!=1)return false;const char digits[]="0123456789abcdef";std::string challenge;for(auto x:nonce){challenge+=digits[x>>4];challenge+=digits[x&15];}
 std::string request="PATH "+token+" "+challenge+"\n";const double began=now();if(!tlsIO(c.ssl,c.fd,reinterpret_cast<unsigned char*>(request.data()),request.size(),true,deadline))return false;
 std::string header;while(header.size()<128){unsigned char ch=0;if(!tlsIO(c.ssl,c.fd,&ch,1,false,deadline))return false;if(ch=='\n')break;header+=char(ch);}
 std::istringstream in(header);std::string tag,reply,route,extra;int bytes=0;in>>tag>>reply>>route>>bytes;if(tag!="PATHOK"||reply!=challenge||(route!="usb-net"&&route!="lan")||bytes!=32768||(in>>extra))return false;
 const double first=now();unsigned char body[32768];if(!tlsIO(c.ssl,c.fd,body,sizeof(body),false,deadline))return false;
 sample.path.authenticated=true;sample.path.consumerSupported=true;sample.path.peer="pinned";sample.path.wired=route=="usb-net";sample.path.measuredAt=now();sample.path.p95ms=std::max(.05,(first-began)*1000);sample.path.goodputMbps=std::min(10000.0,(sizeof(body)*8.0/1e6)/std::max(.0001,now()-began));return true;
}
void stop(){cancelled=true;changed.notify_all();{std::lock_guard<std::mutex>g(lock);if(activeFD>=0)shutdown(activeFD,SHUT_RDWR);}if(worker.joinable())worker.join();std::lock_guard<std::mutex>g(lock);samples.clear();configuration.clear();selection.reset();}
void run(std::string token,std::string cert){sigset_t blocked;sigemptyset(&blocked);sigaddset(&blocked,SIGPIPE);pthread_sigmask(SIG_BLOCK,&blocked,nullptr);
 while(!cancelled){std::vector<Sample> next;{std::lock_guard<std::mutex>g(lock);next=samples;}
  for(size_t i=0;i<next.size()&&!cancelled;++i){auto s=next[i];if(probe(s,token,cert)){s.successes++;s.failures=0;}else{++s.failures;s.successes=0;if(s.failures>=2)s.path.authenticated=false;}
   std::lock_guard<std::mutex>g(lock);if(!cancelled&&i<samples.size())samples[i]=s;
  }
  std::unique_lock<std::mutex>g(lock);changed.wait_for(g,std::chrono::seconds(3),[]{return cancelled.load();});
 }
}
napi_value Configure(napi_env env,napi_callback_info info){size_t n=3;napi_value a[3];napi_get_cb_info(env,info,&n,a,nullptr,nullptr);bool ok=false;
 if(n==3){auto hosts=str(env,a[0]),token=str(env,a[1]),cert=str(env,a[2]);std::vector<Sample> proposed;std::istringstream in(hosts);std::string host;while(std::getline(in,host,',')&&proposed.size()<4){if(edgelinkstore::PrivateAddress(host)&&host.find(':')==std::string::npos&&std::none_of(proposed.begin(),proposed.end(),[&](auto&s){return s.path.id==host;})){Sample s;s.path.id=host;proposed.push_back(s);}}
  if(!proposed.empty()&&token.size()==64&&std::all_of(token.begin(),token.end(),[](unsigned char c){return std::isxdigit(c);})&&cert.size()>100&&cert.size()<=8192){const auto key=hosts+'\n'+token+'\n'+cert;bool same;{std::lock_guard<std::mutex>g(lock);same=configuration==key&&!cancelled;}if(!same){stop();{std::lock_guard<std::mutex>g(lock);samples=proposed;configuration=key;}cancelled=false;worker=std::thread(run,token,cert);}ok=true;}
 }
 napi_value out;napi_get_boolean(env,ok,&out);return out;
}
napi_value Status(napi_env env,napi_callback_info info){size_t n=4;napi_value a[4];napi_get_cb_info(env,info,&n,a,nullptr,nullptr);std::string active=n?str(env,a[0]):"";double elapsed=0;bool dragging=false,alive=false;if(n>1)napi_get_value_double(env,a[1],&elapsed);if(n>2)napi_get_value_bool(env,a[2],&dragging);if(n>3)napi_get_value_bool(env,a[3],&alive);if(!std::isfinite(elapsed)||elapsed<0)elapsed=0;
 std::vector<yingqiao::Path> ready;const double time=now();std::ostringstream out;out<<"{\"paths\":[";std::lock_guard<std::mutex>g(lock);bool comma=false;
 for(auto&s:samples){bool valid=s.path.authenticated&&s.successes>=2&&time-s.path.measuredAt<=10;if(valid)ready.push_back(s.path);if(comma)out<<',';comma=true;out<<"{\"host\":\""<<s.path.id<<"\",\"ready\":"<<(valid?"true":"false")<<",\"route\":\""<<(s.path.wired?"usb-net":"lan")<<"\",\"rttMs\":"<<s.path.p95ms<<",\"probeMbps\":"<<s.path.goodputMbps<<'}';}
 std::string preferred=selection.choose(ready,"pinned",active,time,time-elapsed/1000,dragging,alive);if(alive&&!active.empty()&&std::none_of(ready.begin(),ready.end(),[&](auto&p){return p.id==active;}))preferred=active;
 out<<"],\"preferredHost\":\""<<preferred<<"\"}";auto s=out.str();napi_value value;napi_create_string_utf8(env,s.data(),s.size(),&value);return value;
}
napi_value Interfaces(napi_env env,napi_callback_info){
 struct Row{bool up=false,ipv6=false;std::string host;};std::map<std::string,Row>rows;ifaddrs*first=nullptr;const int error=getifaddrs(&first)==0?0:errno;
 for(auto*p=first;p;p=p->ifa_next){std::string name=p->ifa_name;if(name.rfind("usb",0)!=0&&name.rfind("rndis",0)!=0&&name.rfind("ncm",0)!=0&&name.rfind("eth",0)!=0)continue;if(name.size()>16||name.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789")!=std::string::npos)continue;auto&r=rows[name];r.up=(p->ifa_flags&IFF_UP)!=0;if(!p->ifa_addr)continue;if(p->ifa_addr->sa_family==AF_INET){char text[INET_ADDRSTRLEN];auto*a=(sockaddr_in*)p->ifa_addr;if(inet_ntop(AF_INET,&a->sin_addr,text,sizeof(text))&&edgelinkstore::PrivateAddress(text))r.host=text;}if(p->ifa_addr->sa_family==AF_INET6)r.ipv6=true;}
 if(first)freeifaddrs(first);std::ostringstream out;out<<"{\"error\":"<<error<<",\"interfaces\":[";bool comma=false;for(auto&item:rows){if(comma)out<<',';comma=true;out<<"{\"name\":\""<<item.first<<"\",\"host\":\""<<item.second.host<<"\",\"up\":"<<(item.second.up?"true":"false")<<",\"hasIPv6\":"<<(item.second.ipv6?"true":"false")<<'}';}out<<"]}";auto s=out.str();napi_value v;napi_create_string_utf8(env,s.data(),s.size(),&v);return v;
}
napi_value Stop(napi_env env,napi_callback_info){stop();napi_value v;napi_get_undefined(env,&v);return v;}
}
void RegisterStorePathsAPI(napi_env env,napi_value exports){napi_add_env_cleanup_hook(env,[](void*){stop();},nullptr);napi_property_descriptor d[]={{"storeUSBInterfaces",nullptr,Interfaces,nullptr,nullptr,nullptr,napi_default,nullptr},{"storePathsConfigure",nullptr,Configure,nullptr,nullptr,nullptr,napi_default,nullptr},{"storePathsStatus",nullptr,Status,nullptr,nullptr,nullptr,napi_default,nullptr},{"storePathsStop",nullptr,Stop,nullptr,nullptr,nullptr,napi_default,nullptr}};napi_define_properties(env,exports,4,d);}
