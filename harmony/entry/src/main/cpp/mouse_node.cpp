#include "mouse_node.h"

#include <arkui/native_interface.h>
#include <arkui/native_node.h>
#include <arkui/native_node_napi.h>
#include <arkui/ui_input_event.h>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <map>
#include <mutex>
#include <sstream>
#include <thread>

namespace {
struct Environment {
    napi_env env;
    std::thread::id owner;
    std::atomic<bool> closing{false};
};

struct Binding {
    Environment* context = nullptr;
    napi_env env = nullptr;
    std::thread::id owner;
    ArkUI_NodeHandle node = nullptr;
    napi_ref frame = nullptr;
    napi_ref callback = nullptr;
    uintptr_t cookie = 0;
    std::atomic<bool> active{false};
    bool registered = false; // Registration/lifecycle operations run on the owner thread.
};

std::mutex bindingMutex;
std::shared_ptr<Binding> current;
std::mutex environmentMutex;
std::map<napi_env, Environment*> environments;
std::atomic<uintptr_t> nextCookie{1};
std::atomic<bool> bound{false};
std::atomic<int32_t> result{-1}, unregisterResult{0};
// 0 exports, 1 arguments/owner, 2 Node API initialization, 3 node handle,
// 4 NAPI references, 5 binding ownership, 6 CommonEvent registration.
std::atomic<int32_t> resultStage{0};
std::atomic<uint64_t> events{0}, rawMoves{0}, callbackFailures{0}, wrongThread{0}, staleEvents{0};

void clearException(napi_env env)
{
    bool pending = false;
    if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
        napi_value exception;
        napi_get_and_clear_last_exception(env, &exception);
    }
}

void deleteReferences(const std::shared_ptr<Binding>& binding, bool canUseNapi)
{
    if (canUseNapi) {
        if (binding->callback) { napi_delete_reference(binding->env, binding->callback); }
        if (binding->frame) { napi_delete_reference(binding->env, binding->frame); }
    }
    binding->callback = nullptr;
    binding->frame = nullptr;
}

void unbind(Environment* context, bool ownerThread)
{
    std::shared_ptr<Binding> binding;
    {
        std::lock_guard<std::mutex> guard(bindingMutex);
        if (!current || current->context != context) { return; }
        binding = current;
        // Unregister can synchronously deliver a final event. Disable delivery first,
        // then unregister, clear shared state, and only then drop strong NAPI references.
        binding->active.store(false);
        bound.store(false);
    }
    if (binding->registered && ownerThread) {
        unregisterResult.store(OH_ArkUI_NativeModule_UnregisterCommonEvent(binding->node, NODE_ON_MOUSE));
    }
    {
        std::lock_guard<std::mutex> guard(bindingMutex);
        if (current == binding) { current.reset(); }
    }
    // An environment is responsible for its own references during an abnormal
    // off-owner cleanup. Never call NAPI or ArkUI from that unexpected thread.
    deleteReferences(binding, ownerThread);
}

