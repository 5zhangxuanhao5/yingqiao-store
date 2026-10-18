#pragma once
#include <cstdint>
namespace edgelink {
class ControlStreamOwner {
public:
 struct Snapshot { int fd=-1; uint64_t epoch=0; explicit operator bool() const {return fd>=0&&epoch!=0;} };
 void Bind(int fd,uint64_t epoch){owner_={fd,epoch};}
 bool Release(int fd,uint64_t epoch){if(owner_.fd!=fd||owner_.epoch!=epoch)return false;owner_={};return true;}
 void Reset(){owner_={};}
 Snapshot ForDescriptor(int fd)const{return owner_.fd==fd?owner_:Snapshot{};}
private:
 Snapshot owner_;
};
} // namespace edgelink
