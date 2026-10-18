#pragma once
#include <string>
#include <arpa/inet.h>
namespace edgelinkstore {
inline bool PrivateAddress(const std::string&s){in_addr v{};if(inet_pton(AF_INET,s.c_str(),&v)==1){const auto n=ntohl(v.s_addr);return (n>>24)==10||(n>>20)==0xac1||(n>>16)==0xc0a8||(n>>16)==0xa9fe;}in6_addr a{};if(inet_pton(AF_INET6,s.c_str(),&a)!=1)return false;auto*b=a.s6_addr;if(IN6_IS_ADDR_V4MAPPED(&a)){char text[INET_ADDRSTRLEN];if(!inet_ntop(AF_INET,b+12,text,sizeof(text)))return false;return PrivateAddress(text);}return (b[0]&0xfe)==0xfc||(b[0]==0xfe&&(b[1]&0xc0)==0x80);}
inline bool Allowed(const std::string&host,int port,const std::string&mode,const std::string&transport){if(mode!="extend"||(transport!="store-avc"&&transport!="store-hevc"))return false;
#ifdef ORIGINAL_USB_TEST
 if(host=="127.0.0.1"&&port==49561)return true;
#endif
 return port==49563&&PrivateAddress(host);}
}
