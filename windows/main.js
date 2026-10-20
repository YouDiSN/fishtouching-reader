'use strict';
const { app, BrowserWindow, ipcMain, dialog, globalShortcut, Menu, Tray, nativeImage, shell } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const smokeRoot = process.env.FISHTOUCHING_SMOKE_ROOT;
function traceSmoke(message) {
  if (!smokeRoot) return;
  try {
    fs.mkdirSync(smokeRoot, { recursive: true });
    fs.appendFileSync(path.join(smokeRoot, 'startup.log'), `${new Date().toISOString()} ${message}\n`);
  } catch {}
}
traceSmoke(`main loaded: ${process.execPath}; argv=${JSON.stringify(process.argv)}`);
process.on('uncaughtException', error => { traceSmoke(`uncaught: ${error.stack || error}`); process.exit(1); });
process.on('unhandledRejection', error => { traceSmoke(`rejection: ${error?.stack || error}`); process.exit(1); });
const { Vault, writeAtomic } = require('./vault');
const { PublicLibrary, paragraphs } = require('./library');
const { ImportPluginRegistry, validateManifest } = require('./import-plugins');
const { createUpdates } = require('./updates');

const DEFAULT_NAME = 'FishTouching Reader';
const MAX_VAULTS = 2;
const ICONS = new Set(['fish', 'book', 'night', 'leaf', 'coffee', 'star', 'pencil', 'music', 'sunrise', 'cloud']);
const assets = path.join(__dirname, 'assets');
let root, vault, vaults, publicLibrary, preferences, window, tray, importPlugins;
let activeVaultIndex = 0, resumeVaultIndex = 0, settingsVaultIndex = 0;
let currentTab = 'normal', currentId = null, resumeId = null, pdf = null;
let settingsVisible = false, settingsOpening = false;
let switching = false, dialogOpen = false, quitting = false;
let updates;
let updateMenuItems = [];
const smokeMode = Boolean(process.env.FISHTOUCHING_SMOKE_ROOT) || process.argv.includes('--smoke');
// Both ZIP and installed builds share one library and must not run together.
if (!smokeMode) {
  app.setPath('userData', path.join(app.getPath('appData'), 'FishTouching Reader'));
  if (!app.requestSingleInstanceLock()) app.exit(0);
  app.on('second-instance', () => { window?.show(); window?.focus(); });
}
let smokeStage = 'waiting for Electron';
if (smokeMode) {
  app.commandLine.appendSwitch('disable-gpu');
  setTimeout(() => { traceSmoke(`timed out: ${smokeStage}`); process.stderr.write(`Smoke timed out: ${smokeStage}\n`); process.exit(1); }, 60000).unref();
}

