export const STORE_DOWNLOAD_URL: string = 'https://github.com/5zhangxuanhao5/yingqiao-store/releases/tag/store-v0.3.2-test.1';
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
  if (p.schema!=='yingqiao-pairing-v1'||typeof p.host!=='string'||!(localIPv4(p.host)||p.host==='127.0.0.1')||typeof p.token!=='string'||!/^[0-9a-f]{64}$/.test(p.token)||p.port!==49563||p.udpPort!==49564||typeof p.cert!=='string'||p.cert.length>8192||!p.cert.startsWith('-----BEGIN CERTIFICATE-----')||!p.cert.trim().endsWith('-----END CERTIFICATE-----')||!Array.isArray(p.codecs)||!p.codecs.every((v:string)=>['avc','hevc'].includes(v))||p.codecs.length===0||p.codecs.length>2) { return null; }
  return {schema:p.schema,host:p.host,token:p.token,cert:p.cert,port:p.port,udpPort:p.udpPort,codecs:p.codecs};
 } catch (e) { return null; }
}

export const STORE_INSTALL_STEPS:string='1. 点“复制 Mac 下载链接”，发送到你的 Mac，在电脑浏览器地址栏粘贴并打开。\n\n2. 在网页“Mac 测试版下载”处，点击 Yingqiao-Mac-0.3.2.zip。不要下载 Source code 或 native-dependencies，它们不是安装包。\n\n3. 在 Mac 的“访达 → 下载”找到 ZIP，双击解压。把“映桥”拖进“应用程序”，再双击打开。\n\n4. 阅读电脑端用途说明后点“继续设置”。按 macOS 的权限通知完成“录屏与系统录音”和“辅助功能”授权；这些分别用于显示画面和键鼠操作。认证只在你自己的 Mac 上完成。\n\n5. 保持两端映桥都打开，回到平板点“Mac 已安装，开始使用”，选择附近的 Mac。第一次连接，在 Mac 点“允许连接”，之后无需再次确认。\n\n当前是尚未完成 Apple 公证的测试包；若系统阻止打开，请先停止安装并把提示反馈给我们。';
