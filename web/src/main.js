import {
    Editor,
    rootCtx,
    editorViewCtx,
    editorViewOptionsCtx,
    remarkStringifyOptionsCtx,
} from '@milkdown/core'
import {
    commonmark,
    wrapInHeadingCommand,
    turnIntoTextCommand,
    toggleStrongCommand,
    toggleEmphasisCommand,
    toggleInlineCodeCommand,
    toggleLinkCommand,
    wrapInBlockquoteCommand,
    wrapInBulletListCommand,
    wrapInOrderedListCommand,
    insertHrCommand,
    createCodeBlockCommand,
} from '@milkdown/preset-commonmark'
import {
    gfm,
    insertTableCommand,
    toggleStrikethroughCommand,
} from '@milkdown/preset-gfm'

// 命令注册表:名字 → 预设导出的命令插件对象(注册后带 .run(payload) 方法)。
// 只登记 Swift 侧(@objc 动作)实际转发的命令名——表格行列命令由 tableCommand 自实现,不经此表。
const commandRegistry = {
    toggleStrongCommand, toggleEmphasisCommand, toggleInlineCodeCommand, toggleLinkCommand,
    wrapInHeadingCommand, wrapInBlockquoteCommand, wrapInBulletListCommand, wrapInOrderedListCommand,
    insertHrCommand, createCodeBlockCommand, turnIntoTextCommand,
    insertTableCommand, toggleStrikethroughCommand,
}
import { history } from '@milkdown/plugin-history'
import { listener, listenerCtx } from '@milkdown/plugin-listener'
import { math, katexOptionsCtx } from '@milkdown/plugin-math'
import { prism, prismConfig } from '@milkdown/plugin-prism'
import { diagram, diagramSchema } from '@milkdown/plugin-diagram'
import { clipboard } from '@milkdown/plugin-clipboard'
import { trailing } from '@milkdown/plugin-trailing'
import { getMarkdown, replaceAll, getHTML, insert, $view, $prose } from '@milkdown/utils'
import { Plugin, PluginKey, TextSelection } from '@milkdown/prose/state'
import { Decoration, DecorationSet } from '@milkdown/prose/view'
import { isInTable } from '@milkdown/prose/tables'
import { undo, redo } from 'prosemirror-history'
import { refractor } from 'refractor'
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

import 'prosemirror-view/style/prosemirror.css'
import 'prosemirror-tables/style/tables.css'
import 'katex/dist/katex.min.css'
import 'prismjs/themes/prism.css'
import './typora.css'

// ---------- 全局状态 ----------

const state = {
    editor: null,
    ready: false,
    theme: 'light',
    zoom: 1.0,
    sourceMode: false,
    lastMarkdown: '',
    // 干净基线:文件加载/保存时的序列化结果;仅当内容偏离基线才向原生上报 changed
    baselineMarkdown: '',
    // listener 为异步触发:加载后置位,下一次 listener 回调的内容即新基线
    pendingBaseline: false,
    // 插件档位:'full' | 'no-diagram'(由 init opts 传入,_init 先解析再建编辑器)
    pluginSet: 'full',
}

// 当前文档内容的单一真相源:渲染模式读编辑器 doc,源码模式读 textarea。
// 保存取回(getMarkdown)与干净基线(markClean)必须走同一口径,否则源码模式下
// ⌘S 会把编辑前的旧内容写盘。
function currentMarkdown() {
    if (state.sourceMode) return document.getElementById('source-editor').value
    if (!state.ready || !state.editor) return ''
    return state.editor.action(getMarkdown())
}

const post = (msg) => {
    try {
        window.webkit?.messageHandlers?.mdbridge?.postMessage(msg)
    } catch (e) {
        console.warn('postMessage failed', e)
    }
}

// ---------- 工具 ----------

