#pragma once
#include <string>
#include <cstdint>
void NetworkStart(const std::string&directory,const std::string&networkJSON);
std::string NetworkStatus();
int NetworkNewRequest();
int NetworkDial(const std::string&host,int port,int request);
bool NetworkSupportsUDP();
int NetworkDialUDP(const std::string&host,int port,int request);
// Removes the Go datagram bridge, but never closes the C-owned descriptor.
int NetworkCloseDatagram(int fd);
void NetworkCancel(int request);
// Optional stream owner ABI. Zero means an older runtime has neither capability.
uint64_t NetworkStreamEpoch(int fd);
// Nonblocking: zero only means accepted; this is not a remote STOP acknowledgement.
int NetworkDrainStream(int fd,uint64_t epoch,int timeoutMS);
