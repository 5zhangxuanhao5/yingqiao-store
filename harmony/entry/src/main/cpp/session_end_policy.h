#pragma once
#include <string>
namespace edgelink {
inline const char* FinalSessionControl(const std::string& reason,const std::string& mode,bool handover,bool background){
 if(mode=="extend"&&reason=="background_suspend"&&background)return "RELEASE\nPARK\n";
 if(mode=="extend"&&reason=="local_handover"&&handover)return "RELEASE\nHANDOVER\n";
 return "RELEASE\nSTOP\n";
}
}
