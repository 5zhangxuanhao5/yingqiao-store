#pragma once
#include <vector>
#include <cstdint>
#include <stdexcept>
#include <cstring>
#include <algorithm>
namespace yingqiao::rndis {
using Bytes=std::vector<uint8_t>;
inline uint32_t Read(const uint8_t*p,size_t n,size_t at){if(at>n||n-at<4)throw std::runtime_error("rndis_short");return uint32_t(p[at])|(uint32_t(p[at+1])<<8)|(uint32_t(p[at+2])<<16)|(uint32_t(p[at+3])<<24);}
inline void Write(Bytes&b,size_t at,uint32_t v){if(at>b.size()||b.size()-at<4)throw std::runtime_error("rndis_short");for(int i=0;i<4;i++)b[at+i]=uint8_t(v>>(i*8));}
inline Bytes Initialize(uint32_t request){Bytes b(24);Write(b,0,2);Write(b,4,24);Write(b,8,request);Write(b,12,1);Write(b,20,65536);return b;}
inline Bytes Query(uint32_t request,uint32_t oid){Bytes b(28);Write(b,0,4);Write(b,4,uint32_t(b.size()));Write(b,8,request);Write(b,12,oid);Write(b,20,20);return b;}
inline Bytes Set(uint32_t request,uint32_t oid,uint32_t value){Bytes b(32);Write(b,0,5);Write(b,4,uint32_t(b.size()));Write(b,8,request);Write(b,12,oid);Write(b,16,4);Write(b,20,20);Write(b,28,value);return b;}
inline bool Complete(const Bytes&b,uint32_t type,uint32_t request){return b.size()>=16&&Read(b.data(),b.size(),0)==(type|0x80000000u)&&Read(b.data(),b.size(),4)<=b.size()&&Read(b.data(),b.size(),4)>=16&&Read(b.data(),b.size(),8)==request&&Read(b.data(),b.size(),12)==0;}
inline Bytes QueryData(const Bytes&b,uint32_t request){if(!Complete(b,4,request)||b.size()<24)throw std::runtime_error("rndis_query");size_t n=Read(b.data(),b.size(),16),at=Read(b.data(),b.size(),20);const size_t total=Read(b.data(),b.size(),4);if(at>total||total-at<8)throw std::runtime_error("rndis_offset");at+=8;if(at<24||n>total-at||n>1024)throw std::runtime_error("rndis_length");return Bytes(b.begin()+at,b.begin()+at+n);}
inline Bytes Packet(const uint8_t*data,size_t n){if(n<14||n>1518)throw std::runtime_error("rndis_frame");Bytes b(44+n);Write(b,0,1);Write(b,4,uint32_t(b.size()));Write(b,8,36);Write(b,12,uint32_t(n));std::memcpy(b.data()+44,data,n);return b;}
inline std::vector<Bytes> Parse(const uint8_t*p,size_t n){std::vector<Bytes> frames;if(n>65536)throw std::runtime_error("rndis_transfer_size");size_t at=0;while(n-at>=8){const size_t total=Read(p,n,at+4);if(total<8||total>n-at)throw std::runtime_error("rndis_message_length");if(Read(p,n,at)==1){if(total<44)throw std::runtime_error("rndis_packet_short");size_t off=Read(p,n,at+8),length=Read(p,n,at+12);if(off>total||total-off<8)throw std::runtime_error("rndis_packet_offset");off+=8;if(off<44||length<14||length>1518||length>total-off)throw std::runtime_error("rndis_packet_length");frames.emplace_back(p+at+off,p+at+off+length);}at+=total;}if(at!=n){if(n-at>7||!std::all_of(p+at,p+n,[](uint8_t b){return b==0;}))throw std::runtime_error("rndis_tail");}return frames;}
}
