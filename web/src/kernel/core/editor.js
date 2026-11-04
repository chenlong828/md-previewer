// 主题应用与编辑器装配(含源码模式切换)
import { Editor, rootCtx, editorViewCtx, editorViewOptionsCtx, remarkStringifyOptionsCtx } from '@milkdown/core'
import { commonmark } from '@milkdown/preset-commonmark'
import { gfm } from '@milkdown/preset-gfm'
import { history } from '@milkdown/plugin-history'
import { listener, listenerCtx } from '@milkdown/plugin-listener'
import { math, katexOptionsCtx } from '@milkdown/plugin-math'
import { prism, prismConfig } from '@milkdown/plugin-prism'
import { diagram } from '@milkdown/plugin-diagram'
import { clipboard } from '@milkdown/plugin-clipboard'
import { trailing } from '@milkdown/plugin-trailing'
import { getMarkdown, replaceAll } from '@milkdown/utils'
import mermaid from 'mermaid'
import { state } from '../shared/state.js'
import { currentMarkdown } from './read.js'
import { notify } from '../shared/bus.js'
import { ensureLanguages } from '../components/code/languages.js'
import { scheduleStats } from './stats.js'
import { use } from '../shared/ports.js'
import { selInfoProse } from './selinfo.js'
import { getMermaidView } from './mermaid-view.js'
import { getImageView } from './image-view.js'
import { setupImagePaste } from './image-paste.js'
import { fourSpaceListItem } from './list-indent.js'

export function applyThemeDom() {
    document.documentElement.dataset.theme = state.theme
}

export function applyMermaidTheme() {
    mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'loose',
        theme: state.theme === 'dark' ? 'dark' : 'default',
        fontFamily: 'inherit',
    })
}


// ---------- 编辑器创建 ----------

// 代码高亮语法注册(single source:web/src/languages.js)：
// 代码视图与围栏代码块共用同一 refractor 注册表。
export async function createEditor() {
    applyMermaidTheme()

    const pluginSet = state.pluginSet || 'full'
    const useDiagram = pluginSet === 'full'
    const useMath = pluginSet === 'full' || pluginSet === 'no-diagram'
    const usePrism = pluginSet === 'full' || pluginSet === 'no-diagram'

    const editor = await Editor.make()
        .config((ctx) => {
            ctx.set(rootCtx, document.getElementById('app'))
            ctx.update(
                prismConfig.key,
                () => ({
                    configureRefractor: () => {
                        ensureLanguages()
                    },
                }),
            )
            ctx.update(
                katexOptionsCtx.key,
                (prev) => ({ ...prev, throwOnError: false, strict: false }),
            )
            ctx.update(
                editorViewOptionsCtx,
                (prev) => ({
                    ...prev,
                    attributes: { ...(prev.attributes || {}), spellcheck: 'false', class: 'md-editor-view' },
                }),
            )
            ctx.update(
                remarkStringifyOptionsCtx,
                (prev) => ({
                    ...prev,
                    bullet: '-',
                    emphasis: '*',
                    strong: '*',
                    // 列表嵌套每级 4 空格(标准 Tab 等价缩进);缩进规则单点在
                    // list-indent.js,不用 mdast 的 listItemIndent:'tab'
                    // (会把首行标记也补成 "-   a"),见该文件头注释。
                    handlers: { ...(prev.handlers || {}), listItem: fourSpaceListItem },
                }),
            )
        })
        .use(commonmark)
        .use(gfm)
        .use(history)
        .use(listener)
        .use(useMath ? math : [])
        .use(usePrism ? prism : [])
        .use(useDiagram ? diagram : [])
        .use(useDiagram ? getMermaidView() : [])
        .use(getImageView())
        .use(clipboard)
        .use(trailing)
        .use(use('findService').findProsePlugin)
        .use(selInfoProse)
        .create()

    editor.action((ctx) => {
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown, _prev) => {
            // 单一脏机制:防抖窗(200ms)内的并发编辑会产生携带中间态的过期回调;
            // 只认与当前 doc 同步的序列化结果,过期回调直接丢弃——最新状态必有
            // 更新的回调跟进。基线对齐由 setMarkdown/markClean 同步保证,回调只做比对。
            if (markdown === currentMarkdown()) {
                notify('changed', { dirty: markdown !== state.baselineMarkdown })
            }
            scheduleStats()
            // 查找进行中:文档变化后刷新计数(插件 apply 已重算匹配)
            if (document.body.classList.contains('finding') && !state.sourceMode && use('findService').findUI.query) {
                queueMicrotask(() => {
                    state.editor.action((ctx2) => {
                        const view = ctx2.get(editorViewCtx)
                        const st = use('findService').findKey.getState(view.state)
                        use('findService').updateFindCount(st ? st.matches.length : 0, st ? st.current : -1)
                    })
                })
            }
        })
    })

    // 任务列表复选框:点击 li 左侧复选区域切换勾选状态
    editor.action((ctx) => {
        const view = ctx.get(editorViewCtx)
        view.dom.addEventListener('click', (event) => {
            const li = event.target.closest && event.target.closest('li[data-item-type="task"]')
            if (!li) return
            const rect = li.getBoundingClientRect()
            if (event.clientX - rect.left > 28) return // 只响应复选框区域
            try {
                const pos = view.posAtDOM(li, 0)
                const $pos = view.state.doc.resolve(pos)
                for (let d = $pos.depth; d > 0; d--) {
                    const node = $pos.node(d)
                    if (node.attrs && typeof node.attrs.checked === 'boolean') {
                        view.dispatch(view.state.tr.setNodeMarkup($pos.before(d), undefined, {
                            ...node.attrs,
                            checked: !node.attrs.checked,
                        }))
                        break
                    }
                }
            } catch (e) { /* ignore */ }
        })
    })

    state.editor = editor
    state.ready = true

    // 图片粘贴拦截(需挂在已创建的编辑器 DOM 上,捕获阶段先于 ProseMirror)
    editor.action((ctx) => {
        setupImagePaste(ctx.get(editorViewCtx))
    })

    return editor
}

// ---------- 源码模式 ----------

export function toggleSource(force) {
    const target = force === undefined ? !state.sourceMode : !!force
    if (target === state.sourceMode || !state.ready) return state.sourceMode
    const ta = document.getElementById('source-editor')
    if (target) {
        ta.value = state.editor.action(getMarkdown())
        document.body.classList.add('source-mode')
    } else {
        // 退出源码模式 = 注入 textarea 内容。若内容未偏离基线(未编辑或已保存),
        // 以注入后的序列化结果重设基线——源码原文与序列化产物的尾换行等差异不算修改;
        // 若已偏离基线,交由 listener 按旧基线比对上报脏状态。
        const wasClean = ta.value === state.baselineMarkdown
        document.body.classList.remove('source-mode')
        state.editor.action(replaceAll(ta.value))
        if (wasClean) state.baselineMarkdown = state.editor.action(getMarkdown())
    }
    state.sourceMode = target
    notify('sourceMode', { value: target })
    // 查找进行中:切换后在新界面重新搜索
    if (document.body.classList.contains('finding') && use('findService').findUI.query) {
        use('findService').runFind(use('findService').findUI.query, { caseSensitive: use('findService').findUI.caseSensitive })
    }
    return target
}
