// v2 页面入口：装配内核（transport → contract → core ops）并接上核心端口。
// 壳必须在本 bundle 求值前注入 window.__mdHostChannel.post（见 KernelClient.installScript）。
import './typora.css'
import '@milkdown/prose/view/style/prosemirror.css'
import '@milkdown/prose/tables/style/tables.css'
import 'katex/dist/katex.min.css'

import { bootKernel } from './kernel/main.js'
import { createKernelOps } from './kernel/assemble.js'
import { bindBus, notify } from './kernel/shared/bus.js'

import { scheduleStats } from './kernel/components/editor/stats.js'
import { installV1Shim } from './v1-shim.js'

export const KERNEL_VERSION = '0.1.0'

// 组件端口接线（组合根职责）：组件之间不互相 import
const { ops, findService } = createKernelOps()

const kernel = bootKernel({
    win: window,
    kernelVersion: KERNEL_VERSION,
    registerOps: (registry) => {
        for (const [op, handler] of Object.entries(ops)) {
            registry.register(op, handler)
        }
    },
    onProtocolError: (payload) => {
        // 契约错误只应出现在开发期：这是「静默降级」的替代——可见地报出来
        console.error(`kernel protocol error: ${payload.code} ${payload.message}`)
    },
})

// 内核端口接上契约分发：core 的 notify/hostCall 全部经 registry 走 v2 信封
bindBus({
    notify: (op, payload) => kernel.registry.notify(op, payload),
    callHost: (op, payload) => kernel.registry.callHost(op, payload),
})

// 自检/截图环境才装 v1 方法面（产品 bundle 不暴露 window.mdbridge）
if (window.__MDP_TEST__ === true) installV1Shim()
findService.setupFindBar()

// 源码模式 textarea 编辑 → 脏状态 + 统计（与渲染模式同一口径）
document.getElementById('source-editor').addEventListener('input', () => {
    notify('changed', { dirty: true })
    scheduleStats()
})
