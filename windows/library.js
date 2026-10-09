'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { writeAtomic, words } = require('./vault');

function decodeText(data) {
  for (const encoding of ['utf-8', 'utf-16le', 'gb18030']) {
    try {
      const text = new TextDecoder(encoding, { fatal: true }).decode(data).replace(/^\uFEFF/, '');
      if (!text.includes('\u0000')) return text;
    } catch { /* try the next encoding */ }
  }
  throw new Error('无法识别 TXT 编码。');
}
function paragraphs(data) { return decodeText(data).split(/\r\n|\n|\r/).map(s => s.trim()).filter(Boolean); }
class PublicLibrary {
  constructor(root) {
    this.root = root;
    this.catalogPath = path.join(root, 'catalog.json');
    this.dataDir = path.join(root, 'data');
  }
  list() {
    if (!fs.existsSync(this.catalogPath)) return [];
    return JSON.parse(fs.readFileSync(this.catalogPath, 'utf8')).entries.filter(e => fs.existsSync(this.file(e)));
  }
  file(entry) { return path.join(this.dataDir, `${entry.id}.${entry.kind}`); }
  add(source) {
    const kind = path.extname(source).slice(1).toLowerCase();
    if (!['txt', 'pdf'].includes(kind)) throw new Error('仅支持 TXT 和 PDF。');
    const id = crypto.randomUUID();
    const entry = { id, title: path.basename(source, path.extname(source)), kind: kind === 'txt' ? 'text' : 'pdf',
      importedAt: Date.now(), count: 0, wordCount: 0, pageCount: 0, progress: null };
    if (kind === 'txt') { const parts = paragraphs(fs.readFileSync(source)); entry.count = parts.length; entry.wordCount = words(parts); }
    fs.mkdirSync(this.dataDir, { recursive: true });
    fs.copyFileSync(source, this.file(entry));
    const entries = this.list(); entries.push(entry);
    writeAtomic(this.catalogPath, JSON.stringify({ entries }));
    return entry;
  }
  load(entry) { return fs.readFileSync(this.file(entry)); }
  update(id, values) {
    const entries = this.list();
    const entry = entries.find(e => e.id === id);
    if (!entry) throw new Error('找不到这本书。');
    Object.assign(entry, values);
    writeAtomic(this.catalogPath, JSON.stringify({ entries }));
  }
  remove(id) {
    const entries = this.list();
    const entry = entries.find(e => e.id === id);
    if (!entry) throw new Error('找不到这本书。');
    writeAtomic(this.catalogPath, JSON.stringify({ entries: entries.filter(e => e.id !== id) }));
    const file = this.file(entry);
    if (fs.existsSync(file)) fs.unlinkSync(file);
  }
}
module.exports = { PublicLibrary, paragraphs, decodeText };
