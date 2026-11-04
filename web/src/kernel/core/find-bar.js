// 查找栏 UI:计数显示、命中跳转与查找栏开关 wiring
import { editorViewCtx } from '@milkdown/core'
import { state } from '../shared/state.js'
import { findKey, findUI, searchDoc, selectMatch } from './find.js'
import { findInCode, clearCodeFind } from './code-view.js'

export function updateFindCount(total, current) {
    const el = document.getElementById('find-count')
    if (el) el.textContent = `${total > 0 ? current + 1 : 0}/${total}`
}


export function findInSource(jump) {
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

export function runFind(query, opts = {}) {
    findUI.query = query
    findUI.caseSensitive = !!opts.caseSensitive
    if (!query) {
        clearFindDecorations()
        if (state.codeMode) clearCodeFind()
        updateFindCount(0, -1)
        return
    }
    // 只读代码视图:文本选区实现,不重建 DOM(不打断 token 结构)。
    // 先清掉编辑器侧遗留的查找装饰(切到代码视图后 #app 隐藏,留着会回到 md 时显示旧命中)
    if (state.codeMode) {
        clearFindDecorations()
        const result = findInCode(query, findUI.caseSensitive, opts.jump)
        updateFindCount(result.total, result.current)
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

export function stepFind(dir) {
    const q = findUI.query
    if (!q) return
    if (state.codeMode) {
        const result = findInCode(q, findUI.caseSensitive, dir < 0 ? 'prev' : 'next')
        updateFindCount(result.total, result.current)
        return
    }
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

export function clearFindDecorations() {
    if (!state.ready || state.sourceMode) return
    state.editor.action((ctx) => {
        const view = ctx.get(editorViewCtx)
        view.dispatch(view.state.tr.setMeta(findKey, { query: '', caseSensitive: false, matches: [], current: -1 }))
    })
}

export function openFindBar() {
    document.body.classList.add('finding')
    const input = document.getElementById('find-input')
    input.focus()
    input.select()
    if (input.value) runFind(input.value)
}

export function closeFindBar() {
    document.body.classList.remove('finding')
    clearFindDecorations()
    if (state.codeMode) clearCodeFind()
    findUI.query = ''
    findUI.srcMatches = []
    findUI.srcCurrent = -1
    if (state.codeMode) document.getElementById('code-view').focus()
    if (state.sourceMode) document.getElementById('source-editor').focus()
}

export function setupFindBar() {
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