void onMouse(ArkUI_NodeEvent* event)
{
    events.fetch_add(1);
    if (!event) { return; }
    const auto cookie = reinterpret_cast<uintptr_t>(OH_ArkUI_NodeEvent_GetUserData(event));
    const auto node = OH_ArkUI_NodeEvent_GetNodeHandle(event);
    std::shared_ptr<Binding> binding;
    {
        std::lock_guard<std::mutex> guard(bindingMutex);
        if (!current || !current->active.load() || current->cookie != cookie || current->node != node) {
            staleEvents.fetch_add(1);return;
        }
        binding = current;
    }
    if (std::this_thread::get_id() != binding->owner) { wrongThread.fetch_add(1);return; }
    if (OH_ArkUI_NodeEvent_GetEventType(event) != NODE_ON_MOUSE) { return; }
    auto input = OH_ArkUI_NodeEvent_GetInputEvent(event);
    if (!input || OH_ArkUI_UIInputEvent_GetType(input) != ARKUI_UIINPUTEVENT_TYPE_MOUSE ||
        OH_ArkUI_MouseEvent_GetMouseAction(input) != 3) { return; }

    struct Field { const char* name; double value; };
    const Field fields[] = {
        {"nativeAction", 3}, {"nativeButton", static_cast<double>(OH_ArkUI_MouseEvent_GetMouseButton(input))},
        {"source", static_cast<double>(OH_ArkUI_UIInputEvent_GetSourceType(input))},
        {"sourceTool", static_cast<double>(OH_ArkUI_UIInputEvent_GetToolType(input))},
        {"deviceId", static_cast<double>(OH_ArkUI_UIInputEvent_GetDeviceId(input))},
        {"timestamp", static_cast<double>(OH_ArkUI_UIInputEvent_GetEventTime(input))},
        // This is the ArkTS FrameNode CommonEvent route: SetCommonOnMouse
        // already divides these six coordinates by density. Its C_MOUSE
        // getters return those values directly, despite generic SDK px docs.
        // Preserve vp here; dividing again misplaces the relative-mode anchor.
        {"x", OH_ArkUI_PointerEvent_GetX(input)},
        {"y", OH_ArkUI_PointerEvent_GetY(input)},
        {"windowX", OH_ArkUI_PointerEvent_GetWindowX(input)},
        {"windowY", OH_ArkUI_PointerEvent_GetWindowY(input)},
        {"displayX", OH_ArkUI_PointerEvent_GetDisplayX(input)},
        {"displayY", OH_ArkUI_PointerEvent_GetDisplayY(input)},
        // API 26 exposes hardware movement units; these must not be divided by density.
        {"rawDeltaX", OH_ArkUI_MouseEvent_GetRawDeltaX(input)},
        {"rawDeltaY", OH_ArkUI_MouseEvent_GetRawDeltaY(input)}
    };
    for (const auto& field : fields) {
        if (!std::isfinite(field.value)) { callbackFailures.fetch_add(1);return; }
    }
    rawMoves.fetch_add(1);
    napi_handle_scope scope = nullptr;
    const napi_env env = binding->env;
    if (napi_open_handle_scope(env, &scope) != napi_ok) { callbackFailures.fetch_add(1);return; }
    napi_value callback = nullptr, sample = nullptr, receiver = nullptr;
    bool success = napi_get_reference_value(env, binding->callback, &callback) == napi_ok &&
        napi_create_object(env, &sample) == napi_ok && napi_get_undefined(env, &receiver) == napi_ok;
    for (const auto& field : fields) {
        if (!success) { break; }
        napi_value value = nullptr;
        success = napi_create_double(env, field.value, &value) == napi_ok &&
            napi_set_named_property(env, sample, field.name, value) == napi_ok;
    }
    // Callback may synchronously unbind/rebind. No lock is held; scoped local
    // handles keep this invocation valid even if it deletes the strong references.
    bool stillCurrent;
    {
        std::lock_guard<std::mutex> guard(bindingMutex);
        stillCurrent = current == binding && binding->active.load();
    }
    if (success && stillCurrent) { success = napi_call_function(env, receiver, callback, 1, &sample, nullptr) == napi_ok; }
    if (!success) { callbackFailures.fetch_add(1);clearException(env); }
    napi_close_handle_scope(env, scope);
}

napi_value number(napi_env env, int32_t code)
{
    napi_value value = nullptr;
    napi_create_int32(env, code, &value);
    return value;
}

napi_value bindMouseNode(napi_env env, napi_callback_info info)
{
    resultStage.store(1);
    size_t argc = 3;
    napi_value args[3]{};
    void* data = nullptr;
    if (napi_get_cb_info(env, info, &argc, args, nullptr, &data) != napi_ok || !data) {
        result.store(401);return number(env, 401);
    }
    auto* context = static_cast<Environment*>(data);
    if (std::this_thread::get_id() != context->owner) {
        wrongThread.fetch_add(1);result.store(-2);return number(env, -2);
    }
    if (context->closing.load()) { result.store(-1);return number(env, -1); }
    unbind(context, true);
    double density = 0;
    napi_valuetype callbackType = napi_undefined;
    if (argc != 3 || napi_get_value_double(env, args[1], &density) != napi_ok ||
        !std::isfinite(density) || density <= 0 || napi_typeof(env, args[2], &callbackType) != napi_ok ||
        callbackType != napi_function) { result.store(401);return number(env, 401); }
    // Query initializes the public ArkUI node runtime. The legacy XComponent
    // interface does not initialize it; CommonEvent otherwise returns 500.
    // This obtains an API table only, without creating or changing a UI node.
    resultStage.store(2);
    if (!OH_ArkUI_QueryModuleInterfaceByName(ARKUI_NATIVE_NODE, "ArkUI_NativeNodeAPI_1")) {
        result.store(ARKUI_ERROR_CODE_CAPI_INIT_ERROR);
        return number(env, ARKUI_ERROR_CODE_CAPI_INIT_ERROR);
    }
    ArkUI_NodeHandle node = nullptr;
    resultStage.store(3);
    const int32_t nodeResult = OH_ArkUI_GetNodeHandleFromNapiValue(env, args[0], &node);
    if (nodeResult != 0 || !node) {
        const int32_t code = nodeResult != 0 ? nodeResult : 401;
        result.store(code);return number(env, code);
    }
    auto binding = std::make_shared<Binding>();
    binding->context = context;binding->env = env;binding->owner = context->owner;
    binding->node = node;binding->cookie = nextCookie.fetch_add(1);
    resultStage.store(4);
    if (napi_create_reference(env, args[0], 1, &binding->frame) != napi_ok ||
        napi_create_reference(env, args[2], 1, &binding->callback) != napi_ok) {
        deleteReferences(binding, true);result.store(-1);clearException(env);return number(env, -1);
    }
    resultStage.store(5);
    bool available;
    {
        std::lock_guard<std::mutex> guard(bindingMutex);
        available = !current;
        if (available) { current = binding; }
    }
    if (!available) { deleteReferences(binding, true);result.store(-2);return number(env, -2); }
    // userData is an opaque numeric cookie, never a freed allocation. A queued event
    // from an old registration remains harmless even if unregister reports failure.
    resultStage.store(6);
    const int32_t code = OH_ArkUI_NativeModule_RegisterCommonEvent(node, NODE_ON_MOUSE,
        reinterpret_cast<void*>(binding->cookie), onMouse);
    result.store(code);
    binding->registered = code == 0;
    if (code == 0) { binding->active.store(true);bound.store(true); }
    else { unbind(context, true); }
    return number(env, code);
}

