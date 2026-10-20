// Test-only entry point copied into a synthetic older installation by CI.
// Never included in published packages.
'use strict';
const { app } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { NsisUpdater } = require('electron-updater');
const { Vault, writeAtomic } = require('./vault');
const { PublicLibrary } = require('./library');
const { createUpdates } = require('./updates');
const root = process.env.FTR_UPGRADE_TEST_ROOT;
if (!root || !process.env.FISHTOUCHING_UPDATE_TEST_URL) throw Error('Isolated upgrade test configuration missing');
fs.mkdirSync(root,{recursive:true});
app.setPath('userData', root);
app.whenReady().then(async () => {
  fs.mkdirSync(root,{recursive:true});
  const vault=new Vault(path.join(root,'vault'));
  vault.configure('fixture-update-password');
  const parts=['第一章 测试','虚构的升级验证内容','第二章 保留阅读进度'];
  const book=vault.add({title:'升级验证',kind:'text',data:Buffer.from(JSON.stringify({paragraphs:parts})),paragraphs:parts});
  vault.progress(book.id,{position:1,fraction:.25});vault.lock();
  const publicLibrary=new PublicLibrary(path.join(root,'public'));
  const normal=publicLibrary.addText('普通测试书',parts);
  publicLibrary.update(normal.id,{progress:{position:2,fraction:.5}});
  writeAtomic(path.join(root,'preferences.json'),JSON.stringify({name:'更新测试',iconID:'fish',readerTheme:'forest'}));
  fs.writeFileSync(path.join(root,'upgrade-fixture.json'),JSON.stringify({id:book.id,normalId:normal.id,oldVersion:app.getVersion()}));
  const updater=new NsisUpdater({provider:'generic',url:process.env.FISHTOUCHING_UPDATE_TEST_URL});
  updater.logger={info:()=>{},warn:()=>{},error:message=>fs.appendFileSync(path.join(root,'upgrade-errors.txt'),String(message)+'\n')};
  const updates=createUpdates({updater,installed:true,version:app.getVersion(),
    ask:async options=>{fs.appendFileSync(path.join(root,'upgrade-dialogs.txt'),options.message+'\n');if(options.type==='error')throw Error(options.detail);return {response:0};},
    openExternal:async()=>{throw Error('Unexpected external navigation');},prepareInstall:async()=>{
      fs.writeFileSync(path.join(root,'upgrade-download-ok.txt'),'Actual updater download and checksum validation completed');
    }});
  await updates.check();
}).catch(error=>{fs.writeFileSync(path.join(root,'upgrade-failed.txt'),error.stack);app.exit(1);});
setTimeout(()=>{fs.writeFileSync(path.join(root,'upgrade-failed.txt'),'Upgrade timed out');app.exit(1);},120000).unref();
