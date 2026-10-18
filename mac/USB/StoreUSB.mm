#import <Foundation/Foundation.h>
#import <IOUSBHost/IOUSBHost.h>
#include "StoreUSB.h"
#include "../../usb/RNDIS.hpp"
extern "C" {
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/timeouts.h"
#include "lwip/dhcp.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "netif/ethernet.h"
#include "lwip/etharp.h"
}
#include <arpa/inet.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <map>
#include <set>
#include <chrono>
#include <sstream>
#include <algorithm>
#include <cctype>
using Bytes=yingqiao::rndis::Bytes;
static uint64_t Millis(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
extern "C" u32_t sys_now(void){return u32_t(Millis());}
namespace {
std::atomic<bool> quitting{true};std::thread manager;std::mutex stateLock;std::set<uint16_t> trustedPorts;std::string phase="idle",address;std::atomic<uint32_t>deviceMedia{99},deviceReceived{0},deviceSent{0};std::atomic<uint64_t>rxBytes{0},txBytes{0},rxFrames{0},txFrames{0};
void Phase(const std::string&s){std::lock_guard<std::mutex>g(stateLock);phase=s;}
int Property(io_service_t s,const char*key){CFStringRef k=CFStringCreateWithCString(0,key,kCFStringEncodingUTF8);CFTypeRef v=IORegistryEntryCreateCFProperty(s,k,kCFAllocatorDefault,0);int n=0;if(v&&CFGetTypeID(v)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)v,kCFNumberIntType,&n);if(v)CFRelease(v);CFRelease(k);return n;}
uint64_t DeviceID(io_service_t s){io_registry_entry_t p=0;uint64_t id=0;while(IORegistryEntryGetParentEntry(s,kIOServicePlane,&p)==KERN_SUCCESS){if(s)IOObjectRelease(s);s=p;if(IOObjectConformsTo(s,"IOUSBHostDevice")){IORegistryEntryGetRegistryEntryID(s,&id);break;}}if(s)IOObjectRelease(s);return id;}
struct Adapter {
 IOUSBHostInterface *control=nil,*data=nil;IOUSBHostPipe*incoming=nil,*outgoing=nil;
 std::atomic<bool>alive{false};std::thread reader,writer;std::mutex queueLock;std::condition_variable changed;std::deque<Bytes>rx,tx;size_t rxSize=0,txSize=0;int wake[2]={-1,-1};uint32_t request=0;size_t outgoingPacketSize=512;uint8_t mac[6]={};
 bool command(const Bytes&requestBytes,Bytes&reply){@autoreleasepool{
  NSError*e=nil;IOUSBDeviceRequest q={};q.bmRequestType=0x21;q.bRequest=0;q.wIndex=control.interfaceDescriptor->bInterfaceNumber;q.wLength=requestBytes.size();NSMutableData*d=[NSMutableData dataWithBytes:requestBytes.data() length:requestBytes.size()];NSUInteger n=0;
  if(![control sendDeviceRequest:q data:d bytesTransferred:&n completionTimeout:.5 error:&e])return false;
  for(int i=0;i<15&&!quitting;i++){q.bmRequestType=0xa1;q.bRequest=1;q.wLength=4096;d=[NSMutableData dataWithLength:4096];n=0;e=nil;
   if(![control sendDeviceRequest:q data:d bytesTransferred:&n completionTimeout:.5 error:&e])return false;
   if(n>=16){const uint8_t*p=(const uint8_t*)d.bytes;reply.assign(p,p+n);if(yingqiao::rndis::Read(p,n,0)==7)continue;return true;}usleep(10000);
  }return false;
 }}
 bool open(){io_iterator_t it=0;if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&it)!=KERN_SUCCESS)return false;io_service_t service=0;uint64_t device=0;
  while((service=IOIteratorNext(it))){if(Property(service,"idVendor")==0x12d1&&Property(service,"bInterfaceClass")==224&&Property(service,"bInterfaceProtocol")==3){IOObjectRetain(service);device=DeviceID(service);NSError*error=nil;control=[[IOUSBHostInterface alloc]initWithIOService:service options:0 queue:nil error:&error interestHandler:nil];IOObjectRelease(service);break;}IOObjectRelease(service);}IOObjectRelease(it);if(!control)return false;
  IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&it);
  while((service=IOIteratorNext(it))){IOObjectRetain(service);const auto id=DeviceID(service);if(id==device&&Property(service,"bInterfaceClass")==10){NSError*error=nil;data=[[IOUSBHostInterface alloc]initWithIOService:service options:0 queue:nil error:&error interestHandler:nil];IOObjectRelease(service);break;}IOObjectRelease(service);}IOObjectRelease(it);if(!data)return false;
  const uint8_t*base=(const uint8_t*)data.configurationDescriptor;const auto total=data.configurationDescriptor->wTotalLength;bool selected=false;
  for(size_t offset=0;offset+2<=total;){const uint8_t*d=base+offset;if(d[0]<2||offset+d[0]>total)break;
   if(d[1]==4&&d[0]>=9)selected=d[2]==data.interfaceDescriptor->bInterfaceNumber&&d[3]==data.interfaceDescriptor->bAlternateSetting;
   if(selected&&d[1]==5&&d[0]>=7&&(d[3]&3)==2){NSError*error=nil;auto pipe=[data copyPipeWithAddress:d[2] error:&error];if(d[2]&128)incoming=pipe;else{outgoing=pipe;outgoingPacketSize=(d[4]|(unsigned(d[5])<<8))&2047;}}offset+=d[0];
  }
  if(!incoming||!outgoing)return false;Bytes reply;auto req=++request;if(!command(yingqiao::rndis::Initialize(req),reply)||!yingqiao::rndis::Complete(reply,2,req))return false;
  req=++request;if(!command(yingqiao::rndis::Query(req,0x01010102),reply))return false;auto bytes=yingqiao::rndis::QueryData(reply,req);if(bytes.size()!=6)return false;memcpy(mac,bytes.data(),6);if(mac[0]&1)return false;
  req=++request;if(!command(yingqiao::rndis::Set(req,0x0001010e,0x0f),reply)||!yingqiao::rndis::Complete(reply,5,req))return false;
  if(pipe(wake)!=0)return false;for(int fd:wake)fcntl(fd,F_SETFL,fcntl(fd,F_GETFL,0)|O_NONBLOCK);alive=true;
  reader=std::thread([this]{readLoop();});writer=std::thread([this]{writeLoop();});return true;
 }
 void readLoop(){while(alive&&!quitting){@autoreleasepool{NSMutableData*d=[NSMutableData dataWithLength:65536];NSUInteger n=0;NSError*e=nil;BOOL ok=[incoming sendIORequestWithData:d bytesTransferred:&n completionTimeout:.1 error:&e];if(!ok){if(e.code==-536870186)continue;alive=false;break;}if(!n)continue;
   try{auto frames=yingqiao::rndis::Parse((const uint8_t*)d.bytes,n);std::lock_guard<std::mutex>g(queueLock);for(auto&f:frames){if(rxSize+f.size()>4*1024*1024){alive=false;break;}rxBytes+=f.size();++rxFrames;rxSize+=f.size();rx.push_back(std::move(f));}uint8_t one=1;(void)::write(wake[1],&one,1);}catch(...){alive=false;}
  }}changed.notify_all();}
 void writeLoop(){while(alive&&!quitting){Bytes frame;{std::unique_lock<std::mutex>g(queueLock);changed.wait_for(g,std::chrono::milliseconds(100),[this]{return !alive||quitting||!tx.empty();});if(tx.empty())continue;frame=std::move(tx.front());tx.pop_front();txSize-=frame.size();}
   @autoreleasepool{NSMutableData*d=[NSMutableData dataWithBytes:frame.data() length:frame.size()];NSUInteger n=0;NSError*e=nil;if(![outgoing sendIORequestWithData:d bytesTransferred:&n completionTimeout:.5 error:&e]||n!=frame.size()){alive=false;break;}txBytes+=n;++txFrames;}
  }}
 bool send(Bytes b){if(outgoingPacketSize&&b.size()%outgoingPacketSize==0)b.push_back(0);std::lock_guard<std::mutex>g(queueLock);if(!alive||txSize+b.size()>4*1024*1024)return false;txSize+=b.size();tx.push_back(std::move(b));changed.notify_one();return true;}
 ~Adapter(){alive=false;changed.notify_all();if(reader.joinable())reader.join();if(writer.joinable())writer.join();if(data)[data destroy];if(control)[control destroy];for(int fd:wake)if(fd>=0)::close(fd);}
};
struct Stream{tcp_pcb*pcb=nullptr;int fd=-1;uint16_t port=0;Bytes pending,toTCP;size_t offset=0;bool closed=false,connecting=false,eof=false,localEOF=false;};
struct Link {
 Adapter&adapter;std::string identity;netif interface{};udp_pcb*discovery=nullptr;tcp_pcb*listener=nullptr;std::vector<Stream*>streams;bool added=false;
 explicit Link(Adapter&a,std::string publicIdentity):adapter(a),identity(std::move(publicIdentity)){}
 static err_t output(netif*n,pbuf*p){auto*self=(Link*)n->state;Bytes frame(p->tot_len);pbuf_copy_partial(p,frame.data(),p->tot_len,0);return self->adapter.send(yingqiao::rndis::Packet(frame.data(),frame.size()))?ERR_OK:ERR_MEM;}
 static err_t init(netif*n){auto*self=(Link*)n->state;n->name[0]='u';n->name[1]='q';n->hwaddr_len=6;memcpy(n->hwaddr,self->adapter.mac,6);n->mtu=1500;n->flags=NETIF_FLAG_BROADCAST|NETIF_FLAG_ETHARP|NETIF_FLAG_ETHERNET;n->output=etharp_output;n->linkoutput=output;return ERR_OK;}
 static void error(void*arg,err_t){auto*s=(Stream*)arg;s->pcb=nullptr;s->closed=true;}
 static err_t receive(void*arg,tcp_pcb*,pbuf*p,err_t err){auto*s=(Stream*)arg;if(!p){s->eof=true;return ERR_OK;}if(err!=ERR_OK)return err;if(s->pending.size()-s->offset+p->tot_len>262144)return ERR_MEM;if(s->offset){s->pending.erase(s->pending.begin(),s->pending.begin()+s->offset);s->offset=0;}size_t old=s->pending.size();s->pending.resize(old+p->tot_len);pbuf_copy_partial(p,s->pending.data()+old,p->tot_len,0);pbuf_free(p);return ERR_OK;}
 static err_t accept(void*arg,tcp_pcb*pcb,err_t err){auto*self=(Link*)arg;if(err!=ERR_OK||self->streams.size()>=8){tcp_abort(pcb);return ERR_ABRT;}
  auto*s=new Stream;s->pcb=pcb;s->fd=::socket(AF_INET,SOCK_STREAM,0);if(s->fd<0){delete s;tcp_abort(pcb);return ERR_ABRT;}int yes=1;setsockopt(s->fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));fcntl(s->fd,F_SETFL,fcntl(s->fd,F_GETFL,0)|O_NONBLOCK);
  sockaddr_in local{};local.sin_len=sizeof(local);local.sin_family=AF_INET;local.sin_addr.s_addr=htonl(INADDR_LOOPBACK);if(::bind(s->fd,(sockaddr*)&local,sizeof(local))!=0){::close(s->fd);delete s;tcp_abort(pcb);return ERR_ABRT;}socklen_t n=sizeof(local);getsockname(s->fd,(sockaddr*)&local,&n);s->port=ntohs(local.sin_port);{std::lock_guard<std::mutex>g(stateLock);trustedPorts.insert(s->port);}
  local.sin_port=htons(49566);int result=::connect(s->fd,(sockaddr*)&local,sizeof(local));s->connecting=result<0&&errno==EINPROGRESS;if(result<0&&!s->connecting)s->closed=true;
  tcp_arg(pcb,s);tcp_recv(pcb,receive);tcp_err(pcb,error);tcp_nagle_disable(pcb);self->streams.push_back(s);return ERR_OK;
 }
 static void discover(void*arg,udp_pcb*pcb,pbuf*p,const ip_addr_t*from,u16_t port){auto*self=(Link*)arg;if(!p)return;Bytes bytes(p->tot_len);pbuf_copy_partial(p,bytes.data(),p->tot_len,0);pbuf_free(p);std::string query(bytes.begin(),bytes.end());if(query.size()!=40||query.rfind("YQDISC1 ",0)!=0)return;auto nonce=query.substr(8);if(!std::all_of(nonce.begin(),nonce.end(),[](unsigned char c){return std::isxdigit(c)&&!std::isupper(c);}))return;
  std::string json=self->identity;if(json.empty()||json.back()!='}')return;json.pop_back();json+=",\"nonce\":\""+nonce+"\",\"paths\":[{\"host\":\""+std::string(ip4addr_ntoa(netif_ip4_addr(&self->interface)))+"\",\"route\":\"usb-net\"}]}";pbuf*out=pbuf_alloc(PBUF_TRANSPORT,json.size(),PBUF_RAM);if(out){pbuf_take(out,json.data(),json.size());udp_sendto(pcb,out,from,port);pbuf_free(out);}
 }
 bool start(){ip4_addr_t zero{};if(!netif_add(&interface,&zero,&zero,&zero,this,init,ethernet_input))return false;added=true;netif_set_default(&interface);netif_set_up(&interface);netif_set_link_up(&interface);if(dhcp_start(&interface)!=ERR_OK)return false;
  discovery=udp_new();if(!discovery||udp_bind(discovery,IP_ADDR_ANY,49565)!=ERR_OK)return false;udp_recv(discovery,discover,this);listener=tcp_new();if(!listener||tcp_bind(listener,IP_ADDR_ANY,49563)!=ERR_OK)return false;listener=tcp_listen_with_backlog(listener,8);if(!listener)return false;tcp_arg(listener,this);tcp_accept(listener,accept);return true;
 }
 void pump(){
  std::deque<Bytes>frames;{std::lock_guard<std::mutex>g(adapter.queueLock);frames.swap(adapter.rx);adapter.rxSize=0;}
  for(auto&b:frames){auto*p=pbuf_alloc(PBUF_RAW,b.size(),PBUF_POOL);if(p){pbuf_take(p,b.data(),b.size());if(interface.input(p,&interface)!=ERR_OK)pbuf_free(p);}}
  for(auto*s:streams){if(s->closed||!s->pcb)continue;
   if(s->connecting){pollfd p{s->fd,POLLOUT,0};if(poll(&p,1,0)>0){int e=0;socklen_t n=sizeof(e);getsockopt(s->fd,SOL_SOCKET,SO_ERROR,&e,&n);s->connecting=false;if(e)s->closed=true;}if(s->connecting||s->closed)continue;}
   while(s->offset<s->pending.size()){ssize_t n=::send(s->fd,s->pending.data()+s->offset,std::min<size_t>(65535,s->pending.size()-s->offset),0);if(n>0){s->offset+=size_t(n);tcp_recved(s->pcb,u16_t(n));}else{if(n<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR)s->closed=true;break;}}
   if(s->offset==s->pending.size()){s->pending.clear();s->offset=0;if(s->eof)::shutdown(s->fd,SHUT_WR);}
   const auto available=std::min<unsigned>(tcp_sndbuf(s->pcb),16384);
   if(available&&s->toTCP.empty()&&!s->closed&&!s->localEOF){uint8_t b[16384];const ssize_t n=::recv(s->fd,b,available,0);if(n>0)s->toTCP.assign(b,b+n);else if(n==0)s->localEOF=true;else if(errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR)s->closed=true;}
   if(!s->toTCP.empty()&&tcp_sndbuf(s->pcb)>=s->toTCP.size()){const auto result=tcp_write(s->pcb,s->toTCP.data(),u16_t(s->toTCP.size()),TCP_WRITE_FLAG_COPY);if(result==ERR_OK){s->toTCP.clear();tcp_output(s->pcb);}else if(result!=ERR_MEM)s->closed=true;}
   if(s->localEOF&&s->toTCP.empty()&&s->pcb->snd_buf==TCP_SND_BUF){tcp_arg(s->pcb,nullptr);tcp_recv(s->pcb,nullptr);tcp_err(s->pcb,nullptr);if(tcp_close(s->pcb)==ERR_OK){s->pcb=nullptr;s->closed=true;}else{tcp_arg(s->pcb,s);tcp_recv(s->pcb,receive);tcp_err(s->pcb,error);}}
  }
  for(auto it=streams.begin();it!=streams.end();){Stream*s=*it;if(!s->closed){++it;continue;}cleanup(s);it=streams.erase(it);}
  sys_check_timeouts();
 }
 void hello(){if(ip4_addr_isany_val(*netif_ip4_addr(&interface)))return;auto gateway=netif_ip4_gw(&interface);if(ip4_addr_isany_val(*gateway))return;ip_addr_t target;ip_addr_copy_from_ip4(target,*gateway);const char message[]="YQHELLO1";auto*p=pbuf_alloc(PBUF_TRANSPORT,8,PBUF_RAM);if(p){pbuf_take(p,message,8);udp_sendto(discovery,p,&target,49565);pbuf_free(p);}std::lock_guard<std::mutex>g(stateLock);address=ip4addr_ntoa(netif_ip4_addr(&interface));phase="ready";}
 void cleanup(Stream*s){if(s->pcb){tcp_arg(s->pcb,nullptr);tcp_recv(s->pcb,nullptr);tcp_err(s->pcb,nullptr);tcp_abort(s->pcb);}if(s->fd>=0)::close(s->fd);{std::lock_guard<std::mutex>g(stateLock);trustedPorts.erase(s->port);}delete s;}
 ~Link(){for(auto*s:streams)cleanup(s);if(listener)tcp_close(listener);if(discovery)udp_remove(discovery);if(added){dhcp_stop(&interface);dhcp_cleanup(&interface);netif_remove(&interface);}}
};
void run(std::string publicIdentity){lwip_init();while(!quitting){@autoreleasepool{try{Adapter adapter;Phase("waiting_usb_network");if(!adapter.open()){for(int i=0;i<10&&!quitting;i++)usleep(100000);continue;}Phase("dhcp");Link link(adapter,publicIdentity);if(!link.start()){Phase("network_stack_failed");continue;}uint64_t hello=0,keepalive=Millis();const auto started=Millis();while(adapter.alive&&!quitting){link.pump();const auto now=Millis();if(now-hello>=2000){link.hello();hello=now;}if(now-keepalive>=5000){Bytes reply,request(12);yingqiao::rndis::Write(request,0,8);yingqiao::rndis::Write(request,4,12);yingqiao::rndis::Write(request,8,++adapter.request);if(!adapter.command(request,reply))break;
 for(auto field:{std::pair<uint32_t,std::atomic<uint32_t>*>{0x00010114,&deviceMedia},{0x00020102,&deviceReceived},{0x00020101,&deviceSent}}){auto id=++adapter.request;if(adapter.command(yingqiao::rndis::Query(id,field.first),reply)){auto bytes=yingqiao::rndis::QueryData(reply,id);if(bytes.size()>=4)*field.second=yingqiao::rndis::Read(bytes.data(),bytes.size(),0);}}
 keepalive=now;}if(now-started>15000&&ip4_addr_isany_val(*netif_ip4_addr(&link.interface))){Phase("dhcp_timeout");break;}
 std::vector<pollfd>fds{{adapter.wake[0],POLLIN,0}};for(auto*s:link.streams)if(!s->closed)fds.push_back({s->fd,short((!s->localEOF&&s->toTCP.empty()&&s->pcb&&tcp_sndbuf(s->pcb)>0?POLLIN:0)|(s->connecting||s->offset<s->pending.size()?POLLOUT:0)),0});poll(fds.data(),fds.size(),link.streams.empty()?100:4);uint8_t b[64];while(::read(adapter.wake[0],b,sizeof(b))>0){}
 }{std::lock_guard<std::mutex>g(stateLock);address.clear();}}catch(...){Phase("usb_protocol_failed");} }}Phase("idle");}
}
extern "C" void YQUSBStart(const char*identity){if(!quitting)return;quitting=false;rxBytes=txBytes=rxFrames=txFrames=0;manager=std::thread(run,identity?identity:"");}
extern "C" void YQUSBStop(){quitting=true;if(manager.joinable())manager.join();}
extern "C" int YQUSBTrustedPort(unsigned short port){std::lock_guard<std::mutex>g(stateLock);return trustedPorts.count(port)!=0;}
extern "C" char*YQUSBStatus(){std::lock_guard<std::mutex>g(stateLock);std::ostringstream s;s<<"{\"state\":\""<<phase<<"\",\"address\":\""<<address<<"\",\"rxBytes\":"<<rxBytes<<",\"txBytes\":"<<txBytes<<",\"rxFrames\":"<<rxFrames<<",\"txFrames\":"<<txFrames<<",\"streams\":"<<trustedPorts.size()<<",\"deviceMedia\":"<<deviceMedia<<",\"deviceReceived\":"<<deviceReceived<<",\"deviceSent\":"<<deviceSent<<'}';return strdup(s.str().c_str());}
