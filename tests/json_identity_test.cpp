#include "../harmony/entry/src/main/cpp/store_json.h"
#include <cassert>
#include <iostream>
int main(){
 using edgelinkstore::JSONQuote;
 const std::string pem="-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n";
 assert(JSONQuote("a\nb\r\tc")=="\"a\\u000ab\\u000d\\u0009c\"");
 assert(JSONQuote(std::string("x\0y",3))=="\"x\\u0000y\"");
 assert(JSONQuote("\"\\")=="\"\\\"\\\\\"");
 std::cout<<JSONQuote(pem);
}
