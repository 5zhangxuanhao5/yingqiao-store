#pragma once
#include <vector>
#include <deque>
#include <cstdint>
#include <stdexcept>
#include <algorithm>
namespace yingqiao::usb {
struct Chunk {uint16_t stream;std::vector<uint8_t>payload;};
constexpr size_t maximumChunk=16384,maximumQueue=512*1024;
inline std::vector<uint8_t> Encode(const Chunk&c){if((c.stream!=1&&c.stream!=2)||c.payload.empty()||c.payload.size()>maximumChunk)throw std::invalid_argument("usb_mux_chunk");uint32_t n=uint32_t(c.payload.size());std::vector<uint8_t>out={'Y','Q','U','B',1,0,uint8_t(c.stream>>8),uint8_t(c.stream),uint8_t(n>>24),uint8_t(n>>16),uint8_t(n>>8),uint8_t(n)};out.insert(out.end(),c.payload.begin(),c.payload.end());return out;}
class Decoder {
 std::vector<uint8_t>buffer;
 public:
 std::vector<Chunk> push(const std::vector<uint8_t>&bytes){if(bytes.size()>maximumQueue||buffer.size()+bytes.size()>maximumQueue)throw std::runtime_error("usb_mux_overflow");buffer.insert(buffer.end(),bytes.begin(),bytes.end());std::vector<Chunk>out;size_t at=0;
 while(buffer.size()-at>=12){auto*h=buffer.data()+at;const uint16_t stream=uint16_t(h[6])<<8|h[7];const uint32_t count=uint32_t(h[8])<<24|uint32_t(h[9])<<16|uint32_t(h[10])<<8|h[11];if(h[0]!='Y'||h[1]!='Q'||h[2]!='U'||h[3]!='B'||h[4]!=1||h[5]!=0||(stream!=1&&stream!=2)||!count||count>maximumChunk)throw std::runtime_error("usb_mux_header");if(buffer.size()-at<12+count)break;out.push_back({stream,std::vector<uint8_t>(h+12,h+12+count)});at+=12+count;}
 buffer.erase(buffer.begin(),buffer.begin()+at);return out;
 }
 void reset(){buffer.clear();}
};
class FairWriter {
 std::deque<Chunk>control,video;size_t bytes=0;unsigned controls=0;
 public:
 bool enqueue(Chunk c){if((c.stream!=1&&c.stream!=2)||c.payload.empty()||c.payload.size()>maximumChunk||bytes+c.payload.size()>maximumQueue)return false;bytes+=c.payload.size();(c.stream==1?control:video).push_back(std::move(c));return true;}
 bool pop(Chunk&out){if(control.empty()&&video.empty())return false;const bool first=!control.empty()&&(video.empty()||controls<8);auto&q=first?control:video;out=std::move(q.front());q.pop_front();bytes-=out.payload.size();if(first)++controls;else controls=0;return true;}
 void reset(){control.clear();video.clear();bytes=0;controls=0;}
};
}
