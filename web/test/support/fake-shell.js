// 测试用宿主替身：注入 __mdHostChannel、应答内核请求、按 id 回填响应。
// 它同时就是「最小壳」参照实现（Windows 壳按同一语义实现，见 spec-delta §6.1）。
export class FakeShell {
  constructor({ responders = {}, kernelVersion = 'test-kernel' } = {}) {
    this.responders = responders;
    this.kernelVersion = kernelVersion;
    this.win = null;
    this.seq = 0;
    this.pending = new Map();
    this.responses = [];
    this.notifications = [];
    this.requests = [];
    this.malformed = [];
  }

  install(win) {
    this.win = win;
    win.__mdHostChannel = { post: (json) => this._receiveFromKernel(json) };
    return this;
  }

  _receiveFromKernel(raw) {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      this.malformed.push(raw);
      return;
    }
    if (!msg || typeof msg !== 'object') {
      this.malformed.push(raw);
      return;
    }
    const hasId = typeof msg.id === 'string';
    const hasOp = typeof msg.op === 'string';
    if (hasId && !hasOp) {
      this.responses.push(msg);
      this._settle(msg);
      return;
    }
    if (hasOp && hasId) {
      this.requests.push(msg);
      this._answer(msg);
      return;
    }
    if (hasOp) {
      this.notifications.push(msg);
      return;
    }
    this.malformed.push(raw);
  }

  _settle(msg) {
    const entry = this.pending.get(msg.id);
    if (!entry) return;
    this.pending.delete(msg.id);
    clearTimeout(entry.timer);
    entry.resolve(msg);
  }

  _answer(msg) {
    const responder = this.responders[msg.op];
    const ok = (payload) => this._deliver({ v: 2, id: msg.id, ok: true, payload: payload ?? {} });
    const fail = (code, message) => this._deliver({ v: 2, id: msg.id, ok: false, error: { code, message } });
    if (typeof responder !== 'function') {
      fail('unknown_op', `fake shell has no responder for ${msg.op}`);
      return;
    }
    Promise.resolve()
      .then(() => responder(msg.payload, msg))
      .then((payload) => ok(payload))
      .catch((err) => fail(err && err.code ? err.code : 'internal', err && err.message ? err.message : String(err)));
  }

  _deliver(obj) {
    this.win.__mdKernel.receive(JSON.stringify(obj));
  }

  /** 壳发请求（带 id，等响应） */
  request(op, payload = {}, { timeoutMs = 5000 } = {}) {
    const id = `s${++this.seq}`;
    const msg = { v: 2, op, id, payload };
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`fake shell request timeout: ${op}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, timer });
      this.win.__mdKernel.receive(JSON.stringify(msg));
    });
  }

  /** 发原始文本（非法 JSON 场景） */
  raw(text) {
    this.win.__mdKernel.receive(text);
  }

  /** 发任意信封（版本错配 / 畸形信封场景） */
  sendRaw(obj) {
    this.win.__mdKernel.receive(JSON.stringify(obj));
  }

  notificationsOf(op) {
    return this.notifications.filter((item) => item.op === op);
  }
}
