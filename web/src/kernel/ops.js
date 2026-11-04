// op 装配（组合根的内核侧）：各能力切片自持实现，此处只做汇总。
// 该文件不含业务逻辑；新增 op = 契约清单登记 + 对应切片加一个方法。
import { createSessionOps } from './components/document/ops.js'
import { createEditorOps } from './components/editor/ops.js'
import { createCodeOps } from './components/code/ops.js'
import { createFindOps } from './components/find/ops.js'
import { createMinimapOps } from './components/minimap/ops.js'
import { createOutputOps } from './components/output/ops.js'
import { createDiagnosticsOps } from './components/editor/diagnostics-ops.js'

export { renderMarkdown } from './components/document/render.js'

export function createOps() {
    const table = {}
    Object.assign(table, createSessionOps(table))
    Object.assign(table, createEditorOps(table))
    Object.assign(table, createCodeOps(table))
    Object.assign(table, createFindOps(table))
    Object.assign(table, createMinimapOps(table))
    Object.assign(table, createOutputOps(table))
    Object.assign(table, createDiagnosticsOps(table))
    return table
}