const CJK_RE = /[\u2E80-\u2FFF\u3040-\u30FF\u31C0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/

function computeStats(text) {
    let cjk = 0
    const stripped = text.replace(CJK_RE, (ch) => { cjk++; return ' ' })
    const latinWords = (stripped.match(/[A-Za-z0-9][A-Za-z0-9'_\-]*/g) || []).length
    return { words: latinWords + cjk, chars: text.length }
}

let statsTimer = null
function scheduleStats() {
    if (statsTimer) return
    statsTimer = setTimeout(() => {
        statsTimer = null
        post({ op: 'stats', ...computeStats(state.lastMarkdown) })
    }, 250)
}

function applyThemeDom() {
    document.documentElement.dataset.theme = state.theme
}

function applyMermaidTheme() {
    mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'loose',
        theme: state.theme === 'dark' ? 'dark' : 'default',
        fontFamily: 'inherit',
    })
}

// ---------- Mermaid 图表 NodeView ----------
// plugin-diagram@7.7 只提供 schema 与 remark 转换,SVG 渲染需按官方 recipe 提供 nodeView。
// 交互仿 Typora:正常显示渲染图;点选节点进入源码编辑,失焦提交并重绘。
let mermaidView = null

function createMermaidView() {
    let renderCounter = 0
    return $view(diagramSchema.node, () => (node, view, getPos) => {
        const dom = document.createElement('div')
        dom.dataset.type = 'diagram'

        const svgWrap = document.createElement('div')
        svgWrap.className = 'mermaid-svg'
        const errorTip = document.createElement('div')
        errorTip.className = 'mermaid-error'
        const srcArea = document.createElement('div')
        srcArea.className = 'mermaid-src'
        srcArea.contentEditable = 'true'
        srcArea.spellcheck = false
        srcArea.style.display = 'none'
        srcArea.textContent = node.attrs.value || ''

        dom.appendChild(svgWrap)
        dom.appendChild(errorTip)
        dom.appendChild(srcArea)

        let latest = node.attrs.value || ''
        let editing = false

        const commit = () => {
            const value = srcArea.textContent || ''
            if (value === latest) return
            latest = value
            try {
                const pos = typeof getPos === 'function' ? getPos() : getPos
                if (pos != null) {
                    view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, value }))
                }
            } catch (e) { /* 节点已被删除等情况 */ }
        }

        const render = () => {
            const seq = ++renderCounter
            const code = latest
            if (!code.trim()) {
                svgWrap.innerHTML = '<div class="mermaid-empty">(空图表)</div>'
                return
            }
            const renderId = 'mmd-' + seq + '-' + Math.random().toString(36).slice(2, 8)
            Promise.resolve()
                .then(() => mermaid.render(renderId, code))
                .then(({ svg }) => {
                    if (seq !== renderCounter) return
                    svgWrap.innerHTML = svg
                    errorTip.textContent = ''
                })
                .catch((e) => {
                    if (seq !== renderCounter) return
                    svgWrap.innerHTML = ''
                    errorTip.textContent = 'Mermaid 语法有误: ' + (e && e.message ? e.message : String(e))
                })
        }

        srcArea.addEventListener('blur', () => {
            editing = false
            srcArea.style.display = 'none'
            svgWrap.style.display = ''
            commit()
            render()
        })
        srcArea.addEventListener('keydown', (event) => {
            // Esc / Cmd+Enter 提交
            if (event.key === 'Escape' || (event.key === 'Enter' && (event.metaKey || event.ctrlKey))) {
                event.preventDefault()
                srcArea.blur()
            }
            event.stopPropagation()
        })
        dom.addEventListener('mousedown', () => {
            if (editing) return
            editing = true
            srcArea.style.display = ''
            svgWrap.style.display = 'none'
            errorTip.textContent = ''
            setTimeout(() => srcArea.focus(), 0)
        })

        render()

        return {
            dom,
            update(updatedNode) {
                if (updatedNode.attrs.value !== latest && !editing) {
                    latest = updatedNode.attrs.value || ''
                    srcArea.textContent = latest
                    render()
                }
                return true
            },
            stopEvent(event) {
                return editing && dom.contains(event.target)
            },
            ignoreMutation() {
                return true
            },
            destroy() { /* 无需清理 */ },
        }
    })
}

// ---------- 编辑器创建 ----------

const extraLanguages = [dart, docker, graphql, scala, toml, powershell, haskell, groovy, protobuf, elixir]

