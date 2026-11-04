// 只读代码视图：高亮渲染、语言切换、代码内查找与大文件降级。
// 与编辑器共用一个页面：代码文档隐藏 #app/#source-editor，只显示 #code-view；
// 不进入 ProseMirror，不产生 changed，也不参与脏基线（代码文档恒只读）。
import { state } from './state.js'
import { hasLanguage, highlightInto } from './languages.js'

function codeView() {
    return document.getElementById('code-view')
}

function codeElement() {
    const view = codeView()
    return view ? view.querySelector('code') : null
}

/** 当前匹配位置（代码内查找），切换语言/重新渲染时由 render 重置。 */
let matchOffsets = []
let matchCurrent = -1

function render() {
    const el = codeElement()
    if (!el) return
    const language = state.codeLanguage
    const highlightable = state.codeAllowHighlight && hasLanguage(language)
    el.className = highlightable ? `language-${language}` : ''
    el.textContent = ''
    if (highlightable) {
        highlightInto(el, state.codeText, language)
        // 语言不可用/高亮失败时 highlightInto 返回 false 但可能已追加部分节点：
        // 清空后按纯文本重渲染，保证"降级不残半截"。
        if (!el.querySelector('.token') && state.codeText) {
            el.textContent = state.codeText
        }
    } else {
        el.appendChild(document.createTextNode(state.codeText))
    }
    state.codeTokenCount = el.querySelectorAll('.token').length
    matchOffsets = []
    matchCurrent = -1
}

/** 进入代码视图。opts.language 由 Swift 解析为最终语言 id；allowHighlight=false 走纯文本。 */
export function showCode(text, opts = {}) {
    state.codeMode = true
    state.codeText = text || ''
    state.codeLanguage = opts.language || ''
    state.codeAllowHighlight = opts.allowHighlight !== false
    document.body.classList.add('code-mode')
    render()
    const view = codeView()
    if (view) {
        try {
            view.focus({ preventScroll: true })
        } catch (e) {
            view.focus()
        }
    }
    return true
}

/** 退出代码视图（切回 Markdown/目录模式时由 bridge.setMarkdown 调用）。 */
export function hideCode() {
    if (!state.codeMode) return
    state.codeMode = false
    state.codeText = ''
    state.codeLanguage = ''
    state.codeTokenCount = 0
    document.body.classList.remove('code-mode')
    const el = codeElement()
    if (el) el.textContent = ''
    clearSelection()
}

/** 切换语言：只重绘，不写文件；plaintext 恒纯文本，未知 id 回落纯文本。 */
export function setCodeLanguage(id) {
    if (!state.codeMode) return false
    state.codeLanguage = id || 'plaintext'
    render()
    return true
}

export function isCodeMode() {
    return state.codeMode
}

/** 自检/诊断：代码视图状态快照（不暴露 DOM 节点）。 */
export function codeInfo() {
    return {
        mode: state.codeMode,
        language: state.codeLanguage,
        allowHighlight: state.codeAllowHighlight,
        textLength: state.codeText.length,
        lineCount: state.codeText ? state.codeText.split('\n').length : 0,
        tokenCount: state.codeTokenCount,
    }
}

// ---------- 代码内查找（文本选区实现，不重建 DOM，避免打断高亮结构） ----------

function textNodes(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    const nodes = []
    let node
    while ((node = walker.nextNode())) nodes.push(node)
    return nodes
}

function pointAt(nodes, offset) {
    let acc = 0
    for (const node of nodes) {
        const len = node.nodeValue.length
        if (offset <= acc + len) return { node, offset: Math.max(0, offset - acc) }
        acc += len
    }
    const last = nodes[nodes.length - 1]
    return last ? { node: last, offset: last.nodeValue.length } : null
}

function rangeAt(start, end) {
    const el = codeElement()
    if (!el) return null
    const nodes = textNodes(el)
    if (!nodes.length) return null
    const s = pointAt(nodes, start)
    const e = pointAt(nodes, end)
    if (!s || !e) return null
    const range = document.createRange()
    range.setStart(s.node, Math.min(s.offset, s.node.nodeValue.length))
    range.setEnd(e.node, Math.min(e.offset, e.node.nodeValue.length))
    return range
}

function clearSelection() {
    const sel = window.getSelection()
    if (sel) sel.removeAllRanges()
}

function focusMatch(start, length) {
    const range = rangeAt(start, start + length)
    if (!range) return
    const sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange(range)
    const rect = range.getBoundingClientRect()
    // 视口外才滚动，避免每次输入都把页面抖动到中间
    if (rect.top < 0 || rect.bottom > window.innerHeight) {
        window.scrollBy(0, rect.top - window.innerHeight / 2)
    }
}

/**
 * 在代码文本里查找。jump: undefined=首处、'next'/'prev'=循环切换。
 * 返回 { total, current }；无命中 total=0 且不抛错。
 */
export function findInCode(query, caseSensitive, jump) {
    const needle = query || ''
    matchOffsets = []
    if (needle) {
        const text = state.codeText
        const hay = caseSensitive ? text : text.toLowerCase()
        const target = caseSensitive ? needle : needle.toLowerCase()
        let idx = 0
        const step = Math.max(1, target.length)
        while (idx <= hay.length - target.length) {
            const hit = hay.indexOf(target, idx)
            if (hit === -1) break
            matchOffsets.push(hit)
            idx = hit + step
        }
    }
    if (!matchOffsets.length) {
        matchCurrent = -1
        clearSelection()
        return { total: 0, current: -1 }
    }
    if (jump === 'next') {
        matchCurrent = (matchCurrent + 1) % matchOffsets.length
    } else if (jump === 'prev') {
        matchCurrent = (matchCurrent - 1 + matchOffsets.length) % matchOffsets.length
    } else {
        matchCurrent = 0
    }
    focusMatch(matchOffsets[matchCurrent], needle.length)
    return { total: matchOffsets.length, current: matchCurrent }
}

export function codeFindCount() {
    return matchOffsets.length
}

export function clearCodeFind() {
    matchOffsets = []
    matchCurrent = -1
    clearSelection()
}
