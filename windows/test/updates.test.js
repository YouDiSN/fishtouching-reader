'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createUpdates, RELEASE_URL } = require('../updates');
function fixture({ installed = true, available = true, replies = [0,0], fail, prepareFails = false } = {}) {
  const updater = new EventEmitter(), dialogs = [], calls = [], progress = [];
  updater.checkForUpdates = async () => { calls.push('check'); if (fail === 'check') throw Error('offline'); return { isUpdateAvailable: available, updateInfo: { version: '1.0.12' } }; };
  updater.downloadUpdate = async () => { calls.push('download'); if (fail === 'download') throw Error('checksum mismatch'); updater.emit('download-progress', {percent: 50}); };
  updater.quitAndInstall = (...args) => calls.push(['install', ...args]);
  const ui = createUpdates({ updater, installed, version: '1.0.11', ask: async d => { dialogs.push(d); return { response: replies.shift() ?? 1 }; },
    openExternal: async url => calls.push(url), prepareInstall: async () => { calls.push('save'); if (prepareFails) throw Error('disk full'); }, setProgress: p => progress.push(p) });
  return { updater, ui, calls, dialogs, progress };
}
test('user confirms download and restart, saves before install, never installs on ordinary quit', async () => {
  const f=fixture(); await f.ui.check();
  assert.deepEqual(f.calls,['check','download','save',['install',true,true]]);
  assert.equal(f.updater.autoInstallOnAppQuit,false);assert.equal(f.updater.autoDownload,false);assert.equal(f.updater.allowDowngrade,false);
  assert.deepEqual(f.progress,[0,.5,-1]);
});
test('up to date does not download',async()=>{const f=fixture({available:false});await f.ui.check();assert.deepEqual(f.calls,['check']);assert.match(f.dialogs[0].message,/最新/);});
test('declining download leaves app alone',async()=>{const f=fixture({replies:[1]});await f.ui.check();assert.deepEqual(f.calls,['check']);assert.equal(f.ui.state,'idle');});
test('deferred restart can resume without redownload',async()=>{const f=fixture({replies:[0,1,0]});await f.ui.check();assert.equal(f.ui.state,'ready');await f.ui.check();assert.deepEqual(f.calls,['check','download','save',['install',true,true]]);});
for(const fail of ['check','download']) test(`${fail} failure keeps app running and permits retry`,async()=>{const f=fixture({fail});await f.ui.check();assert.equal(f.ui.state,'idle');assert.equal(f.ui.enabled,true);assert.equal(f.dialogs.at(-1).type,'error');assert.ok(!f.calls.includes('save'));});
test('failure saving progress prevents installer launch',async()=>{const f=fixture({prepareFails:true});await f.ui.check();assert.equal(f.ui.state,'ready');assert.ok(!f.calls.some(x=>Array.isArray(x)));});
test('portable opens only the fixed release page after consent',async()=>{const f=fixture({installed:false});await f.ui.check();assert.deepEqual(f.calls,[RELEASE_URL]);});
test('repeated clicks cannot start concurrent checks',async()=>{const f=fixture();let resolve;f.updater.checkForUpdates=()=>new Promise(r=>resolve=r);const pending=f.ui.check();await f.ui.check();resolve({isUpdateAvailable:false});await pending;assert.equal(f.dialogs.length,1);});

test('installer failure restores retry state',async()=>{const f=fixture();f.updater.quitAndInstall=()=>f.updater.emit('error',Error('installer could not start'));await f.ui.check();assert.equal(f.ui.state,'ready');assert.equal(f.ui.enabled,true);assert.equal(f.dialogs.at(-1).message,'安装未完成');});
