'use strict';
const cheerio = require('cheerio');

function validatedURL(input) {
  let url;
  try { url = new URL(input.trim()); } catch { throw new Error('请输入有效的 http 或 https 网址。'); }
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('请输入有效的 http 或 https 网址。');
  return url;
}
async function fetchHTML(input) {
  const url = validatedURL(input);
  const response = await fetch(url, { signal: AbortSignal.timeout(35000), headers: { 'user-agent': 'Mozilla/5.0 FishTouchingReader/0.4' }, redirect: 'follow' });
  if (!response.ok) throw new Error(`网页下载失败：HTTP ${response.status}`);
  const data = Buffer.from(await response.arrayBuffer());
  if (data.length > 8 * 1024 * 1024) throw new Error('页面超过 8 MB，无法自动导入。');
  const charset = /charset\s*=\s*["']?([^;"'\s]+)/i.exec(response.headers.get('content-type') || '')?.[1] || 'utf-8';
  try { return { html: new TextDecoder(charset).decode(data), url: response.url }; }
  catch { return { html: new TextDecoder('utf-8').decode(data), url: response.url }; }
}
function linesFromElement($, element) {
  const lines = [];
  let current = '';
  function flush() { if (current.trim()) lines.push(current.trim()); current = ''; }
  function visit(node) {
    if (node.type === 'tag' && node.name === 'br') { flush(); return; }
    if (node.type === 'text') { current += node.data || ''; return; }
    for (const child of node.children || []) visit(child);
  }
  visit(element); flush();
  return lines;
}
function extract(html, input) {
  const url = validatedURL(input);
  const $ = cheerio.load(html);
  const title = $('h1.wp-block-post-title, h1.main-title, article h1, h1').first().text().trim();
  if (!title) throw new Error('没有找到文章标题。');
  const next = $('a[rel=next], .pagination a').first().text();
  if (next.includes('下一页')) throw new Error('该文章有分页，需要单独适配。');
  let elements = $('.entry-content.wp-block-post-content > p.wp-block-paragraph');
  if (!elements.length) elements = $('article p, .entry-content p, #thread p, .post-content p, .content p');
  let parts = elements.toArray().flatMap(node => linesFromElement($, node)).filter(s => !s.startsWith('广告信息：'));
  if ((parts.length < 2 || url.hostname.includes('example.invalid'))) {
    const pre = $('#content-section pre, article pre').first();
    if (pre.length) parts = pre.text().split(/\r\n|\n|\r/).map(s => s.trim()).filter(Boolean);
  }
  if (parts.length < 2) throw new Error('没有找到完整的文章正文，请检查预览或页面结构。');
  const slug = url.pathname.split('/').filter(Boolean).at(-1) || encodeURIComponent(title);
  return { sourceURL: url.href, encodedTitle: slug, originalTitle: title, paragraphs: parts };
}
function indexLinks(html, input) {
  const base = validatedURL(input);
  const $ = cheerio.load(html);
  const seen = new Set();
  for (const anchor of $('.entry-content a[href], #content-section a[href]').toArray()) {
    let url;
    try { url = new URL($(anchor).attr('href'), base); } catch { continue; }
    if (url.hostname !== base.hostname) continue;
    const parts = url.pathname.split('/').filter(Boolean);
    const wordpressArticle = parts.length === 4 && /^20\d\d$/.test(parts[0]) && /^\d\d$/.test(parts[1]) && /^\d\d$/.test(parts[2]);
    const thread = url.hostname.includes('example.invalid') && url.searchParams.has('tid') && url.href !== base.href;
    if (wordpressArticle || thread) seen.add(url.href);
  }
  if (!seen.size) throw new Error('目录中没有找到可导入的文章链接。');
  return [...seen];
}
module.exports = { validatedURL, fetchHTML, extract, indexLinks };
