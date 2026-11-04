// 契约套件 A 组：纯 Node，零 DOM、零 WebView（内核可移植性的验收定义）
import test from 'node:test';
import assert from 'node:assert/strict';

import { bootKernel } from '../src/kernel/main.js';
import { CODES } from '../src/kernel/contract/errors.js';
import { PROTOCOL_VERSION, isJsonValue } from '../src/kernel/contract/envelope.js';
import { HOST_OPS, KERNEL_REQUESTS, NOTIFICATIONS } from '../src/kernel/contract/ops.js';
import { FakeShell } from './support/fake-shell.js';

const V2_INIT = { markdown: '', opts: { protocolVersion: 2 } };
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

function makeKernel({ registerOps, responders = {}, kernelVersion = 'test-kernel' } = {}) {
  const win = {};
  const shell = new FakeShell({ responders }).install(win);
  const protocolErrors = [];
  const { registry } = bootKernel({
    win,
    kernelVersion,
    registerOps,
    onProtocolError: (payload) => protocolErrors.push(payload),
  });
  return { win, shell, registry, protocolErrors };
}

function registerAll(registry) {
  for (const op of HOST_OPS) registry.register(op, () => ({}));
}

test('契约清单：39 个 host op、7 个通知、2 个内核请求，且不重复', () => {
  assert.equal(HOST_OPS.length, 39);
  assert.equal(new Set(HOST_OPS).size, 39);
  assert.deepEqual([...NOTIFICATIONS], ['boot', 'ready', 'changed', 'stats', 'sourceMode', 'selinfo', 'jserror']);
  assert.deepEqual([...KERNEL_REQUESTS], ['resolveResources', 'importImage']);
});

test('握手：init{protocolVersion:2} → 回显 kernelVersion/protocolVersion/ops（与注册表全等）', async () => {
  const { shell } = makeKernel({ registerOps: registerAll });
  const res = await shell.request('init', V2_INIT);

  assert.equal(res.ok, true);
  assert.equal(res.payload.protocolVersion, PROTOCOL_VERSION);
  assert.equal(res.payload.kernelVersion, 'test-kernel');
  assert.deepEqual(res.payload.ops, [...HOST_OPS]);
  assert.equal(shell.notificationsOf('boot').length, 1);
});

test('握手拒绝：protocolVersion 1 → unsupported_version，之后内核停用', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({ ok: true }));
      registry.register('getState', () => ({ sourceMode: false }));
    },
  });

  const refused = await shell.request('init', { markdown: '', opts: { protocolVersion: 1 } });
  assert.equal(refused.ok, false);
  assert.equal(refused.error.code, CODES.unsupportedVersion);

  const after = await shell.request('getState', {});
  assert.equal(after.ok, false);
  assert.equal(after.error.code, CODES.unsupportedVersion);
});

test('握手缺字段：init 没带 opts.protocolVersion → bad_payload 且停用', async () => {
  const { shell } = makeKernel({ registerOps: (registry) => registry.register('init', () => ({})) });
  const res = await shell.request('init', { markdown: '', opts: {} });
  assert.equal(res.error.code, CODES.badPayload);
});

test('信封版本错配：v1 消息 → unsupported_version 响应（带原 id）', async () => {
  const { shell } = makeKernel({ registerOps: registerAll });
  shell.sendRaw({ v: 1, op: 'init', id: 'legacy-1', payload: V2_INIT });
  await tick();
  const reply = shell.responses.find((item) => item.id === 'legacy-1');
  assert.ok(reply, '必须给 v1 消息一个显式错误响应');
  assert.equal(reply.error.code, CODES.unsupportedVersion);
});

test('id 回显：两个并发请求各得各的响应', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('getMarkdown', () => ({ md: 'A' }));
      registry.register('getSaveMarkdown', () => ({ md: 'B' }));
    },
  });
  await shell.request('init', V2_INIT);
  const [a, b] = await Promise.all([
    shell.request('getMarkdown', {}),
    shell.request('getSaveMarkdown', {}),
  ]);
  assert.equal(a.payload.md, 'A');
  assert.equal(b.payload.md, 'B');
  assert.notEqual(a.id, b.id);
});

test('unknown_op：未注册的 op 显式报错，不静默丢弃', async () => {
  const { shell } = makeKernel({ registerOps: (registry) => registry.register('init', () => ({})) });
  await shell.request('init', V2_INIT);
  const res = await shell.request('deleteEverything', {});
  assert.equal(res.ok, false);
  assert.equal(res.error.code, CODES.unknownOp);
});

test('bad_payload：字段缺失或类型不对 → bad_payload 并指出字段', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('setZoom', () => ({}));
      registry.register('setCode', () => ({}));
    },
  });
  await shell.request('init', V2_INIT);

  const missing = await shell.request('setZoom', {});
  assert.equal(missing.error.code, CODES.badPayload);
  assert.match(missing.error.message, /scale/);

  const wrongType = await shell.request('setCode', { text: 42 });
  assert.equal(wrongType.error.code, CODES.badPayload);
  assert.match(wrongType.error.message, /text/);
});

