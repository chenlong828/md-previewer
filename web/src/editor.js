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
import dart from 'refractor/dart'
import docker from 'refractor/docker'
import graphql from 'refractor/graphql'
import scala from 'refractor/scala'
import toml from 'refractor/toml'
import powershell from 'refractor/powershell'
import haskell from 'refractor/haskell'
import groovy from 'refractor/groovy'
import protobuf from 'refractor/protobuf'
import elixir from 'refractor/elixir'
import mermaid from 'mermaid'
import { state, post, currentMarkdown } from './state.js'
import { scheduleStats } from './stats.js'
import { findKey, findUI, findProsePlugin } from './find.js'
import { updateFindCount, runFind } from './find-bar.js'
import { selInfoProse } from './selinfo.js'
import { getMermaidView } from './mermaid-view.js'
import { getImageView } from './image-view.js'
import { setupImagePaste } from './image-paste.js'

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

const extraLanguages = [dart, docker, graphql, scala, toml, powershell, haskell, groovy, protobuf, elixir]

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
                    configureRefractor: (ref) => {
                        for (const lang of extraLanguages) {
                            try { ref.register(lang) } catch (e) { /* 已注册或不存在 */ }
                        }
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
                (prev) => ({ ...prev, bullet: '-', emphasis: '*', strong: '*', listItemIndent: 'one' }),
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
        .use(findProsePlugin)
        .use(selInfoProse)
        .create()

    editor.action((ctx) => {
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown, _prev) => {
            state.lastMarkdown = markdown
            // 单一脏机制:防抖窗(200ms)内的并发编辑会产生携带中间态的过期回调;
            // 只认与当前 doc 同步的序列化结果,过期回调直接丢弃——最新状态必有
            // 更新的回调跟进。基线对齐由 setMarkdown/markClean 同步保证,回调只做比对。
            if (markdown === currentMarkdown()) {
                post({ op: 'changed', dirty: markdown !== state.baselineMarkdown })
            }
            scheduleStats()
            // 查找进行中:文档变化后刷新计数(插件 apply 已重算匹配)
            if (document.body.classList.contains('finding') && !state.sourceMode && findUI.query) {
                queueMicrotask(() => {
                    state.editor.action((ctx2) => {
                        const view = ctx2.get(editorViewCtx)
                        const st = findKey.getState(view.state)
                        updateFindCount(st ? st.matches.length : 0, st ? st.current : -1)
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
    post({ op: 'sourceMode', value: target })
    // 查找进行中:切换后在新界面重新搜索
    if (document.body.classList.contains('finding') && findUI.query) {
        runFind(findUI.query, { caseSensitive: findUI.caseSensitive })
    }
    return target
}
