// 渲染入口（跨切片共用）：把磁盘 markdown 落到编辑器，并维护确定性基线。
// 不做路径改写——调用方负责先经 applyForLoad 处理。
import { editorViewCtx } from '@milkdown/core'
import { replaceAll } from '@milkdown/utils'

import { state } from '../shared/state.js'
import { currentMarkdown } from './read.js'
import { hideCode } from '../components/code/code-view.js'

/**
 * 渲染磁盘 markdown（同步）。
 * 不变式：回到 Markdown 文档必须退出只读代码视图（#code-view 隐藏、#app 恢复）。
 */
export function renderMarkdown(md, { baseDir, flush = false } = {}) {
    if (!state.ready) return false
    hideCode()
    if (typeof baseDir === 'string') state.baseDir = baseDir
    state.editor.action(replaceAll(md || '', flush))
    // 确定性基线：同步序列化 replaceAll 落定后的 doc（与保存取回同一口径），
    // 不依赖异步回调的到达时机——并发编辑的防抖回调由 editor 的过期过滤处理
    if (!flush) state.baselineMarkdown = currentMarkdown()
    return true
}

/** 把焦点交给 ProseMirror（编辑面内部使用） */
export function focusEditorView() {
    if (!state.ready) return false
    state.editor.action((ctx) => { ctx.get(editorViewCtx).focus() })
    return true
}
