// 传输层：内核唯一的宿主感知点（防腐层）。
// 壳必须在内核 bundle 求值前注入 window.__mdHostChannel.post(json)；
// 内核只暴露 window.__mdKernel.receive(json) 这一个入口。
export function createTransport({ win = globalThis } = {}) {
  const channel = win.__mdHostChannel;
  if (!channel || typeof channel.post !== 'function') {
    // 严格失败：缺 channel 时 boot 必须可见地挂掉，不静默降级
    throw new Error('kernel transport: window.__mdHostChannel.post is required before kernel evaluation');
  }

  let receive = null;

  function send(message) {
    if (message === null || typeof message !== 'object' || Array.isArray(message)) {
      throw new Error('kernel transport: send() expects a message object');
    }
    channel.post(JSON.stringify(message));
  }

  function expose(handler) {
    if (typeof handler !== 'function') throw new Error('kernel transport: expose() expects a function');
    receive = handler;
    win.__mdKernel = Object.freeze({ receive: (json) => receive(json) });
  }

  /** jserror 三源（onerror / console.error / unhandledrejection）迁自 index.html 内联脚本 */
  function installErrorHooks(report) {
    if (typeof report !== 'function') return () => {};

    const cleanups = [];
    const add = (target, type, listener) => {
      if (target && typeof target.addEventListener === 'function') {
        target.addEventListener(type, listener);
        cleanups.push(() => target.removeEventListener(type, listener));
      }
    };

    add(win, 'error', (event) => {
      const err = event && event.error;
      report({
        message: (event && event.message) || (err && err.message) || 'unknown error',
        where: 'window.onerror',
        stack: err && err.stack ? err.stack : undefined,
      });
    });
    add(win, 'unhandledrejection', (event) => {
      const reason = event ? event.reason : undefined;
      report({
        message: `UnhandledRejection: ${reason && reason.message ? reason.message : String(reason)}`,
        where: 'unhandledrejection',
        stack: reason && reason.stack ? reason.stack : undefined,
      });
    });

    const consoleObj = win.console;
    if (consoleObj && typeof consoleObj.error === 'function') {
      const original = consoleObj.error;
      const patched = (...args) => {
        try {
          report({ message: args.map((arg) => (arg && arg.message) || String(arg)).join(' '), where: 'console.error' });
        } finally {
          original.apply(consoleObj, args);
        }
      };
      consoleObj.error = patched;
      cleanups.push(() => { consoleObj.error = original; });
    }

    return () => cleanups.forEach((fn) => fn());
  }

  return { send, expose, installErrorHooks, hasReceive: () => typeof receive === 'function' };
}
