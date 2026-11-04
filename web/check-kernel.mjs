// 内核分层禁边守门（spec-delta §4.2）。命中即红，进 build.sh 与 npm test。
// 用法：node check-kernel.mjs
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, normalize, relative } from 'node:path';
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
  if (relPath.startsWith('shared/')) return 'shared';
  if (relPath.startsWith('core/')) return 'core';
  const comp = relPath.match(/^components\/([^/]+)\//);
  if (comp) return `component:${comp[1]}`;
  return 'root'; // main.js
}

// 每层允许 import 的目标层（按解析后的内核内路径判定，故 core/ops/* 这类子目录也成立）
const ALLOWED_LAYERS = {
  transport: ['contract'],
  contract: ['contract'],
  semantics: ['semantics'],
  shared: ['shared'],

  // 组合根：可达所有层与组件（唯一的装配点）
  // 组合根与装配文件：可达所有层与组件（唯一的装配点）
  root: ['root', 'transport', 'contract', 'semantics', 'shared', 'component:*'],
  // 组件：只许自身目录 + shared + semantics。跨组件一律经 shared/ports.js 端口，
  // 由 kernel/assemble.js 装配（S4 收口后的硬约束）。
  component: (self) => [`component:${self}`, 'shared', 'semantics'],
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

  // 2. import 白名单：相对 import 解析成内核内路径后按目标层判定
  const rawAllowed = layer.startsWith('component:')
    ? ALLOWED_LAYERS.component(layer.slice('component:'.length))
    : (ALLOWED_LAYERS[layer] ?? []);
  const allowedLayers = rawAllowed;
  for (const match of text.matchAll(/from\s+['"]([^'"]+)['"]/g)) {
    const spec = match[1];
    if (!spec.startsWith('.')) {
      // 第三方依赖只允许出现在 core（编辑器引擎本身）；其余层必须零依赖
      if (layer !== 'core' && !layer.startsWith('component:')) violations.push(`${rel}: ${layer} 层不得 import 第三方包 "${spec}"`);
      continue;
    }
    const target = normalize(join(dirname(rel), spec)).replaceAll('\\', '/');
    if (target.startsWith('..')) {
      violations.push(`${rel}: import 越出内核目录 "${spec}"`);
      continue;
    }
    const targetLayer = layerOf(target);
    const hit = allowedLayers.some((l) => l === targetLayer || (l.endsWith(':*') && targetLayer.startsWith(l.slice(0, -1))));
    if (!hit) {
      violations.push(`${rel}: 非法 import "${spec}" → ${target}（${layer} 层只允许 ${allowedLayers.join(' | ')}）`);
    }
  }
}

if (violations.length > 0) {
  console.error('check-kernel: 分层禁边违规');
  for (const line of violations) console.error(`  - ${line}`);
  process.exit(1);
}
console.log(`check-kernel: OK（${walk(KERNEL_DIR).length} 个内核文件）`);
