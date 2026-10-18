#pragma once
#include <string>
// Candidate-only bridge into the same native availability Manager. UI booleans,
// DNS/service names, private prefixes and a successful TCP dial are not proof.
namespace edgelinkavailability {
std::string CurrentProcessSession();
std::string CurrentDeviceMetadata();
bool CanUseVerifiedLocalPath(const std::string& route,const std::string& host,int standbyPort,
                            const std::string& pairedToken,const std::string& pairedCertificate);
}