function secureParagraphs(data) {
  try { const book = JSON.parse(data.toString('utf8')); if (Array.isArray(book.paragraphs)) return book.paragraphs; }
  catch { /* Earlier TXT imports stored the original bytes. */ }
  return paragraphs(data);
}
function preferencePath() { return path.join(root, 'preferences.json'); }
function savePreferences() { writeAtomic(preferencePath(), JSON.stringify(preferences)); }
function iconPath(id = preferences.iconID) {
  if (id === 'custom') return path.join(root, 'appearance-icon.png');
  return path.join(assets, 'Icons', `${ICONS.has(id) ? id : 'fish'}.png`);
}
function applyAppearance() {
  const name = preferences.name || DEFAULT_NAME;
  if (window) { window.setTitle(name); window.setIcon(nativeImage.createFromPath(iconPath())); }
  if (tray) { tray.setToolTip(name); tray.setImage(nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 })); }
}
function send(data) { if (window && !window.isDestroyed() && !pdf) window.webContents.executeJavaScript(`receive(${JSON.stringify(data)})`).catch(() => {}); }
function sendSettings(extra = {}) {
  if (!window || window.isDestroyed()) return;
  const currentIcon = iconPath();
  const customIcon = iconPath('custom');
  const payload = { name: preferences.pendingName || preferences.name || DEFAULT_NAME,
    iconID: preferences.iconID || 'fish', icon: fs.existsSync(currentIcon) ? `data:image/png;base64,${fs.readFileSync(currentIcon).toString('base64')}` : '',
    hasCustomIcon: fs.existsSync(customIcon), customIcon: fs.existsSync(customIcon) ? `data:image/png;base64,${fs.readFileSync(customIcon).toString('base64')}` : undefined,
    passwordScope: settingsVaultIndex === 0 ? 'primary' : 'private',
    canCreatePrivate: settingsVaultIndex === 0, ...extra };
  window.webContents.executeJavaScript(`receiveSettings(${JSON.stringify(payload)})`).catch(() => {});
}
function error(message, context = currentTab === 'secure' ? 'library' : 'normal') { send({ type: 'error', context, message: String(message?.message || message) }); }
function normalState() {
  return { type: 'normal', pdfs: publicLibrary.list().map(e => ({ id: e.id, title: e.title, kind: e.kind,
    pageCount: e.kind === 'text' ? e.count : e.pageCount,
    pageIndex: e.progress?.position || 0, pageFraction: e.progress?.fraction || 0,
    updatedAt: (e.progress?.updatedAt || 0) / 1000, recentHidden: Boolean(e.progress?.recentHidden) })) };
}
function secureState() {
  return { type: 'library', books: vault.list().map(e => ({ id: e.id, title: e.title,
    host: e.sourceURL ? new URL(e.sourceURL).hostname : (e.kind === 'pdf' ? 'PDF' : '本地文件'),
    count: e.count, wordCount: e.wordCount, kind: e.kind, pageCount: e.pageCount,
    paragraph: e.progress?.position || 0, fraction: e.progress?.fraction || 0,
    updatedAt: (e.progress?.updatedAt || 0) / 1000, recentHidden: Boolean(e.progress?.recentHidden) })) };
}
async function loadReader(data) {
  if (!window.webContents.getURL().endsWith('/index.html')) {
    if (pdf) { pdf.data.fill(0); pdf = null; }
    await window.loadFile(path.join(assets, 'index.html'));
  }
  send(data);
}
async function showNormal() { currentTab = 'normal'; currentId = null; window.setContentProtection(false); await loadReader(normalState()); }
async function showSecure() { currentTab = 'secure'; currentId = null; window.setContentProtection(vault.unlocked); await loadReader(vault.unlocked ? secureState() : { type: 'locked' }); }
async function showText(entry, secure) {
  const data = secure ? vault.load(entry.id) : publicLibrary.load(entry);
  const book = secure ? (() => { try { return JSON.parse(data); } catch { return null; } })() : null;
  const parts = secure ? secureParagraphs(data) : paragraphs(data);
  currentTab = secure ? 'secure' : 'normal'; currentId = entry.id;
  if (secure) { resumeId = entry.id; resumeVaultIndex = activeVaultIndex; }
  await loadReader({ type: 'book', tab: currentTab, id: entry.id, encodedTitle: entry.title,
    paragraphs: parts, hasEPUB: Boolean(book?.epubArchive), paragraph: entry.progress?.position || 0, fraction: entry.progress?.fraction || 0 });
  if (secure) window.setContentProtection(true);
}
async function openPDF(entry, secure, cover = false) {
  const data = secure ? vault.load(entry.id) : publicLibrary.load(entry);
  if (pdf) pdf.data.fill(0);
  pdf = { entry, secure, cover, data };
  currentTab = secure ? 'secure' : 'normal';
  currentId = entry.id;
  if (secure) { resumeId = entry.id; resumeVaultIndex = activeVaultIndex; }
  window.setContentProtection(secure);
  await window.loadFile(path.join(assets, 'pdf.html'));
}
function updateProgress(id, position, fraction, secure = currentTab === 'secure') {
  if (!id || !Number.isFinite(position) || !Number.isFinite(fraction)) return;
  const value = { position: Math.max(0, Math.floor(position)), fraction: Math.max(0, Math.min(1, fraction)) };
  if (secure && vault.unlocked) vault.progress(id, value);
  else if (!secure) publicLibrary.update(id, { progress: { ...value, updatedAt: Date.now() } });
}
async function coverSecure(openCover = true) {
  if (switching || dialogOpen || currentTab !== 'secure') return;
  switching = true;
  try {
    if (!vault.unlocked) {
      currentId = null;
      await showNormal();
      return;
    }
    const previous = currentId;
    if (pdf?.secure) {
      window.webContents.send('pdf-clear');
      pdf.data.fill(0); pdf = null;
    } else if (!pdf) {
      const result = await Promise.race([
        window.webContents.executeJavaScript('prepareSecureLock()').catch(() => null),
        new Promise(resolve => setTimeout(() => resolve(null), 500))
      ]);
      if (result) updateProgress(previous, result.paragraph, result.fraction, true);
    }
    if (previous) { resumeId = previous; resumeVaultIndex = activeVaultIndex; }
    vault.lock(); currentTab = 'normal'; currentId = null;
    window.setContentProtection(false);
    const cover = openCover && previous ? publicLibrary.list().filter(e => e.kind === 'pdf').sort((a, b) => b.importedAt - a.importedAt)[0] : null;
    if (cover) await openPDF(cover, false, true);
    else await showNormal();
  } catch (e) { await showNormal(); error(e); }
  finally { switching = false; }
}
async function openEntry(id, secure) {
  const entry = secure ? vault.list().find(e => e.id === id) : publicLibrary.list().find(e => e.id === id);
  if (!entry) throw new Error('找不到这本书。');
  if (entry.kind === 'pdf') await openPDF(entry, secure);
  else await showText(entry, secure);
}
function sendImportPlugins(extra = {}) {
  let payload;
  try { payload = { plugins: importPlugins.views(), ...extra }; }
  catch (error) { payload = { error: '无法读取插件配置：' + error.message }; }
  if (window && !window.isDestroyed() && !pdf) window.webContents.executeJavaScript(`receiveImportPlugins(${JSON.stringify(payload)})`).catch(() => {});
}
let webJob = null, webPreview = null;
function cancelWebImport() { webJob?.abort(); webJob=null; webPreview=null; }
function sendWeb(payload) { if(window && !window.isDestroyed() && !pdf) window.webContents.executeJavaScript(`receiveWebImport(${JSON.stringify(payload)})`).catch(()=>{}); }
async function confirmPlugin(plugin, source) {
  dialogOpen=true;
  try {
    const permission=plugin.parser==='website' ? `仅访问 ${require("./web-import").rules.hosts(plugin.adapter)}；番茄另需访问 lf6-awef.bytetos.com 校验字体。Fake-IP 时使用 Cloudflare 加密 DNS，仅发送域名。不执行网页脚本。` : '仅读取选择的本地文本文件。';
    const answer=await dialog.showMessageBox(window,{type:'question',message:`安装社区插件“${plugin.name}”？`,detail:`来源：${source}\n作者：${plugin.author}（未经认证）\n版本：${plugin.version}\n权限：${permission}\n同标识插件将更新；安装后默认停用。`,buttons:['安装','取消'],defaultId:1,cancelId:1});
    if(answer.response===0){importPlugins.install(plugin);sendImportPlugins({message:'社区插件已安装，请启用后使用。'});}
  } finally {dialogOpen=false;}
}
async function installWebPlugin(data) {
  const {fetchPublic,packageManifest}=require('./web-import');
  cancelWebImport();const job=new AbortController();webJob=job;
  try {
    const p=data.recommended ? require('./assets/community-plugins.json').find(p=>p.id===data.recommended) : packageManifest(await fetchPublic(data.url,job.signal,262144));
    if(webJob!==job)return;if(!p)throw Error('插件不存在。');webJob=null;await confirmPlugin(p,data.recommended?'随附实验性社区规则（非网站官方）':data.url);
  } catch(e){if(webJob===job){webJob=null;sendImportPlugins({error:e.message});}}
}
async function previewWebsite(data) {
  cancelWebImport();if(currentTab!=='normal'&&!vault.unlocked)return;
  const job=new AbortController();webJob=job;
  try {
    const p=importPlugins.website(data.id),{rules,fetchPublic}=require('./web-import');rules.checkURL(p.adapter,data.url,'book');
    const html=await fetchPublic(data.url,job.signal);if(webJob!==job)return;
    const catalogURL=rules.catalogRequest(p.adapter,data.url);
    const catalogJSON=catalogURL ? (await fetchPublic(catalogURL,job.signal)).toString('utf8') : '';if(webJob!==job)return;
    webPreview={...rules.catalog(p.adapter,data.url,html.toString('utf8'),catalogJSON),pluginID:p.id,source:data.url};webJob=null;sendWeb({preview:webPreview});
  }catch(e){if(webJob===job){webJob=null;sendWeb({error:e.message});}}
}
async function importWebsite(data) {
  if(webJob||!webPreview||(currentTab!=='normal'&&!vault.unlocked))return;
  const preview=webPreview,secure=currentTab==='secure',target=vault,job=new AbortController();webJob=job;webPreview=null;
  try {
    const p=importPlugins.website(preview.pluginID),{rules,fetchPublic}=require('./web-import'),{start,end}=data;
    if(!Number.isInteger(start)||!Number.isInteger(end)||start<1||end<start||end>preview.chapters.length||end-start>=100)throw Error('每次请选择有效的 1–100 章范围。');
    const chapters=preview.chapters.slice(start-1,end),parts=[],fontDigests=new Map();let size=0;
    for(let i=0;i<chapters.length;i++) {
      if(i)await require('node:timers/promises').setTimeout(1000,undefined,{signal:job.signal});job.signal.throwIfAborted();
      const c=chapters[i];rules.checkURL(p.adapter,c.url,'chapter');const body=await fetchPublic(c.url,job.signal);size+=body.length;
      if(size>16*1024*1024)throw Error('本次导入超过 16 MB 限制。');
      const html=body.toString('utf8'),fontURL=rules.fontRequest(p.adapter,html);
      if(fontURL&&!fontDigests.has(fontURL))fontDigests.set(fontURL,require('node:crypto').createHash('sha256').update(await fetchPublic(fontURL,job.signal,524288)).digest('hex'));
      parts.push(c.title,...rules.chapter(p.adapter,html,fontDigests.get(fontURL)));if(webJob===job)sendWeb({message:`已验证 ${i+1}/${chapters.length} 章…`});
    }
    if(webJob!==job)return;
    if((currentTab==='secure')!==secure || secure&&(vault!==target||!vault.unlocked))throw Error('目标书库已切换或锁定。');
    importPlugins.website(p.id);const title=`${preview.title}（目录第${start}–${end}项）`;
    if(secure){const buffer=Buffer.from(JSON.stringify({paragraphs:parts}));try{vault.add({title,kind:'text',paragraphs:parts,data:buffer});}finally{buffer.fill(0);}}
    else publicLibrary.addText(title,parts);
    webJob=null;send(secure?secureState():normalState());
  }catch(e){if(webJob===job){webJob=null;sendWeb({error:'未保存本次导入：'+e.message});}}
}

