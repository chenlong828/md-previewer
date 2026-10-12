// 入口:样式装配、查找栏 wiring、启动消息。职责模块见同目录各文件
// (state/stats/editor/find/find-bar/tables/selinfo/mermaid-view/export/bridge)。
import './bridge.js'
import { post } from './state.js'
import { scheduleStats } from './stats.js'
import { setupFindBar } from './find-bar.js'

// ProseMirror 基础样式统一从 @milkdown/prose 取(禁止独立 prosemirror-* 来源)
import '@milkdown/prose/view/style/prosemirror.css'
import '@milkdown/prose/tables/style/tables.css'
import 'katex/dist/katex.min.css'
import 'prismjs/themes/prism.css'
import './typora.css'

// 源码模式 textarea 编辑 → 标记脏状态
document.getElementById('source-editor').addEventListener('input', () => {
    post({ op: 'changed' })
    scheduleStats()
})

setupFindBar()

// 通知原生:页面脚本已就绪
post({ op: 'boot' })
