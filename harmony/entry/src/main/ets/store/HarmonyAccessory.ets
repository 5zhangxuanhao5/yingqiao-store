import { usbManager } from '@kit.BasicServicesKit';
// Research adapter only: not imported by the product page, no startup permission
// requests, and never marks a path ready until the future TLS peer is verified.
export class HarmonyAccessoryCandidate {
 static readonly sdkContractAvailable: boolean = true;
 private handle: usbManager.USBAccessoryHandle | null = null;
 candidate(): usbManager.USBAccessory | null {
  try {
   const all=usbManager.getAccessoryList();
   for (const a of all) { if (a.manufacturer==='Yingqiao' && a.product==='Yingqiao Display Link' && a.version==='1') { return a; } }
  } catch(e) { /* 801 or absent accessory: keep wireless available. */ }
  return null;
 }
 async openAfterUserAction(): Promise<number> {
  this.close();const accessory=this.candidate();if (!accessory) { return -1; }
  try {
   if (!usbManager.hasAccessoryRight(accessory) && !await usbManager.requestAccessoryRight(accessory)) { return -1; }
   this.handle=usbManager.openAccessory(accessory);const fd=this.handle.accessoryFd;
   if (fd<=0) { this.close();return -1; }
   // The session owner must duplicate/retire the descriptor on a worker and run
   // the same pinned TLS handshake. Accessory metadata is never authentication.
   return fd;
  } catch(e) { this.close();return -1; }
 }
 close(): void {if (this.handle) { try { usbManager.closeAccessory(this.handle); } catch(e) {}this.handle=null; }}
}
