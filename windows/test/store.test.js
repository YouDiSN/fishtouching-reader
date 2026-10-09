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
