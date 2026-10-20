'use strict';
const RELEASE_URL = 'https://github.com/YouDiSN/fishtouching-reader/releases/latest';

// UI orchestration is separate from the updater so failures and user consent can
// be tested without replacing an application or touching a real library.
function createUpdates({ updater, installed, version, ask, openExternal, prepareInstall, cancelInstall = () => {}, setProgress = () => {}, changed = () => {} }) {
  let state = 'idle', downloadedVersion = '', busy = false;
  const setState = value => { state = value; changed(); };
  if (updater) {
    updater.autoDownload = false;
    updater.autoInstallOnAppQuit = false;
    updater.allowPrerelease = false;
    updater.allowDowngrade = false;
    updater.disableDifferentialDownload = true;
    updater.disableWebInstaller = true;
    // Operations below await and report failures; attaching this listener also
    // prevents EventEmitter's unhandled error behaviour.
    updater.on('error', error => {
      if (state !== 'installing') return;
      cancelInstall(); setState('ready');
      Promise.resolve(ask({ type: 'error', message: '安装未完成', detail: `旧版仍可使用，请重试。\n${String(error.message || error).slice(0, 350)}`, buttons: ['好'] })).catch(() => {});
    });
    updater.on('download-progress', info => {
      setProgress(Math.min(1, Math.max(0, info.percent / 100)));
    });
  }
  async function install() {
    const result = await ask({ type: 'info', message: `v${downloadedVersion} 已下载`, detail: '重启后安装更新。书库和阅读进度会保留。', buttons: ['重启并安装', '稍后'], defaultId: 0, cancelId: 1 });
    if (result.response !== 0) return;
    await prepareInstall();
    setState('installing');
    updater.quitAndInstall(true, true);
  }
  async function check() {
    if (busy) return;
    busy = true;
    try {
      if (!installed) {
        const result = await ask({ type: 'info', message: '便携版需要先安装一次安装版', detail: '下载 Windows Setup.exe 并安装，之后即可在应用内更新。现有书库仍保存在原目录。', buttons: ['打开官方下载页', '取消'], defaultId: 0, cancelId: 1 });
        if (result.response === 0) await openExternal(RELEASE_URL);
        return;
      }
      if (state === 'ready') return await install();
      setState('checking');
      const result = await updater.checkForUpdates();
      if (!result?.isUpdateAvailable) {
        setState('idle');
        await ask({ type: 'info', message: '当前已是最新版本', detail: `当前版本：v${version}`, buttons: ['好'] });
        return;
      }
      const next = result.updateInfo.version;
      const answer = await ask({ type: 'info', message: `发现新版本 v${next}`, detail: `当前版本：v${version}\n下载完成后可选择重启安装。`, buttons: ['下载更新', '稍后'], defaultId: 0, cancelId: 1 });
      if (answer.response !== 0) { setState('idle'); return; }
      setState('downloading'); setProgress(0);
      await updater.downloadUpdate();
      setProgress(-1); downloadedVersion = next; setState('ready');
      await install();
    } catch (error) {
      setProgress(-1);
      cancelInstall();
      setState(downloadedVersion ? 'ready' : 'idle');
      await ask({ type: 'error', message: '更新未完成', detail: `请检查网络后重试，或稍后重新检查更新。\n${String(error.message || error).slice(0, 350)}`, buttons: ['好'] });
    } finally { busy = false; changed(); }
  }
  return { check, get state() { return state; }, get enabled() { return !busy && state !== 'installing'; }, get label() {
    return state === 'installing' ? '正在安装更新…' : state === 'checking' ? '正在检查更新…' : state === 'downloading' ? '正在下载更新…' : state === 'ready' ? '重启并安装更新…' : '检查更新…';
  } };
}
module.exports = { createUpdates, RELEASE_URL };
