#pragma once
#include <algorithm>
#include <cmath>
#include <functional>
#include <string>
namespace yingqiao {
struct DisplayProfile {int width=0,height=0,fps=0;std::string codec;bool supported=false;};
inline DisplayProfile ChooseDisplayProfile(int panelWidth,int panelHeight,int refresh,const std::string&preferred,const std::function<bool(const std::string&,int,int,int)>&supports){
 if(panelWidth<480||panelHeight<480||panelWidth>16384||panelHeight>16384||refresh<1)return {};
 // Preserve aspect first; never upscale or identify a panel by a hardcoded model.
 const double ratio=double(panelWidth)/panelHeight;
 for(int fps:{60,30}){if(fps>refresh)continue;for(int edge:{2400,1920,1600,1280}){
  double scale=std::min(1.0,double(edge)/std::max(panelWidth,panelHeight));int w=int(std::floor(panelWidth*scale/2))*2,h=int(std::floor(panelHeight*scale/2))*2;
  if(w<640||h<480||w>3840||h>3200||double(w)*h>8000000||std::abs(double(w)/h-ratio)>0.005)continue;
  for(const std::string&codec:{preferred,std::string("avc"),std::string("hevc")})if((codec=="avc"||codec=="hevc")&&supports(codec,w,h,fps))return {w,h,fps,codec,true};
 }}return {};
}
}
