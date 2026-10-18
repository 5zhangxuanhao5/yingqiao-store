import { mdns, socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { localIPv4 } from './StorePairing';
export interface StoreDiscoveredMac { id: string; name: string; host: string; certificate: string; serviceName: string; }
interface DatagramIdentity {schema:string;nonce:string;id:string;name:string;certificate:string;port:number;}
export class StoreDiscovery {
 private probe:socket.UDPSocket|null=null;
 private probeTimers:number[]=[];
 private finder: mdns.DiscoveryService | null = null;
 private devices: StoreDiscoveredMac[] = [];
 private epoch: number = 0;
 private context:common.UIAbilityContext;
 private changed:(devices:StoreDiscoveredMac[])=>void;
 private failed:(message:string)=>void;
 constructor(context:common.UIAbilityContext,changed:(devices:StoreDiscoveredMac[])=>void,failed:(message:string)=>void){this.context=context;this.changed=changed;this.failed=failed;}
 private attribute(info:mdns.LocalServiceInfo,key:string):string {let out='';for(const item of info.serviceAttribute || []) {if(item.key===key){for(const byte of item.value){out+=String.fromCharCode(byte);}return out;}}return out;}
 start():void {
  this.stop();const generation=++this.epoch;this.startDatagram(generation);
  try {
   const finder=mdns.createDiscoveryService(this.context,'_yingqiaostore._tcp');this.finder=finder;
   hilog.info(0x1234,'StoreDiscovery','created');
   finder.on('discoveryStart',(event:mdns.DiscoveryEventInfo)=>{hilog.info(0x1234,'StoreDiscovery','start code=%{public}d',event.errorCode || 0);if(event.errorCode)this.failed('设备搜索未能启动，请刷新重试。');});
   finder.on('serviceFound',(service:mdns.LocalServiceInfo)=>{
    hilog.info(0x1234,'StoreDiscovery','found');
    mdns.resolveLocalService(this.context,service).then((info:mdns.LocalServiceInfo)=>{
     if(generation!==this.epoch)return;
     const host=info.host?.address || '',count=Number(this.attribute(info,'count')),id=this.attribute(info,'id');
     hilog.info(0x1234,'StoreDiscovery','resolved port=%{public}d ipv4=%{public}s schema=%{public}s count=%{public}d attrs=%{public}d',info.port,String(localIPv4(host)),String(this.attribute(info,'schema')==='store-discovery-v1'),count,(info.serviceAttribute || []).length);
     if(info.port!==49563||!localIPv4(host)||this.attribute(info,'schema')!=='store-discovery-v1'||!/^[0-9a-f]{24}$/.test(id)||!Number.isInteger(count)||count<1||count>40)return;
     let certificate='';for(let i=0;i<count;i++){certificate+=this.attribute(info,`c${i}`);}
     if(certificate.length>8192||!certificate.startsWith('-----BEGIN CERTIFICATE-----')||!certificate.trim().endsWith('-----END CERTIFICATE-----'))return;
     hilog.info(0x1234,'StoreDiscovery','accepted');
     const item:StoreDiscoveredMac={id:id,name:info.serviceName.slice(0,80),host:host,certificate:certificate,serviceName:info.serviceName};
     const next=this.devices.filter((x:StoreDiscoveredMac)=>x.id!==id);next.push(item);this.devices=next.slice(-16);this.changed(this.devices.slice());
    }).catch((e:Error)=>{hilog.warn(0x1234,'StoreDiscovery','resolve error=%{public}s',e.message);});
   });
   finder.on('serviceLost',(info:mdns.LocalServiceInfo)=>{if(generation!==this.epoch)return;this.devices=this.devices.filter((x:StoreDiscoveredMac)=>x.serviceName!==info.serviceName);this.changed(this.devices.slice());});
   finder.startSearchingMDNS();
  }catch(e){hilog.warn(0x1234,'StoreDiscovery','start failed');this.failed('暂时未能搜索设备，请确认两端连接同一局域网后重试。');}
 }
 private async startDatagram(generation:number):Promise<void> {
  const nonce=util.generateRandomUUID(true).replace(/-/g,'').toLowerCase();
  let probe:socket.UDPSocket|null=null;
  try {
   probe=socket.constructUDPSocketInstance();this.probe=probe;
   const owned=probe;
   probe.on('message',(event:socket.SocketMessageInfo)=>{
    if(generation!==this.epoch||!localIPv4(event.remoteInfo.address)||event.message.byteLength>8192)return;
    try{
     const info=JSON.parse(new util.TextDecoder('utf-8').decodeWithStream(new Uint8Array(event.message))) as DatagramIdentity;
     if(info.schema!=='store-discovery-v1'||info.nonce!==nonce||info.port!==49563||!/^[0-9a-f]{24}$/.test(info.id)||typeof info.certificate!=='string'||info.certificate.length>8192||!info.certificate.startsWith('-----BEGIN CERTIFICATE-----')||!info.certificate.trim().endsWith('-----END CERTIFICATE-----'))return;
     const item:StoreDiscoveredMac={id:info.id,name:typeof info.name==='string'?info.name.slice(0,80):'Mac',host:event.remoteInfo.address,certificate:info.certificate,serviceName:info.id};
     const next=this.devices.filter((x:StoreDiscoveredMac)=>x.id!==info.id);next.push(item);this.devices=next.slice(-16);this.changed(this.devices.slice());hilog.info(0x1234,'StoreDiscovery','datagram accepted');
    }catch(e){hilog.warn(0x1234,'StoreDiscovery','datagram invalid');}
   });
   await probe.bind({address:'0.0.0.0',port:0,family:1});await probe.setExtraOptions({broadcast:true});
   if(generation!==this.epoch){await probe.close();return;}
   const send=():void=>{if(generation===this.epoch)owned.send({data:`YQDISC1 ${nonce}`,address:{address:'255.255.255.255',port:49565,family:1}}).catch(()=>{});};
   send();for(const delay of [1000,3000,6000,10000]){this.probeTimers.push(setTimeout(send,delay));}
   this.probeTimers.push(setTimeout(()=>{if(this.probe===owned){this.probe=null;owned.close().catch(()=>{});}},15000));
  }catch(e){hilog.warn(0x1234,'StoreDiscovery','datagram unavailable');if(probe)probe.close().catch(()=>{});}
 }
 stop():void {this.epoch++;for(const timer of this.probeTimers){clearTimeout(timer);}this.probeTimers=[];if(this.probe){this.probe.close().catch(()=>{});this.probe=null;}if(this.finder){try{this.finder.stopSearchingMDNS();this.finder.off('discoveryStart');this.finder.off('serviceFound');this.finder.off('serviceLost');}catch(e){}this.finder=null;}this.devices=[];}
}
