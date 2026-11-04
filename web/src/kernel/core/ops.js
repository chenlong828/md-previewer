// 内核 op 处理器（唯一实现）：v2 契约的 39 个宿主 op 在此落地。
// v1 过渡层（src/bridge.js）与 v2 分发器（kernel/contract/registry）共用同一份实现，
// 差别只在返回值形状的包装——避免「两套方法体」的技术债重新长回来。
import { editorViewCtx } from '@milkdown/core'
import { TextSelection } from '@milkdown/prose/state'
import { isInTable } from '@milkdown/prose/tables'
import { undo, redo } from '@milkdown/prose/history'
import { replaceAll, insert } from '@milkdown/utils'

import { state, currentMarkdown, isCodeMode } from './state.js'
import { notify, hostCall } from './bus.js'
import { computeStats } from './stats.js'
import { createEditor, toggleSource as applySourceToggle, applyThemeDom, applyMermaidTheme } from './editor.js'
import { findKey, findUI } from './find.js'
import { openFindBar, closeFindBar, stepFind, runFind } from './find-bar.js'
import {
    showCode, hideCode, setCodeLanguage as applyCodeLanguage,
    setCodeLineNumbers as applyCodeLineNumbers, codeInfo as readCodeInfo, codeFindCount,
} from './code-view.js'
import { hasLanguage } from './languages.js'
import { tableCommandImpls } from './tables.js'
import { commandRegistry } from './commands.js'
import { exportStandaloneHTML } from './export.js'
import { extractImagePayload } from './image-paste.js'
import { applyForLoad, collectImageRefs, collectResourceRefs, restoreForSave } from '../semantics/markdown.js'

/**
 * 渲染磁盘 markdown（同步）：不做路径改写——调用方负责先经 applyForLoad 处理。
 * v1 过渡层用它（Swift 已在壳侧改写过），v2 的 setMarkdown op 在改写后也用它。
 */
export function renderMarkdown(md, { baseDir, flush = false } = {}) {
    if (!state.ready) return false
    // 不变式：回到 Markdown 文档必须退出只读代码视图（#code-view 隐藏、#app 恢复）
    hideCode()
    if (typeof baseDir === 'string') state.baseDir = baseDir
    state.editor.action(replaceAll(md || '', flush))
    // 确定性基线：同步序列化 replaceAll 落定后的 doc（与保存取回同一口径），
    // 不依赖异步回调的到达时机——并发编辑的防抖回调由 editor 的过期过滤处理
    if (!flush) state.baselineMarkdown = currentMarkdown()
    return true
}

function focusEditorView() {
    if (!state.ready) return false
    state.editor.action((ctx) => { ctx.get(editorViewCtx).focus() })
    return true
}

