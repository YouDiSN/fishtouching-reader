'use strict';
(() => {
  const themes = [
    ['forest','森林绿','安静的深绿','#101716','#293a33','#438868','#e8eee9'],
    ['paper','暖纸','纸页般的温暖','#f4eddf','#e3d7c2','#795d3c','#352d24'],
    ['light','浅色','清爽而明亮','#f5f6f8','#e2e8f1','#365fa1','#202733'],
    ['midnight','午夜蓝','留给夜晚的蓝','#101827','#293d5c','#4069a2','#e3eaf5'],
    ['graphite','石墨灰','纯粹的黑与灰','#191a1d','#373a42','#626875','#ececee']
  ];
  let current={theme:'forest',font:'',fontSize:19},families=[],fontsLoaded=false,fontError='',requesting=false;
  let controlID=0;
  const post=(action,data={})=>window.webkit?.messageHandlers?.app?.postMessage({action,...data});
  const controls=()=>[...document.querySelectorAll('[data-reading-appearance]')];
  function apply(value) {
    const size=Number(value.fontSize);
    const next={theme:themes.some(([id])=>id===value.theme)?value.theme:'forest',font:typeof value.font==='string'?value.font:'',fontSize:Number.isInteger(size)&&size>=15&&size<=30?size:19};
    const changed=Object.keys(next).some(key=>next[key]!==current[key]);
    if(changed)window.dispatchEvent(new Event('reader-appearance-will-change'));
    current=next;document.documentElement.dataset.readerTheme=current.theme;
    document.documentElement.style.setProperty('--reader-size',current.fontSize+'px');
    if(current.font)document.documentElement.style.setProperty('--reader-font',JSON.stringify(current.font));else document.documentElement.style.removeProperty('--reader-font');
    controls().forEach(el=>{
      el.querySelectorAll('[data-theme]').forEach(button=>{const active=button.dataset.theme===current.theme;button.setAttribute('aria-pressed',String(active));button.querySelector('.theme-check').textContent=active?'✓':'';});
      if(el.querySelector('[data-font]')){renderFonts(el);el.querySelector('.appearance-preview').style.removeProperty('--reader-size');el.querySelector('[data-size]').value=current.fontSize;el.querySelector('[data-size-output]').textContent=current.fontSize;}
    });
    // Also synchronize newly mounted readers when native preferences equal defaults.
    if(changed)window.dispatchEvent(new CustomEvent('reader-appearance-changed',{detail:current}));

  }
  function renderFonts(el) {
    const select=el.querySelector('[data-font]');if(!select)return;
    select.replaceChildren(new Option('默认宋体 / 衬线体',''));
    if(current.font&&!families.includes(current.font))select.add(new Option(current.font+'（当前）',current.font));
    families.forEach(name=>select.add(new Option(name,name)));select.value=current.font;
    el.querySelector('[data-font-status]').textContent=fontError||(fontsLoaded?`${families.length} 款系统字体`:'使用本机已安装的字体');
  }
  function requestFonts(){if(!requesting&&!fontsLoaded){requesting=true;post('listSystemFonts');}}
  function mount(){controls().forEach((el,index)=>{
    if(el.dataset.mounted)return;el.dataset.mounted='true';
    if(el.dataset.readingAppearance==='theme'){
      el.innerHTML='<div class="theme-grid" aria-label="选择主题">'+themes.map(([id,name,desc,bg,soft,accent,text])=>`<button class="theme-option" type="button" data-theme="${id}" aria-pressed="${id===current.theme}" style="--tile-bg:${bg};--tile-soft:${soft};--tile-accent:${accent};--tile-text:${text}"><span class="theme-thumbnail" aria-hidden="true"><span class="mini-sidebar"><i></i><i></i><i></i></span><span class="mini-reader"><b>Aa</b><i></i><i></i><i></i><em></em></span></span><span class="theme-caption"><span>${name}</span><span class="theme-check">${id===current.theme?'✓':''}</span></span><span class="theme-description">${desc}</span></button>`).join('')+'</div>';
      el.querySelectorAll('[data-theme]').forEach(button=>button.onclick=()=>post('saveReadingPreferences',{theme:button.dataset.theme}));return;
    }
    const id='reader-font-'+controlID++;
    el.innerHTML=`<div class="font-setting"><div class="font-setting-title"><label for="${id}">正文字体</label><span data-font-status></span></div><div class="font-fields"><select id="${id}" data-font aria-label="选择正文字体"></select></div></div><div class="font-setting"><div class="font-setting-title"><label for="${id}-size">字号</label><output data-size-output>${current.fontSize}</output></div><div class="size-control"><span aria-hidden="true">A</span><input id="${id}-size" data-size type="range" min="15" max="30" step="1" value="${current.fontSize}"><span aria-hidden="true">A</span></div></div><div class="font-preview-label">预览</div><div class="appearance-preview"><div class="preview-chapter">第一章 · 午后</div><p>窗边的阳光落在书页上。风轻轻翻过一页，故事就从这里开始。</p><small>Reading feels like home. 0123456789</small></div><p class="appearance-hint">用于 TXT 和 EPUB 正文。PDF 保留原始排版。</p>`;
    const font=el.querySelector('[data-font]');font.onfocus=requestFonts;font.onpointerdown=requestFonts;font.onchange=()=>post('saveReadingPreferences',{font:font.value});
    const size=el.querySelector('[data-size]');size.oninput=()=>{el.querySelector('[data-size-output]').textContent=size.value;el.querySelector('.appearance-preview').style.setProperty('--reader-size',size.value+'px');};
    size.onchange=()=>post('saveReadingPreferences',{fontSize:Number(size.value)});renderFonts(el);
  });}
  window.receiveReadingPreferences=apply;
  window.receiveSystemFonts=data=>{requesting=false;fontsLoaded=!data.error;fontError=data.error||'';families=[...new Set((data.fonts||[]).filter(x=>typeof x==='string'&&x.length>0&&x.length<=200))].sort((a,b)=>a.localeCompare(b));controls().forEach(renderFonts);};
  window.ReaderAppearance={mount,current:()=>({...current})};mount();requestFonts();post('readingPreferences',{legacyFontSize:Number(localStorage.getItem('fontSize')||19)});
})();
