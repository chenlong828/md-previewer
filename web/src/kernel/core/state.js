// 全局状态单例：每类全局事实只有一个权威来源。
// editor/ready/theme/zoom/mode/sourceMode/baseline 等字段在此显式声明（形状静态可见），
// 其余模块经 import 读写，不各自持有副本。本文件不含任何宿主符号（宿主经 bus.js 交互）。
import { getMarkdown } from '@milkdown/utils'

export const state = {
    editor: null,
    ready: false,
    theme: 'light',
    zoom: 1.0,
    // 视图模式状态机：'markdown' | 'code'，唯一写入口是 setMode()。
    // 代码文档与 Markdown 的互斥由状态迁移保证，不再依赖调用顺序。
    mode: 'markdown',
    // 源码模式只是 markdown 模式下的子状态（代码文档没有源码/渲染切换）
    sourceMode: false,
    // 干净基线：文件加载/保存时的序列化结果；仅当内容偏离基线才向壳上报 changed。
    // 基线由 setMarkdown/markClean 同步落定（确定性口径），不等 200ms 防抖回调。
    baselineMarkdown: '',
    // 插件档位：'full' | 'no-diagram'（由 init opts 传入，_init 先解析再建编辑器）
    pluginSet: 'full',
    // 文档所在目录（图片源码编辑框做相对路径⇄绝对 file:// 换算的基准；
    // 由 setMarkdown opts / setBaseDir 单点写入，不落副本）
    baseDir: '',
    // 只读代码视图：代码文档恒为 true；#app/#source-editor 隐藏，只显示 #code-view。
    // 派生字段：只由 setMode() 写入，读方可用 state.codeMode 或 isCodeMode()。
    codeMode: false,
    codeText: '',
    codeLanguage: '',
    codeAllowHighlight: true,
    codeTokenCount: 0,
    // 行号显示偏好：全局阅读设置（壳侧 UserDefaults 是权威，setCode 时同步过来），
    // 只影响代码视图布局；不是文档内容，不写文件、不产生 changed。
    codeLineNumbers: true,
}

/** 模式迁移唯一入口：代码视图与源码模式互斥由这里保证 */
export function setMode(mode) {
    if (mode !== 'code' && mode !== 'markdown') throw new Error(`invalid view mode: ${mode}`)
    state.mode = mode
    state.codeMode = mode === 'code'
    if (mode === 'code') state.sourceMode = false
}

export function isCodeMode() {
    return state.mode === 'code'
}

// 当前文档内容的单一真相源：渲染模式读编辑器 doc，源码模式读 textarea。
// 保存取回（getSaveMarkdown）与脏基线（markClean）必须走同一口径，否则源码模式下
// ⌘S 会把编辑前的旧内容写盘。
export function currentMarkdown() {
    if (state.sourceMode) return document.getElementById('source-editor').value
    if (!state.ready || !state.editor) return ''
    return state.editor.action(getMarkdown())
}
