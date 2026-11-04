// 消息信封：构造、解码、分类。双向同构，payload 只允许 JSON 原语/数组/对象。
import { CODES, KernelError } from './errors.js';

export const PROTOCOL_VERSION = 2;

export function buildRequest(op, payload, id) {
  return { v: PROTOCOL_VERSION, op, id, payload: payload ?? {} };
}

export function buildNotification(op, payload) {
  return { v: PROTOCOL_VERSION, op, payload: payload ?? {} };
}

export function buildOk(id, payload) {
  return { v: PROTOCOL_VERSION, id, ok: true, payload: payload ?? {} };
}

export function buildError(id, code, message) {
  return { v: PROTOCOL_VERSION, id, ok: false, error: { code, message } };
}

/** 解析壳侧送来的 JSON 文本；非法文本按 bad_payload 拒绝（不静默） */
export function decode(raw) {
  if (typeof raw !== 'string') throw new KernelError(CODES.badPayload, 'message must be a JSON string');
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    throw new KernelError(CODES.badPayload, 'message is not valid JSON');
  }
  if (msg === null || typeof msg !== 'object' || Array.isArray(msg)) {
    throw new KernelError(CODES.badPayload, 'message must be a JSON object');
  }
  return msg;
}

/** response / request / notification / invalid */
export function classify(msg) {
  if (typeof msg.v !== 'number') return 'invalid';
  const hasId = typeof msg.id === 'string';
  if (hasId && typeof msg.ok === 'boolean') return 'response';
  if (hasId && typeof msg.op === 'string') return 'request';
  if (!hasId && typeof msg.op === 'string') return 'notification';
  return 'invalid';
}

/** payload 递归结构断言：只允许 JSON 原语（防第三方对象跨桥） */
export function isJsonValue(value, depth = 0) {
  if (depth > 32) return false;
  if (value === null) return true;
  const t = typeof value;
  if (t === 'string' || t === 'boolean') return true;
  if (t === 'number') return Number.isFinite(value);
  if (t === 'undefined') return false;
  if (Array.isArray(value)) return value.every((item) => isJsonValue(item, depth + 1));
  if (t === 'object') {
    const proto = Object.getPrototypeOf(value);
    if (proto !== Object.prototype && proto !== null) return false;
    return Object.values(value).every((item) => isJsonValue(item, depth + 1));
  }
  return false;
}