napi_value unbindMouseNode(napi_env env, napi_callback_info info)
{
    size_t argc = 0;
    void* data = nullptr;
    napi_get_cb_info(env, info, &argc, nullptr, nullptr, &data);
    if (auto* context = static_cast<Environment*>(data)) {
        if (std::this_thread::get_id() == context->owner) { unbind(context, true); }
        else { wrongThread.fetch_add(1); }
    }
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}

void cleanup(void* data)
{
    auto* context = static_cast<Environment*>(data);
    const bool ownerThread = std::this_thread::get_id() == context->owner;
    context->closing.store(true);
    if (!ownerThread) { wrongThread.fetch_add(1); }
    unbind(context, ownerThread);
    {
        std::lock_guard<std::mutex> guard(environmentMutex);
        const auto found = environments.find(context->env);
        if (found != environments.end() && found->second == context) { environments.erase(found); }
    }
    delete context;
}
} // namespace

void RegisterMouseNodeAPI(napi_env env, napi_value exports)
{
    Environment* context;
    bool created = false;
    {
        std::lock_guard<std::mutex> guard(environmentMutex);
        auto found = environments.find(env);
        if (found != environments.end()) { context = found->second; }
        else {
            context = new Environment{env, std::this_thread::get_id()};
            environments[env] = context;created = true;
        }
    }
    // ArkTS import and XComponent library initialization may register exports
    // twice in one environment. Both must share the same binding and cleanup.
    if (context->owner != std::this_thread::get_id() || context->closing.load()) {
        resultStage.store(0);result.store(-2);return;
    }
    if (created && napi_add_env_cleanup_hook(env, cleanup, context) != napi_ok) {
        { std::lock_guard<std::mutex> guard(environmentMutex);environments.erase(env); }
        delete context;resultStage.store(0);result.store(-1);return;
    }
    napi_property_descriptor functions[] = {
        {"bindMouseNode", nullptr, bindMouseNode, nullptr, nullptr, nullptr, napi_default, context},
        {"unbindMouseNode", nullptr, unbindMouseNode, nullptr, nullptr, nullptr, napi_default, context}
    };
    if (napi_define_properties(env, exports, 2, functions) != napi_ok) { resultStage.store(0);result.store(-1); }
}

std::string NativeMouseNodeStats()
{
    // Client.stats may hold Client.lock. These independent atomic reads never
    // take the binding lock and therefore cannot participate in an input deadlock.
    std::ostringstream out;
    out << "\"nativeMouseNodeBound\":" << (bound.load() ? "true" : "false")
        << ",\"nativeMouseNodeResult\":" << result.load()
        << ",\"nativeMouseNodeResultStage\":" << resultStage.load()
        << ",\"nativeMouseNodeUnregisterResult\":" << unregisterResult.load()
        << ",\"nativeMouseNodeEvents\":" << events.load()
        << ",\"nativeMouseNodeRawMoves\":" << rawMoves.load()
        << ",\"nativeMouseNodeCallbackFailures\":" << callbackFailures.load()
        << ",\"nativeMouseNodeWrongThread\":" << wrongThread.load()
        << ",\"nativeMouseNodeStaleEvents\":" << staleEvents.load();
    return out.str();
}
