// 全局状态单例与原生消息通道。
// 每类全局事实只有一个权威来源:editor/ready/theme/zoom/sourceMode/baseline 等字段
// 在此显式声明(形状静态可见),其余模块经 import 读写,不各自持有副本。
import { getMarkdown } from '@milkdown/utils'

export const state = {
    editor: null,
    ready: false,
    theme: 'light',
    zoom: 1.0,
    sourceMode: false,
    lastMarkdown: '',
    // 干净基线:文件加载/保存时的序列化结果;仅当内容偏离基线才向原生上报 changed。
    // 基线由 setMarkdown/markClean 同步落定(确定性口径),不等 200ms 防抖回调。
    baselineMarkdown: '',
    // 插件档位:'full' | 'no-diagram'(由 init opts 传入,_init 先解析再建编辑器)
    pluginSet: 'full',
    // 文档所在目录(图片源码编辑框做 相对路径⇄绝对 file:// 换算的基准;
    // 由 setMarkdown opts / setBaseDir 单点写入,不落副本)
    baseDir: '',
    // 只读代码视图:代码文档恒为 true;#app/#source-editor 隐藏,只显示 #code-view。
    // 与 sourceMode 互斥(代码文档没有源码/渲染切换)。
    codeMode: false,
    codeText: '',
    codeLanguage: '',
    codeAllowHighlight: true,
    codeTokenCount: 0,
}

// 当前文档内容的单一真相源:渲染模式读编辑器 doc,源码模式读 textarea。
// 保存取回(getMarkdown)与干净基线(markClean)必须走同一口径,否则源码模式下
// ⌘S 会把编辑前的旧内容写盘。
export function currentMarkdown() {
    if (state.sourceMode) return document.getElementById('source-editor').value
    if (!state.ready || !state.editor) return ''
    return state.editor.action(getMarkdown())
}

export const post = (msg) => {
    try {
        window.webkit?.messageHandlers?.mdbridge?.postMessage(msg)
    } catch (e) {
        console.warn('postMessage failed', e)
    }
}
