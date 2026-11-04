// 语义套件 B 组：与 Swift 现行实现（ImagePathRewriter）逐字节对拍。
// 黄金件 web/test/fixtures/semantics-golden.json 由 tools/semantics-dump（Swift）生成，
// 生成命令见该目录注释；Swift 实现下线后本套件即唯一真相。
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  applyForLoad, collectImageRefs, collectResourceRefs, nextResourceName, refCandidates,
  restoreForSave, splitInner,
} from '../src/kernel/semantics/markdown.js';
import { fileUrlFromPath, joinBase, normalizePath, urlToPath } from '../src/kernel/semantics/paths.js';

const GOLDEN = JSON.parse(readFileSync(new URL('./fixtures/semantics-golden.json', import.meta.url), 'utf8'));
const BASE = '/virtual/base';

/** 按壳的作答语义构造 resources：字面存在→url；两口径存在→paths（宁多保护） */
function shellAnswers(markdown, files) {
  const fileSet = new Set(files);
  const resources = {};
  for (const ref of collectImageRefs(markdown)) {
    const candidates = refCandidates(ref, { baseDir: BASE });
    const literal = candidates[0];
    const decoded = candidates[1] ?? literal;
    const literalRel = literal.slice(BASE.length + 1);
    const decodedRel = decoded.slice(BASE.length + 1);
    const literalExists = fileSet.has(literalRel);
    const decodedExists = decodedRel !== literalRel && fileSet.has(decodedRel);
    const paths = [];
    if (literalExists) paths.push(literal);
    if (decodedExists) paths.push(decoded);
    resources[ref] = {
      url: literalExists ? fileUrlFromPath(literal) : null,
      exists: literalExists,
      isImage: true,
      paths,
    };
  }
  return resources;
}

const rebase = (text) => text.replaceAll(BASE, '$BASE');

for (const item of GOLDEN.cases) {
  const markdown = item.md.replaceAll('$BASE', BASE);
  const resources = shellAnswers(markdown, item.files);

  test(`对拍·装载改写：${item.name}`, () => {
    assert.equal(rebase(applyForLoad(markdown, { resources })), item.forLoad);
  });

  test(`对拍·保存还原：${item.name}`, () => {
    assert.equal(rebase(restoreForSave(markdown, { baseDir: BASE })), item.forSave);
  });

  test(`对拍·引用收集：${item.name}`, () => {
    assert.deepEqual(collectResourceRefs(markdown, { resources }).map(rebase).sort(), item.refs);
  });
}

test('splitInner：尖括号优先、尾部标题、整体路径三态', () => {
  assert.deepEqual(splitInner('<a b.png> "t"'), { path: 'a b.png', title: 't' });
  assert.deepEqual(splitInner('a.png "t"'), { path: 'a.png', title: 't' });
  assert.deepEqual(splitInner("a.png 't'"), { path: 'a.png', title: 't' });
  assert.deepEqual(splitInner('a b.png'), { path: 'a b.png', title: '' });
  assert.equal(splitInner('<>'), null);
  assert.equal(splitInner('   '), null);
  assert.equal(splitInner('<a.png> junk'), null);
});

test('PathPolicy：file URL 编解码与 Swift 同口径（空格/括号/中文）', () => {
  assert.equal(fileUrlFromPath('/x/my pic.png'), 'file:///x/my%20pic.png');
  assert.equal(fileUrlFromPath('/x/a(1).png'), 'file:///x/a(1).png');
  assert.equal(fileUrlFromPath('/x/图 1.png'), 'file:///x/%E5%9B%BE%201.png');
  assert.equal(fileUrlFromPath('/x/a&b=c.png'), 'file:///x/a&b=c.png');
  assert.equal(urlToPath('file:///x/my%20pic.png'), '/x/my pic.png');
  assert.equal(urlToPath('https://x/y.png'), null);
  // 字面 % 与合法 %XX 混排：分段解码，不整体解码
  assert.equal(urlToPath('file:///x/a%20b%2525.png'), '/x/a b%25.png');
});

test('normalizePath：posix 与 win32 两风格', () => {
  assert.equal(normalizePath('/a//b/./c/../d/'), '/a/b/d');
  assert.equal(normalizePath('C:\\docs\\..\\a\\b.md', { style: 'win32' }), 'C:\\a\\b.md');
  assert.equal(joinBase('/a/b', 'img/x.png'), '/a/b/img/x.png');
  assert.equal(joinBase('/a/b', '/abs/x.png'), '/abs/x.png');
  assert.equal(joinBase('C:\\docs', 'img\\x.png', { style: 'win32' }), 'C:\\docs\\img\\x.png');
});

test('nextResourceName：blob 顺序命名与 file 冲突后缀', () => {
  assert.equal(nextResourceName({ existing: [], kind: 'blob', mime: 'image/png' }), 'img_001.png');
  assert.equal(
    nextResourceName({ existing: ['img_001.png', 'img_007.png'], kind: 'blob', mime: 'image/jpeg' }),
    'img_008.jpg',
  );
  assert.equal(
    nextResourceName({ existing: ['shot.png'], kind: 'file', preferredName: 'shot.png' }),
    'shot-2.png',
  );
  assert.equal(
    nextResourceName({ existing: ['shot.png', 'shot-2.png'], kind: 'file', preferredName: 'shot.png' }),
    'shot-3.png',
  );
});

test('引用收集的宁多保护：字面与解码两口径同时存在时都进集合', () => {
  const md = '![a](img/a%20b.png)';
  const resources = {
    'img/a%20b.png': {
      url: fileUrlFromPath(`${BASE}/img/a%20b.png`),
      exists: true,
      isImage: true,
      paths: [`${BASE}/img/a b.png`, `${BASE}/img/a%20b.png`],
    },
  };
  const refs = collectResourceRefs(md, { resources }).sort();
  assert.deepEqual(refs, [`${BASE}/img/a b.png`, `${BASE}/img/a%20b.png`]);
});
