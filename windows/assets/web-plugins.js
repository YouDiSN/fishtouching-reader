/* MIT License, Copyright (c) 2026 YouDiSN. Pure data parsing; never evaluates page code. */
(function (root) {
  'use strict';
  const fontMap = typeof FanqieFontMap !== 'undefined' ? FanqieFontMap : (typeof require==='function' ? require('./fanqie-font-map.json') : null);
  const sources = {
    fanqie: { name: '番茄书源', hosts: ['fanqienovel.com'], book: /^\/page\/\d+\/?$/, chapter: /^\/reader\/\d+\/?$/, content: 'muye-reader-content' },
    qimao: { name: '七猫书源', hosts: ['www.qimao.com'], book: /^\/shuku\/\d+\/?$/, chapter: /^\/shuku\/\d+-\d+\/?$/, content: 'chapter-detail-article' },
    qidian: { name: '起点免费书源', hosts: ['www.qidian.com', 'book.qidian.com', 'read.qidian.com'], book: /^\/(?:info|book)\/\d+\/?$/, chapter: /^\/chapter\/[A-Za-z0-9_\/-]+\/?$/, content: 'read-content' }
  };
  function address(raw) {
    const catalogAPI = /^https:\/\/www\.qimao\.com\/api\/book\/chapter-list\?book_id=([0-9]{1,20})$/.exec(raw);
    if(catalogAPI)return {host:'www.qimao.com',path:'/api/book/chapter-list',bookID:catalogAPI[1]};
    const match = /^https:\/\/([a-z0-9.-]+)(\/[A-Za-z0-9_./%~-]*)?$/.exec(raw);
    if (!match || raw.length > 2048 || raw.includes('..') || /%/i.test(raw)) throw Error('仅支持无参数的 HTTPS 地址；不接受账号、端口或跳转地址。');
    return { host: match[1], path: match[2] || '/' };
  }
  function validate(p) {
    const keys = ['schemaVersion','id','name','version','author','description','extensions','parser','adapter'].sort().join();
    if (!p || Object.keys(p).sort().join() !== keys || p.schemaVersion !== 2 || p.parser !== 'website' || typeof p.adapter !== 'string' || !Object.prototype.hasOwnProperty.call(sources,p.adapter) ||
      typeof p.id !== 'string' || typeof p.version !== 'string' ||
      !/^community\.[a-z0-9][a-z0-9.-]{0,62}$/.test(p.id) || !/^\d{1,4}\.\d{1,4}\.\d{1,4}$/.test(p.version) ||
      !Array.isArray(p.extensions) || p.extensions.length ||
      !['name','author','description'].every(k => typeof p[k] === 'string' && p[k].trim() && p[k].length <= ({name:60,author:80,description:300})[k])) throw Error('无效的 v2 书源规则；只允许内置受限适配器，不接受脚本或额外权限。');
    return p;
  }
  function checkURL(adapter, raw, kind) {
    const s = sources[adapter], u = address(raw);
    if (!s || !s.hosts.includes(u.host) || !s[kind].test(u.path)) throw Error('地址不属于该插件支持的书籍或章节页面。');
    return raw;
  }
  function decode(s) { return s.replace(/&#(x[0-9a-f]+|\d+);|&(amp|lt|gt|quot|apos|nbsp);/gi, (_, n, k) => {
    if (n) { const code = n[0].toLowerCase() === 'x' ? parseInt(n.slice(1),16) : +n; return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : ''; }
    return {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",nbsp:' '}[k.toLowerCase()];
  }); }
  function clean(s) { return decode(s.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>|<style\b[^>]*>[\s\S]*?<\/style\s*>|<!--[\s\S]*?-->/gi,'').replace(/<[^>]*>/g,'')).trim(); }
  // Extract a balanced element by class; foreign HTML is never added to the reader DOM.
  function elements(html, cls) {
    const tags=/<\/?([a-z][a-z0-9]*)\b[^>]*>/gi, found=[];let m,start=-1,depth=0,name;
    while((m=tags.exec(html))) {
      if(start<0) { const c=/\bclass\s*=\s*["']([^"']*)["']/i.exec(m[0]);
        if(!m[0].startsWith('</')&&c&&c[1].split(/\s+/).includes(cls)){start=tags.lastIndex;name=m[1].toLowerCase();depth=1;}
      } else if(m[1].toLowerCase()===name) {
        depth+=m[0].startsWith('</')?-1:1;
        if(!depth){found.push(html.slice(start,m.index));start=-1;}
      }
    }
    return found;
  }
  function element(html,cls){return elements(html,cls)[0]||'';}
  function challenge(html) {return /<script[^>]+src=["'][^"']*\/probe\.js|<[^>]+(?:id|class)=["'](?:captcha|geetest|verify-container)(?:["' ])/i.test(html);}
  function catalogRequest(adapter,url) {
    checkURL(adapter,url,'book');
    return adapter==='qimao'?'https://www.qimao.com/api/book/chapter-list?book_id='+address(url).path.split('/')[2]:'';
  }
  function catalog(adapter, url, html, catalogJSON) {
    checkURL(adapter,url,'book'); const s=sources[adapter];
    if(challenge(html))throw Error('网站返回访问验证页，未读取目录；请在网站完成验证，本插件不绕过验证。');
    if(adapter==='qimao' && catalogJSON) {
      const data=JSON.parse(catalogJSON),items=data?.data?.chapters;
      if(!Array.isArray(items)||!items.length||items.length>10000)throw Error('七猫目录响应格式不正确。');
      const bookID=address(url).path.split('/')[2],chapters=[],seen=new Set();let restrictedCount=0;
      for(const item of items) {
        if(item.is_vip!==0 && item.is_vip!=='0' && item.is_vip!==false){restrictedCount++;continue;}
        const id=String(item.id);
        if(!/^[0-9]{1,20}$/.test(id)||typeof item.title!=='string'||!item.title.trim())throw Error('七猫目录条目格式不正确。');
        if(seen.has(id))continue;seen.add(id);
        chapters.push({url:'https://www.qimao.com/shuku/'+bookID+'-'+id+'/',title:item.title.slice(0,200)});
      }
      if(!chapters.length)throw Error('该目录没有明确标记为免费的章节。');
      const title=clean((/<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html)||[])[1]||( /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html)||[])[1]?.split(/免费阅读|最新章节/)[0]||'七猫书籍').slice(0,120);
      return {title,chapters,restrictedCount,warning:'发现 '+chapters.length+' 个标记免费的目录条目，排除 '+restrictedCount+' 个受限条目；正文仍需逐章验证，不代表完整全书。'};
    }
    let directory=elements(html,adapter==='fanqie'?'chapter':adapter==='qimao'?'chapter-list':'volume-wrap').join('');
    let restrictedCount=0;
    if(adapter==='fanqie'){const items=elements(directory,'chapter-item');if(items.length)directory=items.filter(item=>{if(/class=["'][^"']*\bchapter-item-lock\b/.test(item)){restrictedCount++;return false;}return true;}).join('');}
    if(!directory)throw Error('没有公开可解析的目录容器；页面可能需要 App、动态加载或访问验证。');
    const chapters=[], seen=new Set(); let m; const re=/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a\s*>/gi;
    while ((m=re.exec(directory))) {
      let href=decode(m[1]); if(href.startsWith('//'))href='https:'+href; else if(href.startsWith('/'))href='https://'+address(url).host+href;
      try { checkURL(adapter,href,'chapter'); } catch { continue; }
      const title=clean(m[2]); if(!title || seen.has(href) || /最新|开始阅读|立即阅读/.test(title))continue;
      seen.add(href);chapters.push({url:href,title:title.slice(0,200)}); if(chapters.length>10000)throw Error('目录超过 10000 章。');
    }
    if (!chapters.length) throw Error('没有找到公开章节目录：网站可能要求验证、使用 App 或动态加载。本插件不会绕过限制。');
    const title=clean(element(html,'info-name') || (/<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html)||[])[1] || '网络书籍').slice(0,120);
    return {title, chapters, restrictedCount, warning:(restrictedCount?'已排除 '+restrictedCount+' 个带锁目录条目。':'')+'仅发现 '+chapters.length+' 个章节链接，不代表全书完整或正文可下载。每次最多导入 100 章；正文会逐章验证。'};
  }
  function fontRequest(adapter,html) {
    if(adapter!=='fanqie' || !fontMap || !/[\ue000-\uf8ff]/.test(decode(element(html,sources.fanqie.content))))return '';
    if(!html.includes(fontMap.family)||!html.includes('/'+fontMap.asset+'.woff'))throw Error('网页使用了未验证的新字体，暂不导入以避免乱码。');
    return 'https://lf6-awef.bytetos.com/obj/awesome-font/c/'+fontMap.asset+'.woff';
  }
  function chapter(adapter, html, fontDigest) {
    if(challenge(html))throw Error('网站返回访问验证页，未读取正文。');
    let body=element(html,sources[adapter].content);
    if(adapter==='qimao') {
      // Nuxt's public response contains a JSON string literal; parse only that literal, never run the surrounding JavaScript.
      const scripts=Array.from(html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)).map(m=>m[1]).filter(s=>s.includes('window.__NUXT__='));
      if(scripts.length===1){
        const content=Array.from(scripts[0].matchAll(/(?:[,{])content\s*:\s*("(?:[^"\\]|\\.)*")/g));
        if(content.length===1){const value=JSON.parse(content[0][1]);if(typeof value==='string' && value.trim())body=value;}
      }
    }
    if(!body)throw Error('没有找到正文区域，可能是网站布局变化或受限页面；未导入。');
    if(/qm-canvas-txt|<canvas\b/i.test(body))throw Error('正文通过画布显示，当前适配器不支持提取；未导入。');
    let decoded=decode(body);
    if(adapter==='fanqie' && /[\ue000-\uf8ff]/.test(decoded) && fontMap && fontDigest===fontMap.sha256 && fontRequest(adapter,html)) {
      body=body.replace(/&#(x[0-9a-f]+|\d+);/gi,(token,n)=>{const code=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):+n;return code>=0xe000&&code<=0xf8ff?String.fromCharCode(code):token;}).replace(/[\ue000-\uf8ff]/g,c=>{const plain=fontMap.mapping[String(c.charCodeAt(0))];return plain?plain.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'):c;});
      decoded=decode(body);
    }
    if(/[\ue000-\uf8ff]/.test(decoded))throw Error('正文含特殊字体编码，当前适配器不能可靠还原文字；未导入乱码。');
    // Strip scripts before splitting so script text cannot leak into paragraphs.
    const textOnly=body.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>|<style\b[^>]*>[\s\S]*?<\/style\s*>/gi,'');
    const paragraphs=textOnly.split(/<\/(?:p|div|section)\s*>|<br\s*\/?>/i).map(clean).filter(Boolean);
    const text=paragraphs.join('');
    if(!text)throw Error('正文为空，未导入。');
    const restrictionUI=/<[^>]+class=["'][^"']*(?:paywall|subscribe-wall|chapter-lock|login-required)\b/i.test(body);
    const onlyNotice=text.length<300 && /下载.{0,8}APP.{0,15}(阅读|全文)|订阅.{0,8}章节|登录后阅读|^请.{0,8}(输入|完成).{0,8}验证码/i.test(text);
    if(restrictionUI||onlyNotice)throw Error('页面是 App、登录或订阅提示，未导入正文。');
    return paragraphs;
  }
  const hosts=adapter=>sources[adapter].hosts.join("、");
  const api={sources,hosts,address,validate,checkURL,catalogRequest,catalog,fontRequest,chapter};root.WebPlugins=api;
  if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
