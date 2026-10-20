'use strict';
const https = require('node:https');
const dns = require('node:dns').promises;
const { unzipSync } = require('fflate');
const rules = require('./assets/web-plugins');
function publicIPv4(ip) {
  const a = ip.split('.').map(Number);
  return a.length === 4 && a.every(n => Number.isInteger(n) && n >= 0 && n <= 255) &&
    !([0,10,127].includes(a[0]) || a[0]>=224 || a[0]===100 && a[1]>=64 && a[1]<=127 || a[0]===169 && a[1]===254 || a[0]===172 && a[1]>=16 && a[1]<=31 || a[0]===192 && [0,2,168].includes(a[1]) || a[0]===198 && [18,19,51].includes(a[1]) || a[0]===203 && a[1]===0 && a[2]===113);
}
const resolverCache=new WeakMap();
async function fetchPublic(raw, signal, limit = 2*1024*1024) {
  signal.throwIfAborted(); const {host} = rules.address(raw);
  const cache=resolverCache.get(signal)||new Map();resolverCache.set(signal,cache);
  const cached=cache.get(host);
  let records = cached && Date.now()-cached.time<60000 ? cached.records : await dns.resolve4(host); signal.throwIfAborted();
  if (records.length && records.every(ip=>/^198\.(18|19)\./.test(ip))) {
    const body=await requestPinned('https://cloudflare-dns.com/dns-query?name='+host+'&type=A',['1.1.1.1'],signal,65536,{'Accept':'application/dns-json'});
    const answer=JSON.parse(body.toString('utf8'));
    if(answer.Status!==0 || answer.Question?.[0]?.name?.replace(/\.$/,'')!==host || !Array.isArray(answer.Answer))throw Error('公共 DNS 未返回有效结果。');
    records=answer.Answer.filter(r=>r.type===1).map(r=>r.data);
  }
  if (!records.length || !records.every(publicIPv4)) throw Error('DNS 解析到本机、局域网或保留地址，连接已阻止。如果启用了代理 Fake-IP，请为目标域名使用真实公网 DNS 后重试。');
  cache.set(host,{time:Date.now(),records});
  if(host==='www.qimao.com')return requestCurl(raw,host,records[0],signal,limit);
  return requestPinned(raw,records,signal,limit);
}
function requestPinned(raw,records,signal,limit,headers={}) {
  signal.throwIfAborted();
  return new Promise((resolve,reject) => {
    // Custom lookup pins the validated address; no cookies, proxies or redirects.
    const req = https.get(raw, { signal, family:4, lookup:(_h,options,cb)=>cb(null,...(options.all ? [[{address:records[0],family:4}]] : [records[0],4])),
      headers:{'User-Agent':'FishTouchingReader/1.0 (public-page-import)','Accept-Encoding':'identity',...headers} }, res => {
      if (res.statusCode!==200) { res.resume(); reject(Error(res.statusCode===202?'网站返回 HTTP 202 访问验证页，尚未取得正文；请在官网查看。':'网站拒绝访问或发生重定向；请使用直接 HTTPS 地址。'));req.destroy();return; }
      let size=0;const chunks=[];
      res.on('data',chunk=>{size+=chunk.length;if(size>limit)req.destroy(Error('响应超过大小限制。'));else chunks.push(chunk);});
      res.on('end',()=>resolve(Buffer.concat(chunks)));res.on('error',reject);
    });
    const timer=setTimeout(()=>req.destroy(Error('请求超时。')),20000);req.on('close',()=>clearTimeout(timer));req.on('error',reject);
  });
}
function packageManifest(data) {
  if(data.length>262144)throw Error('插件包不能超过 256 KB。');
  if(data[0]===0x50 && data[1]===0x4b) {
    let count=0;
    const files=unzipSync(data,{filter:entry=>{count++;if(entry.name!=='manifest.json'||entry.originalSize>65536||count>1)throw Error('ZIP 必须只含根目录 manifest.json，解压不能超过 64 KB。');return true;}});
    if(count!==1||!files['manifest.json']||files['manifest.json'].length>65536)throw Error('ZIP 清单无效。');
    data=Buffer.from(files['manifest.json']);
  }
  return require('./import-plugins').validateManifest(data);
}
module.exports={rules,publicIPv4,fetchPublic,packageManifest};

function requestCurl(raw,host,ip,signal,limit) {
  const {spawn}=require('node:child_process');
  const executable=process.platform==='win32'?require('node:path').join(process.env.SystemRoot||'C:\\Windows','System32','curl.exe'):'/usr/bin/curl';
  return new Promise((resolve,reject)=>{
    signal.throwIfAborted();
    const args=['-q','--silent','--fail','--noproxy','*','--proto','=https','--max-time','20','--connect-timeout','8','--max-filesize',String(limit),'--resolve',`${host}:443:${ip}`,'--user-agent','FishTouchingReader/1.0 (public-page-import)','--write-out','\n%{http_code}',raw];
    const child=spawn(executable,args,{windowsHide:true,stdio:['ignore','pipe','ignore']});let size=0,chunks=[],failed=false;
    const stop=error=>{failed=true;child.kill();reject(error);};
    const abort=()=>stop(Error('任务已取消。'));signal.addEventListener('abort',abort,{once:true});if(signal.aborted)abort();
    const timer=setTimeout(()=>stop(Error('请求超时。')),22000);
    child.on('error',()=>stop(Error('系统 curl 不可用，无法使用七猫 HTTP 兼容传输。')));
    child.stdout.on('data',d=>{size+=d.length;if(size>limit+4)stop(Error('响应超过大小限制。'));else chunks.push(d);});
    child.on('close',code=>{clearTimeout(timer);signal.removeEventListener('abort',abort);if(failed)return;const data=Buffer.concat(chunks);if(code!==0||data.subarray(-4).toString()!=='\n200')reject(Error('网站拒绝访问、发生重定向或请求超时。'));else resolve(data.subarray(0,-4));});
  });
}
