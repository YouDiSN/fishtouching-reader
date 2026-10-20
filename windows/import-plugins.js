'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { paragraphs } = require('./library');
const { paragraphsFromEPUB } = require('./epub');
const { writeAtomic } = require('./vault');

const official = [
  { id: 'official.txt', name: 'TXT 文本', description: '导入纯文本，自动识别常用文字编码。', extensions: ['txt'], parser: 'txt' },
  { id: 'official.pdf', name: 'PDF 文档', description: '保留原始页面、图片与书签。', extensions: ['pdf'], parser: 'pdf' },
  { id: 'official.epub', name: 'EPUB 电子书', description: '按书籍顺序提取文字；加密书库保留原始 EPUB。', extensions: ['epub'], parser: 'epub' },
].map(p => Object.freeze({ ...p, schemaVersion: 1, version: '1.0.0', author: 'YouDiSN' }));
const manifestKeys = ['schemaVersion', 'id', 'name', 'version', 'author', 'description', 'extensions', 'parser'].sort();
function validateManifest(data) {
  if (Buffer.byteLength(data) > 65536) throw new Error('插件规则文件不能超过 64 KB。');
  const p = JSON.parse(data.toString());
  if (p?.schemaVersion === 2) return require('./assets/web-plugins').validate(p);
  if (!p || Array.isArray(p) || Object.keys(p).sort().join() !== manifestKeys.join()) throw new Error('仅支持 JSON 插件规则，不接受脚本、网络权限或自定义身份声明。');
  const string = (value, max, required = true) => typeof value === 'string' && [...value].length <= max && (!required || value.trim().length > 0);
  if (p.schemaVersion !== 1 || !string(p.id, 73) || !/^community\.[a-z0-9][a-z0-9.-]{0,62}$/.test(p.id) ||
      !string(p.version, 14) || !/^\d{1,4}\.\d{1,4}\.\d{1,4}$/.test(p.version) ||
      !string(p.name, 60) || !string(p.author, 80) || !string(p.description, 300, false) ||
      p.parser !== 'txt' || !Array.isArray(p.extensions) || p.extensions.length < 1 || p.extensions.length > 8 ||
      new Set(p.extensions).size !== p.extensions.length || p.extensions.some(e => typeof e !== 'string' || !/^[a-z][a-z0-9]{0,9}$/.test(e) || ['txt', 'pdf', 'epub'].includes(e))) {
    throw new Error('社区插件格式不合法。本版支持本地文本格式扩展，不能覆盖官方 TXT／PDF／EPUB，也不执行网址或脚本。');
  }
  return p;
}
class ImportPluginRegistry {
  constructor(root) { this.root = root; this.file = path.join(root, 'plugins.json'); }
  config() {
    if (!fs.existsSync(this.file)) return { community: [], disabled: [] };
    if (fs.statSync(this.file).size > 512000) throw new Error('插件配置过大。');
    const config = JSON.parse(fs.readFileSync(this.file, 'utf8'));
    if (!Array.isArray(config.community) || config.community.length > 50 || !Array.isArray(config.disabled) || config.disabled.some(id => typeof id !== 'string')) throw new Error('插件配置损坏。');
    const ids = new Set(), extensions = new Set();
    for (const raw of config.community) {
      const p = validateManifest(JSON.stringify(raw));
      if (ids.has(p.id) || p.extensions.some(e => extensions.has(e))) throw new Error('社区插件之间存在重复标识或文件类型。');
      ids.add(p.id); p.extensions.forEach(e => extensions.add(e));
    }
    return config;
  }
  save(config) { fs.mkdirSync(this.root, { recursive: true, mode: 0o700 }); writeAtomic(this.file, JSON.stringify(config)); }
  views() {
    const config = this.config();
    return [...official, ...config.community].map(p => ({ ...p, origin: p.id.startsWith('official.') ? 'official' : 'community',
      enabled: !config.disabled.includes(p.id), permissions: p.parser === 'website' ? '仅访问该书源指定的 HTTPS 网站；不运行网页脚本或访问其他书籍。' : '仅读取你选择的本地文件；不能联网或访问其他书籍' }));
  }
  website(id) { const p=this.views().find(p=>p.id===id && p.enabled && p.parser==='website');if(!p)throw Error('请先安装并启用书源插件。');return p; }
  enabledExtensions() { return this.views().filter(p => p.enabled).flatMap(p => p.extensions); }
  install(raw) {
    const p = validateManifest(JSON.stringify(raw)), config = this.config();
    const other = config.community.filter(item => item.id !== p.id);
    if (other.length >= 50 || other.some(item => item.extensions.some(e => p.extensions.includes(e)))) throw new Error('插件数量达到上限，或扩展名已被其他社区插件使用。');
    config.community = [...other, p];
    if (!config.disabled.includes(p.id)) config.disabled.push(p.id);
    this.save(config);
  }
  setEnabled(id, enabled) {
    const config = this.config();
    if (![...official, ...config.community].some(p => p.id === id)) throw new Error('插件不存在。');
    config.disabled = config.disabled.filter(value => value !== id);
    if (!enabled) config.disabled.push(id);
    this.save(config);
  }
  remove(id) {
    const config = this.config();
    if (!config.community.some(p => p.id === id)) throw new Error('官方插件不能卸载，可以停用。');
    config.community = config.community.filter(p => p.id !== id); config.disabled = config.disabled.filter(value => value !== id);
    this.save(config);
  }
  parse(file) {
    const extension = path.extname(file).slice(1).toLowerCase();
    const plugin = this.views().find(p => p.enabled && p.extensions.includes(extension));
    if (!plugin) throw new Error('没有已启用的插件支持这个文件，请在“导入插件”中检查。');
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size < 1 || stat.size > 256 * 1024 * 1024) throw new Error('文件为空、不是普通文件，或超过 256 MB。');
    if (plugin.parser === 'txt' && stat.size > 32 * 1024 * 1024) throw new Error('文本文件超过 32 MB，请先拆分。');
    const title = path.basename(file, path.extname(file));
    if (plugin.parser === 'pdf') {
      const data = fs.readFileSync(file);
      if (!data.subarray(0, 1024).includes(Buffer.from('%PDF-'))) throw new Error('不是有效的 PDF 文件。');
      return { title, kind: 'pdf', data, paragraphs: [] };
    }
    const parts = plugin.parser === 'epub' ? paragraphsFromEPUB(file) : paragraphs(fs.readFileSync(file));
    if (!parts.length) throw new Error('文件没有可阅读的正文。');
    const epubArchive = plugin.parser === 'epub' ? fs.readFileSync(file).toString('base64') : undefined;
    return { title, kind: 'text', paragraphs: parts, data: Buffer.from(JSON.stringify({ paragraphs: parts, ...(epubArchive ? { epubArchive } : {}) })) };
  }
}
module.exports = { ImportPluginRegistry, validateManifest };
