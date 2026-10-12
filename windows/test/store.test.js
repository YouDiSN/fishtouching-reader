'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Vault } = require('../vault');
const { PublicLibrary, paragraphs } = require('../library');

function temporary(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fishtouching-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}
test('secure title, content and progress stay encrypted and password can change', t => {
  const root = temporary(t);
  const vault = new Vault(path.join(root, 'vault'));
  vault.configure('4321');
  const title = '窗边的橘猫';
  const entry = vault.add({ title, kind: 'text', data: Buffer.from(JSON.stringify({ paragraphs: [title, '午后的办公室很安静。'] })), paragraphs: [title, '午后的办公室很安静。'] });
  vault.progress(entry.id, { position: 1, fraction: 0.4 });
  for (const file of [vault.catalogPath, path.join(vault.dataDir, `${entry.id}.bin`)]) {
    assert.equal(fs.readFileSync(file).includes(Buffer.from(title)), false);
  }
  vault.lock();
  assert.throws(() => vault.load(entry.id), /锁定/);
  assert.throws(() => vault.unlock('wrong'), /密码不正确/);
  vault.unlock('4321');
  assert.equal(vault.list()[0].progress.position, 1);
  vault.changePassword('4321', 'new4'); vault.lock();
  assert.throws(() => vault.unlock('4321'), /密码不正确/);
  vault.unlock('new4');
  assert.match(vault.load(entry.id).toString(), /橘猫/);
  vault.remove(entry.id);
  assert.equal(vault.list().length, 0);
});
test('independent vaults keep passwords and transferred progress separate', t => {
  const root = temporary(t);
  const first = new Vault(path.join(root, 'vault'));
  const second = new Vault(path.join(root, 'vault-spaces', '2'));
  first.configure('first-space-pass'); second.configure('second-space-pass');
  const data = Buffer.from(JSON.stringify({ paragraphs: ['第一卷', '第二卷'] }));
  const original = first.add({ title: '虚构合卷', kind: 'text', data, paragraphs: ['第一卷', '第二卷'] });
  first.progress(original.id, { position: 1, fraction: 0.4 });
  const movedID = first.transfer(original.id, second);
  assert.equal(first.list().length, 0);
  assert.equal(second.list()[0].id, movedID);
  assert.deepEqual(JSON.parse(second.load(movedID)), JSON.parse(data));
  assert.equal(second.list()[0].progress.position, 1);
  assert.equal(second.list()[0].progress.fraction, 0.4);
  const legacyTXT = Buffer.from('旧版导入的原文\n第二段', 'utf8');
  const legacy = first.add({ title: '旧版 TXT', kind: 'text', data: legacyTXT, paragraphs: ['旧版导入的原文', '第二段'] });
  const legacyMoved = first.transfer(legacy.id, second);
  assert.deepEqual(second.load(legacyMoved), legacyTXT);
  assert.equal(second.list().find(e => e.id === legacyMoved).count, 2);
  first.lock(); second.lock();
  assert.equal(first.matchesPassword('first-space-pass'), true);
  assert.equal(first.matchesPassword('second-space-pass'), false);
  assert.equal(second.matchesPassword('second-space-pass'), true);
  assert.equal(second.matchesPassword('first-space-pass'), false);
  first.changePassword('first-space-pass', 'first-space-updated'); first.lock();
  assert.equal(first.matchesPassword('first-space-pass'), false);
  assert.equal(first.matchesPassword('first-space-updated'), true);
  assert.equal(second.matchesPassword('second-space-pass'), true);
});
test('removing an imported public copy keeps the original file', t => {
  const root = temporary(t);
  const source = path.join(root, '正式.txt');
  fs.writeFileSync(source, '第一段\n第二段');
  const library = new PublicLibrary(path.join(root, 'public'));
  const entry = library.add(source);
  assert.deepEqual(paragraphs(library.load(entry)), ['第一段', '第二段']);
  library.update(entry.id, { progress: { position: 1, fraction: 0.2, updatedAt: Date.now() } });
  library.remove(entry.id);
  assert.equal(library.list().length, 0);
  assert.equal(fs.readFileSync(source, 'utf8'), '第一段\n第二段');
});