test('not_ready：握手前的 gated op 显式报错；init 后可调用', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('getState', () => ({ sourceMode: false, codeMode: false }));
    },
  });

  const early = await shell.request('getState', {});
  assert.equal(early.error.code, CODES.notReady);

  await shell.request('init', V2_INIT);
  const later = await shell.request('getState', {});
  assert.equal(later.ok, true);
  assert.equal(later.payload.sourceMode, false);
});

test('通知无响应：changed 只进通知通道，不产生响应', async () => {
  const { shell, registry } = makeKernel({ registerOps: registerAll });
  await shell.request('init', V2_INIT);
  const before = shell.responses.length;

  registry.notify('changed', { dirty: true });

  assert.equal(shell.responses.length, before);
  const changed = shell.notificationsOf('changed');
  assert.equal(changed.length, 1);
  assert.equal(changed[0].payload.dirty, true);
  assert.equal(changed[0].id, undefined);
});

test('通知 payload 非法：内核侧直接抛错（不静默发半截消息）', async () => {
  const { registry } = makeKernel({ registerOps: registerAll });
  assert.throws(() => registry.notify('stats', { words: 3 }), (err) => err.code === CODES.badPayload);
});

test('handler 抛普通异常 → internal，错误消息原样上抛', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('tableInfo', () => {
        throw new Error('boom from core');
      });
    },
  });
  await shell.request('init', V2_INIT);
  const res = await shell.request('tableInfo', {});
  assert.equal(res.error.code, CODES.internal);
  assert.match(res.error.message, /boom from core/);
});

test('handler 返回非 JSON 值 → internal（防第三方对象跨桥）', async () => {
  const { shell } = makeKernel({
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('tableInfo', () => ({ rows: undefined, cols: 2 }));
    },
  });
  await shell.request('init', V2_INIT);
  const res = await shell.request('tableInfo', {});
  assert.equal(res.error.code, CODES.internal);
  assert.match(res.error.message, /non-JSON/);
});

test('内核 → 壳请求：callHost 按 id 关联，响应回填到调用方', async () => {
  let observed = null;
  const { shell } = makeKernel({
    responders: {
      resolveResources: (payload) => {
        observed = payload;
        return { resources: { 'a.png': { url: 'file:///tmp/a.png', exists: true, isImage: true } } };
      },
    },
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('print', async () => {
        const res = await registry.callHost('resolveResources', { refs: ['a.png'] });
        return { ok: true, resources: res.resources };
      });
    },
  });
  await shell.request('init', V2_INIT);

  const res = await shell.request('print', {});
  assert.deepEqual(observed, { refs: ['a.png'] });
  assert.equal(res.payload.resources['a.png'].exists, true);
  assert.equal(shell.requests.length, 1);
  assert.equal(shell.requests[0].op, 'resolveResources');
});

test('内核 → 壳请求失败：错误响应 → callHost reject，错误码保留', async () => {
  const { shell } = makeKernel({
    responders: {
      importImage: () => Promise.reject(Object.assign(new Error('disk full'), { code: 'internal' })),
    },
    registerOps: (registry) => {
      registry.register('init', () => ({}));
      registry.register('insertImage', async () => {
        await registry.callHost('importImage', { kind: 'blob', mime: 'image/png', data: 'AA==' });
        return { ok: true };
      });
    },
  });
  await shell.request('init', V2_INIT);
  const res = await shell.request('insertImage', { src: 'x' });
  assert.equal(res.ok, false);
  assert.equal(res.error.code, CODES.internal);
  assert.match(res.error.message, /disk full/);
});

test('畸形输入：非法 JSON 与非对象信封进协议错误通道，内核不崩', async () => {
  const { shell, protocolErrors } = makeKernel({ registerOps: registerAll });
  shell.raw('这不是 JSON');
  shell.raw('[]');
  await tick();
  assert.ok(protocolErrors.length >= 2);
  assert.equal(protocolErrors[0].code, CODES.badPayload);

  const res = await shell.request('init', V2_INIT);
  assert.equal(res.ok, true, '畸形输入之后内核仍可用');
});

test('无主响应：未知 id 的响应进协议错误通道，不污染 pending', async () => {
  const { shell, protocolErrors } = makeKernel({ registerOps: registerAll });
  shell.sendRaw({ v: 2, id: 'ghost', ok: true, payload: {} });
  await tick();
  assert.ok(protocolErrors.some((item) => /unknown request id/.test(item.message)));
});

test('JSON 原语守门：函数 / Map / undefined / 类实例一律拒绝', () => {
  assert.equal(isJsonValue({ a: 1, b: [true, null, 'x'] }), true);
  assert.equal(isJsonValue({ fn: () => {} }), false);
  assert.equal(isJsonValue({ map: new Map() }), false);
  assert.equal(isJsonValue({ missing: undefined }), false);
  assert.equal(isJsonValue(new Date()), false);
  assert.equal(isJsonValue({ deep: { deeper: [1, { ok: false }] } }), true);
});
