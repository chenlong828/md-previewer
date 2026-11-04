// 内核 ⇄ 壳 的端口：core 只经这两个函数与壳交互，不感知宿主实现。
// 组合根在启动时绑定一次（v2：kernel/main.js；迁移期：src/bridge.js 的 v1 适配）。
let notifier = null
let hostCaller = null

export function bindBus({ notify: notifyFn, callHost: callHostFn } = {}) {
    if (typeof notifyFn === 'function') notifier = notifyFn
    if (typeof callHostFn === 'function') hostCaller = callHostFn
}

export function notify(op, payload = {}) {
    if (!notifier) throw new Error(`kernel bus: notifier not bound (op=${op})`)
    notifier(op, payload)
}

export function hostCall(op, payload = {}) {
    if (!hostCaller) return Promise.reject(new Error(`kernel bus: host caller not bound (op=${op})`))
    return hostCaller(op, payload)
}

export function isBound() {
    return notifier !== null
}
