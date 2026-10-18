#pragma once
// Host fixture only. These declarations are never part of the Harmony build.
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <vector>
struct FixtureValue { int32_t number=0; std::string text; };
using napi_env = void *;
using napi_value = FixtureValue *;
using napi_callback_info = std::vector<napi_value> *;
using napi_callback = napi_value (*)(napi_env,napi_callback_info);
constexpr int napi_default=0;
constexpr size_t NAPI_AUTO_LENGTH=size_t(-1);
struct napi_property_descriptor {
 const char *utf8name;void *name;napi_callback method;
 void *getter,*setter,*value;int attributes;void *data;
};
struct napi_module {
 int version,flags;const char *filename;
 napi_value (*register_func)(napi_env,napi_value);
 const char *name;void *priv;void *reserved[4];
};
inline std::map<std::string,napi_callback>& FixtureExports(){static std::map<std::string,napi_callback> v;return v;}
inline int napi_define_properties(napi_env,napi_value,size_t count,const napi_property_descriptor *d){for(size_t i=0;i<count;++i)FixtureExports()[d[i].utf8name]=d[i].method;return 0;}
inline void napi_module_register(napi_module*){}
inline int napi_get_cb_info(napi_env,napi_callback_info info,size_t *count,napi_value *values,void*,void*){*count=std::min(*count,info->size());std::copy_n(info->begin(),*count,values);return 0;}
inline int napi_get_value_int32(napi_env,napi_value v,int32_t *out){*out=v->number;return 0;}
inline int napi_get_value_string_utf8(napi_env,napi_value v,char *out,size_t count,size_t *written){*written=std::min(v->text.size(),count-1);std::memcpy(out,v->text.data(),*written);out[*written]=0;return 0;}
inline int napi_create_string_utf8(napi_env,const char *text,size_t count,napi_value *out){static FixtureValue result;result.text=count==NAPI_AUTO_LENGTH?text:std::string(text,count);*out=&result;return 0;}
