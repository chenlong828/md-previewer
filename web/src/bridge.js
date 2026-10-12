// 桥接 API:window.mdbridge 是 Swift 壳调用的唯一入口表面。
// Swift↔JS 命令名的 JS 侧权威见 commands.js 与 tables.js。
import { editorViewCtx } from '@milkdown/core'
import { TextSelection } from '@milkdown/prose/state'
import { isInTable } from '@milkdown/prose/tables'
import { undo, redo } from 'prosemirror-history'
import { replaceAll, insert } from '@milkdown/utils'
import { state, post, currentMarkdown } from './state.js'
import { computeStats } from './stats.js'
import { createEditor, toggleSource, applyThemeDom, applyMermaidTheme } from './editor.js'
import { findKey, findUI } from './find.js'
import { openFindBar, closeFindBar, stepFind } from './find-bar.js'
import { tableCommandImpls } from './tables.js'
import { commandRegistry } from './commands.js'
import { exportStandaloneHTML } from './export.js'

window.mdbridge = {
    async init(markdown, opts = {}) {
        try {
            return await this._init(markdown, opts)
        } catch (e) {
            post({ op: 'jserror', message: 'init failed: ' + (e && e.message ? e.message : String(e)), stack: e && e.stack ? String(e.stack) : '' })
            throw e
        }
    },

    async _init(markdown, opts = {}) {
        // 先解析配置(theme/zoom/plugins/title)再创建编辑器:
        // 首帧 DOM 与 mermaid 都按目标主题初始化,pluginSet 条件加载真正可达。
        state.pluginSet = opts.plugins || 'full'
        state.theme = opts.theme === 'dark' ? 'dark' : 'light'
        applyThemeDom()
        if (!state.editor) await createEditor()
        if (opts.zoom) this.setZoom(opts.zoom)
        this.setTitle(opts.title || '')
        if (markdown) {
            this.setMarkdown(markdown)
        }
        post({ op: 'ready' })
        return 'ok'
    },

    setMarkdown(md, flush = false) {
        if (!state.ready) return
        state.suppressChange = true
        state.pendingBaseline = true
        try {
            state.editor.action(replaceAll(md || '', flush))
        } finally {
            queueMicrotask(() => { state.suppressChange = false })
        }
    },

    /** 保存成功后由原生调用:以当前所见内容为新基线(源码模式下即 textarea 内容) */
    markClean() {
        if (state.ready) state.baselineMarkdown = currentMarkdown()
        state.pendingBaseline = false
        return true
    },

    getMarkdown() {
        return currentMarkdown()
    },

    /** 原生在文件名变化时同步 web 层 document.title(HTML 导出标题的来源) */
    setTitle(title) {
        document.title = title || 'MDPreview'
        return true
    },

    setTheme(mode) {
        const target = mode === 'dark' ? 'dark' : 'light'
        if (target === state.theme) return
        state.theme = target
        applyThemeDom()
        applyMermaidTheme()
        if (state.ready) {
            // 已渲染的 mermaid 图需要重绘
            state.editor.action(replaceAll(state.lastMarkdown))
        }
    },

    setZoom(scale) {
        const s = Math.min(3, Math.max(0.5, scale))
        state.zoom = s
        document.documentElement.style.setProperty('--app-zoom', String(s))
        return s
    },

    getZoom() { return state.zoom },

    toggleSource(force) { return toggleSource(force) },

    /** 表格行列命令 */
    tableCommand(name) {
        const impl = tableCommandImpls[name]
        if (!state.ready || !impl) return false
        return state.editor.action((ctx) => {
            const view = ctx.get(editorViewCtx)
            try {
                return impl(view)
            } catch (e) {
                console.warn('tableCommand failed', name, e)
                return false
            }
        })
    },

    /** 右键定位:把光标移到点击处(原生文本行为),并同步返回该处是否在表格内 */
    focusAt(x, y) {
        if (!state.ready) return { ok: false, inTable: false }
        return state.editor.action((ctx) => {
            const view = ctx.get(editorViewCtx)
            try {
                const info = view.posAtCoords({ left: x, top: y })
                if (!info || info.pos == null) return { ok: false, inTable: false }
                const $pos = view.state.doc.resolve(info.pos)
                view.dispatch(view.state.tr.setSelection(TextSelection.near($pos)))
                // inTable 判定与右键菜单/表格命令同源(prosemirror-tables isInTable)
                let inTable = false
                try { inTable = isInTable(view.state) } catch (e) { inTable = false }
                return { ok: true, inTable }
            } catch (e) {
                return { ok: false, inTable: false }
            }
        })
    },

    /** 测试辅助:把光标放进文档第一张表格的首个单元格 */
    debugFocusTable() {
        if (!state.ready) return false
        return state.editor.action((ctx) => {
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
        })
    },

    /** 测试诊断:光标处表格信息。inTable 判定同源 isInTable;行列数仅辅助自检 */
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

    /** 文档内查找 */
    openFindBar() {
        openFindBar()
        return true
    },
    closeFindBar() {
        closeFindBar()
        return true
    },
    findNext() {
        stepFind(1)
        return true
    },
    findPrev() {
        stepFind(-1)
        return true
    },
    findInfo() {
        return {
            active: document.body.classList.contains('finding'),
            query: findUI.query,
            // count 恒为数字;-1 表示编辑器未就绪
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
    isSourceMode() { return state.sourceMode },

    undo() {
        if (!state.ready) return
        state.editor.action((ctx) => {
            const view = ctx.get(editorViewCtx)
            undo(view.state, view.dispatch, view)
        })
    },

    redo() {
        if (!state.ready) return
        state.editor.action((ctx) => {
            const view = ctx.get(editorViewCtx)
            redo(view.state, view.dispatch, view)
        })
    },

    /** 诊断:校验命令名是否已注册且可运行(供 selftest 做双端一致性校验);
     *  格式命令在 commandRegistry,表格命令在 tableCommandImpls */
    hasCommands(names) {
        return names.map((n) => ({
            name: n,
            ok: typeof commandRegistry[n]?.run === 'function' || typeof tableCommandImpls[n] === 'function',
        }))
    },

    /** 通过命令名调用预设命令(供原生菜单使用) */
    formatCommand(name, payload) {
        if (!state.ready) return false
        const cmd = commandRegistry[name]
        if (!cmd || typeof cmd.run !== 'function') {
            console.warn('formatCommand: unknown or unregistered command:', name)
            return false
        }
        try {
            return cmd.run(payload) !== false
        } catch (e) {
            console.warn('formatCommand failed', name, e)
            return false
        }
    },

    insertTable(row, col) {
        if (!state.ready) return false
        const ok = this.formatCommand('insertTableCommand', { row: row || 3, col: col || 3 })
        if (!ok) return false
        // 把光标放进新表格的首个单元格(插入后光标可能留在外部,或为整表 CellSelection)
        state.editor.action((ctx) => {
            const view = ctx.get(editorViewCtx)
            try {
                const $from = view.state.selection.$from
                // 新表格位于插入点(光标处或其后);不优先包含表,避免落回旧表
                let target = null
                view.state.doc.descendants((node, pos) => {
                    if (target == null && node.type.name === 'table' && pos >= $from.pos - 2) target = pos
                })
                if (target == null) return
                view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(target + 1), 1)))
            } catch (e) { /* 定位失败不影响插入 */ }
        })
        return true
    },

    /** 在光标处插入一段 markdown 文本 */
    insertMarkdown(md) {
        if (!state.ready) return
        state.editor.action(insert(md))
    },

    focus() {
        if (!state.ready) return
        if (state.sourceMode) {
            document.getElementById('source-editor').focus()
            return
        }
        state.editor.action((ctx) => { ctx.get(editorViewCtx).focus() })
    },

    requestStats() {
        post({ op: 'stats', ...computeStats(state.sourceMode ? document.getElementById('source-editor').value : state.lastMarkdown) })
    },

    exportStandaloneHTML,
}

