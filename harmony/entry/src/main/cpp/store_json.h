#pragma once
#include <string>
namespace edgelinkstore {
// Preserve PEM newlines and every control byte when embedding public identity
// or nested pairing JSON. Dropping them changes the certificate being compared.
inline std::string JSONQuote(const std::string& value){
 static const char hex[]="0123456789abcdef";std::string out="\"";
 for(unsigned char c:value){
  if(c=='"'||c=='\\'){out+='\\';out+=char(c);}
  else if(c<32){out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
  else out+=char(c);
 }
 return out+'"';
}
}
