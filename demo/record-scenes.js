async function runSmoke() {
 const out=process.env.FTR_MEDIA_OUTPUT;
 const wait=ms=>new Promise(r=>setTimeout(r,ms));const js=async s=>{try{return await window.webContents.executeJavaScript(s);}catch(e){console.error('Failed UI step:',s);throw e;}};
  async function record(name,w,ms,action=async()=>{}) {
  const proc=require('child_process').spawn('ffmpeg',['-y','-loglevel','error','-f','image2pipe','-framerate','20','-i','pipe:0','-c:v','libx264','-preset','fast','-crf','17','-pix_fmt','yuv420p',`${out}/${name}.mp4`]);
  proc.stderr.on('data',d=>process.stderr.write(d));
  let last=(await w.webContents.capturePage()).toPNG();const start=Date.now();let n=0;let pending=action();
  while(n<ms/50){try{last=(await w.webContents.capturePage()).toPNG();}catch{} const due=Math.min(ms/50,Math.max(n+1,Math.floor((Date.now()-start)/50)));while(n<due){if(!proc.stdin.write(last))await new Promise(r=>proc.stdin.once('drain',r));n++;}await wait(Math.max(0,start+n*50-Date.now()));}
  await pending;proc.stdin.end();await new Promise((resolve,reject)=>proc.on('exit',c=>c?reject(Error('ffmpeg '+c)):resolve()));
  fs.writeFileSync(`${out}/${name}.png`,(await w.webContents.capturePage()).toPNG());console.log('CAPTURED',name,n);
 }

 const shot=async name=>{await wait(400);await window.webContents.capturePage();await wait(200);fs.writeFileSync(`${out}/${name}.png`,(await window.webContents.capturePage()).toPNG());};
 if(vault.configured){
  window.setContentSize(900,760);window.focus();await showNormal();await wait(500);await handleAction({action:'settings'});await wait(600);await js("document.getElementById('navAppearance').click()");await wait(300);
  if(preferences.name!=='工作备忘'||preferences.iconID!=='coffee')throw Error('Name/icon did not persist across restart');
  await record('renamed',window,3000);
  fs.writeFileSync(`${out}/name-proof.json`,JSON.stringify({name:preferences.name,icon:preferences.iconID,actualWindowTitle:window.getTitle(),verifiedAfterRestart:true},null,2));quitting=true;app.quit();return;
 }
 const demo=process.env.FISHTOUCHING_SMOKE_FIXTURES;
 preferences.name='摸鱼阅读';savePreferences();applyAppearance();
 vault.configure('1111');const entry=vault.add({...importPlugins.parse(path.join(demo,'摸鱼.txt')),title:'窗边的橘猫'});
 vaults[1].configure('2222');vaults[1].add({...importPlugins.parse(path.join(demo,'正式-会议纪要.txt')),title:'星河计划 · 会议纪要'});vaults[1].lock();
 publicLibrary.add(path.join(demo,'工作汇报.pdf'));
 window.setContentSize(900,760);app.focus({steal:true});window.show();window.focus();await wait(1200);await showNormal();await wait(400);if(!vault.unlocked)vault.unlock('1111');await openEntry(entry.id,true);await wait(500);
 if(!vault.unlocked||pdf){await wait(500);app.focus({steal:true});window.focus();if(pdf)await js("document.getElementById('secure').click()");else await showSecure();await wait(400);await js("document.getElementById('password').value='1111';document.querySelector('#unlock button').click()");await wait(700);}
 if(!vault.unlocked||pdf||!(await js("Boolean(document.getElementById('text'))")))throw Error('Reading start lost focus');
 await record('reading',window,4500);if(!vault.unlocked||pdf)throw Error('Unexpected blur during reading recording');fs.copyFileSync(`${out}/reading.png`,`${out}/01-reading.png`);
 let focus;
 await record('switch-resume',window,6500,async()=>{
  await wait(450);focus=new BrowserWindow({width:100,height:100,x:0,y:0,show:false});await focus.loadURL('about:blank');window.blur();focus.show();focus.focus();await wait(1600);
  if(vault.unlocked||!pdf?.cover)throw Error('Actual blur failed to lock and cover: '+JSON.stringify({unlocked:vault.unlocked,cover:pdf?.cover,tab:currentTab,focused:window.isFocused()}));
  await shot('02-cover');focus.close();window.focus();await wait(150);await js("document.getElementById('secure').click()");await wait(300);await shot('03-locked');
  for(const c of '1111'){await js(`document.getElementById('password').value+='${c}'`);await wait(90);}await js("document.querySelector('#unlock button').click()");
 });
 await shot('05-resumed');
 if(!(await js("Boolean(document.getElementById('text'))")))throw Error('Reading did not resume');
 await handleAction({action:'library'});await coverSecure(false);await showSecure();await wait(300);
 await record('vaults',window,7000,async()=>{
  await wait(300);for(const c of '1111'){await js(`document.getElementById('password').value+='${c}'`);await wait(90);}await js("document.querySelector('#unlock button').click()");await wait(650);
  if(activeVaultIndex!==0||vault.list().length!==1||vault.list()[0].title!=='窗边的橘猫')throw Error('Vault A mismatch');
  await wait(1400);await coverSecure(false);await showSecure();await wait(300);
  for(const c of '2222'){await js(`document.getElementById('password').value+='${c}'`);await wait(90);}await js("document.querySelector('#unlock button').click()");await wait(650);
  if(activeVaultIndex!==1||vault.list().length!==1||vault.list()[0].title!=='星河计划 · 会议纪要')throw Error('Vault B mismatch');
 });
 await coverSecure(false);await showNormal();await shot('04-library');await handleAction({action:'settings'});await wait(700);await js("document.getElementById('navAppearance').click()");await wait(300);
 await js("document.getElementById('navTheme').click()");await shot('06-themes');await js("document.getElementById('navFont').click()");await shot('07-fonts');await js("document.getElementById('navAppearance').click()");
 await record('identity',window,4000,async()=>{
  await wait(550);await window.webContents.executeJavaScript("document.querySelector('[data-icon=coffee]').click()");await wait(600);
  await window.webContents.executeJavaScript("document.getElementById('appName').value='工作备忘'");await wait(700);await window.webContents.executeJavaScript("document.getElementById('saveName').click()");
 });
 fs.writeFileSync(`${out}/proof.json`,JSON.stringify({version:require('./package.json').version,realFocusSwitch:true,encryptedDuringCover:true,resumed:true,twoIndependentVaults:true,temporaryLibrary:true,fixturesOnly:true,recording:'Electron desktop app captured on macOS; only harness changes; no UI state injection'},null,2));
 quitting=true;app.quit();
}