export function createOps() {
    const ops = {
        // ---------- 会话与文档 ----------

        /** 建编辑器并装载首篇文档；path 改写在 setMarkdown 里做（壳先作答资源） */
        async init(payload = {}) {
            const opts = payload.opts || {}
            state.pluginSet = opts.plugins || 'full'
            state.theme = opts.theme === 'dark' ? 'dark' : 'light'
            if (typeof opts.baseDir === 'string') state.baseDir = opts.baseDir
            applyThemeDom()
            if (!state.editor) await createEditor()
            if (opts.zoom) ops.setZoom({ scale: opts.zoom })
            ops.setTitle({ title: opts.title || '' })
            if (payload.markdown) await ops.setMarkdown({ md: payload.markdown, baseDir: opts.baseDir })
            notify('ready', {})
            return { ok: true }
        },

        /** 装载磁盘 markdown：先问壳每个引用的真实位置，再改写为可加载 URL */
        async setMarkdown(payload = {}) {
            const md = typeof payload.md === 'string' ? payload.md : ''
            let text = md
            if (md.length > 0) {
                const refs = collectImageRefs(md)
                if (refs.length > 0) {
                    let resources = {}
                    try {
                        const answer = await hostCall('resolveResources', { refs })
                        resources = (answer && answer.resources) || {}
                    } catch (e) {
                        // 壳未实现该请求（v1 适配）：按原文装载，缺失引用保持原样
                        console.warn('resolveResources unavailable; loading as-is', e)
                    }
                    text = applyForLoad(md, { resources })
                }
            }
            const ok = renderMarkdown(text, { baseDir: payload.baseDir, flush: payload.flush === true })
            return { ok }
        },

        getMarkdown() {
            return { md: currentMarkdown() }
        },

        /** 写盘口径：文档目录内相对化，目录外保留绝对路径 */
        getSaveMarkdown() {
            return { md: restoreForSave(currentMarkdown(), { baseDir: state.baseDir }) }
        },

        markClean() {
            if (state.ready) state.baselineMarkdown = currentMarkdown()
            return { ok: true }
        },

        setBaseDir(payload = {}) {
            state.baseDir = payload.path || ''
            return { ok: true }
        },

        setTitle(payload = {}) {
            document.title = payload.title || 'MDPreview'
            return { ok: true }
        },

        setTheme(payload = {}) {
            const target = payload.theme === 'dark' ? 'dark' : 'light'
            if (target === state.theme) return { ok: true }
            state.theme = target
            applyThemeDom()
            applyMermaidTheme()
            if (state.ready) {
                // 已渲染的 mermaid 图需要重绘（读当前内容，不用可能过期的镜像）
                state.editor.action(replaceAll(currentMarkdown()))
            }
            return { ok: true }
        },

        setZoom(payload = {}) {
            const s = Math.min(3, Math.max(0.5, payload.scale))
            state.zoom = s
            document.documentElement.style.setProperty('--app-zoom', String(s))
            return { zoom: s }
        },

        getState() {
            return {
                ready: state.ready,
                sourceMode: state.sourceMode,
                codeMode: isCodeMode(),
                theme: state.theme,
                zoom: state.zoom,
                baseDir: state.baseDir,
                title: document.title,
                code: readCodeInfo(),
            }
        },

        toggleSource(payload = {}) {
            // 代码文档没有源码/渲染切换（需求明确「代码恒为纯源码、不支持切换」）
            if (isCodeMode()) return { sourceMode: false }
            return { sourceMode: applySourceToggle(payload.force) }
        },

        focus() {
            if (isCodeMode()) {
                const view = document.getElementById('code-view')
                if (view) view.focus()
                return { ok: true }
            }
            if (state.sourceMode) {
                document.getElementById('source-editor').focus()
                return { ok: true }
            }
            return { ok: focusEditorView() }
        },

        /** 右键定位：光标移到点击处，并同步返回该处是否在表格内 */
        focusAt(payload = {}) {
            if (!state.ready) return { ok: false, inTable: false }
            return state.editor.action((ctx) => {
                const view = ctx.get(editorViewCtx)
                try {
                    const info = view.posAtCoords({ left: payload.x, top: payload.y })
                    if (!info || info.pos == null) return { ok: false, inTable: false }
                    const $pos = view.state.doc.resolve(info.pos)
                    view.dispatch(view.state.tr.setSelection(TextSelection.near($pos)))
                    let inTable = false
                    try { inTable = isInTable(view.state) } catch (e) { inTable = false }
                    return { ok: true, inTable }
                } catch (e) {
                    return { ok: false, inTable: false }
                }
            })
        },

        // ---------- 代码视图 ----------

        /** 进入只读代码视图；语言由壳（FileSupport）解析后传入 */
        setCode(payload = {}) {
            if (!state.ready) return { ok: false }
            if (state.sourceMode) applySourceToggle(false)
            showCode(payload.text || '', {
                language: typeof payload.language === 'string' ? payload.language : 'plaintext',
                allowHighlight: payload.allowHighlight !== false,
                lineNumbers: typeof payload.lineNumbers === 'boolean' ? payload.lineNumbers : undefined,
            })
            if (document.body.classList.contains('finding') && findUI.query) {
                runFind(findUI.query, { caseSensitive: findUI.caseSensitive })
            }
            return { ok: true }
        },

        setCodeLanguage(payload = {}) {
            const ok = applyCodeLanguage(typeof payload.id === 'string' ? payload.id : 'plaintext')
            if (ok && document.body.classList.contains('finding') && findUI.query) {
                runFind(findUI.query, { caseSensitive: findUI.caseSensitive })
            }
            return { ok }
        },

        setCodeLineNumbers(payload = {}) {
            return { ok: applyCodeLineNumbers(payload.visible === true) }
        },

        codeInfo() {
            return readCodeInfo()
        },

        hasLanguages(payload = {}) {
            const ids = Array.isArray(payload.ids) ? payload.ids : []
            return { supported: ids.filter((id) => hasLanguage(id)) }
        },

        // ---------- 命令 ----------

        undo() {
            if (state.ready) {
                state.editor.action((ctx) => {
                    const view = ctx.get(editorViewCtx)
                    undo(view.state, view.dispatch, view)
                })
            }
            return { ok: true }
        },

        redo() {
            if (state.ready) {
                state.editor.action((ctx) => {
                    const view = ctx.get(editorViewCtx)
                    redo(view.state, view.dispatch, view)
                })
            }
            return { ok: true }
        },

        requestStats() {
            notify('stats', computeStats(currentMarkdown()))
            return { ok: true }
        },

        /** 通过命令名调用预设命令（原生菜单） */
        formatCommand(payload = {}) {
            if (!state.ready) return { applied: false }
            const cmd = commandRegistry[payload.name]
            if (!cmd || typeof cmd.run !== 'function') {
                console.warn('formatCommand: unknown or unregistered command:', payload.name)
                return { applied: false }
            }
            try {
                return { applied: cmd.run(payload.payload) !== false }
            } catch (e) {
                console.warn('formatCommand failed', payload.name, e)
                return { applied: false }
            }
        },

        tableCommand(payload = {}) {
            const impl = tableCommandImpls[payload.name]
            if (!state.ready || !impl) return { applied: false }
            return { applied: state.editor.action((ctx) => {
                const view = ctx.get(editorViewCtx)
                try {
                    return impl(view) === true
                } catch (e) {
                    console.warn('tableCommand failed', payload.name, e)
                    return false
                }
            }) }
        },

        insertTable(payload = {}) {
            if (!state.ready) return { ok: false }
            const applied = ops.formatCommand({
                name: 'insertTableCommand',
                payload: { row: payload.row || 3, col: payload.col || 3 },
            }).applied
            if (!applied) return { ok: false }
            // 把光标放进新表格的首个单元格（插入后光标可能留在外部，或为整表 CellSelection）
            state.editor.action((ctx) => {
                const view = ctx.get(editorViewCtx)
                try {
                    const $from = view.state.selection.$from
                    let target = null
                    view.state.doc.descendants((node, pos) => {
                        if (target == null && node.type.name === 'table' && pos >= $from.pos - 2) target = pos
                    })
                    if (target == null) return
                    view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(target + 1), 1)))
                } catch (e) { /* 定位失败不影响插入 */ }
            })
            return { ok: true }
        },

        insertMarkdown(payload = {}) {
            if (!state.ready) return { ok: false }
            state.editor.action(insert(payload.md || ''))
            return { ok: true }
        },

        insertImage(payload = {}) {
            return { applied: ops.formatCommand({
                name: 'insertImageCommand',
                payload: { src: payload.src || '', alt: payload.alt || '', title: payload.title || '' },
            }).applied }
        },

        // ---------- 查找 ----------

        openFindBar() {
            openFindBar()
            return { ok: true }
        },

        closeFindBar() {
            closeFindBar()
            return { ok: true }
        },

        findNext() {
            stepFind(1)
            return { ok: true }
        },

        findPrev() {
            stepFind(-1)
            return { ok: true }
        },

        findInfo() {
            const active = document.body.classList.contains('finding')
            if (isCodeMode()) return { active, query: findUI.query, count: codeFindCount() }
            return {
                active,
                query: findUI.query,
                // count 恒为数字；-1 表示编辑器未就绪
                count: state.sourceMode ? findUI.srcMatches.length : (state.ready ? (() => {
                    try {
                        return state.editor.action((ctx) => {
                            const st = findKey.getState(ctx.get(editorViewCtx).state)
                            return st ? st.matches.length : 0
                        })
                    } catch (e) { return -1 }
                })() : -1),
            }
        },

        // ---------- 输出 ----------

        async exportStandaloneHTML() {
            return { html: await exportStandaloneHTML() }
        },

        print() {
            window.print()
            return { ok: true }
        },

        /** 供壳校准 PDF 页面几何：内容区尺寸（CSS 像素） */
        getContentSize() {
            const root = document.documentElement
            return { width: root.scrollWidth, height: root.scrollHeight }
        },

        // ---------- 资源 ----------

        /** GC 引用收集：宁多保护不误删（壳回答每个引用的全部存在路径） */
        async getResourceRefs() {
            const md = currentMarkdown()
            const refs = collectImageRefs(md)
            let resources = {}
            if (refs.length > 0) {
                try {
                    const answer = await hostCall('resolveResources', { refs })
                    resources = (answer && answer.resources) || {}
                } catch (e) {
                    console.warn('resolveResources unavailable; no refs collected', e)
                }
            }
            return { paths: collectResourceRefs(md, { resources }) }
        },

        // ---------- 诊断档 ----------

        hasCommands(payload = {}) {
            const names = Array.isArray(payload.names) ? payload.names : []
            return { results: names.map((n) => ({
                name: n,
                ok: typeof commandRegistry[n]?.run === 'function' || typeof tableCommandImpls[n] === 'function',
            })) }
        },

        debugFocusTable() {
            if (!state.ready) return { ok: false }
            return { ok: state.editor.action((ctx) => {
                const view = ctx.get(editorViewCtx)
                try {
                    let target = null
                    view.state.doc.descendants((node, pos) => {
                        if (target == null && node.type.name === 'table') target = pos
                    })
                    if (target == null) return false
                    view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(target + 1), 1)))
                    return true
                } catch (e) { return false }
            }) }
        },

        tableInfo() {
            if (!state.ready) return { inTable: false }
            return state.editor.action((ctx) => {
                const view = ctx.get(editorViewCtx)
                let inTable = false
                try { inTable = isInTable(view.state) } catch (e) { inTable = false }
                if (!inTable) return { inTable: false }
                const $from = view.state.selection.$from
                for (let d = $from.depth; d > 0; d--) {
                    if ($from.node(d).type.name === 'table') {
                        const header = $from.node(d).firstChild
                        return { inTable: true, rows: $from.node(d).childCount, cols: header ? header.childCount : 0 }
                    }
                }
                return { inTable: true }
            })
        },

        testImagePayload(payload = {}) {
            const result = extractImagePayload(payload.data)
            return { payload: result ? { kind: result.kind, path: result.path || '' } : null }
        },
    }
    return ops
}
