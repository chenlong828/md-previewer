// 诊断档与资源引用：G1 限定面（自检/截图/调试） + GC 引用收集。
import { editorViewCtx } from '@milkdown/core'
import { TextSelection } from '@milkdown/prose/state'
import { isInTable } from '@milkdown/prose/tables'

import { state } from '../../shared/state.js'
import { currentMarkdown } from '../read.js'
import { hostCall } from '../../shared/bus.js'
import { commandRegistry } from '../commands.js'
import { tableCommandImpls } from '../tables.js'
import { extractImagePayload } from '../../components/media/image-paste.js'
import { collectImageRefs, collectResourceRefs } from '../../semantics/markdown.js'

export function createDiagnosticsOps(_table) {
    return {
            async getResourceRefs() {
                const md = currentMarkdown()
                const refs = collectImageRefs(md)
                let resources = {}
                if (refs.length > 0) {
                    try {
                        const answer = await hostCall('resolveResources', { refs, baseDir: state.baseDir })
                        resources = (answer && answer.resources) || {}
                    } catch (e) {
                        console.warn('resolveResources unavailable; no refs collected', e)
                    }
                }
                return { paths: collectResourceRefs(md, { resources }) }
            },

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
}
