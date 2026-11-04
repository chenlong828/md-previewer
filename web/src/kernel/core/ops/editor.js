// 编辑面：焦点、撤销重做、统计、命令转发、表格与插入。
import { editorViewCtx } from '@milkdown/core'
import { TextSelection } from '@milkdown/prose/state'
import { isInTable } from '@milkdown/prose/tables'
import { undo, redo } from '@milkdown/prose/history'
import { insert } from '@milkdown/utils'

import { state, isCodeMode } from '../../shared/state.js'
import { currentMarkdown } from '../read.js'
import { notify } from '../../shared/bus.js'
import { computeStats } from '../stats.js'
import { commandRegistry } from '../commands.js'
import { tableCommandImpls } from '../tables.js'
import { focusEditorView } from '../render.js'

export function createEditorOps(table) {
    return {
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
                const applied = table.formatCommand({
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
                return { applied: table.formatCommand({
                    name: 'insertImageCommand',
                    payload: { src: payload.src || '', alt: payload.alt || '', title: payload.title || '' },
                }).applied }
            },
    }
}
