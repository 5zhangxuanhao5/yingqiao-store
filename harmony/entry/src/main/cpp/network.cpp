#include "network.h"
void NetworkStart(const std::string&,const std::string&){}
std::string NetworkStatus(){return "{\"state\":\"disabled_store_edition\"}";}
int NetworkNewRequest(){return -1;} int NetworkDial(const std::string&,int,int){return -1;}
bool NetworkSupportsUDP(){return false;}int NetworkDialUDP(const std::string&,int,int){return -1;}
int NetworkCloseDatagram(int){return -1;}void NetworkCancel(int){}
uint64_t NetworkStreamEpoch(int){return 0;}int NetworkDrainStream(int,uint64_t,int){return -1;}
