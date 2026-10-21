#include "../harmony/entry/src/main/cpp/session_end_policy.h"
#include <cassert>
#include <string>
#include <iostream>
int main(){
 using edgelink::FinalSessionControl;
 for(bool handover:{false,true})for(bool background:{false,true}){
  assert(std::string(FinalSessionControl("user_end","extend",handover,background))=="RELEASE\nSTOP\n");
  assert(std::string(FinalSessionControl("background_suspend","remote",handover,background))=="RELEASE\nSTOP\n");
  assert(std::string(FinalSessionControl("background_suspend","extend",handover,background))==(background?"RELEASE\nPARK\n":"RELEASE\nSTOP\n"));
  assert(std::string(FinalSessionControl("local_handover","extend",handover,background))==(handover?"RELEASE\nHANDOVER\n":"RELEASE\nSTOP\n"));
 }
 std::cout<<"PASS session close protocol: authenticated capability, extension only, explicit End and old-host fallback\n";
}
