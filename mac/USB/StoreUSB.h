#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Only public discovery identity enters the USB adapter. TLS private material,
// tokens and video plaintext remain in the existing authenticated host.
void YQUSBStart(const char *publicIdentityJSON);
void YQUSBStop(void);
int YQUSBTrustedPort(unsigned short port);
char *YQUSBStatus(void); // caller frees
#ifdef __cplusplus
}
#endif
