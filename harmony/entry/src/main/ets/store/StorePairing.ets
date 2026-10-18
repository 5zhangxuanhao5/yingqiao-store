export const STORE_DOWNLOAD_URL: string = 'https://github.com/5zhangxuanhao5/yingqiao-store';
export interface StorePairing { schema: string; token: string; cert: string; host: string; port: number; udpPort: number; codecs: string[]; }
export function localIPv4(host: string): boolean {
 if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) { return false; }
 const x=host.split('.').map((v:string)=>Number(v));
 if (x.some((v:number)=>v<0||v>255) || host.split('.').some((v:string)=>v.length>1&&v.startsWith('0'))) { return false; }
 return x[0]===10 || (x[0]===172&&x[1]>=16&&x[1]<=31) || (x[0]===192&&x[1]===168) || (x[0]===169&&x[1]===254);
}
export function validatePairing(text: string): StorePairing | null {
 if (text.length>12288) { return null; }
 try {
  const p=JSON.parse(text) as StorePairing;
  if (p.schema!=='yingqiao-pairing-v1'||typeof p.host!=='string'||!localIPv4(p.host)||typeof p.token!=='string'||!/^[0-9a-f]{64}$/.test(p.token)||p.port!==49563||p.udpPort!==49564||typeof p.cert!=='string'||p.cert.length>8192||!p.cert.startsWith('-----BEGIN CERTIFICATE-----')||!p.cert.trim().endsWith('-----END CERTIFICATE-----')||!Array.isArray(p.codecs)||!p.codecs.every((v:string)=>['avc','hevc'].includes(v))||p.codecs.length===0||p.codecs.length>2) { return null; }
  return {schema:p.schema,host:p.host,token:p.token,cert:p.cert,port:p.port,udpPort:p.udpPort,codecs:p.codecs};
 } catch (e) { return null; }
}
