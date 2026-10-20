'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { unzipSync, strFromU8 } = require('fflate');
const { DOMParser } = require('@xmldom/xmldom');

const blocks = new Set(['p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'section', 'article', 'br']);
const ignored = new Set(['head', 'script', 'style', 'svg', 'nav']);
function elements(root, name) {
  return Array.from(root.getElementsByTagName('*')).filter(node => node.localName === name);
}
function parseXML(data) {
  const text = strFromU8(data);
  if (/<!ENTITY/i.test(text)) throw new Error('EPUB 包含不受支持的 XML 实体声明。');
  return new DOMParser({ onError(level, message) { if (level !== 'warning') throw new Error(message); } })
    .parseFromString(text, 'application/xml');
}
function textParagraphs(root) {
  const result = [];
  let buffer = '';
  function flush() {
    const value = buffer.trim().replace(/[\t ]+/g, ' ');
    if (value) result.push(value);
    buffer = '';
  }
  function walk(node) {
    if (node.nodeType === 3 || node.nodeType === 4) { buffer += node.nodeValue; return; }
    if (node.nodeType !== 1) return;
    const tag = node.localName?.toLowerCase();
    if (ignored.has(tag)) { flush(); return; }
    if (blocks.has(tag)) flush();
    for (let child = node.firstChild; child; child = child.nextSibling) walk(child);
    if (blocks.has(tag)) flush();
  }
  walk(root.documentElement);
  flush();
  return result;
}
function paragraphsFromEPUB(file) {
  const input = fs.readFileSync(file);
  if (input.length > 300 * 1024 * 1024) throw new Error('EPUB 文件过大。');
  let total = 0, count = 0;
  const archive = unzipSync(input, { filter(entry) {
    if (++count > 10000) throw new Error('EPUB 文件数量超过安全限制。');
    if (!/\.(xml|opf|xhtml|html|htm)$/i.test(entry.name)) return false;
    total += entry.originalSize;
    if (entry.originalSize > 16 * 1024 * 1024 || total > 64 * 1024 * 1024) throw new Error('EPUB 解压后正文超过安全限制。');
    return true;
  } });
  const get = name => {
    const normalized = path.posix.normalize(name);
    if (!normalized || normalized.startsWith('/') || normalized.split('/').includes('..') || !archive[normalized]) throw new Error('EPUB 文件不完整。');
    return archive[normalized];
  };
  const container = parseXML(get('META-INF/container.xml'));
  const opfPath = elements(container, 'rootfile')[0]?.getAttribute('full-path');
  if (!opfPath) throw new Error('EPUB 缺少书籍目录。');
  const opf = parseXML(get(opfPath));
  const items = new Map(elements(opf, 'item').map(node => [node.getAttribute('id'), node.getAttribute('href')]));
  const base = path.posix.dirname(opfPath);
  const result = [];
  for (const ref of elements(opf, 'itemref')) {
    const href = items.get(ref.getAttribute('idref'));
    if (!href) throw new Error('EPUB 阅读顺序不完整。');
    const chapter = decodeURIComponent(href.split('#')[0]);
    result.push(...textParagraphs(parseXML(get(path.posix.join(base, chapter)))));
  }
  if (!result.length) throw new Error('EPUB 没有可阅读的正文。');
  return result;
}
module.exports = { paragraphsFromEPUB };
