// 消息泵：op 注册与分发、id 关联、版本握手、错误码。
// 契约不变量：响应必回显请求 id；通知无响应；payload 只含 JSON 原语；单通道串行。
import {
  PROTOCOL_VERSION, buildError, buildNotification, buildOk, buildRequest, classify, decode, isJsonValue,
} from './envelope.js';
import { CODES, KernelError, errorPayload } from './errors.js';
import { validateNotification, validatePayload } from './ops.js';

// init 是唯一允许在 ready 前调用的 op（握手本身）
const READY_EXEMPT = new Set(['init']);

export function createRegistry({ transport, kernelVersion = 'unknown', protocolVersion = PROTOCOL_VERSION, onProtocolError } = {}) {
  if (!transport || typeof transport.send !== 'function') {
    throw new Error('registry: transport with send() is required');
  }

  const handlers = new Map();
  const pending = new Map();
  let ready = false;
  let disabled = false;
  let seq = 0;

  const report = (err) => {
    const payload = errorPayload(err);
    if (typeof onProtocolError === 'function') onProtocolError(payload);
    else console.error(`kernel contract error: ${payload.code} ${payload.message}`);
  };

  function nextId(prefix) {
    seq += 1;
    return `${prefix}${seq}`;
  }

  function register(op, handler, { readyGated = true } = {}) {
    if (typeof op !== 'string' || op.length === 0) throw new Error('register: op must be a non-empty string');
    if (typeof handler !== 'function') throw new Error(`register(${op}): handler must be a function`);
    handlers.set(op, { handler, readyGated });
    return registry;
  }

  function ops() {
    return [...handlers.keys()];
  }

  function isReady() {
    return ready;
  }

  function settlePending(msg) {
    const entry = pending.get(msg.id);
    if (!entry) {
      report(new KernelError(CODES.badPayload, `response for unknown request id: ${msg.id}`));
      return;
    }
    pending.delete(msg.id);
    if (msg.ok) {
      // 空响应也必须给对象，壳侧统一按字典取
      entry.resolve(msg.payload === undefined ? {} : msg.payload);
    } else {
      const code = msg.error && msg.error.code ? msg.error.code : CODES.internal;
      const message = msg.error && msg.error.message ? msg.error.message : 'kernel request failed';
      entry.reject(new KernelError(code, message));
    }
  }

  function assertHandshake(payload) {
    const opts = payload && payload.opts;
    const claimed = opts ? opts.protocolVersion : undefined;
    if (claimed === undefined) {
      disabled = true;
      throw new KernelError(CODES.badPayload, 'init.opts.protocolVersion is required');
    }
    if (claimed !== protocolVersion) {
      disabled = true;
      throw new KernelError(
        CODES.unsupportedVersion,
        `shell protocolVersion ${claimed} != kernel ${protocolVersion}`,
      );
    }
  }

  async function handleIncoming(msg, kind) {
    const isRequest = kind === 'request';
    try {
      if (disabled) throw new KernelError(CODES.unsupportedVersion, 'kernel disabled after handshake failure');
      const entry = handlers.get(msg.op);
      if (!entry) throw new KernelError(CODES.unknownOp, `unknown op: ${msg.op}`);
      if (entry.readyGated && !ready && !READY_EXEMPT.has(msg.op)) {
        throw new KernelError(CODES.notReady, `kernel not ready: ${msg.op}`);
      }
      if (msg.op === 'init') assertHandshake(msg.payload);
      const badField = validatePayload(msg.op, msg.payload);
      if (badField) throw new KernelError(CODES.badPayload, `bad payload for ${msg.op}: ${badField}`);
      const result = await entry.handler(msg.payload ?? {}, { id: msg.id });
      const payload = result === undefined || result === null ? {} : result;
      if (!isJsonValue(payload)) {
        throw new KernelError(CODES.internal, `${msg.op} returned a non-JSON payload`);
      }
      if (!isRequest) return; // 通知：无响应
      if (msg.op === 'init') {
        ready = true;
        transport.send(buildOk(msg.id, {
          ...payload,
          kernelVersion,
          protocolVersion,
          ops: ops(),
        }));
        return;
      }
      transport.send(buildOk(msg.id, payload));
    } catch (err) {
      if (isRequest) {
        const { code, message } = errorPayload(err);
        transport.send(buildError(msg.id, code, message));
      } else {
        report(err);
      }
    }
  }

  /** 壳 → 内核唯一入口；永不抛出（壳侧是 fire-and-forget 调用） */
  async function receive(raw) {
    let msg;
    try {
      msg = decode(raw);
    } catch (err) {
      // 连 id 都没有，无法应答：只进协议错误通道
      report(err);
      return;
    }
    if (msg.v !== protocolVersion) {
      if (typeof msg.id === 'string') {
        transport.send(buildError(msg.id, CODES.unsupportedVersion, `envelope v${msg.v} != ${protocolVersion}`));
      } else {
        report(new KernelError(CODES.unsupportedVersion, `notification envelope v${msg.v} != ${protocolVersion}`));
      }
      return;
    }
    const kind = classify(msg);
    if (kind === 'invalid') {
      if (typeof msg.id === 'string') {
        transport.send(buildError(msg.id, CODES.badPayload, 'invalid envelope'));
      } else {
        report(new KernelError(CODES.badPayload, 'invalid envelope'));
      }
      return;
    }
    if (kind === 'response') {
      settlePending(msg);
      return;
    }
    await handleIncoming(msg, kind);
  }

  /** 内核 → 壳通知；payload 非法是内核 bug，直接暴露（不静默发半截消息） */
  function notify(op, payload = {}) {
    const badField = validateNotification(op, payload);
    if (badField) throw new KernelError(CODES.badPayload, `bad notification ${op}: ${badField}`);
    if (!isJsonValue(payload)) throw new KernelError(CODES.internal, `notification ${op} has non-JSON payload`);
    transport.send(buildNotification(op, payload));
  }

  /** 内核 → 壳请求；调用方决定超时与取消语义（协议层不设超时） */
  function callHost(op, payload = {}) {
    const id = nextId('h');
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      try {
        transport.send(buildRequest(op, payload, id));
      } catch (err) {
        pending.delete(id);
        reject(err);
      }
    });
  }

  function shutdown() {
    for (const entry of pending.values()) entry.reject(new KernelError(CODES.internal, 'kernel shutdown'));
    pending.clear();
    handlers.clear();
  }

  const registry = { register, ops, isReady, receive, notify, callHost, shutdown, protocolVersion, kernelVersion };
  return registry;
}
