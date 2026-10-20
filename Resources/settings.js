'use strict';
(() => {

const $ = id => document.getElementById(id);
let previousPasswordScope = null;
const presetIcons = [['fish','摸鱼'],['book','书本'],['night','夜读'],['leaf','绿叶'],['coffee','咖啡'],['star','星星'],['pencil','铅笔'],['music','音乐'],['sunrise','日出'],['cloud','云朵']];
function post(action,data={}) {window.webkit?.messageHandlers?.settings?.postMessage({action,...data});}
function renderIconChoices(active, customIcon) {
  const choices = presetIcons.map(([id,label])=>({id,label,src:`Icons/${id}.png`}));
  if (customIcon) choices.push({id:'custom',label:'此前自定义',src:customIcon});
  $('presetIcons').innerHTML = choices.map(({id,label,src})=>{
    const button=`<button type="button" class="icon-choice ${active===id?'active':''}" data-icon="${id}" aria-label="使用${label}图标" aria-pressed="${active===id}"><img src="${src}" alt=""></button>`;
    return id==='custom'?`<div class="icon-custom">${button}<button type="button" class="icon-delete" id="deleteCustomIcon" aria-label="删除自定义图标">×</button></div>`:button;
  }).join('');
  $('presetIcons').querySelectorAll('.icon-choice').forEach(button=>button.onclick=()=>post(button.dataset.icon==='custom'?'selectCustomIcon':'selectIcon',{id:button.dataset.icon}));
  if ($('deleteCustomIcon')) $('deleteCustomIcon').onclick=()=>$('deleteIconDialog').showModal();
}
function select(section) {
  for(const [id,nav] of [['theme','navTheme'],['font','navFont'],['appearance','navAppearance'],['security','navSecurity']]) {
    $(id).classList.toggle('hidden',section!==id);$(nav).classList.toggle('active',section===id);
    $(nav).setAttribute('aria-current',section===id?'page':'false');
  }
  $('notice').textContent=''; $('notice').classList.remove('error');
}
for(const [id,nav] of [['theme','navTheme'],['font','navFont'],['appearance','navAppearance'],['security','navSecurity']])$(nav).onclick=()=>select(id);
$('closeSettings').onclick=()=>post('closeSettings');
window.resetSettingsForms=()=>{ $('passwordForm').reset();$('privateForm').reset();document.querySelectorAll('#settingsView dialog[open]').forEach(d=>d.close());$('notice').textContent=''; };
window.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('settingsView').hidden&&!document.querySelector('dialog[open]'))post('closeSettings');});
$('saveName').onclick=()=>post('saveName',{name:$('appName').value});
$('chooseIcon').onclick=()=>post('chooseIcon');
$('passwordForm').onsubmit=e=>{e.preventDefault();post('changePassword',{old:$('oldPassword').value,new:$('newPassword').value,confirm:$('confirmPassword').value});};
$('privateForm').onsubmit=e=>{e.preventDefault();post('createPrivate',{primary:$('primaryPassword').value,password:$('privatePassword').value,confirm:$('confirmPrivatePassword').value});};
$('dismissSuccess').onclick=()=>$('passwordUpdated').close();
$('restartLater').onclick=()=>$('restartDialog').close();
$('restartNow').onclick=()=>{ $('restartNow').disabled=true; post('restart'); };
$('cancelDeleteIcon').onclick=()=>$('deleteIconDialog').close();
$('confirmDeleteIcon').onclick=()=>{ $('deleteIconDialog').close(); post('deleteCustomIcon'); };
window.receiveSettings=function(data) {
  if (previousPasswordScope !== null && previousPasswordScope !== data.passwordScope) {
    $('passwordForm').reset(); $('privateForm').reset();
  }
  previousPasswordScope = data.passwordScope;
  $('passwordScope').textContent=data.passwordScope==='private'?'当前为独立书库；这里只修改独立书库的密码。':'当前修改普通加密书库的密码。我的书库无需密码。';
  $('privateSetup').classList.toggle('hidden',!data.canCreatePrivate);
  if (data.name) { $('brandName').textContent=data.name; if (document.activeElement!==$('appName')) $('appName').value=data.name; }
  if (data.icon) { $('brandIcon').src=data.icon; $('iconPreview').src=data.icon; }
  if (data.iconID) renderIconChoices(data.iconID,data.customIcon);
  if (data.message || data.error) {
    $('notice').textContent=data.error||data.message;
    $('notice').classList.toggle('error',!!data.error);
    if (data.message==='密码已更新。') { $('passwordForm').reset(); $('passwordUpdated').showModal(); }
    if (data.message==='独立书库已创建。锁定后输入新密码即可进入。') $('privateForm').reset();
  }
  if (data.restartPrompt) { $('restartNow').disabled=false; $('restartDialog').showModal(); }
}

window.showInlineSettings=()=>{
  document.getElementById('settingsView').hidden=false;document.body.style.overflow='hidden';document.getElementById('app').setAttribute('inert','');document.getElementById('closeSettings').focus();
};
window.hideInlineSettings=()=>{
  window.resetSettingsForms();document.getElementById('settingsView').hidden=true;document.body.style.overflow='';document.getElementById('app').removeAttribute('inert');document.getElementById('settings')?.focus();
};

})();
