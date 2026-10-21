const fs=require('fs'),vm=require('vm'),assert=require('assert');
const ts=require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const code=ts.transpileModule(fs.readFileSync('harmony/entry/src/main/ets/service/BackgroundExtension.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
const flush=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));};
function fixture(){
 const state={running:true,backgroundRetainSupported:true,sessionID:19},storage=new Map(),commands=[],ends=[],disconnects=[];
 let starts=0,stops=0,start=async()=>{},agent=async()=>({});
 const native={input:s=>{commands.push(s);return true;},stats:()=>JSON.stringify(state),availabilityEnd:s=>ends.push(s),disconnect:r=>{disconnects.push(r);state.running=false;state.stopReason=r;}};
 const tasks={BackgroundMode:{MULTI_DEVICE_CONNECTION:6},startBackgroundRunning:async(c,mode,a)=>{assert.equal(mode,6);starts++;await start();},stopBackgroundRunning:async()=>{stops++;}};
 const kit={wantAgent:{getWantAgent:()=>agent(),OperationType:{START_ABILITY:1},WantAgentFlags:{UPDATE_PRESENT_FLAG:1}}};
 const sandbox={exports:{},require:n=>n==='libedgelink.so'?{default:native}:n==='@kit.AbilityKit'?kit:{backgroundTaskManager:tasks},Date,Promise,AppStorage:{get:k=>storage.get(k),setOrCreate:(k,v)=>storage.set(k,v)}};
 vm.runInNewContext(code,sandbox);
 return{C:sandbox.exports.BackgroundExtension,state,storage,commands,ends,disconnects,setStart:f=>start=f,setAgent:f=>agent=f,counts:()=>({starts,stops})};
}
(async()=>{
 let f=fixture();f.C.arm({},true);await flush();assert.equal(f.counts().starts,1);assert(f.C.suspend());assert(f.C.suspend());assert.equal(f.disconnects.length,1);assert(f.C.parked());
 f.C.prepareResume();assert(!f.C.parked()&&f.C.resuming);assert(f.C.retryResume());f.C.prepareResume();f.state.running=true;f.C.arm({},true);await flush();assert(!f.C.resuming);f.C.end();await flush();assert.equal(f.counts().stops,1);assert(!f.C.parked());
 f=fixture();let grant;f.setStart(()=>new Promise(r=>grant=r));f.C.arm({},true);await flush();f.C.end();grant();await flush();assert.deepEqual(f.counts(),{starts:1,stops:1},'End racing grant must remove granted task');
 f=fixture();let agent;f.setAgent(()=>new Promise(r=>agent=r));f.C.arm({},true);await flush();f.C.end();agent({});await flush();assert.equal(f.counts().starts,0,'End while preparing cannot start OS task');
 f=fixture();f.setStart(async()=>{throw Error('denied');});f.C.arm({},true);await flush();assert(!f.C.suspend());f.C.arm({},true);await flush();assert.equal(f.counts().starts,1,'denial must not loop');
 f=fixture();f.C.arm({},false);await flush();assert.equal(f.counts().starts,0);assert(!f.C.suspend());
 f=fixture();f.C.arm({},true);await flush();f.C.suspend();f.C.end();await flush();assert.deepEqual(f.ends,[19]);assert.equal(f.counts().stops,1);
 console.log('PASS background task owner: grant/park/resume/end, duplicate lifecycle, End races, denial, old host and explicit parked End');
})().catch(e=>{console.error(e);process.exitCode=1;});
