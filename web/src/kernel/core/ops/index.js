// op 装配（组合根的内核侧）：各能力切片自持实现，此处只做汇总。
// 该文件不含业务逻辑；新增 op = 契约清单登记 + 对应切片加一个方法。
import { createSessionOps } from './session.js'
import { createEditorOps } from './editor.js'
import { createCodeOps } from './code.js'
import { createFindOps } from './find.js'
import { createOutputOps } from './output.js'
import { createDiagnosticsOps } from './diagnostics.js'

export { renderMarkdown } from '../render.js'

export function createOps() {
    const table = {}
    Object.assign(table, createSessionOps(table))
    Object.assign(table, createEditorOps(table))
    Object.assign(table, createCodeOps(table))
    Object.assign(table, createFindOps(table))
    Object.assign(table, createOutputOps(table))
    Object.assign(table, createDiagnosticsOps(table))
    return table
}
