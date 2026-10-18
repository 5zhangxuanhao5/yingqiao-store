#include "cursor_channel.h"
#include <atomic>
#include <cmath>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <thread>

namespace {
struct Environment {
    napi_env env;
    std::thread::id owner;
    bool closing = false; // Protected by stateMutex.
};
struct Binding {
    Environment* environment = nullptr;
    uint64_t epoch = 0;
    napi_threadsafe_function function = nullptr;
    bool active = false;
    bool pending = false;
    bool hasLatest = false;
    CursorChannelSample latest;
    std::atomic<bool> released{false};
};
std::mutex stateMutex;
std::map<napi_env, Environment*> environments;
std::shared_ptr<Binding> current;
uint64_t nextEpoch = 0;
uint64_t activeEpoch = 0;
CursorChannelSample sessionLatest;
bool sessionHasLatest = false;
void queueLatest(uint64_t epoch, const CursorChannelSample* sample);
std::atomic<uint64_t> epochStat{0}, samples{0}, coalesced{0}, callbacks{0}, stale{0}, failures{0};
std::atomic<bool> bound{false};
std::atomic<int32_t> bindResult{-1};

void clearException(napi_env env)
{
    bool pending = false;
    if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
        napi_value exception;
        napi_get_and_clear_last_exception(env, &exception);
    }
}
void releaseBinding(const std::shared_ptr<Binding>& binding)
{
    if (binding && !binding->released.exchange(true)) {
        // Non-blocking abort. The finalizer, rather than this caller, owns the
        // last context reference while an already queued callback is drained.
        napi_release_threadsafe_function(binding->function, napi_tsfn_abort);
    }
}
std::shared_ptr<Binding> detachLocked()
{
    auto old = current;
    if (old) { old->active = false; old->hasLatest = false; }
    current.reset();
    bound = false;
    return old;
}
void finalize(napi_env, void* data, void*)
{
    delete static_cast<std::shared_ptr<Binding>*>(data);
}
bool property(napi_env env, napi_value object, const char* name, double value)
{
    napi_value number;
    return napi_create_double(env, value, &number) == napi_ok &&
        napi_set_named_property(env, object, name, number) == napi_ok;
}
void callJS(napi_env env, napi_value callback, void* context, void*)
{
    auto* binding = static_cast<Binding*>(context);
    CursorChannelSample sample;
    uint64_t epoch = 0;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        binding->pending = false;
        if (!env || !callback || !binding->active || current.get() != binding ||
            activeEpoch != binding->epoch || !binding->hasLatest) { ++stale; return; }
        if (binding->environment->owner != std::this_thread::get_id()) { ++failures; return; }
        sample = binding->latest;
        epoch = binding->epoch;
        binding->hasLatest = false;
    }
    napi_handle_scope scope = nullptr;
    if (napi_open_handle_scope(env, &scope) != napi_ok) { ++failures; return; }
    napi_value object, receiver, result;
    bool ok = napi_create_object(env, &object) == napi_ok &&
        property(env, object, "sessionEpoch", double(epoch)) &&
        property(env, object, "cursorSequence", double(sample.cursorSequence)) &&
        property(env, object, "sourceOwner", double(sample.sourceOwner)) &&
        property(env, object, "edgeInputAck", double(sample.edgeInputAck)) &&
        property(env, object, "visible", double(sample.visible)) &&
        property(env, object, "sampleTimeNs", double(sample.sampleTimeNs)) &&
        property(env, object, "x", sample.x) && property(env, object, "y", sample.y) &&
        napi_get_undefined(env, &receiver) == napi_ok;
    if (ok) {
        bool stillCurrent;
        {
            std::lock_guard<std::mutex> guard(stateMutex);
            stillCurrent = binding->active && current.get() == binding && activeEpoch == epoch;
        }
        // Property setters can reenter ArkTS and stop/rebind the session while
        // the sample object is built. Never call the old callback afterward.
        if (!stillCurrent) { ++stale; napi_close_handle_scope(env, scope); return; }
        ok = napi_call_function(env, receiver, callback, 1, &object, &result) == napi_ok;
    }
    if (ok) { ++callbacks; } else { ++failures; clearException(env); }
    napi_close_handle_scope(env, scope);
}
void cleanup(void* data)
{
    auto* environment = static_cast<Environment*>(data);
    std::shared_ptr<Binding> old;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        environment->closing = true;
        if (current && current->environment == environment) { old = detachLocked(); }
        environments.erase(environment->env);
    }
    releaseBinding(old);
    // An aborted TSFN can still finalize later. Its callback never dereferences
    // the environment after active=false, but keep ownership explicit as well.
    delete environment;
}
napi_value integer(napi_env env, int32_t value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}
napi_value bind(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value callback = nullptr;
    void* data = nullptr;
    napi_valuetype type;
    if (napi_get_cb_info(env, info, &argc, &callback, nullptr, &data) != napi_ok || argc != 1 ||
        napi_typeof(env, callback, &type) != napi_ok || type != napi_function) {
        bindResult = -1; return integer(env, -1);
    }
    auto* environment = static_cast<Environment*>(data);
    auto binding = std::make_shared<Binding>();
    std::shared_ptr<Binding> old;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        if (!environment || environment->closing || environment->env != env ||
            environment->owner != std::this_thread::get_id() || !activeEpoch ||
            (current && current->environment != environment)) { bindResult = -2; return integer(env, -2); }
        old = detachLocked();
        binding->environment = environment;
        binding->epoch = activeEpoch;
    }
    releaseBinding(old);
    napi_value name = nullptr;
    napi_status status = napi_create_string_utf8(env, "EdgeLinkCursor", NAPI_AUTO_LENGTH, &name);
    auto* finalizerOwner = new std::shared_ptr<Binding>(binding);
    if (status == napi_ok) {
        status = napi_create_threadsafe_function(env, callback, nullptr, name, 1, 1,
            finalizerOwner, finalize, binding.get(), callJS, &binding->function);
    }
    if (status != napi_ok) {
        delete finalizerOwner; bindResult = int32_t(status); return integer(env, int32_t(status));
    }
    // The callback must not keep the application alive after its own UI exits.
    status = napi_unref_threadsafe_function(env, binding->function);
    bool accepted = false;
    if (status == napi_ok) {
        std::lock_guard<std::mutex> guard(stateMutex);
        if (!environment->closing && activeEpoch == binding->epoch && !current) {
            binding->active = true; current = binding; bound = true; accepted = true;
        }
    }
    if (!accepted) { releaseBinding(binding); bindResult = status == napi_ok ? -3 : int32_t(status); }
    else { bindResult = 0; queueLatest(binding->epoch, nullptr); }
    return integer(env, bindResult.load());
}
napi_value unbind(napi_env env, napi_callback_info info)
{
    void* data = nullptr;
    size_t argc = 0;
    napi_get_cb_info(env, info, &argc, nullptr, nullptr, &data);
    std::shared_ptr<Binding> old;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        if (current && current->environment == data) { old = detachLocked(); }
    }
    releaseBinding(old);
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}
}

