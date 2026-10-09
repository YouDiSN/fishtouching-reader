'use strict';
const { app, BrowserWindow, ipcMain, dialog, globalShortcut, Menu, Tray, nativeImage } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { Vault, writeAtomic } = require('./vault');
const { PublicLibrary, paragraphs } = require('./library');
const importer = require('./importer');

const DEFAULT_NAME = 'FishTouching Reader';
const ICONS = new Set(['fish', 'book', 'night', 'leaf', 'coffee', 'star', 'pencil', 'music', 'sunrise', 'cloud']);
const assets = path.join(__dirname, 'assets');
let root, vault, publicLibrary, preferences, window, settingsWindow, tray;
let currentTab = 'normal', currentId = null, resumeId = null, pdf = null, pending = null;
let busy = false, switching = false, dialogOpen = false, quitting = false;
let batchGeneration = 0;
const smokeMode = Boolean(process.env.FISHTOUCHING_SMOKE_ROOT) || process.argv.includes('--smoke');
let smokeStage = 'waiting for Electron';
if (smokeMode) {
  app.commandLine.appendSwitch('disable-gpu');
  setTimeout(() => { process.stderr.write(`Smoke timed out: ${smokeStage}\n`); process.exit(1); }, 60000).unref();
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
  if (settingsWindow) settingsWindow.setTitle(`设置 · ${name}`);
  if (tray) { tray.setToolTip(name); tray.setImage(nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 })); }
}
function send(data) { if (window && !window.isDestroyed() && !pdf) window.webContents.executeJavaScript(`receive(${JSON.stringify(data)})`).catch(() => {}); }
function sendSettings(extra = {}) {
  if (!settingsWindow || settingsWindow.isDestroyed()) return;
  const currentIcon = iconPath();
  const customIcon = iconPath('custom');
  const payload = { name: preferences.pendingName || preferences.name || DEFAULT_NAME,
    iconID: preferences.iconID || 'fish', icon: fs.existsSync(currentIcon) ? `data:image/png;base64,${fs.readFileSync(currentIcon).toString('base64')}` : '',
    hasCustomIcon: fs.existsSync(customIcon), customIcon: fs.existsSync(customIcon) ? `data:image/png;base64,${fs.readFileSync(customIcon).toString('base64')}` : undefined, ...extra };
  settingsWindow.webContents.executeJavaScript(`receiveSettings(${JSON.stringify(payload)})`).catch(() => {});
}
function error(message, context = currentTab === 'secure' ? 'library' : 'normal') { send({ type: 'error', context, message: String(message?.message || message) }); }
function normalState() {
  return { type: 'normal', pdfs: publicLibrary.list().map(e => ({ id: e.id, title: e.title, kind: e.kind,
    pageCount: e.kind === 'text' ? e.count : e.pageCount,
    pageIndex: e.progress?.position || 0, pageFraction: e.progress?.fraction || 0,
    updatedAt: (e.progress?.updatedAt || 0) / 1000 })) };
}
function secureState() {
  return { type: 'library', books: vault.list().map(e => ({ id: e.id, title: e.title,
    host: e.sourceURL ? new URL(e.sourceURL).hostname : (e.kind === 'pdf' ? 'PDF' : '本地文件'),
    count: e.count, wordCount: e.wordCount, kind: e.kind, pageCount: e.pageCount,
    paragraph: e.progress?.position || 0, fraction: e.progress?.fraction || 0,
    updatedAt: (e.progress?.updatedAt || 0) / 1000 })), batchRunning: busy };
}
async function loadReader(data) {
  if (!window.webContents.getURL().endsWith('/index.html')) {
    if (pdf) { pdf.data.fill(0); pdf = null; }
    await window.loadFile(path.join(assets, 'index.html'));
  }
  send(data);
}
async function showNormal() { currentTab = 'normal'; currentId = null; window.setContentProtection(false); await loadReader(normalState()); }
async function showSecure() { currentTab = 'secure'; window.setContentProtection(vault.unlocked); await loadReader(vault.unlocked ? secureState() : { type: 'locked' }); }
async function showText(entry, secure) {
  const data = secure ? vault.load(entry.id) : publicLibrary.load(entry);
  const parts = secure ? JSON.parse(data).paragraphs : paragraphs(data);
  currentTab = secure ? 'secure' : 'normal'; currentId = entry.id;
  if (secure) resumeId = entry.id;
  await loadReader({ type: 'book', tab: currentTab, id: entry.id, encodedTitle: entry.title,
    paragraphs: parts, paragraph: entry.progress?.position || 0, fraction: entry.progress?.fraction || 0 });
  if (secure) window.setContentProtection(true);
}
async function openPDF(entry, secure, cover = false) {
  const data = secure ? vault.load(entry.id) : publicLibrary.load(entry);
  if (pdf) pdf.data.fill(0);
  pdf = { entry, secure, cover, data };
  currentTab = secure ? 'secure' : 'normal';
  currentId = entry.id;
  if (secure) resumeId = entry.id;
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
  if (switching || dialogOpen || currentTab !== 'secure' || !vault.unlocked) return;
  switching = true;
  try {
    const previous = currentId;
    if (pdf?.secure) {
      window.webContents.send('pdf-clear');
      pdf.data.fill(0); pdf = null;
    } else if (!pdf) {
      const result = await window.webContents.executeJavaScript('prepareSecureLock()').catch(() => null);
      if (result) updateProgress(previous, result.paragraph, result.fraction, true);
    }
    resumeId = previous;
    vault.lock(); pending = null; currentTab = 'normal'; currentId = null;
    window.setContentProtection(false);
    const cover = openCover ? publicLibrary.list().filter(e => e.kind === 'pdf').sort((a, b) => b.importedAt - a.importedAt)[0] : null;
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
async function importLocal() {
  dialogOpen = true;
  try {
    const selection = await dialog.showOpenDialog(window, { properties: ['openFile', 'multiSelections'], filters: [{ name: '书籍', extensions: ['txt', 'pdf'] }] });
    if (selection.canceled) return;
    for (const file of selection.filePaths) {
      if (currentTab === 'secure') {
        if (!vault.unlocked) throw new Error('加密书库已锁定。');
        if (!['.txt', '.pdf'].includes(path.extname(file).toLowerCase())) throw new Error('仅支持 TXT 和 PDF。');
        const kind = path.extname(file).toLowerCase() === '.pdf' ? 'pdf' : 'text';
        const data = fs.readFileSync(file);
        const parts = kind === 'text' ? paragraphs(data) : [];
        vault.add({ title: path.basename(file, path.extname(file)), kind, data, paragraphs: parts });
      } else publicLibrary.add(file);
    }
    send(currentTab === 'secure' ? secureState() : normalState());
  } finally { dialogOpen = false; }
}
async function chooseIcon() {
  dialogOpen = true;
  try {
    const selection = await dialog.showOpenDialog(settingsWindow || window, { properties: ['openFile'], filters: [{ name: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp'] }] });
    if (selection.canceled) return;
    const image = nativeImage.createFromPath(selection.filePaths[0]);
    if (image.isEmpty()) throw new Error('无法读取这张图片。');
    writeAtomic(iconPath('custom'), image.toPNG());
    preferences.iconID = 'custom'; savePreferences(); applyAppearance();
    sendSettings({ message: '任务栏图标已更新。' });
    if (!settingsWindow) window.webContents.executeJavaScript("selectSetupIcon('custom')").catch(() => {});
  } finally { dialogOpen = false; }
}
async function importURL(value, index = false) {
  if (busy || !vault.unlocked) return;
  const generation = ++batchGeneration;
  busy = true;
  try {
    if (!index) {
      send({ type: 'busy', message: '正在下载和提取正文…' });
      const response = await importer.fetchHTML(value);
      pending = importer.extract(response.html, response.url);
      if (currentTab !== 'secure' || !vault.unlocked) return;
      send({ type: 'preview', encodedTitle: pending.encodedTitle, originalTitle: pending.originalTitle,
        count: pending.paragraphs.length, sample: pending.paragraphs.slice(0, 8).join('\n') });
    } else {
      send({ type: 'batch', message: '正在读取目录…' });
      const response = await importer.fetchHTML(value);
      const links = importer.indexLinks(response.html, response.url);
      let added = 0, failed = 0, skipped = 0;
      const existing = new Set(vault.list().map(e => e.sourceURL));
      for (let i = 0; i < links.length; i++) {
        if (generation !== batchGeneration || currentTab !== 'secure' || !vault.unlocked) return;
        if (existing.has(links[i])) { skipped++; continue; }
        send({ type: 'batch', message: `逐篇导入中：${i + 1}/${links.length}，已保存 ${added} 本，失败 ${failed} 本。` });
        try { const page = await importer.fetchHTML(links[i]); const book = importer.extract(page.html, page.url);
          vault.add({ title: book.originalTitle, sourceURL: book.sourceURL, kind: 'text',
            data: Buffer.from(JSON.stringify(book)), paragraphs: book.paragraphs }); added++; }
        catch { failed++; }
      }
      send({ ...secureState(), batchStatus: `目录导入完成：新增 ${added} 本，跳过已有 ${skipped} 本，失败 ${failed} 本。` });
    }
  } catch (e) { error(e); }
  finally { busy = false; }
}
async function handleAction(data) {
  const action = data?.action;
  try {
    switch (action) {
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
        try { vault.unlock(data.password || ''); if (resumeId && vault.list().some(e => e.id === resumeId)) await openEntry(resumeId, true); else await showSecure(); }
        catch (e) { send({ type: 'locked', error: e.message }); }
        break;
      }
      case 'lock': if (currentTab === 'secure') { await coverSecure(); await showSecure(); } break;
      case 'library': if (currentTab === 'secure') { resumeId = null; currentId = null; send(secureState()); } else await showNormal(); break;
      case 'read': if (currentTab === 'secure' && vault.unlocked) await openEntry(data.id, true); else if (currentTab === 'normal') await openEntry(data.id, false); break;
      case 'openPDF': if (currentTab === 'normal') await openEntry(data.id, false); break;
      case 'importLocal': case 'importPDF': await importLocal(); break;
      case 'removeBook': {
        if (currentTab === 'secure') { if (!vault.unlocked) return; vault.remove(data.id); if (resumeId === data.id) resumeId = null; send(secureState()); }
        else { publicLibrary.remove(data.id); send(normalState()); }
        break;
      }
      case 'progress': if (!pdf) updateProgress(currentId, data.paragraph, data.fraction); break;
      case 'import': await importURL(data.url); break;
      case 'importIndex': await importURL(data.url, true); break;
      case 'saveImport': if (pending && vault.unlocked) { vault.add({ title: pending.originalTitle, sourceURL: pending.sourceURL,
        kind: 'text', data: Buffer.from(JSON.stringify(pending)), paragraphs: pending.paragraphs }); pending = null; send(secureState()); } break;
      case 'cancelImport': pending = null; send(secureState()); break;
      case 'selectIcon': if (ICONS.has(data.id)) { preferences.iconID = data.id; savePreferences(); applyAppearance();
        window.webContents.executeJavaScript(`selectSetupIcon(${JSON.stringify(data.id)})`).catch(() => {}); } break;
      case 'chooseIcon': await chooseIcon(); break;
      case 'settings': await coverSecure(); showSettings(); break;
      case 'hide': await coverSecure(); window.hide(); break;
    }
  } catch (e) { error(e, action === 'setup' ? 'setup' : undefined); }
}
function showSettings() {
  if (settingsWindow && !settingsWindow.isDestroyed()) { settingsWindow.show(); settingsWindow.focus(); return; }
  settingsWindow = new BrowserWindow({ width: 780, height: 560, minWidth: 660, minHeight: 460,
    title: `设置 · ${preferences.name}`, parent: window, icon: iconPath(), autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), nodeIntegration: false, contextIsolation: true, sandbox: true } });
  settingsWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  settingsWindow.webContents.on('did-finish-load', () => sendSettings());
  settingsWindow.on('closed', () => { settingsWindow = null; });
  settingsWindow.loadFile(path.join(assets, 'settings.html'));
}
async function settingsAction(data) {
  try {
    switch (data?.action) {
      case 'ready': sendSettings(); break;
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
        vault.changePassword(data.old || '', data.new || '');
        sendSettings({ message: '密码已更新。' }); break;
      }
    }
  } catch (e) { sendSettings({ error: e.message }); }
}
function toggleWindow() {
  if (window.isVisible()) { coverSecure().finally(() => window.hide()); }
  else { window.show(); window.focus(); }
}
function createWindow() {
  window = new BrowserWindow({ width: 940, height: 740, minWidth: 680, minHeight: 520,
    title: preferences.name, icon: iconPath(), backgroundColor: '#101716', autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), nodeIntegration: false, contextIsolation: true, sandbox: true } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.webContents.on('did-finish-load', () => { if (!pdf) send(!vault.configured ? { type: 'setup', iconID: preferences.iconID } : currentTab === 'secure' ? (vault.unlocked ? secureState() : { type: 'locked' }) : normalState()); });
  window.on('blur', () => { coverSecure(); });
  window.on('close', event => { if (!quitting) { event.preventDefault(); coverSecure().finally(() => window.hide()); } });
  const loaded = window.loadFile(path.join(assets, 'index.html'));
  const menu = Menu.buildFromTemplate([{ label: '文件', submenu: [
    { label: '设置', accelerator: 'CommandOrControl+,', click: () => { coverSecure().finally(showSettings); } },
    { label: '显示／隐藏', accelerator: 'Control+Alt+H', click: toggleWindow },
    { type: 'separator' }, { label: '退出', click: () => { quitting = true; app.quit(); } }
  ] }]);
  Menu.setApplicationMenu(menu);
  tray = new Tray(nativeImage.createFromPath(iconPath()).resize({ width: 16, height: 16 }));
  tray.setToolTip(preferences.name);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: '显示／隐藏    Ctrl+Alt+H', click: toggleWindow },
    { label: '设置    Ctrl+,', click: () => coverSecure().finally(showSettings) },
    { type: 'separator' }, { label: '退出', click: () => { quitting = true; app.quit(); } }
  ]));
  globalShortcut.register('Control+Alt+H', toggleWindow);
  return loaded;
}
async function runSmoke() {
  smokeStage = 'configure vault'; process.stdout.write(`${smokeStage}\n`);
  const demo = process.env.FISHTOUCHING_SMOKE_FIXTURES
    ? path.resolve(process.env.FISHTOUCHING_SMOKE_FIXTURES)
    : path.resolve(__dirname, '../demo/fixtures');
  vault.configure('test4321');
  publicLibrary.add(path.join(demo, '工作汇报.pdf'));
  const body = fs.readFileSync(path.join(demo, '摸鱼.txt'));
  const entry = vault.add({ title: '窗边的橘猫', kind: 'text', data: Buffer.from(JSON.stringify({ paragraphs: paragraphs(body) })), paragraphs: paragraphs(body) });
  smokeStage = 'render secure TXT'; process.stdout.write(`${smokeStage}\n`);
  await openEntry(entry.id, true);
  const reading = await window.webContents.executeJavaScript("document.getElementById('text')?.textContent.includes('橘猫')");
  if (!reading) throw new Error('Secure reader did not render.');
  smokeStage = 'switch to cover PDF'; process.stdout.write(`${smokeStage}\n`);
  await coverSecure();
  if (vault.unlocked || currentTab !== 'normal' || !pdf?.cover) throw new Error('Focus cover did not lock and open the PDF.');
  for (let i = 0; i < 40; i++) {
    const loaded = await window.webContents.executeJavaScript("document.getElementById('page')?.textContent").catch(() => '');
    if (loaded?.includes('1 /')) break;
    if (i === 39) throw new Error('PDF viewer did not render.');
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  smokeStage = 'unlock and resume'; process.stdout.write(`${smokeStage}\n`);
  await showSecure();
  vault.unlock('test4321');
  await openEntry(resumeId, true);
  const resumed = await window.webContents.executeJavaScript("document.getElementById('text')?.textContent.includes('橘猫')");
  if (!resumed) throw new Error('Secure reader did not resume.');
  fs.writeFileSync(path.join(root, 'smoke-ok.txt'), 'read, cover PDF, lock, resume');
  process.stdout.write('Windows app smoke passed: read, cover PDF, lock, resume.\n');
  process.exit(0);
}
app.whenReady().then(async () => {
  smokeStage = 'create window';
  app.setAppUserModelId('com.youdisn.fishtouching-reader');
  root = smokeMode && process.env.FISHTOUCHING_SMOKE_ROOT
    ? path.resolve(process.env.FISHTOUCHING_SMOKE_ROOT)
    : path.join(app.getPath('appData'), 'FishTouching Reader');
  if (smokeMode) app.setPath('userData', root);
  fs.mkdirSync(root, { recursive: true });
  preferences = fs.existsSync(preferencePath()) ? JSON.parse(fs.readFileSync(preferencePath(), 'utf8')) : { name: DEFAULT_NAME, iconID: 'fish' };
  if (preferences.pendingName) { preferences.name = preferences.pendingName; delete preferences.pendingName; savePreferences(); }
  vault = new Vault(path.join(root, 'vault'));
  publicLibrary = new PublicLibrary(path.join(root, 'public'));
  ipcMain.on('app-action', (event, data) => { if (event.sender === window?.webContents) handleAction(data); });
  ipcMain.on('settings-action', (event, data) => { if (event.sender === settingsWindow?.webContents) settingsAction(data); });
  ipcMain.on('pdf-ready', event => { if (event.sender === window?.webContents && pdf) {
    window.webContents.send('pdf-document', { title: pdf.entry.title, data: pdf.data.toString('base64'),
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
  await createWindow();
  if (smokeMode) await runSmoke();
}).catch(e => { process.stderr.write(`${e.stack || e}\n`); process.exit(1); });
app.on('will-quit', () => { globalShortcut.unregisterAll(); vault?.lock(); });
app.on('window-all-closed', () => { if (quitting) app.quit(); });
