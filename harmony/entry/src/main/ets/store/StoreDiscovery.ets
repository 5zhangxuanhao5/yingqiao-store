import native from 'libedgelink.so';
import { mdns, socket, connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { localIPv4 } from './StorePairing';
export interface StoreDiscoveredPath { host:string;route:string; }
export interface StoreDiscoveredMac { startRequested?:boolean; paths:StoreDiscoveredPath[]; id: string; name: string; host: string; certificate: string; serviceName: string; }
interface USBIdentity {certificate:string;identity:DatagramIdentity;}
interface DatagramIdentity {startRequested?:boolean;paths?:StoreDiscoveredPath[];schema:string;nonce:string;id:string;name:string;certificate:string;port:number;}
export class StoreDiscovery {
 private candidates:Map<string,StoreDiscoveredMac>=new Map();
 private checks:Set<string>=new Set();
 private presenceTimer:number=-1;
 private probe:socket.UDPSocket|null=null;
 private usbTimer:number=-1;
 private usbPending:boolean=false;
 private seen:Map<string,number>=new Map();
 private datagramSeen:Map<string,number>=new Map();
 private serviceIDs:Map<string,string>=new Map();
 private probeTimers:number[]=[];
 private probeInterval:number=-1;
 private recoveryTimer:number=-1;
 private finder: mdns.DiscoveryService | null = null;
 private devices: StoreDiscoveredMac[] = [];
 private epoch: number = 0;
 private rememberedHost:string='';
 private context:common.UIAbilityContext;
 private changed:(devices:StoreDiscoveredMac[])=>void;
 private failed:(message:string)=>void;
 constructor(context:common.UIAbilityContext,changed:(devices:StoreDiscoveredMac[])=>void,failed:(message:string)=>void,rememberedHost:string=''){this.rememberedHost=rememberedHost;this.context=context;this.changed=changed;this.failed=failed;}
 acceptDevice(item:StoreDiscoveredMac):void {
  const previous=this.candidates.get(item.id);
  const combined=item.paths.slice();combined.unshift({host:item.host,route:item.host==='127.0.0.1'?'usb':'lan'});
  if(previous&&previous.certificate===item.certificate){combined.push(...previous.paths);}
  item.paths=combined.filter((p:StoreDiscoveredPath,i:number)=>combined.findIndex((v:StoreDiscoveredPath)=>v.host===p.host)===i).slice(0,4);
  this.candidates.set(item.id,item);this.seen.set(item.id,Date.now());
  if(this.candidates.size>16){const oldest:string=Array.from(this.candidates.keys())[0];this.candidates.delete(oldest);}
  this.verifyDevice(item,this.epoch);
 }
 private async reachable(path:StoreDiscoveredPath):Promise<boolean>{
  const channel=socket.constructTCPSocketInstance();
  try{await channel.connect({address:{address:path.host,port:path.host==='127.0.0.1'?49561:49563,family:1},timeout:1200});return true;}
  catch(e){return false;}finally{await channel.close().catch(()=>{});}
 }
 private async verifyDevice(item:StoreDiscoveredMac,generation:number):Promise<void>{
  if(this.checks.has(item.id))return;this.checks.add(item.id);
  try{
   const paths=item.paths.slice();const ready=await Promise.all(paths.map((p:StoreDiscoveredPath)=>this.reachable(p)));
   if(generation!==this.epoch||this.candidates.get(item.id)!==item)return;
   const alive=paths.filter((_p:StoreDiscoveredPath,i:number)=>ready[i]);
   const previous=this.devices.find((d:StoreDiscoveredMac)=>d.id===item.id);
   this.devices=this.devices.filter((d:StoreDiscoveredMac)=>d.id!==item.id);
   if(alive.length>0){
    const preferred=alive.find((p:StoreDiscoveredPath)=>p.host===previous?.host)||alive[0];
    this.devices.push({id:item.id,name:item.name,host:preferred.host,certificate:item.certificate,serviceName:item.serviceName,paths:alive,startRequested:item.startRequested});
    this.seen.set(item.id,Date.now());
   }else if(Date.now()-(this.seen.get(item.id)||0)>60000){this.candidates.delete(item.id);this.seen.delete(item.id);}
   this.changed(this.devices.slice());
  }finally{if(generation===this.epoch)this.checks.delete(item.id);}
 }
 private verifyAll():void{for(const item of this.candidates.values()){this.verifyDevice(item,this.epoch);}}
 private attribute(info:mdns.LocalServiceInfo,key:string):string {let out='';for(const item of info.serviceAttribute || []) {if(item.key===key){for(const byte of item.value){out+=String.fromCharCode(byte);}return out;}}return out;}
 start():void {
  this.stop();const generation=++this.epoch;this.startDatagram(generation);this.scanUSB(generation);this.usbTimer=setInterval(()=>this.scanUSB(generation),5000);this.presenceTimer=setInterval(()=>this.verifyAll(),3000);
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
     const item:StoreDiscoveredMac={id:id,name:info.serviceName.slice(0,80),host:host,certificate:certificate,serviceName:info.serviceName,paths:[]};
     this.serviceIDs.set(info.serviceName,id);this.acceptDevice(item);
    }).catch((e:Error)=>{hilog.warn(0x1234,'StoreDiscovery','resolve error=%{public}s',e.message);});
   });
   finder.on('serviceLost',(info:mdns.LocalServiceInfo)=>{if(generation!==this.epoch)return;this.serviceIDs.delete(info.serviceName);this.verifyAll();});
   finder.startSearchingMDNS();
  }catch(e){hilog.warn(0x1234,'StoreDiscovery','start failed');this.failed('暂时未能搜索设备，请确认两端软件已打开并保持设备连接。');}
 }
 private async scanUSB(generation:number):Promise<void>{
  if(this.usbPending)return;this.usbPending=true;
  try{const raw=await native.storeUSBDiscover();if(generation!==this.epoch)return;
   if(!raw){const remaining:StoreDiscoveredMac[]=[];for(const d of this.devices){if(d.host!=='127.0.0.1'){remaining.push(d);continue;}const lan=d.paths.find((p:StoreDiscoveredPath)=>localIPv4(p.host));if(lan){d.host=lan.host;d.paths=d.paths.filter((p:StoreDiscoveredPath)=>p.host!=='127.0.0.1');remaining.push(d);}}this.devices=remaining;this.changed(this.devices.slice());return;}
   const value=JSON.parse(raw) as USBIdentity;const info=value.identity;
   if(info.schema!=='store-discovery-v1'||info.certificate!==value.certificate||!/^[0-9a-f]{24}$/.test(info.id)||info.port!==49563)return;
   this.acceptDevice({startRequested:info.startRequested===true,id:info.id,name:info.name.slice(0,80),host:'127.0.0.1',certificate:info.certificate,serviceName:info.id,paths:[{host:'127.0.0.1',route:'usb'}]});
  }catch(e){}finally{this.usbPending=false;}
 }
 probeHost(host:string):void{if(localIPv4(host)){this.rememberedHost=host;this.refreshPaths();}}
 refreshPaths():void {
  if(this.probeInterval>=0){clearInterval(this.probeInterval);this.probeInterval=-1;}
  for(const timer of this.probeTimers){clearTimeout(timer);}this.probeTimers=[];if(this.probe){this.probe.close().catch(()=>{});this.probe=null;}
  this.startDatagram(this.epoch);
 }
 private async startDatagram(generation:number):Promise<void> {
  hilog.info(0x1234,'StoreDiscovery','datagram begin');
  let probe:socket.UDPSocket|null=null;
  try {
   const nonce=util.generateRandomUUID(true).replace(/-/g,'').toLowerCase();
   probe=socket.constructUDPSocketInstance();this.probe=probe;
   const owned=probe;
   probe.on('message',(event:socket.SocketMessageInfo)=>{
    if(generation!==this.epoch||!localIPv4(event.remoteInfo.address)||event.message.byteLength>8192)return;
    try{
     const text=new util.TextDecoder('utf-8').decodeWithStream(new Uint8Array(event.message));
     if(text==='YQHELLO1'){owned.send({data:`YQDISC1 ${nonce}`,address:{address:event.remoteInfo.address,port:49565,family:1}}).catch(()=>{});return;}
     if(text.startsWith('YQDISC1 '))return; // A broadcast can loop back to its sender.
     const info=JSON.parse(text) as DatagramIdentity;
     if(info.schema!=='store-discovery-v1'||info.nonce!==nonce||info.port!==49563||!/^[0-9a-f]{24}$/.test(info.id)||typeof info.certificate!=='string'||info.certificate.length>8192||!info.certificate.startsWith('-----BEGIN CERTIFICATE-----')||!info.certificate.trim().endsWith('-----END CERTIFICATE-----'))return;
     const item:StoreDiscoveredMac={id:info.id,name:typeof info.name==='string'?info.name.slice(0,80):'Mac',host:event.remoteInfo.address,certificate:info.certificate,serviceName:info.id,paths:(info.paths || []).filter((p:StoreDiscoveredPath)=>localIPv4(p.host)&&(p.route==='usb-net'||p.route==='lan')).slice(0,8)};
     this.datagramSeen.set(item.id,Date.now());this.acceptDevice(item);hilog.info(0x1234,'StoreDiscovery','datagram accepted');
    }catch(e){hilog.warn(0x1234,'StoreDiscovery','datagram invalid');}
   });
   await probe.bind({address:'0.0.0.0',port:49565,family:1});await probe.setExtraOptions({broadcast:true});hilog.info(0x1234,'StoreDiscovery','datagram bound');
   if(generation!==this.epoch){await probe.close();return;}
   const destinations:string[]=['255.255.255.255'];if(localIPv4(this.rememberedHost)){destinations.push(this.rememberedHost);}
   const diagnostic=AppStorage.get<string>('storeProbeAddress') || '';if(localIPv4(diagnostic)){destinations.push(diagnostic);hilog.info(0x1234,'StoreDiscovery','diagnostic unicast requested');}
   try{for(const net of connection.getAllNetsSync()){const props=connection.getConnectionPropertiesSync(net);for(const link of props.linkAddresses){const address=link.address.address;if(!localIPv4(address)||link.prefixLength<8||link.prefixLength>30)continue;const value=address.split('.').reduce((a:number,b:string)=>(a*256+Number(b))>>>0,0);const mask=(0xffffffff << (32-link.prefixLength))>>>0;const end=(value | ~mask)>>>0;const broadcast=[(end>>>24)&255,(end>>>16)&255,(end>>>8)&255,end&255].join('.');if(!destinations.includes(broadcast))destinations.push(broadcast);hilog.info(0x1234,'StoreDiscovery','network prefix=%{public}d',link.prefixLength);}}}catch(e){hilog.warn(0x1234,'StoreDiscovery','network info unavailable');}
   const send=():void=>{
    if(generation!==this.epoch||this.probe!==owned)return;
    // A failed old Wi-Fi destination must not tear down a healthy USB socket.
    const attempts:Promise<boolean>[]=destinations.slice(0,5).map((destination:string)=>
     owned.send({data:`YQDISC1 ${nonce}`,address:{address:destination,port:49565,family:1}})
      .then(()=>true).catch(()=>false));
    Promise.all(attempts).then((results:boolean[])=>{
     if(generation!==this.epoch||this.probe!==owned||results.some((ok:boolean)=>ok)||this.recoveryTimer>=0)return;
     const failedAt=Date.now();
     this.recoveryTimer=setTimeout(()=>{
      this.recoveryTimer=-1;if(generation!==this.epoch||this.probe!==owned)return;
      // USB hello/reply may still be healthy even if every old destination failed.
      if(Array.from(this.datagramSeen.values()).some((at:number)=>at>=failedAt-5000))return;
      this.refreshPaths();
     },2000);
    });
   };
   send();for(const delay of [1000,3000,6000,10000]){this.probeTimers.push(setTimeout(send,delay));}
   this.probeInterval=setInterval(send,8000);
  }catch(e){
   hilog.warn(0x1234,'StoreDiscovery','datagram unavailable error=%{public}s',(e as Error).message);
   if(probe){await probe.close().catch(()=>{});if(this.probe===probe)this.probe=null;}
   if(generation!==this.epoch)return;
   this.failed('设备搜索正在恢复，请稍候…');
   this.probeTimers.push(setTimeout(()=>{if(generation===this.epoch&&!this.probe)this.startDatagram(generation);},2000));
  }
 }
 stop():void {this.epoch++;if(this.presenceTimer>=0){clearInterval(this.presenceTimer);this.presenceTimer=-1;}this.candidates.clear();this.checks.clear();if(this.recoveryTimer>=0){clearTimeout(this.recoveryTimer);this.recoveryTimer=-1;}if(this.probeInterval>=0){clearInterval(this.probeInterval);this.probeInterval=-1;}if(this.usbTimer>=0){clearInterval(this.usbTimer);this.usbTimer=-1;}for(const timer of this.probeTimers){clearTimeout(timer);}this.probeTimers=[];if(this.probe){this.probe.close().catch(()=>{});this.probe=null;}if(this.finder){try{this.finder.stopSearchingMDNS();this.finder.off('discoveryStart');this.finder.off('serviceFound');this.finder.off('serviceLost');}catch(e){}this.finder=null;}this.devices=[];this.seen.clear();this.datagramSeen.clear();this.serviceIDs.clear();}
}
