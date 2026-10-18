#pragma once
#include <cstddef>
#include <deque>
#include <istream>
#include <string>

struct PeerControlCapabilities {
 bool cursor=false,desktopOverview=false;
};
inline PeerControlCapabilities ParseControlCapabilities(std::istream& fields) {
 PeerControlCapabilities result;std::string token;
 while(fields>>token){
  if(token=="cursor-v1")result.cursor=true;
  else if(token=="overview-v1")result.desktopOverview=true;
 }
 return result;
}

// Call only while the client's input mutex is held. A negotiated application
// command replaces hotkey injection, so Mac shortcut preferences do not affect
// this request and no synthetic modifier can remain down.
inline const char* DesktopShortcutWire(const std::string& command) {
 if (command == "DESKTOP overview") return "DESKTOP overview";
 return nullptr;
}

inline bool EnqueueDesktopShortcut(std::deque<std::string>& commands, const std::string& command,
 bool running, bool stopRequested, bool localUI, std::size_t heldKeyCount, std::size_t heldButtonCount,
 bool hostSupported, const std::string& mode,
 std::size_t capacity = 1024) {
 const char* wire = DesktopShortcutWire(command);
 // Session-menu entry first queues RELEASE and clears held state. Refuse to
 // modify input outside that local UI boundary or while any key/button remains.
 if (!wire || !hostSupported || (mode!="remote"&&mode!="extend") ||
  !running || stopRequested || !localUI || heldKeyCount != 0 || heldButtonCount != 0 ||
  commands.size() >= capacity) return false;
 commands.emplace_back(wire);
 return true;
}
