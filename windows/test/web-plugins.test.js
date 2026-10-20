'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {rules,publicIPv4,packageManifest,fetchPublic}=require('../web-import');
const {zipSync,strToU8}=require('fflate');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {ImportPluginRegistry}=require('../import-plugins');
const examples=require('../assets/community-plugins.json');
const fictional='纸船沿着虚构的小河前行，故事里的旅行者正在寻找一座不存在的城市。'.repeat(8);
test('community website identity, explicit permissions, disabled install, persistence and removal',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'ftr-website-test-'));
 try{const r=new ImportPluginRegistry(root);for(const p of examples){r.install(p);assert.equal(r.views().find(v=>v.id===p.id).enabled,false);assert.throws(()=>r.website(p.id));r.setEnabled(p.id,true);assert.equal(new ImportPluginRegistry(root).website(p.id).origin,'community');r.remove(p.id);assert.throws(()=>r.website(p.id));}}finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('JSON and single-file ZIP share strict schema; no spoofing, executable, traversal or bomb',()=>{
 const p=examples[0],json=JSON.stringify(p);assert.equal(packageManifest(Buffer.from(json)).id,p.id);
 assert.equal(packageManifest(Buffer.from(zipSync({'manifest.json':strToU8(json)}))).id,p.id);
 for(const files of [{'../manifest.json':strToU8(json)},{'manifest.json':strToU8(json),'run.js':strToU8('bad')},{'manifest.json':new Uint8Array(65537)}])assert.throws(()=>packageManifest(Buffer.from(zipSync(files))));
 for(const patch of [{id:'official.fake'},{adapter:'unknown'},{adapter:'__proto__'},{adapter:'constructor'},{id:['community.fake']},{script:'execute'},{origin:'official'},{extensions:['txt']}])assert.throws(()=>rules.validate({...p,...patch}));
});
test('HTTPS address and DNS destination restrictions',()=>{
 for(const url of ['http://example.com/a','https://u:p@example.com/a','https://example.com:443/a','https://example.com/a?token=x','https://example.com/../a','https://example.com/%2f','https://example.com\\evil'])assert.throws(()=>rules.address(url));
 for(const ip of ['127.0.0.1','10.0.0.1','169.254.169.254','100.64.0.1','192.168.1.1','172.31.1.1','0.0.0.0','224.1.1.1','198.18.0.1','::1'])assert.equal(publicIPv4(ip),false);
 assert.equal(publicIPv4('8.8.8.8'),true);
 assert.throws(()=>rules.checkURL('fanqie','https://example.com/page/1','book'));
});
test('fictional catalog order, deduplication, safe plain text; reject encoded/canvas/paywall pages',()=>{
 const url='https://fanqienovel.com/page/1';
 const html='<h1>虚构纸船</h1><a href="/reader/3">最新章节</a><div class="chapter"><a href="/reader/1">第一章</a><a href="/reader/2">第二章</a><a href="/reader/1">重复</a><a href="https://example.com/reader/9">外站</a></div>';
 const c=rules.catalog('fanqie',url,html);assert.deepEqual(c.chapters.map(c=>c.title),['第一章','第二章']);assert.match(c.warning,/不代表全书完整/);
 assert.deepEqual(rules.chapter('fanqie',`<div class="muye-reader-content"><p>${fictional}</p><script>bad()</script></div>`),[fictional]);
 for(const body of ['<p>&#xe001;</p>','<p>\ue002</p>','<canvas></canvas>','<p>下载 APP 阅读全文</p>'])assert.throws(()=>rules.chapter('fanqie',`<div class="muye-reader-content">${body}</div>`));
 assert.throws(()=>rules.catalog('qimao','https://www.qimao.com/shuku/1/','<script>only app</script>'));
 for(const adapter of ['qimao','qidian'])assert.deepEqual(rules.chapter(adapter,`<div class="${rules.sources[adapter].content}"><p>${fictional}</p></div>`),[fictional]);
});
test('cancellation stops before network access',async()=>{const c=new AbortController();c.abort();await assert.rejects(fetchPublic('https://example.com/plugin.json',c.signal));});
test('all directory groups, locked entries excluded and precise content failures',()=>{
 const html='<h1>虚构故事</h1><div class="chapter"><div class="chapter-item"><a href="/reader/1">第一章</a></div><div class="chapter-item"><a href="/reader/2">第二章</a><i class="chapter-item-lock muyeicon-lock"></i></div></div><div class="chapter"><div class="chapter-item"><a href="/reader/3">第三章</a></div></div>';
 const c=rules.catalog('fanqie','https://fanqienovel.com/page/1',html);
 assert.deepEqual(c.chapters.map(c=>c.title),['第一章','第三章']);assert.equal(c.restrictedCount,1);
 const content=s=>`<div class="muye-reader-content">${s}</div>`;
 assert.deepEqual(rules.chapter('fanqie',content('<p>她收到一条验证码，随后关上手机。</p>')),['她收到一条验证码，随后关上手机。']);
 assert.deepEqual(rules.chapter('fanqie',content('<div>短章第一段。</div><div>短章第二段。</div><script><p>不能作为正文</p></script>')),['短章第一段。','短章第二段。']);
 assert.throws(()=>rules.chapter('fanqie',content('<p>请下载 APP 阅读全文</p>')),/提示/);
 assert.throws(()=>rules.chapter('fanqie',content('<canvas></canvas>')),/画布/);
 assert.throws(()=>rules.chapter('fanqie',content('<p>&#xe001;</p>')),/字体编码/);
 assert.throws(()=>rules.catalog('qidian','https://www.qidian.com/book/1/','<script src="/abc/probe.js"></script>'),/验证页/);
});
test('Qimao public catalog JSON and literal Nuxt text; no script evaluation',()=>{
 const html='<title>虚构纸船免费阅读-七猫</title>',url='https://www.qimao.com/shuku/1/';
 const response=JSON.stringify({data:{chapters:[{id:'10',title:'第一章',is_vip:'0'},{id:'20',title:'收费章节',is_vip:'1'}]}});
 assert.equal(rules.catalogRequest('qimao',url),'https://www.qimao.com/api/book/chapter-list?book_id=1');
 assert.equal(rules.address(rules.catalogRequest('qimao',url)).host,'www.qimao.com');
 assert.throws(()=>rules.address('https://www.qimao.com/api/book/chapter-list?book_id=1&url=http://localhost'));
 const c=rules.catalog('qimao',url,html,response);assert.equal(c.title,'虚构纸船');assert.equal(c.chapters.length,1);assert.equal(c.restrictedCount,1);
 const page='<div class="chapter-detail-article"><canvas></canvas></div><script>window.__NUXT__=(function(){throw Error("never execute");return {content:'+JSON.stringify('<p>纸船沿着虚构的小河前行。</p>')+'};})();</script>';
 assert.deepEqual(rules.chapter('qimao',page),['纸船沿着虚构的小河前行。']);
 assert.throws(()=>rules.chapter('qimao',page.replace('content:', 'content:evil(),other:')));
});
test('font conversion requires exact fingerprint, all unknown glyphs rejected',()=>{
 const font=require('../assets/fanqie-font-map.json');
 const entry=Object.entries(font.mapping).find(([,v])=>v==='的');assert.ok(entry);
 const glyph=String.fromCharCode(Number(entry[0]));const html=`<style>${font.family} url(/${font.asset}.woff)</style><div class="muye-reader-content"><p>虚构${glyph}故事 &lt;测试&gt;</p></div>`;
 assert.match(rules.fontRequest('fanqie',html),/^https:\/\/lf6-awef\.bytetos\.com\/obj\/awesome-font\/c\//);
 assert.throws(()=>rules.chapter('fanqie',html));assert.throws(()=>rules.chapter('fanqie',html,'wrong'));
 assert.deepEqual(rules.chapter('fanqie',html,font.sha256),['虚构的故事 <测试>']);
 assert.deepEqual(rules.chapter('fanqie',html.replace(glyph,'&#'+entry[0]+';'),font.sha256),['虚构的故事 <测试>']);
 assert.throws(()=>rules.fontRequest('fanqie',html.replace(font.asset,'unknown')));
 assert.throws(()=>rules.chapter('fanqie',html.replace(glyph,'\ue000'),font.sha256));
});
test('Fake-IP fallback pins resolver and public destination, rejects private DoH answers',async()=>{
 const dns=require('node:dns').promises,https=require('node:https'),{EventEmitter}=require('node:events');
 const oldDNS=dns.resolve4,oldGet=https.get;let answerIP='8.8.8.8',destinations=[];
 dns.resolve4=async()=>['198.18.0.1'];
 https.get=(url,options,callback)=>{
  const req=new EventEmitter();req.destroy=error=>{if(error)req.emit('error',error);req.emit('close');};
  options.lookup(new URL(url).hostname,{all:true},(_e,records)=>destinations.push(records[0].address));
  setImmediate(()=>{const res=new EventEmitter();res.statusCode=200;res.resume=()=>{};callback(res);
   const body=url.includes('dns-query')?JSON.stringify({Status:0,Question:[{name:'example.com.'}],Answer:[{type:1,data:answerIP}]}):'<p>public</p>';
   res.emit('data',Buffer.from(body));res.emit('end');req.emit('close');});return req;
 };
 try{
  assert.equal((await fetchPublic('https://example.com/book',new AbortController().signal)).toString(),'<p>public</p>');
  assert.deepEqual(destinations,['1.1.1.1','8.8.8.8']);destinations=[];answerIP='127.0.0.1';
  await assert.rejects(fetchPublic('https://example.com/book',new AbortController().signal),/DNS/);assert.deepEqual(destinations,['1.1.1.1']);
  dns.resolve4=async()=>['10.0.0.1'];destinations=[];await assert.rejects(fetchPublic('https://example.com/book',new AbortController().signal),/DNS/);assert.deepEqual(destinations,[]);
 }finally{dns.resolve4=oldDNS;https.get=oldGet;}
});
