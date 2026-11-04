// 页面入口（v1 过渡）：样式装配、查找栏 wiring、启动消息。
// 内核能力在 kernel/core；v2 页面入口在 T5 切换为 page.js + kernel/main.js。
import './bridge.js'
import { notify } from './kernel/core/bus.js'
import { scheduleStats } from './kernel/core/stats.js'
import { setupFindBar } from './kernel/core/find-bar.js'

// ProseMirror 基础样式统一从 @milkdown/prose 取(禁止独立 prosemirror-* 来源)
import '@milkdown/prose/view/style/prosemirror.css'
import '@milkdown/prose/tables/style/tables.css'
import 'katex/dist/katex.min.css'
// 代码高亮 token 调色板在 typora.css 内自持(唯一真源),不引入第三方整份主题:
// 整份主题是浅色的,深色只能逐条打补丁,漏项会回落成浅色(token 白底缺陷成因)。
import './typora.css'

// 源码模式 textarea 编辑 → 标记脏状态
document.getElementById('source-editor').addEventListener('input', () => {
    notify('changed', { dirty: true })
    scheduleStats()
})

setupFindBar()

// 通知原生:页面脚本已就绪
notify('boot', {})
