import { mdns, socket } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { localIPv4 } from './StorePairing';
// Public discovery only. A request can show connection intent; it never grants access.
export class NearbyPad {
 private channel:socket.UDPSocket|null=null;
 private published:mdns.LocalServiceInfo|null=null;
 private alive:boolean=true;
 private lastRequest:number=0;
 private context:common.UIAbilityContext;private id:string;private name:string;private request:(id:string,host:string)=>void;
 constructor(context:common.UIAbilityContext,id:string,name:string,request:(id:string,host:string)=>void){this.context=context;this.id=id;this.name=name;this.request=request;}
 async start():Promise<void>{
  try{
   const channel=socket.constructUDPSocketInstance();this.channel=channel;
   channel.on('message',(event:socket.SocketMessageInfo)=>{
    if(!this.alive||event.message.byteLength>128||!localIPv4(event.remoteInfo.address)||Date.now()-this.lastRequest<3000)return;
    const words=new util.TextDecoder('utf-8').decodeWithStream(new Uint8Array(event.message)).trim().split(' ');
    if(words.length!==3||words[0]!=='YQSTART1'||!/^[0-9a-f]{24}$/.test(words[1])||words[2]!==event.remoteInfo.address)return;
    this.lastRequest=Date.now();this.request(words[1],event.remoteInfo.address);
   });
   await channel.bind({address:'0.0.0.0',port:49568,family:1});if(!this.alive){channel.close().catch(()=>{});return;}
   const service:mdns.LocalServiceInfo={serviceType:'_yingqiaopad._udp',serviceName:this.name+'-'+this.id.slice(0,6),port:49568,serviceAttribute:[{key:'id',value:Array.from(new util.TextEncoder().encodeInto(this.id))},{key:'name',value:Array.from(new util.TextEncoder().encodeInto(this.name))}]};
   this.published=await mdns.addLocalService(this.context,service);if(!this.alive&&this.published)mdns.removeLocalService(this.context,this.published).catch(()=>{});
  }catch(e){}
 }
 stop():void{this.alive=false;if(this.channel)this.channel.close().catch(()=>{});this.channel=null;if(this.published)mdns.removeLocalService(this.context,this.published).catch(()=>{});this.published=null;}
}
