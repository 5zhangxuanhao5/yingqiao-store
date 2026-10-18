#pragma once

#include <cstdint>
#include <string>

// These requests never wait for the UI thread. A serial worker applies the latest state.
void RequestCursorLock(int32_t windowId, bool enabled, bool followMovement = true);
void ReleaseCursorLock();
// Only call after the named window is confirmed inactive/hidden/destroyed.
void NotifyCursorWindowInactive(int32_t windowId);
std::string CursorLockStats();
