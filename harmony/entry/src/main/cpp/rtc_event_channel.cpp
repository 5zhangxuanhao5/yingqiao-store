#include "rtc_event_channel.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <map>
#include <thread>
#include <sstream>
namespace {
struct Environment { napi_env env;std::thread::id thread;bool closing=false; };
struct Binding {std::shared_ptr<Environment>env;napi_threadsafe_function function=nullptr;bool active=true;std::atomic<bool>released{false};size_t bytes=0;};
struct Event {uint64_t epoch;std::string session,kind,body;size_t size;};
std::mutex mutex_;std::shared_ptr<Binding>binding_;std::map<napi_env,std::shared_ptr<Environment>>envs;uint64_t nextEpoch=0,activeEpoch=0;
std::atomic<uint64_t>published{0},delivered{0},stale{0},failed{0};
void release(const std::shared_ptr<Binding>&b){if(b&&!b->released.exchange(true))napi_release_threadsafe_function(b->function,napi_tsfn_abort);}
void finalize(napi_env,void*data,void*){delete static_cast<std::shared_ptr<Binding>*>(data);}
void js(napi_env env,napi_value callback,void*context,void*data){
 std::unique_ptr<Event>e(static_cast<Event*>(data));auto*b=static_cast<Binding*>(context);bool accepted=false;
 {std::lock_guard<std::mutex>g(mutex_);b->bytes=b->bytes>=e->size?b->bytes-e->size:0;accepted=env&&callback&&b->active&&binding_.get()==b&&activeEpoch==e->epoch&&!b->env->closing&&b->env->thread==std::this_thread::get_id();}
 if(!accepted){++stale;return;}
 napi_handle_scope scope=nullptr;if(napi_open_handle_scope(env,&scope)!=napi_ok){++failed;return;}
 napi_value object,value,receiver,result;bool ok=napi_create_object(env,&object)==napi_ok;
 auto string=[&](const char*name,const std::string&s){if(napi_create_string_utf8(env,s.data(),s.size(),&value)!=napi_ok||napi_set_named_property(env,object,name,value)!=napi_ok)ok=false;};
 if(ok){string("session",e->session);string("kind",e->kind);string("body",e->body);if(napi_create_double(env,double(e->epoch),&value)!=napi_ok||napi_set_named_property(env,object,"epoch",value)!=napi_ok)ok=false;}
 {std::lock_guard<std::mutex>g(mutex_);ok=ok&&b->active&&binding_.get()==b&&activeEpoch==e->epoch;}
 if(ok&&napi_get_undefined(env,&receiver)==napi_ok&&napi_call_function(env,receiver,callback,1,&object,&result)==napi_ok)++delivered;
 else{++failed;bool pending=false;if(napi_is_exception_pending(env,&pending)==napi_ok&&pending){napi_value error;napi_get_and_clear_last_exception(env,&error);}}
 napi_close_handle_scope(env,scope);
}
void cleanup(void*data){auto*hold=static_cast<std::shared_ptr<Environment>*>(data);std::shared_ptr<Binding>old;
 {std::lock_guard<std::mutex>g(mutex_);(*hold)->closing=true;if(binding_&&binding_->env==*hold){old=binding_;old->active=false;binding_.reset();}envs.erase((*hold)->env);}release(old);delete hold;}
napi_value bind(napi_env env,napi_callback_info info){size_t n=1;napi_value value;napi_get_cb_info(env,info,&n,&value,nullptr,nullptr);napi_valuetype type=napi_undefined;if(n)napi_typeof(env,value,&type);
 std::shared_ptr<Binding>old;std::shared_ptr<Environment>environment;
 {std::lock_guard<std::mutex>g(mutex_);if(binding_){old=binding_;old->active=false;binding_.reset();}auto found=envs.find(env);if(found!=envs.end())environment=found->second;}
 release(old);
 bool ok=false;if(n==1&&type==napi_function&&environment&&!environment->closing){auto b=std::make_shared<Binding>();b->env=environment;napi_value name;napi_create_string_utf8(env,"edgelink-rtc-current-owner",NAPI_AUTO_LENGTH,&name);auto*hold=new std::shared_ptr<Binding>(b);
  if(napi_create_threadsafe_function(env,value,nullptr,name,64,1,hold,finalize,b.get(),js,&b->function)==napi_ok){std::lock_guard<std::mutex>g(mutex_);if(!environment->closing){binding_=b;ok=true;}else{b->active=false;release(b);}}else delete hold;
 }
 napi_value result;napi_get_boolean(env,ok,&result);return result;
}
}
uint64_t BeginRtcOwner(){std::lock_guard<std::mutex>g(mutex_);activeEpoch=++nextEpoch;return activeEpoch;}
void EndRtcOwner(uint64_t epoch){std::lock_guard<std::mutex>g(mutex_);if(activeEpoch==epoch)activeEpoch=0;}
bool PublishRtcEvent(uint64_t epoch,const std::string&session,const std::string&kind,const std::string&body){if(body.size()>65536||session.size()!=64||kind.size()>16)return false;
 auto e=std::make_unique<Event>();e->epoch=epoch;e->session=session;e->kind=kind;e->body=body;e->size=body.size()+session.size()+kind.size()+64;
 std::lock_guard<std::mutex>g(mutex_);auto b=binding_;if(!b||!b->active||b->env->closing||activeEpoch!=epoch||b->bytes+e->size>256*1024){++failed;return false;}
 b->bytes+=e->size;if(napi_call_threadsafe_function(b->function,e.get(),napi_tsfn_nonblocking)!=napi_ok){b->bytes-=e->size;++failed;return false;}e.release();++published;return true;
}
void RegisterRtcEventAPI(napi_env env,napi_value exports){auto environment=std::make_shared<Environment>();environment->env=env;environment->thread=std::this_thread::get_id();{std::lock_guard<std::mutex>g(mutex_);envs[env]=environment;}auto*hold=new std::shared_ptr<Environment>(environment);napi_add_env_cleanup_hook(env,cleanup,hold);napi_property_descriptor descriptor={"bindRtcEvents",nullptr,bind,nullptr,nullptr,nullptr,napi_default,nullptr};napi_define_properties(env,exports,1,&descriptor);}
std::string RtcEventStats(){std::lock_guard<std::mutex>g(mutex_);std::ostringstream s;s<<"\"rtcOwnerEpoch\":"<<activeEpoch<<",\"rtcEventPublished\":"<<published<<",\"rtcEventDelivered\":"<<delivered<<",\"rtcEventStale\":"<<stale<<",\"rtcEventFailed\":"<<failed;return s.str();}
