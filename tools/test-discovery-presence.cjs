const fs=require('fs'),vm=require('vm'),ts=require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const assert=require('assert');let reachable=new Set(),opens=0,closes=0,pending=null;
const native={async storeUSBDiscover(host){opens++;try{if(pending)await pending;if(!reachable.has(host))return '';return JSON.stringify({certificate:'fixture-public-identity',identity:{id:'a'.repeat(24),certificate:'fixture-public-identity',name:'Fixture Mac',port:49563,schema:'store-discovery-v1'}});}finally{closes++;}}};
const sandbox={exports:{},require:n=>n==='libedgelink.so'?{default:native}:n==='@kit.NetworkKit'?{socket:{}}:n==='./StorePairing'?{localIPv4:h=>h.startsWith('10.')||h.startsWith('192.168.')}:n==='@kit.PerformanceAnalysisKit'?{hilog:{}}:{},setInterval:()=>1,clearInterval(){},setTimeout:()=>1,clearTimeout(){},Date,Promise,Map,Set};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('harmony/entry/src/main/ets/store/StoreDiscovery.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,sandbox);
let visible=[];const Discovery=sandbox.exports.StoreDiscovery;const d=new Discovery({},v=>visible=v,()=>{});const item=(host,paths=[])=>({id:'a'.repeat(24),name:'Synthetic Mac',host,certificate:'fixture-public-identity',serviceName:'fixture',paths});
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 d.acceptDevice(item('10.1.1.2'));await flush();assert.equal(visible.length,0,'unreachable observation must not enable start');
 reachable.add('10.1.1.2');d.verifyAll();await flush();assert.equal(visible.length,1,'online remembered candidate is rediscovered by live check');
 reachable.clear();d.verifyAll();await flush();assert.equal(visible.length,0,'device disappears when no live path remains');
 reachable.add('192.168.11.5');d.acceptDevice(item('192.168.11.5',[{host:'192.168.11.5',route:'usb-net'}]));await flush();assert.equal(visible.length,1,'USB networking discovery must not require Wi-Fi');assert.equal(visible[0].host,'192.168.11.5');
 reachable.add('10.1.1.2');d.acceptDevice(item('10.1.1.2',[{host:'192.168.11.5',route:'usb-net'}]));await flush();reachable.delete('10.1.1.2');d.verifyAll();await flush();assert.equal(visible.length,1);assert.equal(visible[0].host,'192.168.11.5','failed Wi-Fi must not hide a live USB device');
 let resume;pending=new Promise(r=>resume=r);d.verifyAll();d.stop();visible=[];resume();await flush();assert.equal(visible.length,0,'late result after stop must not resurrect stale devices');assert.equal(opens,closes,'all short presence sockets close');
 console.log('PASS discovery presence: unreachable/online/offline, USB without Wi-Fi, failed-route coexistence, stop race and socket cleanup');
})().catch(e=>{console.error(e);process.exitCode=1;});
