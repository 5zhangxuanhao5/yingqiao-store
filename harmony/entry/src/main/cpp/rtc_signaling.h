#pragma once
#include <openssl/evp.h>
#include <algorithm>
#include <cstdint>
#include <functional>
#include <map>
#include <sstream>
#include <string>
#include <vector>
namespace edgelinkrtc {
inline bool Hex(const std::string&s,size_t min,size_t max){return s.size()>=min&&s.size()<=max&&std::all_of(s.begin(),s.end(),[](char c){return(c>='0'&&c<='9')||(c>='a'&&c<='f');});}
inline std::vector<std::string> Encode(char kind,const std::string&token,uint64_t id,const std::string&json){
 if((kind!='C'&&kind!='S')||!Hex(token,64,64)||!id||json.empty()||json.size()>65536)return{};
 const size_t count=(json.size()+2047)/2048;std::ostringstream hex;hex<<std::hex<<id;std::vector<std::string>lines;
 for(size_t n=0;n<count;n++){const size_t size=std::min<size_t>(2048,json.size()-n*2048);std::string b64(4*((size+2)/3)+1,'\0');int len=EVP_EncodeBlock((unsigned char*)b64.data(),(const unsigned char*)json.data()+n*2048,int(size));if(len<=0)return{};b64.resize(size_t(len));lines.push_back("RTC "+std::string(1,kind)+" "+token+" "+hex.str()+" "+std::to_string(n)+" "+std::to_string(count)+" "+std::to_string(json.size())+" "+b64);}
 return lines;
}
class SignalAssembler {
 struct Partial{uint64_t created=0;size_t total=0,count=0;std::vector<std::string>parts;size_t got=0;};std::map<std::string,Partial>pending_;
public:
 uint64_t expired=0,rejected=0,completed=0;
 void reset(){pending_.clear();expired=rejected=completed=0;}
 void expire(uint64_t now){for(auto i=pending_.begin();i!=pending_.end();)if(now<i->second.created||now-i->second.created>2000000000ULL){i=pending_.erase(i);++expired;}else++i;}
 // 0 is an unrelated legacy reply; 1 is accepted fragment; -1 is invalid.
 int consume(const std::string&line,const std::string&token,uint64_t now,const std::function<void(char,const std::string&)>&complete){
  if(line.rfind("RTC ",0)!=0)return 0;expire(now);
  auto fail=[this]{++rejected;return -1;};
  if(line.size()>8191||!Hex(token,64,64))return fail();
  std::istringstream f(line);std::string prefix,kind,session,id,b64,extra;size_t index=0,count=0,total=0;
  if(!(f>>prefix>>kind>>session>>id>>index>>count>>total>>b64)||(f>>extra)||session!=token||(kind!="C"&&kind!="S")||!Hex(id,1,16)||!count||count>32||index>=count||!total||total>65536||count!=(total+2047)/2048||b64.size()>2732||b64.size()%4)return fail();
  if(!std::all_of(b64.begin(),b64.end(),[](char c){return(c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='+'||c=='/'||c=='=';}))return fail();
  std::string decoded(b64.size()/4*3,'\0');int len=EVP_DecodeBlock((unsigned char*)decoded.data(),(const unsigned char*)b64.data(),int(b64.size()));if(len<0)return fail();
  if(!b64.empty()&&b64.back()=='=')--len;if(b64.size()>1&&b64[b64.size()-2]=='=')--len;
  if(len<0||size_t(len)!=std::min<size_t>(2048,total-index*2048))return fail();decoded.resize(size_t(len));
  const auto key=kind+":"+id;auto found=pending_.find(key);if(found==pending_.end()){if(pending_.size()>=2)return fail();Partial p;p.created=now;p.total=total;p.count=count;p.parts.resize(count);found=pending_.emplace(key,std::move(p)).first;}
  auto&p=found->second;if(p.total!=total||p.count!=count)return fail();if(!p.parts[index].empty()){if(p.parts[index]!=decoded)return fail();return 1;}
  p.parts[index]=std::move(decoded);p.got++;if(p.got==count){std::string body;body.reserve(total);for(auto&s:p.parts)body+=s;pending_.erase(found);++completed;complete(kind[0],body);}return 1;
 }
};
}
