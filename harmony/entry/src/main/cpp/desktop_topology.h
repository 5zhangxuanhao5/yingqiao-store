#pragma once
#include <cmath>
#include <istream>
#include <ostream>
#include <string>
#include <vector>

// CoreGraphics global desktop coordinates, independent of encoded video pixels.
struct DesktopRect { double x=0, y=0, width=0, height=0; };
struct DesktopTopology { bool valid=false; DesktopRect capture; std::vector<DesktopRect> displays; };

inline bool ValidDesktopRect(const DesktopRect& r) {
 return std::isfinite(r.x) && std::isfinite(r.y) && std::isfinite(r.width) && std::isfinite(r.height) &&
  std::abs(r.x)<=1000000 && std::abs(r.y)<=1000000 && r.width>=1 && r.height>=1 &&
  r.width<=65536 && r.height<=65536;
}
inline bool SameDesktopRect(const DesktopRect& a,const DesktopRect& b) {
 return std::abs(a.x-b.x)<0.001 && std::abs(a.y-b.y)<0.001 &&
  std::abs(a.width-b.width)<0.001 && std::abs(a.height-b.height)<0.001;
}
inline DesktopTopology ParseDesktopTopology(std::istream& input,bool extend) {
 DesktopTopology result;std::string capability,countText;
 if(!extend || !(input>>capability) || capability!="desktop-v1")return result;
 DesktopTopology candidate;
 if(!(input>>candidate.capture.x>>candidate.capture.y>>candidate.capture.width>>candidate.capture.height>>countText) ||
    !ValidDesktopRect(candidate.capture) || countText.size()!=1 || countText[0]<'1' || countText[0]>'8')return result;
 const int count=countText[0]-'0';
 bool includesCapture=false;
 for(int i=0;i<count;++i){
  DesktopRect r;
  if(!(input>>r.x>>r.y>>r.width>>r.height) || !ValidDesktopRect(r))return result;
  for(const auto& previous:candidate.displays)if(SameDesktopRect(previous,r))return result;
  includesCapture=includesCapture || SameDesktopRect(candidate.capture,r);candidate.displays.push_back(r);
 }
 if(!includesCapture)return result;
 candidate.valid=true;return candidate;
}
inline void WriteDesktopTopologyStats(std::ostream& out,const DesktopTopology& topology) {
 out<<",\"desktopTopologyValid\":"<<(topology.valid?"true":"false")
  <<",\"desktopCaptureX\":"<<topology.capture.x<<",\"desktopCaptureY\":"<<topology.capture.y
  <<",\"desktopCaptureWidth\":"<<topology.capture.width<<",\"desktopCaptureHeight\":"<<topology.capture.height
  <<",\"desktopDisplays\":[";
 bool first=true;for(const auto& r:topology.displays){if(!first)out<<',';first=false;
  out<<"{\"x\":"<<r.x<<",\"y\":"<<r.y<<",\"width\":"<<r.width<<",\"height\":"<<r.height<<'}';}
 out<<']';
}
