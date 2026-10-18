#include "store_policy.h"
#include <napi/native_api.h>
#include <openssl/ssl.h>
#include <openssl/pem.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <thread>
#include <mutex>
#include <atomic>
#include <string>
#include <cstring>
#include <stdexcept>
#include <cstdio>
#include <chrono>
namespace {
std::mutex mutex;std::thread worker;std::atomic<bool>cancelled{false};int activeFD=-1;
std::string phase="idle",code,result,error;
std::string arg(napi_env env,napi_value v){size_t n=0;napi_get_value_string_utf8(env,v,nullptr,0,&n);if(n>8192)return {};std::string s(n+1,'\0');napi_get_value_string_utf8(env,v,s.data(),s.size(),&n);s.resize(n);return s;}
std::string quote(const std::string&s){std::string o="\"";for(unsigned char c:s){if(c=='"'||c=='\\')o+='\\';if(c>=32)o+=char(c);}return o+'"';}
void state(std::string p,std::string e=""){std::lock_guard<std::mutex>g(mutex);phase=std::move(p);error=std::move(e);}
void cancel(){cancelled=true;{std::lock_guard<std::mutex>g(mutex);if(activeFD>=0)shutdown(activeFD,SHUT_RDWR);}if(worker.joinable())worker.join();}
struct Channel{int fd=-1;SSL_CTX*ctx=nullptr;SSL*ssl=nullptr;~Channel(){if(ssl)SSL_free(ssl);if(ctx)SSL_CTX_free(ctx);{std::lock_guard<std::mutex>g(mutex);if(activeFD==fd)activeFD=-1;}if(fd>=0)close(fd);}};
void run(std::string host,std::string cert){
 try{
  Channel c;c.fd=socket(AF_INET,SOCK_STREAM,0);if(c.fd<0)throw std::runtime_error("无法打开局域网连接");
  {std::lock_guard<std::mutex>g(mutex);if(cancelled)throw std::runtime_error("已取消连接");activeFD=c.fd;}
  sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(49563);inet_pton(AF_INET,host.c_str(),&addr.sin_addr);
  int flags=fcntl(c.fd,F_GETFL,0);fcntl(c.fd,F_SETFL,flags|O_NONBLOCK);int connected=connect(c.fd,(sockaddr*)&addr,sizeof(addr));
  if(connected<0&&errno==EINPROGRESS){pollfd p{c.fd,POLLOUT,0};int e=0;socklen_t n=sizeof(e);if(poll(&p,1,5000)>0&&getsockopt(c.fd,SOL_SOCKET,SO_ERROR,&e,&n)==0&&e==0)connected=0;}
  if(connected!=0||cancelled)throw std::runtime_error("电脑暂时无法连接，请确认两端在同一局域网");
  fcntl(c.fd,F_SETFL,flags);timeval timeout{5,0};setsockopt(c.fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(c.fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
  c.ctx=SSL_CTX_new(TLS_client_method());if(!c.ctx)throw std::runtime_error("安全连接尚未就绪");SSL_CTX_set_min_proto_version(c.ctx,TLS1_2_VERSION);SSL_CTX_set_verify(c.ctx,SSL_VERIFY_PEER,nullptr);
  BIO*b=BIO_new_mem_buf(cert.data(),int(cert.size()));X509*expected=b?PEM_read_bio_X509(b,nullptr,nullptr,nullptr):nullptr;if(b)BIO_free(b);if(!expected)throw std::runtime_error("设备身份信息不完整，请刷新设备");
  X509_STORE_add_cert(SSL_CTX_get_cert_store(c.ctx),expected);c.ssl=SSL_new(c.ctx);SSL_set_fd(c.ssl,c.fd);
  if(SSL_connect(c.ssl)!=1){X509_free(expected);throw std::runtime_error("电脑身份检查失败，请刷新设备后重试");}
  X509*actual=SSL_get1_peer_certificate(c.ssl);bool same=actual&&X509_cmp(expected,actual)==0;X509_free(expected);X509_free(actual);if(!same)throw std::runtime_error("电脑身份发生变化，请重新选择设备");
  unsigned char secret[32];const char label[]="EXPORTER-Yingqiao-Link-v1";if(SSL_export_keying_material(c.ssl,secret,sizeof(secret),label,sizeof(label)-1,nullptr,0,0)!=1)throw std::runtime_error("安全连接检查失败");
  uint32_t n=(uint32_t(secret[0])<<24)|(uint32_t(secret[1])<<16)|(uint32_t(secret[2])<<8)|secret[3];OPENSSL_cleanse(secret,sizeof(secret));char digits[7];snprintf(digits,sizeof(digits),"%06u",n%1000000);
  std::string request=std::string("LINK store-v1 ")+digits+"\n";size_t written=0;while(written<request.size()){int x=SSL_write(c.ssl,request.data()+written,int(request.size()-written));if(x<=0)throw std::runtime_error("连接请求发送失败");written+=x;}
  {std::lock_guard<std::mutex>g(mutex);code=digits;phase="awaiting";}
  timeout={1,0};setsockopt(c.fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));std::string line;const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(45);
  while(!cancelled&&std::chrono::steady_clock::now()<deadline){char data[2048];int count=SSL_read(c.ssl,data,sizeof(data));if(count>0){line.append(data,count);if(line.size()>12288)throw std::runtime_error("电脑返回了无效响应");if(line.find('\n')!=std::string::npos)break;}else{const int e=SSL_get_error(c.ssl,count);if(e==SSL_ERROR_WANT_READ||e==SSL_ERROR_WANT_WRITE||(e==SSL_ERROR_SYSCALL&&(errno==EAGAIN||errno==EWOULDBLOCK||errno==EINTR)))continue;throw std::runtime_error("电脑已关闭连接请求");}}
  if(cancelled)throw std::runtime_error("已取消连接");if(line.rfind("LINKED ",0)!=0)throw std::runtime_error(line.rfind("ERR denied",0)==0?"电脑未允许此次连接":"请在电脑允许本次连接，然后重试");
  const size_t end=line.find('\n');{std::lock_guard<std::mutex>g(mutex);result=line.substr(7,end-7);phase="ready";code.clear();}
 }catch(const std::exception&e){state(cancelled?"idle":"error",e.what());}
}
napi_value Start(napi_env env,napi_callback_info info){size_t n=2;napi_value args[2];napi_get_cb_info(env,info,&n,args,nullptr,nullptr);bool ok=false;
 if(n==2){auto h=arg(env,args[0]),c=arg(env,args[1]);if(edgelinkstore::PrivateAddress(h)&&h.find(':')==std::string::npos&&c.size()>=100&&c.size()<=8192){cancel();{std::lock_guard<std::mutex>g(mutex);phase="connecting";error.clear();result.clear();code.clear();}cancelled=false;worker=std::thread(run,h,c);ok=true;}}
 napi_value value;napi_get_boolean(env,ok,&value);return value;}
napi_value Status(napi_env env,napi_callback_info){std::string s;{std::lock_guard<std::mutex>g(mutex);s="{\"phase\":"+quote(phase)+",\"code\":"+quote(code)+",\"error\":"+quote(error)+",\"pairing\":"+quote(result)+"}";}napi_value value;napi_create_string_utf8(env,s.data(),s.size(),&value);return value;}
napi_value Stop(napi_env env,napi_callback_info){cancel();{std::lock_guard<std::mutex>g(mutex);phase="idle";code.clear();result.clear();error.clear();}napi_value v;napi_get_undefined(env,&v);return v;}
}
void RegisterStoreLinkAPI(napi_env env,napi_value exports){napi_add_env_cleanup_hook(env,[](void*){cancel();},nullptr);napi_property_descriptor methods[]={{"storeLinkStart",nullptr,Start,nullptr,nullptr,nullptr,napi_default,nullptr},{"storeLinkStatus",nullptr,Status,nullptr,nullptr,nullptr,napi_default,nullptr},{"storeLinkCancel",nullptr,Stop,nullptr,nullptr,nullptr,napi_default,nullptr}};napi_define_properties(env,exports,3,methods);}
