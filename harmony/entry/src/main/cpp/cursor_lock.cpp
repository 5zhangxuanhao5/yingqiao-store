#include "cursor_lock.h"

#include <condition_variable>
#include <map>
#include <mutex>
#include <sstream>
#include <thread>
#include <window_manager/oh_window.h>

namespace {
class CursorLockState {
public:
    void request(int32_t windowId, bool enabled, bool followMovement = true)
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (enabled && windowId <= 0) { result = 401;return; }
        const int32_t target = enabled ? windowId : -1;
        const bool targetFollows = !enabled || followMovement;
        if (requested == enabled && requestedWindow == target && requestedFollows == targetFollows &&
            (revision != completed || (result == 0 && !uncertain))) {
            return;
        }
        requested = enabled;
        requestedWindow = target;
        requestedFollows = targetFollows;
        ++revision;
        pruneInactiveWindows();
        if (!workerStarted) {
            workerStarted = true;
            // The NDK internally synchronously dispatches to the UI thread. Never hold this
            // mutex while calling it, and never make the UI wait for this worker to finish.
            std::thread([this] { run(); }).detach();
        }
        wake.notify_one();
    }

    void inactive(int32_t windowId)
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (windowId <= 0 || (windowId != lockedWindow && windowId != requestedWindow &&
            windowId != inFlightWindow)) { return; }
        inactiveWindows[windowId] = ++inactiveSequence;
        if (requestedWindow == windowId) {
            requested = false;requestedWindow = -1;requestedFollows = true;
        }
        ++revision;
        pruneInactiveWindows();
        wake.notify_one();
    }

    std::string stats()
    {
        std::lock_guard<std::mutex> guard(mutex);
        std::ostringstream out;
        out << "\"cursorLockRequested\":" << (requested ? "true" : "false")
            << ",\"cursorLocked\":" << (lockedWindow > 0 ? "true" : "false")
            << ",\"cursorLockPending\":" << (revision != completed ? "true" : "false")
            << ",\"cursorLockStateUncertain\":" << (uncertain ? "true" : "false")
            << ",\"cursorLockAutoReleased\":" << (autoReleased ? "true" : "false")
            << ",\"cursorLockAutoReleaseCount\":" << autoReleaseCount
            << ",\"cursorLockWindowId\":" << lockedWindow
            << ",\"cursorFollowMovement\":" << (lockedFollows ? "true" : "false")
            << ",\"cursorLockFollowRequested\":" << (requestedFollows ? "true" : "false")
            << ",\"cursorLockResult\":" << result
            << ",\"cursorUnlockResult\":" << releaseResult;
        return out.str();
    }

private:
    uint64_t inactiveStamp(int32_t windowId) const
    {
        const auto found = inactiveWindows.find(windowId);
        return found == inactiveWindows.end() ? 0 : found->second;
    }

    void pruneInactiveWindows()
    {
        for (auto it = inactiveWindows.begin(); it != inactiveWindows.end();) {
            if (it->first != lockedWindow && it->first != requestedWindow && it->first != inFlightWindow) {
                it = inactiveWindows.erase(it);
            } else { ++it; }
        }
    }

    void run()
    {
        for (;;) {
            uint64_t task;
            int32_t target;
            int32_t previous;
            bool needsRelease;
            bool follows;
            uint64_t acquisitionStamp = 0;
            {
                std::unique_lock<std::mutex> guard(mutex);
                wake.wait(guard, [this] { return revision != completed; });
                task = revision;
                target = requested ? requestedWindow : -1;
                previous = lockedWindow;
                follows = requestedFollows;
                needsRelease = previous > 0 && (previous != target || lockedFollows != follows || uncertain ||
                    inactiveStamp(previous) > lockedStamp);
            }
            if (needsRelease) {
                const int32_t code = OH_WindowManager_UnlockCursor(previous);
                std::lock_guard<std::mutex> guard(mutex);
                releaseResult = code;
                result = code;
                // The SDK releases capture on focus loss. Unlock then reports STATE_ABNORMAL
                // when the old window is unfocused or gone. Only a matching lifecycle fact
                // after this acquisition permits reconciling that result as an automatic release.
                const bool automatic = code == 1300002 && inactiveStamp(previous) > lockedStamp;
                uncertain = code != 0 && !automatic;
                if (code == 0 || automatic) {
                    lockedWindow = -1;lockedFollows = true;lockedStamp = 0;
                    autoReleased = automatic;
                    if (automatic) { ++autoReleaseCount; }
                }
                // Do not acquire another window after a failed release. Keep the last
                // known state, mark it uncertain, and permit a later lifecycle retry.
                if (uncertain) { completed = task;pruneInactiveWindows();continue; }
            }
            {
                std::lock_guard<std::mutex> guard(mutex);
                // A menu, focus loss or disconnect supersedes work before lock dispatch.
                if (task != revision) { completed = task;pruneInactiveWindows();continue; }
                if (target < 1 || (lockedWindow == target && lockedFollows == follows)) {
                    completed = task;
                    result = 0;
                    pruneInactiveWindows();
                    continue;
                }
                inFlightWindow = target;
                acquisitionStamp = inactiveStamp(target);
            }
            const int32_t code = OH_WindowManager_LockCursor(target, follows);
            {
                std::lock_guard<std::mutex> guard(mutex);
                result = code;
                if (code == 0) {
                    lockedWindow = target;lockedFollows = follows;lockedStamp = acquisitionStamp;
                    // A late success after focus loss still needs the serial worker's cleanup.
                    // A new request for this same ID must not erase that focus-loss evidence.
                    uncertain = inactiveStamp(target) > acquisitionStamp;
                    autoReleased = false;
                }
                inFlightWindow = -1;
                completed = task;
                pruneInactiveWindows();
                // If a release arrived during the call, the next iteration applies it.
            }
        }
    }

    std::mutex mutex;
    std::condition_variable wake;
    bool workerStarted = false;
    bool requested = false;
    bool uncertain = false;
    bool autoReleased = false;
    bool requestedFollows = true;
    bool lockedFollows = true;
    int32_t requestedWindow = -1;
    int32_t lockedWindow = -1;
    int32_t inFlightWindow = -1;
    int32_t result = 0;
    int32_t releaseResult = 0;
    uint64_t revision = 0;
    uint64_t completed = 0;
    uint64_t lockedStamp = 0;
    uint64_t inactiveSequence = 0;
    uint64_t autoReleaseCount = 0;
    std::map<int32_t, uint64_t> inactiveWindows;
};

CursorLockState& state()
{
    // Process-lifetime native module: avoid a main-thread shutdown join while the NDK
    // may be waiting for that same main thread. The idle worker consumes no CPU.
    static CursorLockState* value = new CursorLockState();
    return *value;
}
}

void RequestCursorLock(int32_t windowId, bool enabled, bool followMovement) { state().request(windowId, enabled, followMovement); }
void ReleaseCursorLock() { state().request(-1, false); }
void NotifyCursorWindowInactive(int32_t windowId) { state().inactive(windowId); }
std::string CursorLockStats() { return state().stats(); }