async function createEditor() {
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
        .use(useDiagram ? (mermaidView ??= createMermaidView()) : [])
        .use(clipboard)
        .use(trailing)
        .use(findProsePlugin)
        .use(selInfoProse)
        .create()

    editor.action((ctx) => {
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown, _prev) => {
            state.lastMarkdown = markdown
            if (state.pendingBaseline) {
                // 加载后的第一次回调即为干净基线
                state.pendingBaseline = false
                state.baselineMarkdown = markdown
            } else if (!state.suppressChange) {
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
    return editor
}

// ---------- 源码模式 ----------

function toggleSource(force) {
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

// ---------- 文档内查找 ----------

const findKey = new PluginKey('md-find')
const findUI = { query: '', caseSensitive: false, srcMatches: [], srcCurrent: -1 }

// 在文档中搜索:按文本块(段落/标题/代码块/单元格)拼接其内联文本后匹配,
// 返回 {from, to} 文档位置;内联原子节点用占位符阻断跨节点误匹配。
function searchDoc(doc, query, caseSensitive) {
    const matches = []
    if (!query) return { matches }
    const needle = caseSensitive ? query : query.toLowerCase()
    const lower = (s) => (caseSensitive ? s : s.toLowerCase())

    let blockText = ''
    let segs = [] // {start, end, pos}

    const posAt = (offset) => {
        for (const s of segs) {
            if (offset >= s.start && offset <= s.end) return s.pos + (offset - s.start)
        }
        return null
    }
    const flush = () => {
        if (blockText) {
            const hay = lower(blockText)
            let idx = 0
            while (needle && (idx = hay.indexOf(needle, idx)) !== -1) {
                const from = posAt(idx)
                const to = posAt(idx + needle.length)
                if (from != null && to != null) matches.push({ from, to })
                idx += needle.length
            }
        }
        blockText = ''
        segs = []
    }

    doc.descendants((node, pos) => {
        if (!node.isTextblock) return
        node.forEach((child, childOffset) => {
            if (child.isText && child.text) {
                segs.push({ start: blockText.length, end: blockText.length + child.text.length, pos: pos + 1 + childOffset })
                blockText += child.text
            } else {
                blockText += '\u0000' // 内联原子占位
            }
        })
        flush()
    })
    return { matches }
}

function buildFindDeco(doc, matches, current) {
    if (!matches || !matches.length) return DecorationSet.empty
    return DecorationSet.create(doc, matches.map((m, i) =>
        Decoration.inline(m.from, m.to, { class: 'md-find-match' + (i === current ? ' md-find-current' : '') })))
}

const findPlugin = new Plugin({
    key: findKey,
    state: {
        init: () => ({ query: '', caseSensitive: false, matches: [], current: -1, decorations: DecorationSet.empty }),
        apply(tr, value) {
            let next = value
            if (tr.docChanged && value.query) {
                // 文档编辑后重算匹配位置
                const { matches } = searchDoc(tr.doc, value.query, value.caseSensitive)
                const current = matches.length ? Math.max(0, Math.min(value.current, matches.length - 1)) : -1
                next = { ...value, matches, current }
            }
            const meta = tr.getMeta(findKey)
            if (meta) next = { ...next, ...meta }
            return { ...next, decorations: buildFindDeco(tr.doc, next.matches, next.current) }
        },
    },
    props: {
        decorations(st) {
            const v = findKey.getState(st)
            return v ? v.decorations : DecorationSet.empty
        },
    },
})

const findProsePlugin = $prose(() => findPlugin)

// 光标位置信息上报:供原生右键菜单按需启用表格操作
const selInfoProse = $prose(() => {
    let last
    return new Plugin({
        view() {
            return {
                update(view) {
                    let inTable = false
                    try { inTable = isInTable(view.state) } catch (e) { /* ignore */ }
                    if (last !== undefined && inTable === last) return
                    last = inTable
                    post({ op: 'selinfo', inTable })
                },
            }
        },
    })
})

// 表格结构辅助:定位光标所在单元格深度
function findTableCellDepth($from) {
    for (let d = $from.depth; d > 0; d--) {
        const name = $from.node(d).type.name
        if (name === 'table_cell' || name === 'table_header') return d
    }
    return -1
}

// 插入行(schema 感知;milkdown 7.7 的 addRow*Command 工厂嵌套三层,其 CommandManager 只解两层,调用是静默 no-op)
function insertRowInTable(view, after) {
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
function deleteRowInTable(view) {
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
function insertColumnInTable(view, after) {
    const { state, dispatch } = view
    const $from = state.selection.$from
    const cellD = findTableCellDepth($from)
    if (cellD < 0) return false
    const rowD = cellD - 1
    const tableD = cellD - 2
    const row = $from.node(rowD)
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

function deleteColumnInTable(view) {
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

function deleteTableInTable(view) {
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

function updateFindCount(total, current) {
    const el = document.getElementById('find-count')
    if (el) el.textContent = `${total > 0 ? current + 1 : 0}/${total}`
}

function selectMatch(view, m) {
    const tr = view.state.tr.setSelection(TextSelection.create(view.state.doc, m.from, m.to)).scrollIntoView()
    view.dispatch(tr)
}

function findInSource(jump) {
    const ta = document.getElementById('source-editor')
    const text = ta.value
    const hay = findUI.caseSensitive ? text : text.toLowerCase()
    const needle = findUI.caseSensitive ? findUI.query : findUI.query.toLowerCase()
    findUI.srcMatches = []
    let idx = 0
    while (needle && (idx = hay.indexOf(needle, idx)) !== -1) {
        findUI.srcMatches.push(idx)
        idx += needle.length
    }
    findUI.srcCurrent = findUI.srcMatches.length ? (jump === 'prev' ? findUI.srcMatches.length - 1 : 0) : -1
    const m = findUI.srcMatches[findUI.srcCurrent]
    if (m != null) {
        ta.focus()
        ta.setSelectionRange(m, m + findUI.query.length)
    }
    updateFindCount(findUI.srcMatches.length, findUI.srcCurrent)
}

function runFind(query, opts = {}) {
    findUI.query = query
    findUI.caseSensitive = !!opts.caseSensitive
    if (!query) {
        clearFindDecorations()
        updateFindCount(0, -1)
        return
    }
    if (state.sourceMode) {
        findInSource(opts.jump)
        return
    }
    if (!state.ready) return
    state.editor.action((ctx) => {
        const view = ctx.get(editorViewCtx)
        const { matches } = searchDoc(view.state.doc, query, findUI.caseSensitive)
        const current = matches.length ? (opts.jump === 'prev' ? matches.length - 1 : 0) : -1
        view.dispatch(view.state.tr.setMeta(findKey, { query, caseSensitive: findUI.caseSensitive, matches, current }))
        if (current >= 0) selectMatch(view, matches[current])
        updateFindCount(matches.length, current)
    })
}

function stepFind(dir) {
    const q = findUI.query
    if (!q) return
    if (state.sourceMode) {
        if (!findUI.srcMatches.length) { findInSource(dir < 0 ? 'prev' : undefined); return }
        const n = findUI.srcMatches.length
        findUI.srcCurrent = ((findUI.srcCurrent + dir) % n + n) % n
        const ta = document.getElementById('source-editor')
        const m = findUI.srcMatches[findUI.srcCurrent]
        ta.focus()
        ta.setSelectionRange(m, m + q.length)
        updateFindCount(n, findUI.srcCurrent)
        return
    }
    if (!state.ready) return
    state.editor.action((ctx) => {
        const view = ctx.get(editorViewCtx)
        const st = findKey.getState(view.state)
        if (!st || !st.matches || !st.matches.length) {
            runFind(q)
            return
        }
        const n = st.matches.length
        const current = ((st.current + dir) % n + n) % n
        view.dispatch(view.state.tr.setMeta(findKey, { ...st, current }))
        selectMatch(view, st.matches[current])
        updateFindCount(n, current)
    })
}

function clearFindDecorations() {
    if (!state.ready || state.sourceMode) return
    state.editor.action((ctx) => {
        const view = ctx.get(editorViewCtx)
        view.dispatch(view.state.tr.setMeta(findKey, { query: '', caseSensitive: false, matches: [], current: -1 }))
    })
}

function openFindBar() {
    document.body.classList.add('finding')
    const input = document.getElementById('find-input')
    input.focus()
    input.select()
    if (input.value) runFind(input.value)
}

function closeFindBar() {
    document.body.classList.remove('finding')
    clearFindDecorations()
    findUI.query = ''
    findUI.srcMatches = []
    findUI.srcCurrent = -1
    if (state.sourceMode) document.getElementById('source-editor').focus()
}

function setupFindBar() {
    const input = document.getElementById('find-input')
    input.addEventListener('input', () => runFind(input.value))
    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault()
            stepFind(e.shiftKey ? -1 : 1)
        } else if (e.key === 'Escape') {
            e.preventDefault()
            e.stopPropagation()
            closeFindBar()
        }
    })
    document.getElementById('find-next').addEventListener('click', () => { stepFind(1); input.focus() })
    document.getElementById('find-prev').addEventListener('click', () => { stepFind(-1); input.focus() })
    document.getElementById('find-close').addEventListener('click', () => closeFindBar())
    // 焦点在编辑器等处时 Esc 也能关闭
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && document.body.classList.contains('finding') && document.activeElement !== input) {
            closeFindBar()
        }
    }, true)
}
setupFindBar()

// ---------- 导出独立 HTML ----------

async function cssToDataUrl(cssUrl) {
    try {
        const resp = await fetch(cssUrl)
        const buf = await resp.arrayBuffer()
        const ext = cssUrl.split('.').pop().split('?')[0].toLowerCase()
        const mime = { woff2: 'font/woff2', woff: 'font/woff', ttf: 'font/ttf', eot: 'font/eot', svg: 'image/svg+xml', png: 'image/png', gif: 'image/gif', jpg: 'image/jpeg', jpeg: 'image/jpeg' }[ext] || 'application/octet-stream'
        let binary = ''
        const bytes = new Uint8Array(buf)
        for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
        return `data:${mime};base64,${btoa(binary)}`
    } catch (e) {
        return cssUrl
    }
}

async function collectCss() {
    const chunks = []
    for (const sheet of Array.from(document.styleSheets)) {
        try {
            const rules = sheet.cssRules
            if (!rules) continue
            chunks.push(Array.from(rules).map((r) => r.cssText).join('\n'))
        } catch (e) {
            // 跨域样式表读不了 cssRules,用 XHR 兜底
            try {
                const resp = await fetch(sheet.href)
                chunks.push(await resp.text())
            } catch (e2) { /* ignore */ }
        }
    }
    let css = chunks.join('\n\n')
    // 内联资源引用(字体等),让导出的 HTML 离线可用
    const urls = new Set()
    const re = /url\((['"]?)([^'")]+)\1\)/g
    let m
    while ((m = re.exec(css)) !== null) {
        if (!m[2].startsWith('data:')) urls.add(m[2])
    }
    for (const u of urls) {
        const abs = new URL(u, document.baseURI).href
        const data = await cssToDataUrl(abs)
        css = css.split(u).join(data)
    }
    return css
}

async function exportStandaloneHTML() {
    const inSource = state.sourceMode
    if (inSource) toggleSource(false)
    const bodyHtml = state.editor.action(getHTML())
    const css = await collectCss()
    const title = document.title || 'Document'
    const html = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title.replace(/[<>&]/g, '')}</title>
<style>
${css}
</style>
</head>
<body class="typora-export">
<div id="write" class="is-mac">
${bodyHtml}
</div>
</body>
</html>`
    if (inSource) toggleSource(true)
    return html
}

// ---------- 桥接 API ----------

// 表格命令表:名字 → view 实现(全部 schema 感知自定义:
// milkdown 7.7 的 addRow*Command 工厂嵌套三层,其 CommandManager 只解两层,调用是静默 no-op;
// 列命令会复制邻列内容)。Swift 侧 spec 携带这里的名字,由 selftest 校验双端一致。
const tableCommandImpls = {
    insertRowAbove: (view) => insertRowInTable(view, false),
    insertRowBelow: (view) => insertRowInTable(view, true),
    insertColLeft: (view) => insertColumnInTable(view, false),
    insertColRight: (view) => insertColumnInTable(view, true),
    deleteRow: deleteRowInTable,
    deleteColumn: deleteColumnInTable,
    deleteTable: deleteTableInTable,
}

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

// 源码模式 textarea 编辑 → 标记脏状态
document.getElementById('source-editor').addEventListener('input', () => {
    post({ op: 'changed' })
    scheduleStats()
})

// 通知原生:页面脚本已就绪
post({ op: 'boot' })
