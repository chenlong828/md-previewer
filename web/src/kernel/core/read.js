// 当前文档内容的单一真相源（core 层：序列化依赖编辑器引擎）。
// 渲染模式读编辑器 doc，源码模式读 textarea。
// 保存取回（getSaveMarkdown）与脏基线（markClean）必须走同一口径，否则源码模式下
// ⌘S 会把编辑前的旧内容写盘。
import { getMarkdown } from '@milkdown/utils'

import { state } from '../shared/state.js'

export function currentMarkdown() {
    if (state.sourceMode) return document.getElementById('source-editor').value
    if (!state.ready || !state.editor) return ''
    return state.editor.action(getMarkdown())
}
