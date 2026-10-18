#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>
namespace yingqiao::usb {
// Device access is supplied by a platform adapter. This unit never enumerates,
// opens or changes a real device by itself.
class ControlPipe {public:virtual ~ControlPipe()=default;virtual bool transfer(uint8_t direction,uint8_t request,uint16_t index,std::vector<uint8_t>&data)=0;};
enum class StartResult {permissionRequired,unsupported,transferFailed,waitingForReenumeration};
inline int ProtocolVersion(ControlPipe&pipe){std::vector<uint8_t>data(2);if(!pipe.transfer(0xc0,51,0,data)||data.size()!=2)return 0;return data[0]|(int(data[1])<<8);}
inline StartResult Start(ControlPipe&pipe,bool consent,const std::string&sessionSerial){
 if(!consent)return StartResult::permissionRequired;
 if(sessionSerial.empty()||sessionSerial.size()>64||sessionSerial.find('\0')!=std::string::npos)return StartResult::transferFailed;
 const auto version=ProtocolVersion(pipe);if(version<1||version>2)return StartResult::unsupported;
 const std::array<std::string,6>identity={"Yingqiao","Yingqiao Display Link","Paired display transport","1","https://github.com/5zhangxuanhao5/yingqiao-store",sessionSerial};
 for(size_t i=0;i<identity.size();++i){std::vector<uint8_t>data(identity[i].begin(),identity[i].end());data.push_back(0);if(data.size()>256||!pipe.transfer(0x40,52,uint16_t(i),data))return StartResult::transferFailed;}
 std::vector<uint8_t>none;if(!pipe.transfer(0x40,53,0,none))return StartResult::transferFailed;return StartResult::waitingForReenumeration;
}
inline bool AccessoryID(uint16_t vendor,uint16_t product){return vendor==0x18d1&&(product==0x2d00||product==0x2d01);}
}
