// 桥协议 v2 错误码：契约面只允许这五个码（可扩充 = 版本变更）
export const CODES = Object.freeze({
  unknownOp: 'unknown_op',
  badPayload: 'bad_payload',
  notReady: 'not_ready',
  unsupportedVersion: 'unsupported_version',
  internal: 'internal',
});

const VALID = new Set(Object.values(CODES));

export class KernelError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'KernelError';
    this.code = VALID.has(code) ? code : CODES.internal;
  }
}

/** 任意异常 → 契约错误信封；非 KernelError 一律 internal（不把实现细节漏成错误码） */
export function errorPayload(err) {
  const code = err instanceof KernelError ? err.code : CODES.internal;
  const message = err && typeof err.message === 'string' ? err.message : String(err);
  return { code, message };
}
