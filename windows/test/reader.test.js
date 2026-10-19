'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the shared reader without opening a real library or persisting content.
function reader() {
  const html = fs.readFileSync(path.join(__dirname, '../../Resources/index.html'), 'utf8');
  const element = { addEventListener() {} };
  const context = vm.createContext({
    document: { getElementById: () => element },
    localStorage: { getItem: () => null },
    window: {}, clearTimeout() {},
  });
  vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
  return code => JSON.parse(vm.runInContext(`JSON.stringify(${code})`, context));
}

test('chapter detection keeps volume context and removes repeated contents headings', () => {
  const run = reader();
  const headings = run(`detectChapters(['第一卷 晨光','第一章 出发','第二章 来信',
    '第一卷 晨光','第一章 出发','这是正文。','第二章 来信','第二卷 夜色','第一章 归来',
    '正文提到第三章，不是标题。','第三章讲的是一段故事。'])`);
  assert.deepEqual(headings.map(c => c.index), [3, 4, 6, 7, 8]);
  assert.equal(headings[4].volume, '第二卷 夜色');
  assert.equal(run(`chapterNumber('一千零二十三')`), 1023);
  assert.equal(run(`chapterNumber('１２')`), 12);
});

test('clean layout never merges across a page or chapter boundary', () => {
  const run = reader();
  const groups = run(`(()=>{
    book={paragraphs:Array.from({length:702},(_,i)=>i===351?'第二章 来信':'虚构短行')};
    chapters=detectChapters(book.paragraphs);layoutMode='clean';buildDisplayParagraphs();
    return displayParagraphs.map(p=>[p.start,p.end,p.heading]);
  })()`);
  assert.deepEqual(groups, [[0,349,false],[350,350,false],[351,351,true],[352,699,false],[700,701,false]]);
});

test('merged text progress stays within its original paragraph and fractional offset', () => {
  const run = reader();
  const progress = run(`(()=>{
    book={paragraphs:Array(20).fill('虚构短行')};
    displayParagraphs=[{start:10,end:19,text:'虚构短行'}];
    document.querySelector=()=>({getBoundingClientRect:()=>({bottom:70})});
    document.querySelectorAll=()=>[{dataset:{index:'0'},getBoundingClientRect:()=>({top:-259,height:1000})}];
    return currentProgress();
  })()`);
  assert.equal(progress.paragraph, 13);
  assert.ok(Math.abs(progress.fraction - .45) < 1e-8);
});
