'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { zipSync, strToU8 } = require('fflate');
const { ImportPluginRegistry, validateManifest } = require('../import-plugins');
const { PublicLibrary } = require('../library');
const { Vault } = require('../vault');
const manifest = { schemaVersion: 1, id: 'community.fixture', name: '虚构文本插件', author: '测试作者', version: '1.0.0', description: '仅供测试', extensions: ['md'], parser: 'txt' };
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ftr-plugins-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, registry: new ImportPluginRegistry(path.join(root, 'plugins')) };
}
test('default plugins classify TXT/PDF/EPUB as official and obey disablement', t => {
  const { root, registry } = fixture(t);
  assert.deepEqual(registry.views().map(p => p.id), ['official.txt', 'official.pdf', 'official.epub']);
  assert.ok(registry.views().every(p => p.origin === 'official' && p.enabled));
  const file = path.join(root, 'story.txt'); fs.copyFileSync(path.join(__dirname, '../../demo/fixtures/摸鱼.txt'), file);
  assert.ok(registry.parse(file).paragraphs.some(p => p.includes('橘猫')));
  const pdf = path.join(__dirname, '../../demo/fixtures/工作汇报.pdf'); assert.equal(registry.parse(pdf).kind, 'pdf');
  registry.setEnabled('official.txt', false); assert.throws(() => registry.parse(file));
  registry.setEnabled('official.txt', true); assert.equal(registry.parse(file).kind, 'text');
  assert.throws(() => registry.remove('official.txt'));
  assert.throws(() => registry.setEnabled('unknown', true));
});
test('community install/update needs enablement; uninstall preserves books, originals and progress', t => {
  const { root, registry } = fixture(t);
  registry.install(manifest);
  const file = path.join(root, 'story.md'); fs.copyFileSync(path.join(__dirname, '../../demo/fixtures/摸鱼.txt'), file);
  assert.throws(() => registry.parse(file)); registry.setEnabled(manifest.id, true);
  const reopened = new ImportPluginRegistry(path.join(root, 'plugins'));
  assert.equal(reopened.views().at(-1).origin, 'community');
  const content = reopened.parse(file), library = new PublicLibrary(path.join(root, 'library'));
  const entry = library.addText(content.title, content.paragraphs);
  library.update(entry.id, { progress: { position: 1, fraction: .3 } });
  const vault = new Vault(path.join(root, 'vault')); vault.configure('test-plugin-pass');
  const secure = vault.add(content);
  assert.equal(vault.load(secure.id).toString(), content.data.toString());
  reopened.install(manifest); assert.throws(() => reopened.parse(file));
  reopened.remove(manifest.id);
  assert.equal(library.list()[0].progress.position, 1);
  assert.ok(library.load(entry).toString().includes('橘猫'));
  assert.ok(fs.existsSync(file)); assert.equal(reopened.views().length, 3);
});
test('community rules cannot claim official identity, add code/network permissions, or override formats', () => {
  for (const patch of [{ id: 'official.txt' }, { origin: 'official' }, { parser: 'javascript' }, { script: 'alert(1)' }, { permissions: ['network'] }, { extensions: ['pdf'] }, { extensions: ['../txt'] }, { extensions: ['md', 'md'] }, { schemaVersion: 2 }]) {
    assert.throws(() => validateManifest(JSON.stringify({ ...manifest, ...patch })));
  }
  assert.throws(() => validateManifest(Buffer.alloc(65537)));
});
test('conflicting extensions and invalid persisted definitions fail closed', t => {
  const { root, registry } = fixture(t); registry.install(manifest);
  assert.throws(() => registry.install({ ...manifest, id: 'community.other' }));
  fs.writeFileSync(path.join(root, 'plugins/plugins.json'), JSON.stringify({ community: [{ ...manifest, id: 'official.txt' }], disabled: [] }));
  assert.throws(() => registry.views());
});
test('EPUB uses official parser, retains original, rejects entity payloads and oversized expansion', t => {
  const { root, registry } = fixture(t);
  const files = {
    'META-INF/container.xml': strToU8('<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>'),
    'book.opf': strToU8('<package><manifest><item id="a" href="chapter.xhtml"/></manifest><spine><itemref idref="a"/></spine></package>'),
    'chapter.xhtml': strToU8('<html><body><h1>第一章</h1><p>虚构的橘猫故事。</p></body></html>'),
  };
  const file = path.join(root, 'story.epub'); fs.writeFileSync(file, zipSync(files));
  assert.deepEqual(registry.parse(file).paragraphs, ['第一章', '虚构的橘猫故事。']);
  assert.ok(JSON.parse(registry.parse(file).data).epubArchive);
  files['chapter.xhtml'] = strToU8('<!DOCTYPE html [<!ENTITY a "danger">]><html><body>&a;</body></html>');
  fs.writeFileSync(file, zipSync(files)); assert.throws(() => registry.parse(file), /实体/);
  files['chapter.xhtml'] = new Uint8Array(17 * 1024 * 1024);
  fs.writeFileSync(file, zipSync(files)); assert.throws(() => registry.parse(file), /安全限制/);
});
