#include "../../usb/AccessoryProtocol.hpp"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <memory>
namespace yingqiao::usb {
// Build-only research adapter. Not linked into the GUI and has no static
// initializer, enumeration, auto-activation or device-seize operation.
class MacControlPipe final:public ControlPipe {
 IOUSBDeviceInterface500**device=nullptr;
 public:
 ~MacControlPipe(){if(device){(*device)->USBDeviceClose(device);(*device)->Release(device);}}
 static std::unique_ptr<MacControlPipe> OpenSelected(io_service_t service,bool explicitlyAllowed){
  if(!explicitlyAllowed)return {};IOCFPlugInInterface**plugin=nullptr;SInt32 score=0;
  if(IOCreatePlugInInterfaceForService(service,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score)!=kIOReturnSuccess||!plugin)return {};
  auto pipe=std::make_unique<MacControlPipe>();HRESULT result=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID500),reinterpret_cast<LPVOID*>(&pipe->device));IODestroyPlugInInterface(plugin);
  if(result||!pipe->device)return {};if((*pipe->device)->USBDeviceOpen(pipe->device)!=kIOReturnSuccess)return {};return pipe;
 }
 bool transfer(uint8_t direction,uint8_t request,uint16_t index,std::vector<uint8_t>&data)override{
  if(!device||data.size()>256)return false;IOUSBDevRequestTO q{};q.bmRequestType=direction;q.bRequest=request;q.wValue=0;q.wIndex=index;q.wLength=uint16_t(data.size());q.pData=data.empty()?nullptr:data.data();q.noDataTimeout=1000;q.completionTimeout=1000;
  if((*device)->DeviceRequestTO(device,&q)!=kIOReturnSuccess)return false;if(direction&0x80)data.resize(q.wLenDone);return true;
 }
};
}
