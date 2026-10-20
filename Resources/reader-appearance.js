'use strict';
(() => {
  const themes = [['forest','森林绿'],['paper','暖纸'],['light','浅色'],['midnight','午夜蓝'],['graphite','石墨灰']];
  let current = {theme:'forest',font:''}, families = [], fontsLoaded = false, fontError = '', requesting = false;
  const channel = document.querySelector('#appearance') ? 'settings' : 'app';
  const post = (action, data={}) => window.webkit?.messageHandlers?.[channel]?.postMessage({action,...data});
  const controls = () => [...document.querySelectorAll('[data-reading-appearance]')];
  function apply(value) {
    const next = {theme:themes.some(([id])=>id===value.theme)?value.theme:'forest',font:typeof value.font==='string'?value.font:''};
    const changed = next.theme!==current.theme || next.font!==current.font;
    if(changed) window.dispatchEvent(new Event('reader-appearance-will-change'));
    current = next;
    document.documentElement.dataset.readerTheme=current.theme;
    // A quoted CSS family cannot inject declarations; unavailable glyphs use normal system fallback.
    if(current.font) document.documentElement.style.setProperty('--reader-font',JSON.stringify(current.font));
    else document.documentElement.style.removeProperty('--reader-font');
    controls().forEach(el=>{el.querySelector('[data-theme]').value=current.theme;renderFonts(el);});
    if(changed) window.dispatchEvent(new Event('reader-appearance-changed'));
  }
  function renderFonts(el) {
    const select=el.querySelector('[data-font]'), query=el.querySelector('[data-font-search]').value.trim().toLocaleLowerCase();
    select.replaceChildren(new Option('默认宋体 / 衬线体',''));
    const visible=families.filter(name=>name.toLocaleLowerCase().includes(query));
    if(current.font && !visible.includes(current.font)) select.add(new Option(current.font+'（当前）',current.font));
    for(const name of visible) select.add(new Option(name,name));
    select.value=current.font;
    el.querySelector('[data-font-status]').textContent=fontError || (fontsLoaded ? `系统字体 ${families.length} 款${query?` · 匹配 ${visible.length} 款`:''}。仅影响 TXT / EPUB，缺少的字符使用系统备用字体。` : '展开字体选择时读取本机已安装字体，不下载字体。');
  }
  function requestFonts() { if(!requesting && !fontsLoaded){requesting=true;post('listSystemFonts');} }
  function mount() {
    controls().forEach((el,index)=>{
      if(el.dataset.mounted)return;el.dataset.mounted='true';
      const id='reading-appearance-'+index;
      el.innerHTML=`<label for="${id}-theme">主题</label><select id="${id}-theme" data-theme></select><label for="${id}-search">正文字体</label><input id="${id}-search" data-font-search type="search" placeholder="搜索系统字体" aria-label="搜索系统字体" autocomplete="off"><select id="${id}-font" data-font aria-label="选择正文字体"></select><p class="appearance-hint" data-font-status role="status"></p><p class="appearance-preview" aria-label="字体预览">窗边的阳光落在书页上。<br>Reading · 0123456789</p>`;
      const theme=el.querySelector('[data-theme]');themes.forEach(([id,name])=>theme.add(new Option(name,id)));theme.value=current.theme;
      theme.onchange=()=>post('saveReadingPreferences',{theme:theme.value});
      const font=el.querySelector('[data-font]');font.onfocus=requestFonts;font.onpointerdown=requestFonts;
      font.onchange=()=>post('saveReadingPreferences',{font:font.value});
      const search=el.querySelector('[data-font-search]');search.onfocus=requestFonts;search.oninput=()=>renderFonts(el);
      renderFonts(el);
    });
  }
  window.receiveReadingPreferences = apply;
  window.receiveSystemFonts = data => {
    requesting=false;fontsLoaded=!data.error;fontError=data.error||'';
    families=[...new Set((data.fonts||[]).filter(x=>typeof x==='string'&&x.length>0&&x.length<=200))].sort((a,b)=>a.localeCompare(b));
    controls().forEach(renderFonts);
  };
  window.ReaderAppearance={mount};
  mount();post('readingPreferences');
})();
