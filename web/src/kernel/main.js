// 内核组合根：装配 transport → 建 contract → 注册 op → 发 boot。
// 只做装配与顺序，不含任何编辑能力（能力由 core 注册）。
import { PROTOCOL_VERSION } from './contract/envelope.js';
import { createRegistry } from './contract/registry.js';
import { createTransport } from './transport/channel.js';

export function bootKernel({ win = globalThis, kernelVersion = 'unknown', registerOps, onProtocolError } = {}) {
  const transport = createTransport({ win });
  const registry = createRegistry({ transport, kernelVersion, onProtocolError });

  transport.expose((json) => registry.receive(json));
  const uninstallHooks = transport.installErrorHooks((payload) => {
    try {
      registry.notify('jserror', payload);
    } catch {
      // 诊断通道自身不能成为新的失败源
    }
  });

  if (typeof registerOps === 'function') registerOps(registry, { transport, win });

  registry.notify('boot', {});
  return { registry, transport, stop: uninstallHooks };
}

export { PROTOCOL_VERSION };
