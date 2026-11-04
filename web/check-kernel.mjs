// 内核分层禁边守门（spec-delta §4.2）。命中即红，进 build.sh 与 npm test。
// 用法：node check-kernel.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const KERNEL_DIR = fileURLToPath(new URL('./src/kernel', import.meta.url));
const HOST_SYMBOLS = [/window\.webkit/, /messageHandlers/, /__mdHostChannel/, /chrome\.webview/, /window\.chrome\./];

const violations = [];

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const stat = statSync(full);
    if (stat.isDirectory()) walk(full, out);
    else if (name.endsWith('.js')) out.push(full);
  }
  return out;
}

function layerOf(relPath) {
  if (relPath.startsWith('transport/')) return 'transport';
  if (relPath.startsWith('contract/')) return 'contract';
  if (relPath.startsWith('semantics/')) return 'semantics';
  if (relPath.startsWith('core/')) return 'core';
  return 'root'; // main.js
}

// 每层允许 import 的相对前缀（其他层禁止横调，禁止反向依赖）
const ALLOWED_IMPORTS = {
  transport: ['../contract/'],
  contract: ['./', '../contract/'],
  semantics: ['./', '../semantics/'],
  core: ['./', '../core/', '../contract/', '../semantics/'],
  root: ['./transport/', './contract/', './semantics/', './core/', './main.js'],
};

for (const file of walk(KERNEL_DIR)) {
  const rel = relative(KERNEL_DIR, file).replaceAll('\\', '/');
  const text = readFileSync(file, 'utf8');
  const layer = layerOf(rel);

  // 1. 宿主符号：只有 transport 豁免
  if (layer !== 'transport') {
    for (const pattern of HOST_SYMBOLS) {
      if (pattern.test(text)) violations.push(`${rel}: 出现宿主符号 ${pattern}（仅 transport/ 允许）`);
    }
  }

  // 2. import 白名单
  const allowed = ALLOWED_IMPORTS[layer] ?? [];
  for (const match of text.matchAll(/from\s+['"]([^'"]+)['"]/g)) {
    const spec = match[1];
    if (!spec.startsWith('.')) {
      // 第三方依赖只允许出现在 core（编辑器引擎本身）；transport/contract/semantics 必须零依赖
      if (layer !== 'core') violations.push(`${rel}: ${layer} 层不得 import 第三方包 "${spec}"`);
      continue;
    }
    const ok = allowed.length === 0 ? false : allowed.some((prefix) => spec.startsWith(prefix) || spec === '.') ;
    // 同层直接 import 兄弟文件：'./x.js' 归入 './' 前缀，已覆盖
    if (!ok) violations.push(`${rel}: 非法 import "${spec}"（${layer} 层只允许 ${allowed.join(' | ')}）`);
  }
}

if (violations.length > 0) {
  console.error('check-kernel: 分层禁边违规');
  for (const line of violations) console.error(`  - ${line}`);
  process.exit(1);
}
console.log(`check-kernel: OK（${walk(KERNEL_DIR).length} 个内核文件）`);