uint64_t BeginCursorSession()
{
    std::shared_ptr<Binding> old;
    uint64_t epoch;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        old = detachLocked();
        // Epochs remain exactly representable in ArkTS Number.
        if (++nextEpoch > 9007199254740991ULL) { nextEpoch = 1; }
        epoch = activeEpoch = nextEpoch;
        sessionHasLatest = false; sessionLatest = {};
        epochStat = epoch;
    }
    releaseBinding(old);
    return epoch;
}
void EndCursorSession(uint64_t epoch)
{
    std::shared_ptr<Binding> old;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        if (!epoch || activeEpoch != epoch) { return; }
        activeEpoch = 0; epochStat = 0;
        sessionHasLatest = false; sessionLatest = {};
        old = detachLocked();
    }
    releaseBinding(old);
}
namespace {
void queueLatest(uint64_t epoch, const CursorChannelSample* sample)
{
    std::shared_ptr<Binding> binding;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        if (!epoch || activeEpoch != epoch) { ++stale; return; }
        if (sample) {
            ++samples;
            if (sessionHasLatest && sample->cursorSequence <= sessionLatest.cursorSequence) { ++stale; return; }
            sessionLatest = *sample;
            sessionHasLatest = true;
        }
        // One authenticated sample survives a producer arriving before ArkTS
        // binds. A bind reads this current slot under the same lock, so a newer
        // publish can never be overwritten by a captured, older bind replay.
        if (!sessionHasLatest || !current || !current->active || current->epoch != epoch) { return; }
        binding = current;
        binding->latest = sessionLatest;
        binding->hasLatest = true;
        if (binding->pending) { ++coalesced; return; }
        // Acquire is a thread-counter operation, not a JS call. Doing it under
        // this lock prevents an abort/finalize race before the producer call.
        if (napi_acquire_threadsafe_function(binding->function) != napi_ok) { ++failures; return; }
        binding->pending = true;
    }
    const auto status = napi_call_threadsafe_function(binding->function, nullptr, napi_tsfn_nonblocking);
    if (status != napi_ok) {
        std::lock_guard<std::mutex> guard(stateMutex);
        binding->pending = false;
        ++failures;
    }
    napi_release_threadsafe_function(binding->function, napi_tsfn_release);
}
}
void PublishCursorSample(uint64_t epoch, const CursorChannelSample& sample)
{
    queueLatest(epoch, &sample);
}
void RegisterCursorChannelAPI(napi_env env, napi_value exports)
{
    Environment* environment = nullptr;
    bool created = false;
    {
        std::lock_guard<std::mutex> guard(stateMutex);
        auto found = environments.find(env);
        if (found != environments.end()) { environment = found->second; }
        else { environment = new Environment{env, std::this_thread::get_id()}; environments.emplace(env, environment); created = true; }
    }
    if (created && napi_add_env_cleanup_hook(env, cleanup, environment) != napi_ok) {
        std::lock_guard<std::mutex> guard(stateMutex);
        environments.erase(env); delete environment; bindResult = -4; return;
    }
    napi_property_descriptor descriptors[] = {
        {"bindCursorChannel", nullptr, bind, nullptr, nullptr, nullptr, napi_default, environment},
        {"unbindCursorChannel", nullptr, unbind, nullptr, nullptr, nullptr, napi_default, environment}
    };
    if (napi_define_properties(env, exports, 2, descriptors) != napi_ok) { bindResult = -5; }
}
std::string CursorChannelStats()
{
    std::ostringstream out;
    out << "\"cursorChannelBound\":" << (bound ? "true" : "false")
        << ",\"cursorChannelBindResult\":" << bindResult << ",\"cursorSessionEpoch\":" << epochStat
        << ",\"cursorChannelSamples\":" << samples << ",\"cursorChannelCoalesced\":" << coalesced
        << ",\"cursorChannelCallbacks\":" << callbacks << ",\"cursorChannelStale\":" << stale
        << ",\"cursorChannelFailures\":" << failures;
    return out.str();
}
