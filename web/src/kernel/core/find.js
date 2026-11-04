// 文档内查找:搜索核心与 ProseMirror 高亮插件(纯逻辑,不含查找栏 UI)
import { Plugin, PluginKey, TextSelection } from '@milkdown/prose/state'
import { Decoration, DecorationSet } from '@milkdown/prose/view'
import { $prose } from '@milkdown/utils'

export const findKey = new PluginKey('md-find')
export const findUI = { query: '', caseSensitive: false, srcMatches: [], srcCurrent: -1 }

// 在文档中搜索:按文本块(段落/标题/代码块/单元格)拼接其内联文本后匹配,
// 返回 {from, to} 文档位置;内联原子节点用占位符阻断跨节点误匹配。
export function searchDoc(doc, query, caseSensitive) {
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

export const findProsePlugin = $prose(() => findPlugin)

export function selectMatch(view, m) {
    const tr = view.state.tr.setSelection(TextSelection.create(view.state.doc, m.from, m.to)).scrollIntoView()
    view.dispatch(tr)
}
