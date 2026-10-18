#include "../shared/DisplayProfile.hpp"
#include "../shared/TransportPolicy.hpp"
#include <cassert>
#include <iostream>
#include <utility>
#include <vector>

int main() {
  using namespace yingqiao;
  for (const auto &panel : std::vector<std::pair<int, int>>{
           {3120, 2080}, {2880, 1920}, {2800, 1840}, {2456, 1600},
           {2560, 1600}, {1600, 2560}, {2048, 2048}, {3840, 2160}}) {
    auto profile = ChooseDisplayProfile(panel.first, panel.second, 120, "hevc",
        [](const std::string &, int w, int h, int fps) {
          return w <= 2400 && h <= 2400 && fps <= 60;
        });
    assert(profile.supported && profile.width % 2 == 0 && profile.height % 2 == 0);
    assert(profile.width <= panel.first && profile.height <= panel.second);
    assert(std::abs(double(profile.width) / profile.height -
                    double(panel.first) / panel.second) < .005);
  }
  auto fallback = ChooseDisplayProfile(2800, 1840, 60, "hevc",
      [](const std::string &codec, int w, int, int fps) {
        return codec == "avc" && w <= 1920 && fps <= 30;
      });
  assert(fallback.supported && fallback.codec == "avc" && fallback.fps == 30);
  assert(fallback.width <= 1920);
  assert(!ChooseDisplayProfile(0, 2080, 60, "avc",
      [](const std::string &, int, int, int) { return true; }).supported);
  assert(!ChooseDisplayProfile(3120, 2080, 60, "avc",
      [](const std::string &, int, int, int) { return false; }).supported);

  std::vector<Path> paths = {
      {"wifi", "paired", true, false, true, 100, 20, 100},
      {"usb", "paired", true, true, true, 100, 3, 500}};
  assert(PreferredPath(paths, "paired", "wifi", 101, 90, false) == "usb");
  assert(PreferredPath(paths, "paired", "wifi", 101, 90, true) == "wifi");
  assert(PreferredPath(paths, "paired", "wifi", 101, 100, false) == "wifi");
  paths[1].p95ms = 40; // A cable alone must not override a faster wireless route.
  assert(PreferredPath(paths, "paired", "wifi", 101, 90, false) == "wifi");
  paths[1].p95ms = 3;
  paths[1].authenticated = false;
  assert(PreferredPath(paths, "paired", "wifi", 101, 90, false) == "wifi");
  paths[1].authenticated = true;
  paths[0].authenticated = false; // Failover bypasses drag/cooldown preference.
  assert(PreferredPath(paths, "paired", "wifi", 101, 100, true) == "usb");
  assert(PreferredPath(paths, "paired", "usb", 120, 90, false).empty());
  DisplayLease lease;
  lease.retain("paired", 100);
  assert(!lease.adopt("unpaired", 101));
  assert(!lease.adopt("paired", 111));
  lease.retain("paired", 120);
  assert(lease.adopt("paired", 125));
  assert(!lease.adopt("paired", 126));
  lease.retain("paired", 130);
  lease.explicitEnd();
  assert(!lease.adopt("paired", 131));
  std::cout << "PASS portable geometry, hardware fallback, authenticated route "
               "selection and display lease simulation; no device certification.\n";
}