async function installImportPlugin() {
  dialogOpen=true;
  try {
    const selection=await dialog.showOpenDialog(window,{properties:['openFile'],filters:[{name:'社区插件',extensions:['json','zip']}]});
    if(selection.canceled)return;const file=selection.filePaths[0];
    if(fs.statSync(file).size>262144)throw Error('插件包不能超过 256 KB。');
    const p=require('./web-import').packageManifest(fs.readFileSync(file));await confirmPlugin(p,path.basename(file));
  }catch(e){sendImportPlugins({error:e.message});}finally{dialogOpen=false;}
}
async function removeImportPlugin(id) {
  dialogOpen = true;
  try {
    const decision = await dialog.showMessageBox(window, { type: 'question', message: '移除这个社区插件？', detail: '已导入的书籍和阅读进度会保留。', buttons: ['移除', '取消'], defaultId: 1, cancelId: 1 });
    if (decision.response === 0) { importPlugins.remove(id); sendImportPlugins({ message: '插件已移除，书籍保持不变。' }); }
  } catch (error) { sendImportPlugins({ error: error.message }); }
  finally { dialogOpen = false; }
}
async function importLocal() {
  dialogOpen = true;
  let imported = 0;
  const secure = currentTab === 'secure', targetVault = vault;
  try {
    const extensions = importPlugins.enabledExtensions();
    if (!extensions.length) throw new Error('没有已启用的导入插件，请先在“导入插件”中启用。');
    const selection = await dialog.showOpenDialog(window, { properties: ['openFile', 'multiSelections'], filters: [{ name: '已启用插件支持的书籍', extensions }] });
    if (selection.canceled) return;
    if ((currentTab === 'secure') !== secure || (secure && (vault !== targetVault || !vault.unlocked))) throw new Error('目标书库已切换或锁定，请重新导入。');
    for (const file of selection.filePaths) {
      const content = importPlugins.parse(file);
      try {
        if (secure) vault.add(content);
        else if (content.kind === 'pdf') publicLibrary.addPDF(content.title, content.data);
        else publicLibrary.addText(content.title, content.paragraphs);
        imported++;
      } finally { content.data.fill(0); }
    }
    send(secure ? secureState() : normalState());
  } catch (failure) {
    send(secure ? secureState() : normalState());
    error(`已导入 ${imported} 个文件。${failure.message}`, secure ? 'library' : 'normal');
  } finally { dialogOpen = false; }
}
async function chooseIcon() {
  dialogOpen = true;
  try {
    const selection = await dialog.showOpenDialog(window, { properties: ['openFile'], filters: [{ name: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp'] }] });
    if (selection.canceled) return;
    const image = nativeImage.createFromPath(selection.filePaths[0]);
    if (image.isEmpty()) throw new Error('无法读取这张图片。');
    writeAtomic(iconPath('custom'), image.toPNG());
    preferences.iconID = 'custom'; savePreferences(); applyAppearance();
    sendSettings({ message: '任务栏图标已更新。' });
    if (!settingsVisible) window.webContents.executeJavaScript("selectSetupIcon('custom')").catch(() => {});
  } finally { dialogOpen = false; }
}
async function handleReadingAppearance(data, target) {
  if (!['readingPreferences','saveReadingPreferences','listSystemFonts'].includes(data?.action)) return false;
  const deliver=(view, fn, payload)=>{if(view&&!view.isDestroyed())view.webContents.executeJavaScript(`window.${fn}?.(${JSON.stringify(payload)})`).catch(()=>{});};
  if(data.action==='listSystemFonts') {
    try { deliver(target,'receiveSystemFonts',{fonts:await require('./reading-appearance').systemFonts()}); }
    catch(e) { deliver(target,'receiveSystemFonts',{error:e.message}); }
    return true;
  }
  if(data.action==='readingPreferences' && preferences.readerFontSize===undefined && Number.isInteger(data.legacyFontSize) && data.legacyFontSize>=15 && data.legacyFontSize<=30){preferences.readerFontSize=data.legacyFontSize;savePreferences();}
  if(data.action==='saveReadingPreferences') {
    if(Number.isInteger(data.fontSize)&&data.fontSize>=15&&data.fontSize<=30)preferences.readerFontSize=data.fontSize;
    if(['forest','paper','light','midnight','graphite'].includes(data.theme))preferences.readerTheme=data.theme;
    if(typeof data.font==='string') {
      if(!data.font) preferences.readerFont='';
      else { try { if((await require('./reading-appearance').systemFonts()).includes(data.font))preferences.readerFont=data.font; } catch(e) { deliver(target,'receiveSystemFonts',{error:e.message}); } }
    }
    savePreferences();
  }
  const payload={theme:preferences.readerTheme||'forest',font:preferences.readerFont||'',fontSize:preferences.readerFontSize||19};
  deliver(target,'receiveReadingPreferences',payload);
  return true;
}
async function handleAction(data) {
  if(await handleReadingAppearance(data, window))return;
  const action = data?.action;
  if(["selectNormal","selectSecure","unlock","lock","settings","read","library","toggleImportPlugin","removeImportPlugin"].includes(action))cancelWebImport();
  try {
    switch (action) {
      case 'installWebPlugin': await installWebPlugin(data); break;
      case 'previewWebsite': await previewWebsite(data); break;
      case 'importWebsite': await importWebsite(data); break;
      case 'cancelWebImport': cancelWebImport(); break;
      case 'retry': send(currentTab === 'secure' ? (vault.unlocked ? secureState() : { type: 'locked' }) : normalState()); break;
      case 'selectNormal': if (currentTab === 'secure' && vault.unlocked) await coverSecure(false); else await showNormal(); break;
      case 'selectSecure': await showSecure(); break;
      case 'setup': {
        if (data.password !== data.confirm) { send({ type: 'setup', error: '两次输入的密码不一致。' }); break; }
        vault.configure(data.password || '');
        preferences.name = String(data.name || '').trim().slice(0, 40) || DEFAULT_NAME;
        savePreferences(); applyAppearance(); await showNormal(); break;
      }
      case 'unlock': {
        try {
          const password = data.password || '';
          vaults.forEach(v => v.lock());
          const index = vaults.findIndex(v => v.matchesPassword(password));
          if (index < 0) throw new Error('密码不正确。');
          activeVaultIndex = index; vault = vaults[index];
          vault.unlock(password);
          if (resumeId && resumeVaultIndex === activeVaultIndex && vault.list().some(e => e.id === resumeId)) await openEntry(resumeId, true);
          else { resumeId = null; await showSecure(); }
        }
        catch (e) { send({ type: 'locked', error: e.message }); }
        break;
      }
      case 'lock': if (currentTab === 'secure') { await coverSecure(); await showSecure(); } break;
      case 'library': if (currentTab === 'secure') { resumeId = null; currentId = null; send(secureState()); } else await showNormal(); break;
      case 'read': if (currentTab === 'secure' && vault.unlocked) await openEntry(data.id, true); else if (currentTab === 'normal') await openEntry(data.id, false); break;
      case 'exportText': {
        if (currentTab !== 'secure' || !vault.unlocked || currentId !== data.id) break;
        const entry = vault.list().find(e => e.id === data.id && e.kind === 'text');
        if (!entry) break;
        const name = entry.title.replace(/[\\/:*?"<>|\r\n]/g, '-');
        dialogOpen = true;
        try {
          const result = await dialog.showSaveDialog(window, { defaultPath: path.join(app.getPath('downloads'), `${name}.txt`), filters: [{ name: 'TXT', extensions: ['txt'] }] });
          if (!result.canceled && result.filePath) {
            const data = vault.load(entry.id);
            try {
              fs.writeFileSync(result.filePath, secureParagraphs(data).join('\n\n'), { encoding: 'utf8', mode: 0o600 });
            } finally { data.fill(0); }
          }
        } finally { dialogOpen = false; }
        break;
      }
      case 'exportEPUB': {
        if (currentTab !== 'secure' || !vault.unlocked || currentId !== data.id) break;
        const entry = vault.list().find(e => e.id === data.id && e.kind === 'text');
        if (!entry) break;
        const book = JSON.parse(vault.load(entry.id).toString('utf8'));
        if (!book.epubArchive) break;
        const name = entry.title.replace(/[\\/:*?"<>|\r\n]/g, '-');
        dialogOpen = true;
        try {
          const result = await dialog.showSaveDialog(window, { defaultPath: path.join(app.getPath('downloads'), `${name}.epub`), filters: [{ name: 'EPUB', extensions: ['epub'] }] });
          if (!result.canceled && result.filePath) fs.writeFileSync(result.filePath, Buffer.from(book.epubArchive, 'base64'), { mode: 0o600 });
        } finally { dialogOpen = false; }
        break;
      }
      case 'openPDF': if (currentTab === 'normal') await openEntry(data.id, false); break;
      case 'listImportPlugins': sendImportPlugins(); break;
      case 'installImportPlugin': await installImportPlugin(); break;
      case 'removeImportPlugin': await removeImportPlugin(data.id); break;
      case 'toggleImportPlugin':
        try { importPlugins.setEnabled(data.id, data.enabled === true); sendImportPlugins(); }
        catch (error) { sendImportPlugins({ error: error.message }); }
        break;
      case 'importLocal': case 'importPDF': await importLocal(); break;
      case 'removeBook': {
        if (currentTab === 'secure') { if (!vault.unlocked) return; vault.remove(data.id); if (resumeId === data.id) resumeId = null; send(secureState()); }
        else { publicLibrary.remove(data.id); send(normalState()); }
        break;
      }
      case 'removeRecent': {
        if (currentTab === 'secure') { if (!vault.unlocked) return; vault.hideFromRecent(data.id); send(secureState()); }
        else { publicLibrary.hideFromRecent(data.id); send(normalState()); }
        break;
      }
      case 'transferBook': {
        if (currentTab !== 'secure' || !vault.unlocked) break;
        const target = vaults.find((v, index) => index !== activeVaultIndex && v.matchesPassword(data.password || ''));
        if (!target) throw new Error('另一书库密码不正确，或书库尚未创建。');
        target.unlock(data.password || '');
        try {
          vault.transfer(data.id, target);
          if (resumeId === data.id) resumeId = null;
          if (currentId === data.id) currentId = null;
          send(secureState());
        } finally { target.lock(); }
        break;
      }
      case 'progress': if (!pdf) updateProgress(currentId, data.paragraph, data.fraction); break;
      case 'selectIcon': if (ICONS.has(data.id)) { preferences.iconID = data.id; savePreferences(); applyAppearance();
        window.webContents.executeJavaScript(`selectSetupIcon(${JSON.stringify(data.id)})`).catch(() => {}); } break;
      case 'chooseIcon': await chooseIcon(); break;
      case 'settings': await showSettings(); break;
      case 'hide': await coverSecure(); window.hide(); break;
    }
  } catch (e) { error(e, action === 'setup' ? 'setup' : undefined); }
}
async function showSettings() {
  if(settingsVisible||settingsOpening)return;
  settingsOpening=true;
  try {
  settingsVaultIndex=currentTab==='secure'&&vault.unlocked?activeVaultIndex:0;
  if(!pdf)await window.webContents.executeJavaScript("window.flushProgress?.()").catch(()=>{});
  await coverSecure(false); await showNormal();
  settingsVisible=true;
  await window.webContents.executeJavaScript('showInlineSettings()');sendSettings();
  } finally {settingsOpening=false;}
}
function closeSettings() {
  settingsVisible=false;settingsVaultIndex=0;
  window.webContents.executeJavaScript('hideInlineSettings()').catch(()=>{});
}
async function settingsAction(data) {
  if(await handleReadingAppearance(data, window))return;
  try {
    switch (data?.action) {
      case 'ready': sendSettings(); break;
      case 'closeSettings': closeSettings(); break;
      case 'chooseIcon': await chooseIcon(); break;
      case 'selectIcon': if (ICONS.has(data.id)) { preferences.iconID = data.id; savePreferences(); applyAppearance(); sendSettings({ message: '任务栏图标已更新。' }); } break;
      case 'selectCustomIcon': if (fs.existsSync(iconPath('custom'))) { preferences.iconID = 'custom'; savePreferences(); applyAppearance(); sendSettings({ message: '任务栏图标已更新。' }); } break;
      case 'deleteCustomIcon': {
        const file = iconPath('custom'); if (fs.existsSync(file)) fs.unlinkSync(file);
        if (preferences.iconID === 'custom') preferences.iconID = 'fish';
        savePreferences(); applyAppearance(); sendSettings({ message: '自定义图标已删除。' }); break;
      }
      case 'saveName': preferences.pendingName = String(data.name || '').trim().replace(/[\\/\r\n]/g, ' ').slice(0, 40) || DEFAULT_NAME;
        savePreferences(); sendSettings({ restartPrompt: true }); break;
      case 'restart': app.relaunch(); quitting = true; app.quit(); break;
      case 'changePassword': {
        if (data.new !== data.confirm) throw new Error('两次输入的新密码不一致。');
        if (vaults.some((v, i) => i !== settingsVaultIndex && v.matchesPassword(data.new || '')))
          throw new Error('不同书库不能使用相同密码。');
        const target = vaults[settingsVaultIndex], wasLocked = !target.unlocked;
        try { target.changePassword(data.old || '', data.new || ''); }
        finally { if (wasLocked) target.lock(); }
        sendSettings({ message: '密码已更新。' }); break;
      }
      case 'createPrivate': {
        if (settingsVaultIndex !== 0) throw new Error('请从普通加密书库创建独立书库。');
        const target = vaults.find((v, i) => i > 0 && !v.configured);
        if (!target) throw new Error('书库已达到数量上限。');
        if (data.password !== data.confirm) throw new Error('两次输入的新密码不一致。');
        if (!vaults[0].matchesPassword(data.primary || '')) throw new Error('当前书库密码不正确。');
        if (vaults.some(v => v.matchesPassword(data.password || ''))) throw new Error('不同书库不能使用相同密码。');
        target.configure(data.password || ''); target.lock();
        sendSettings({ message: '独立书库已创建。锁定后输入新密码即可进入。' }); break;
      }
    }
  } catch (e) { sendSettings({ error: e.message }); }
}
function toggleWindow() {
  if (window.isVisible()) { coverSecure().finally(() => window.hide()); }
  else { window.show(); window.focus(); }
}
async function prepareUpdateInstall() {
  // Read the current position before quitting, including debounced scrolls.
  if (window && !window.isDestroyed() && !settingsVisible) {
    if (pdf && !pdf.cover) {
      const position = await window.webContents.executeJavaScript('({position: pageIndex, fraction: fraction()})');
      updateProgress(pdf.entry.id, position.position, position.fraction, pdf.secure);
    } else if (!pdf && currentId) {
      const position = await window.webContents.executeJavaScript('currentProgress()');
      if (position) updateProgress(currentId, position.paragraph, position.fraction);
    }
  }
  savePreferences();
  vaults.forEach(v => v.lock());
  quitting = true; // Otherwise the close handler hides the window and blocks install.
}
function createWindow() {
  window = new BrowserWindow({ width: 940, height: 740, minWidth: 680, minHeight: 520,
    title: preferences.name, icon: iconPath(), backgroundColor: '#101716', autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), nodeIntegration: false, contextIsolation: true, sandbox: true } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.on('blur',()=>{cancelWebImport();sendWeb({error:'窗口失焦，任务已取消，请重新预览。',reset:true});});
  window.webContents.on('did-finish-load', () => { if (!pdf) send(!vault.configured ? { type: 'setup', iconID: preferences.iconID } : currentTab === 'secure' ? (vault.unlocked ? secureState() : { type: 'locked' }) : normalState()); });
  window.on('blur', () => { window.webContents.executeJavaScript('window.resetSettingsForms?.()').catch(()=>{});if(settingsVisible&&settingsVaultIndex>0)closeSettings();coverSecure(); });
  window.on('close', event => { if (!quitting) { event.preventDefault(); coverSecure().finally(() => window.hide()); } });
  const loaded = window.loadFile(path.join(assets, 'index.html'));
  const installed = process.platform === 'win32' && app.isPackaged && fs.existsSync(path.join(process.resourcesPath, 'app-update.yml'));
  updates = createUpdates({
    updater: installed ? require('electron-updater').autoUpdater : null,
    installed, version: app.getVersion(), openExternal: url => shell.openExternal(url),
    ask: async options => {
      // Cover encrypted content before an update dialog takes focus.
      await coverSecure(false);
      dialogOpen = true;
      try { return await dialog.showMessageBox(window, options); }
      finally { dialogOpen = false; }
    },
    prepareInstall: prepareUpdateInstall,
    cancelInstall: () => { quitting = false; },
    setProgress: value => window.setProgressBar(value),
    changed: () => updateMenuItems.forEach(item => { item.label = updates.label; item.enabled = updates.enabled; })
  });
  const updateItem = () => ({ id: 'check-update', label: '检查更新…', click: () => updates.check() });
  const menu = Menu.buildFromTemplate([{ label: '文件', submenu: [
    { label: '设置', accelerator: 'CommandOrControl+,', click: () => {showSettings().catch(error);} },
    { label: '显示／隐藏', accelerator: 'Control+Alt+H', click: toggleWindow },
    updateItem(),
    { type: 'separator' }, { label: '退出', click: () => { quitting = true; app.quit(); } }
  ] }]);
  Menu.setApplicationMenu(menu);
  tray = new Tray(nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 }));
  tray.setToolTip(preferences.name);
  const trayMenu = Menu.buildFromTemplate([
    { label: '显示／隐藏    Ctrl+Alt+H', click: toggleWindow },
    { label: '设置    Ctrl+,', click: () => {showSettings().catch(error);} },
    updateItem(),
    { type: 'separator' }, { label: '退出', click: () => { quitting = true; app.quit(); } }
  ]);
  tray.setContextMenu(trayMenu);
  updateMenuItems = [menu.getMenuItemById('check-update'), trayMenu.getMenuItemById('check-update')];
  globalShortcut.register('Control+Alt+H', toggleWindow);
  return loaded;
}
async function runSmoke() {
  smokeStage = 'configure vault'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  const demo = process.env.FISHTOUCHING_SMOKE_FIXTURES
    ? path.resolve(process.env.FISHTOUCHING_SMOKE_FIXTURES)
    : path.resolve(__dirname, '../demo/fixtures');
  vault.configure('test4321');
  publicLibrary.add(path.join(demo, '工作汇报.pdf'));
  smokeStage = 'verify import plugin manager'; traceSmoke(smokeStage);
  await showNormal();
  await window.webContents.executeJavaScript("document.getElementById('manageImportPlugins').click()");
  for (let i = 0; i < 40; i++) {
    const count = await window.webContents.executeJavaScript("document.querySelectorAll('.plugin-entry').length");
    if (count === 3) break;
    if (i === 39) throw new Error('Official import plugins did not render.');
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  await handleAction({ action: 'toggleImportPlugin', id: 'official.txt', enabled: false });
  if (importPlugins.enabledExtensions().includes('txt')) throw new Error('Plugin disable did not persist.');
  await handleAction({ action: 'toggleImportPlugin', id: 'official.txt', enabled: true });
  if (!importPlugins.parse(path.join(demo, '摸鱼.txt')).paragraphs.length) throw new Error('Official TXT plugin did not parse.');
  await window.webContents.executeJavaScript("document.getElementById('closePlugins').click()");
  const body = fs.readFileSync(path.join(demo, '摸鱼.txt'));
  const smokeParagraphs = Array.from({length:80},()=>paragraphs(body)).flat();
  const entry = vault.add({ title: '窗边的橘猫', kind: 'text', data: Buffer.from(JSON.stringify({ paragraphs: smokeParagraphs })), paragraphs: smokeParagraphs });
  smokeStage = 'render secure TXT'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  await openEntry(entry.id, true);
  const reading = await window.webContents.executeJavaScript("document.getElementById('text')?.textContent.includes('橘猫')");
  if (!reading) throw new Error('Secure reader did not render.');
  smokeStage = 'reading themes and system fonts'; traceSmoke(smokeStage);
  await window.webContents.executeJavaScript('showChunk(0,20,0.25)');
  await window.webContents.executeJavaScript('document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
  const beforeAppearance = await window.webContents.executeJavaScript('currentProgress()');
  await handleReadingAppearance({action:'saveReadingPreferences',theme:'paper'},window);
  await window.webContents.executeJavaScript('document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
  const appearance = await window.webContents.executeJavaScript('({theme:document.documentElement.dataset.readerTheme,position:currentProgress()})');
  if(appearance.theme!=='paper'||appearance.position.paragraph!==beforeAppearance.paragraph||Math.abs(appearance.position.fraction-beforeAppearance.fraction)>.03)throw new Error('Theme changed reading position: '+JSON.stringify({beforeAppearance,appearance}));
  await handleReadingAppearance({action:'saveReadingPreferences',fontSize:24},window);
  await window.webContents.executeJavaScript('document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
  const sized=await window.webContents.executeJavaScript('({size:getComputedStyle(document.getElementById("text")).fontSize,position:currentProgress()})');
  if(sized.size!=='24px'||sized.position.paragraph!==beforeAppearance.paragraph||Math.abs(sized.position.fraction-beforeAppearance.fraction)>.05)throw new Error('Font size or reading position was not preserved.');
  if(process.platform==='win32') {
    const fonts=await require('./reading-appearance').systemFonts();
    if(!fonts.length)throw new Error('System font list is empty.');
    const font=fonts.find(name=>name==='Arial')||fonts[0];
    await handleReadingAppearance({action:'saveReadingPreferences',font},window);
    await window.webContents.executeJavaScript('document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
    const fontPosition=await window.webContents.executeJavaScript('currentProgress()');
    if(preferences.readerFont!==font||fontPosition.paragraph!==beforeAppearance.paragraph||Math.abs(fontPosition.fraction-beforeAppearance.fraction)>.05)throw new Error('Font preference or reading position was not preserved.');
  }
  const savedAppearance=JSON.parse(fs.readFileSync(preferencePath(),'utf8'));
  if(savedAppearance.readerTheme!=='paper')throw new Error('Theme was not persisted.');
  smokeStage = 'switch to cover PDF'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  await coverSecure();
  if (vault.unlocked || currentTab !== 'normal' || !pdf?.cover) throw new Error('Focus cover did not lock and open the PDF.');
  for (let i = 0; i < 40; i++) {
    const loaded = await window.webContents.executeJavaScript("document.getElementById('page')?.textContent").catch(() => '');
    if (loaded?.includes('1 /')) break;
    if (i === 39) throw new Error('PDF viewer did not render.');
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  smokeStage = 'unlock and resume'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  await showSecure();
  await coverSecure(false);
  const ordinary = await window.webContents.executeJavaScript("document.querySelector('h1')?.textContent");
  if (currentTab !== 'normal' || ordinary !== '我的书库') throw new Error('Locked secure tab stayed visible after focus loss.');
  await showSecure();
  vault.unlock('test4321');
  await openEntry(resumeId, true);
  const resumed = await window.webContents.executeJavaScript("document.getElementById('text')?.textContent.includes('橘猫')");
  if (!resumed) throw new Error('Secure reader did not resume.');
  smokeStage = 'switch from secure library'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  await showSecure();
  await coverSecure();
  const library = await window.webContents.executeJavaScript("document.querySelector('h1')?.textContent");
  if (currentTab !== 'normal' || pdf || library !== '我的书库') throw new Error('Secure library did not switch to the ordinary library.');
  smokeStage = 'route independent vault passwords'; traceSmoke(smokeStage); process.stdout.write(`${smokeStage}\n`);
  if (vaults.length !== MAX_VAULTS) throw new Error('Vault limit mismatch.');
  vaults[1].configure('second-space-pass');
  vaults[1].add({ title: '另一份虚构短篇', kind: 'text', data: Buffer.from(JSON.stringify({ paragraphs: ['另一份虚构短篇'] })), paragraphs: ['另一份虚构短篇'] });
  vaults[1].lock();
  await showSecure();
  await handleAction({ action: 'unlock', password: 'second-space-pass' });
  if (activeVaultIndex !== 1 || vault.list().map(e => e.title).join() !== '另一份虚构短篇') throw new Error('Second vault leaked primary catalog.');
  await coverSecure(false); await showSecure();
  await handleAction({ action: 'unlock', password: 'test4321' });
  if (activeVaultIndex !== 0 || vault.list().map(e => e.title).join() !== '窗边的橘猫') throw new Error('Primary vault leaked second catalog.');
  await openEntry(entry.id,true);
  smokeStage='single-page settings navigation and synchronization';traceSmoke(smokeStage);
  await showSettings();
  const singlePage=await window.webContents.executeJavaScript('document.querySelectorAll("iframe").length===0&&!document.getElementById("settingsView").hidden');
  if(!singlePage||BrowserWindow.getAllWindows().length!==1||vault.unlocked)throw Error('Settings did not stay in one document or vault stayed unlocked');
  await window.webContents.executeJavaScript(`(()=>{document.getElementById('settingsView').__reuseMarker=1;document.querySelector('#settingsView [data-theme="light"]').click();document.getElementById('navFont').click();const size=document.querySelector('#settingsView [data-size]');size.value='22';size.dispatchEvent(new Event('change',{bubbles:true}));})()`);
  for(let i=0;i<40&&(preferences.readerTheme!=='light'||preferences.readerFontSize!==22);i++)await new Promise(resolve=>setTimeout(resolve,100));
  if(preferences.readerTheme!=='light'||preferences.readerFontSize!==22)throw Error('Settings did not save preferences');
  closeSettings();await showSettings();
  const reused=await window.webContents.executeJavaScript('document.getElementById("settingsView").__reuseMarker===1');
  if(!reused)throw Error('Settings view was recreated');closeSettings();
  await showSecure();await handleAction({action:'unlock',password:'second-space-pass'});await showSettings();
  if(settingsVaultIndex!==1||vault.unlocked)throw Error('Independent settings scope or lock failed');
  await window.webContents.executeJavaScript('document.getElementById("oldPassword").value="temporary-smoke-input"');
  window.emit('blur');await new Promise(resolve=>setTimeout(resolve,150));
  const cleared=await window.webContents.executeJavaScript('document.getElementById("settingsView").hidden&&document.getElementById("oldPassword").value===""');
  if(settingsVisible||!cleared)throw Error('Settings focus loss retained private form');
  fs.writeFileSync(path.join(root, 'smoke-ok.txt'), 'read, cover PDF, lock, resume');
  process.stdout.write('Windows app smoke passed: read, cover PDF, lock, resume, independent vaults.\n');
  process.exit(0);
}
app.whenReady().then(async () => {
  smokeStage = 'create window'; traceSmoke(smokeStage);
  app.setAppUserModelId('com.youdisn.fishtouching-reader');
  root = smokeMode && process.env.FISHTOUCHING_SMOKE_ROOT
    ? path.resolve(process.env.FISHTOUCHING_SMOKE_ROOT)
    : path.join(app.getPath('appData'), 'FishTouching Reader');
  if (smokeMode) app.setPath('userData', root);
  fs.mkdirSync(root, { recursive: true });
  preferences = fs.existsSync(preferencePath()) ? JSON.parse(fs.readFileSync(preferencePath(), 'utf8')) : { name: DEFAULT_NAME, iconID: 'fish' };
  if (preferences.pendingName) { preferences.name = preferences.pendingName; delete preferences.pendingName; savePreferences(); }
  vaults = [new Vault(path.join(root, 'vault')),
    ...Array.from({ length: MAX_VAULTS - 1 }, (_, i) => new Vault(path.join(root, 'vault-spaces', String(i + 2))))];
  vault = vaults[0];
  publicLibrary = new PublicLibrary(path.join(root, 'public'));
  importPlugins = new ImportPluginRegistry(path.join(root, 'import-plugins'));
  ipcMain.on('app-action', (event, data) => { if (event.sender === window?.webContents) handleAction(data); });
  ipcMain.on('settings-action', (event, data) => { if (event.sender === window?.webContents) settingsAction(data); });
  ipcMain.on('pdf-ready', event => { if (event.sender === window?.webContents && pdf) {
    window.webContents.send('pdf-document', { title: pdf.entry.title, data: pdf.data,
      position: pdf.entry.progress?.position || 0, fraction: pdf.entry.progress?.fraction || 0, secure: pdf.secure });
  } });
  ipcMain.on('pdf-progress', (event, data) => { if (event.sender === window?.webContents && pdf && !pdf.cover)
    updateProgress(pdf.entry.id, data.position, data.fraction, pdf.secure); });
  ipcMain.on('pdf-count', (event, count) => { if (event.sender !== window?.webContents || !pdf || !Number.isSafeInteger(count) || count < 1) return;
    pdf.entry.pageCount = count;
    if (pdf.secure) vault.update(pdf.entry.id, { pageCount: count });
    else publicLibrary.update(pdf.entry.id, { pageCount: count });
  });
  ipcMain.on('pdf-back', async event => { if (event.sender !== window?.webContents || !pdf) return;
    const secure = pdf.secure; pdf.data.fill(0); pdf = null;
    if (secure) await showSecure(); else await showNormal(); });
  ipcMain.on('pdf-secure', async event => { if (event.sender !== window?.webContents) return;
    if (pdf) { pdf.data.fill(0); pdf = null; } await showSecure(); });
  await createWindow(); traceSmoke('window ready');
  if (smokeMode) await runSmoke();
}).catch(e => { traceSmoke(`startup error: ${e.stack || e}`); process.stderr.write(`${e.stack || e}\n`); process.exit(1); });
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', () => { globalShortcut.unregisterAll(); vaults?.forEach(v => v.lock()); });
app.on('window-all-closed', () => { if (quitting) app.quit(); });
