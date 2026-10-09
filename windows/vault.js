'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const SCRYPT = { N: 131072, r: 8, p: 1, maxmem: 256 * 1024 * 1024 };
const bytes = n => crypto.randomBytes(n);
const uuid = () => crypto.randomUUID();
function writeAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${uuid()}.tmp`;
  try { fs.writeFileSync(temp, data); fs.renameSync(temp, file); }
  finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
}
function seal(data, key) {
  const nonce = bytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const encrypted = Buffer.concat([cipher.update(data), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), encrypted]);
}
function open(data, key) {
  if (data.length < 28) throw new Error('加密文件损坏。');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, data.subarray(0, 12));
  decipher.setAuthTag(data.subarray(12, 28));
  return Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]);
}
function derive(password, salt) { return crypto.scryptSync(password, salt, 32, SCRYPT); }
function words(paragraphs) { return paragraphs.join('').match(/[\p{L}\p{N}]/gu)?.length || 0; }

class Vault {
  constructor(root) {
    this.root = root;
    this.configPath = path.join(root, 'vault.json');
    this.catalogPath = path.join(root, 'catalog.bin');
    this.dataDir = path.join(root, 'data');
    this.key = null;
  }
  get configured() { return fs.existsSync(this.configPath); }
  get unlocked() { return this.key !== null; }
  _config(master, password) {
    const salt = bytes(16);
    return { version: 1, kdf: 'scrypt', N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p,
      salt: salt.toString('base64'), wrappedKey: seal(master, derive(password, salt)).toString('base64') };
  }
  configure(password) {
    if (this.configured) throw new Error('加密书库已创建。');
    if ([...password].length < 4) throw new Error('密码至少需要 4 个字符。');
    const master = bytes(32);
    fs.mkdirSync(this.dataDir, { recursive: true });
    writeAtomic(this.catalogPath, seal(Buffer.from(JSON.stringify({ entries: [] })), master));
    writeAtomic(this.configPath, JSON.stringify(this._config(master, password)));
    this.key = master;
  }
  unlock(password) {
    const config = JSON.parse(fs.readFileSync(this.configPath, 'utf8'));
    if (config.version !== 1 || config.kdf !== 'scrypt' || config.N !== SCRYPT.N || config.r !== SCRYPT.r || config.p !== SCRYPT.p) throw new Error('不支持的书库格式。');
    let master;
    try { master = open(Buffer.from(config.wrappedKey, 'base64'), derive(password, Buffer.from(config.salt, 'base64'))); }
    catch { throw new Error('密码不正确。'); }
    if (master.length !== 32) throw new Error('书库密钥损坏。');
    const catalog = JSON.parse(open(fs.readFileSync(this.catalogPath), master));
    if (!Array.isArray(catalog.entries)) throw new Error('书库目录损坏。');
    this.key = master;
  }
  lock() { if (this.key) this.key.fill(0); this.key = null; }
  changePassword(oldPassword, newPassword) {
    if ([...newPassword].length < 4) throw new Error('密码至少需要 4 个字符。');
    const wasUnlocked = this.unlocked;
    this.unlock(oldPassword);
    writeAtomic(this.configPath, JSON.stringify(this._config(this.key, newPassword)));
    if (!wasUnlocked) this.lock();
  }
  _requireKey() { if (!this.key) throw new Error('加密书库已锁定。'); }
  _catalog() { this._requireKey(); return JSON.parse(open(fs.readFileSync(this.catalogPath), this.key)); }
  _writeCatalog(catalog) { writeAtomic(this.catalogPath, seal(Buffer.from(JSON.stringify(catalog)), this.key)); }
  list() { return this._catalog().entries; }
  add({ title, sourceURL = '', kind, data, paragraphs = [], pageCount = 0 }) {
    const catalog = this._catalog();
    const id = uuid();
    const entry = { id, title, sourceURL, kind, importedAt: Date.now(), count: paragraphs.length,
      wordCount: kind === 'text' ? words(paragraphs) : 0, pageCount, progress: null };
    writeAtomic(path.join(this.dataDir, `${id}.bin`), seal(data, this.key));
    catalog.entries.push(entry);
    this._writeCatalog(catalog);
    return entry;
  }
  load(id) {
    this._requireKey();
    if (!this.list().some(e => e.id === id)) throw new Error('找不到这本书。');
    return open(fs.readFileSync(path.join(this.dataDir, `${id}.bin`)), this.key);
  }
  progress(id, value) {
    const catalog = this._catalog();
    const entry = catalog.entries.find(e => e.id === id);
    if (!entry) throw new Error('找不到这本书。');
    entry.progress = { ...value, updatedAt: Date.now() };
    this._writeCatalog(catalog);
  }
  update(id, values) {
    const catalog = this._catalog();
    const entry = catalog.entries.find(e => e.id === id);
    if (!entry) throw new Error('找不到这本书。');
    Object.assign(entry, values);
    this._writeCatalog(catalog);
  }
  remove(id) {
    const catalog = this._catalog();
    const index = catalog.entries.findIndex(e => e.id === id);
    if (index < 0) throw new Error('找不到这本书。');
    catalog.entries.splice(index, 1);
    this._writeCatalog(catalog);
    const file = path.join(this.dataDir, `${id}.bin`);
    if (fs.existsSync(file)) fs.unlinkSync(file);
  }
}
module.exports = { Vault, seal, open, writeAtomic, words };
