// 表格结构操作:行列几何全部 schema 感知(表头行是专用 table_header_row 节点)。
// 全部自定义实现的原因:milkdown 7.7 的 addRow*Command 工厂嵌套三层,其 CommandManager
// 只解两层,调用是静默 no-op;列命令会复制邻列内容。
// 表格结构辅助:定位光标所在单元格深度
export function findTableCellDepth($from) {
    for (let d = $from.depth; d > 0; d--) {
        const name = $from.node(d).type.name
        if (name === 'table_cell' || name === 'table_header') return d
    }
    return -1
}

// 插入行(schema 感知;milkdown 7.7 的 addRow*Command 工厂嵌套三层,其 CommandManager 只解两层,调用是静默 no-op)
export function insertRowInTable(view, after) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const rowD = cellD - 1
    const row = $from.node(rowD)
    const rowPos = $from.before(rowD)
    const isHeader = row.type.name === 'table_header_row'
    // 新行:沿用所在行单元格内容/对齐;表头行的单元格转为 body 单元格
    const cells = []
    row.forEach((cell) => {
        // 新行为空行:仅沿用列对齐属性,不复制内容
        const type = isHeader ? state.schema.nodes.table_cell : cell.type
        const cellNode = type.createAndFill(cell.attrs)
        if (cellNode) cells.push(cellNode)
    })
    const newRow = state.schema.nodes.table_row.create(null, cells)
    let insertPos = after ? rowPos + row.nodeSize : rowPos
    if (!after && isHeader) {
        // 表头上方不插行(表头必须是首行):落到表头之后
        insertPos = rowPos + row.nodeSize
    }
    dispatch(state.tr.insert(insertPos, newRow))
    return true
}

// 删除光标所在行(schema 感知:表格首行是专用 table_header_row 节点)
export function deleteRowInTable(view) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const rowD = cellD - 1
    const tableD = cellD - 2
    const row = $from.node(rowD)
    const table = $from.node(tableD)
    const rowPos = $from.before(rowD)
    const tablePos = $from.before(tableD)
    const tr = state.tr
    if (row.type.name === 'table_header_row') {
        if (table.childCount < 2) return false
        // 表头行不可直接删:用第一个 body 行顶替(单元格转为表头)
        const firstBody = table.child(1)
        const bodyPos = rowPos + row.nodeSize
        tr.delete(bodyPos, bodyPos + firstBody.nodeSize)
        const cells = []
        firstBody.forEach((cell) => cells.push(state.schema.nodes.table_header.create(cell.attrs, cell.content)))
        tr.replaceWith(rowPos, rowPos + row.nodeSize, state.schema.nodes.table_header_row.create(null, cells))
    } else if (table.childCount <= 2) {
        // 表头 + 唯一 body 行 → 删除整表
        tr.delete(tablePos, tablePos + table.nodeSize)
    } else {
        tr.delete(rowPos, rowPos + row.nodeSize)
    }
    dispatch(tr)
    return true
}

// 删除光标所在列(逐行移除对应单元格,从后往前避免位置偏移)
// 插入列(schema 感知:逐行插入空单元格,沿用邻列对齐;milkdown 列命令会复制邻列内容)
export function insertColumnInTable(view, after) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const tableD = cellD - 2
    const table = $from.node(tableD)
    const colIdx = $from.index(cellD - 1) + (after ? 1 : 0)
    const tr = state.tr
    const tableBase = $from.before(tableD) + 1
    const rows = []
    table.forEach((child, offset) => rows.push({ node: child, pos: tableBase + offset }))
    // 从最后一行往前插,位置不受影响
    for (let i = rows.length - 1; i >= 0; i--) {
        const r = rows[i].node
        const isHeaderRow = r.type.name === 'table_header_row'
        const neighbor = r.child(Math.min(colIdx, r.childCount - 1))
        const type = isHeaderRow ? state.schema.nodes.table_header : state.schema.nodes.table_cell
        const attrs = neighbor ? { alignment: neighbor.attrs.alignment } : undefined
        const cellNode = type.createAndFill(attrs)
        if (!cellNode) return false
        let p = rows[i].pos + 1
        for (let k = 0; k < colIdx && k < r.childCount; k++) p += r.child(k).nodeSize
        tr.insert(p, cellNode)
    }
    dispatch(tr)
    return true
}

export function deleteColumnInTable(view) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const rowD = cellD - 1
    const tableD = cellD - 2
    const row = $from.node(rowD)
    const table = $from.node(tableD)
    const tablePos = $from.before(tableD)
    const colIdx = $from.index(cellD - 1)
    if (row.childCount <= 1) {
        // 只剩一列 → 删除整表
        dispatch(state.tr.delete(tablePos, tablePos + table.nodeSize))
        return true
    }
    const tr = state.tr
    const tableBase = $from.before(tableD) + 1
    const rows = []
    table.forEach((child, offset) => rows.push({ node: child, pos: tableBase + offset }))
    for (let i = rows.length - 1; i >= 0; i--) {
        const r = rows[i].node
        if (colIdx >= r.childCount) continue
        let p = rows[i].pos + 1
        for (let k = 0; k < colIdx; k++) p += r.child(k).nodeSize
        tr.delete(p, p + r.child(colIdx).nodeSize)
    }
    dispatch(tr)
    return true
}

export function deleteTableInTable(view) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const tableD = cellD - 2
    const tablePos = $from.before(tableD)
    const table = $from.node(tableD)
    dispatch(state.tr.delete(tablePos, tablePos + table.nodeSize))
    return true
}

// 表格命令表:名字 → view 实现。Swift 侧 spec 携带这里的名字,由 selftest 校验双端一致。
export const tableCommandImpls = {
    insertRowAbove: (view) => insertRowInTable(view, false),
    insertRowBelow: (view) => insertRowInTable(view, true),
    insertColLeft: (view) => insertColumnInTable(view, false),
    insertColRight: (view) => insertColumnInTable(view, true),
    deleteRow: deleteRowInTable,
    deleteColumn: deleteColumnInTable,
    deleteTable: deleteTableInTable,
}
