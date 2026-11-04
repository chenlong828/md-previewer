// 只读代码视图：高亮渲染、语言切换、行号/软换行、当前行、代码内查找与大文件降级。
// 与编辑器共用一个页面：代码文档隐藏 #app/#source-editor，只显示 #code-view；
// 不进入 ProseMirror，不产生 changed，也不参与脏基线（代码文档恒只读）。
//
// 行结构是表现层：每个逻辑行一个 .code-line，行号由 CSS ::before 生成，不进入
// 文本节点；逐行 .code-line-content 以 \n 拼接必须等于 state.codeText。
import { state, setMode } from '../../shared/state.js'
import { cloneReadonly } from '../../shared/readonly-clone.js'
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

/** 逻辑行元数据：start/end 是原文 UTF-16 偏移，content 是该行文本节点容器。 */
let lineMeta = []
/** 当前行下标（0 基，-1 表示无）；会话级，不持久化。 */
let currentLine = -1
let interactionsBound = false

// ---------- 行拆分：先完整高亮，再按 \n 切；跨行 token 每行克隆同一外壳 ----------

function shellOf(element) {
    const clone = document.createElement(element.tagName)
    for (const attr of Array.from(element.attributes)) {
        clone.setAttribute(attr.name, attr.value)
    }
    return clone
}

function splitTextLines(text) {
    const parts = String(text).split('\n')
    return parts.map((part) => {
        const fragment = document.createDocumentFragment()
        if (part) fragment.appendChild(document.createTextNode(part))
        return fragment
    })
}

/** 把 incoming 的第一行接到 target 最后一行之后，其余行依次追加。 */
function mergeLineFragments(target, incoming) {
    if (!incoming.length) return target
    if (!target.length) {
        for (const fragment of incoming) target.push(fragment)
        return target
    }
    target[target.length - 1].appendChild(incoming[0])
    for (let i = 1; i < incoming.length; i += 1) target.push(incoming[i])
    return target
}

/**
 * 把一个节点拆成若干“行片段”。元素按行克隆外壳，文本节点按 \n 切开；
 * 这样多行 token 的 class/属性在每一行都保留，且不会按行重新解析语法。
 */
function splitNodeIntoLines(node) {
    if (node.nodeType === Node.TEXT_NODE) return splitTextLines(node.nodeValue || '')
    if (node.nodeType !== Node.ELEMENT_NODE) {
        return [document.createDocumentFragment()]
    }
    const contentLines = []
    for (const child of Array.from(node.childNodes)) {
        mergeLineFragments(contentLines, splitNodeIntoLines(child))
    }
    if (!contentLines.length) contentLines.push(document.createDocumentFragment())
    return contentLines.map((content) => {
        const shell = shellOf(node)
        shell.appendChild(content)
        const fragment = document.createDocumentFragment()
        fragment.appendChild(shell)
        return fragment
    })
}

function splitIntoLines(fragment) {
    const lines = []
    for (const child of Array.from(fragment.childNodes)) {
        mergeLineFragments(lines, splitNodeIntoLines(child))
    }
    return lines
}

// ---------- 行号/当前行布局 ----------

function applyLineNumbers() {
    const view = codeView()
    if (view) view.classList.toggle('no-line-numbers', !state.codeLineNumbers)
}

function applyCurrentLine(index, scroll) {
    if (currentLine >= 0 && lineMeta[currentLine]) {
        lineMeta[currentLine].line.classList.remove('is-current')
    }
    const next = index >= 0 && index < lineMeta.length ? index : -1
    if (next >= 0) {
        const line = lineMeta[next].line
        line.classList.add('is-current')
        if (scroll) line.scrollIntoView({ block: 'nearest' })
    }
    currentLine = next
}

function ensureInteractions() {
    const view = codeView()
    if (!view || interactionsBound) return
    interactionsBound = true
    view.addEventListener('click', (event) => {
        if (!state.codeMode) return
        const target = event.target instanceof Element ? event.target.closest('.code-line') : null
        if (!target) return
        // 拖选文本后不抢当前行；单击（选区折叠）才移动当前行。
        const selection = window.getSelection()
        if (selection && !selection.isCollapsed) return
        try {
            view.focus({ preventScroll: true })
        } catch (e) {
            view.focus()
        }
        applyCurrentLine(Number(target.dataset.line) - 1, false)
    })
    view.addEventListener('keydown', (event) => {
        if (!state.codeMode || !lineMeta.length) return
        if (event.metaKey || event.ctrlKey || event.altKey) return
        if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return
        event.preventDefault()
        let next = currentLine < 0 ? 0 : currentLine
        if (event.key === 'ArrowDown') next = Math.min(lineMeta.length - 1, next + 1)
        else if (event.key === 'ArrowUp') next = Math.max(0, next - 1)
        else if (event.key === 'Home') next = 0
        else if (event.key === 'End') next = lineMeta.length - 1
        applyCurrentLine(next, true)
    })
}

function render() {
    const el = codeElement()
    if (!el) return
    const language = state.codeLanguage
    const highlightable = state.codeAllowHighlight && hasLanguage(language)
    el.className = highlightable ? `code-lines language-${language}` : 'code-lines'
    el.textContent = ''
    lineMeta = []
    const text = state.codeText
    if (!text) {
        currentLine = -1
        applyLineNumbers()
        state.codeTokenCount = 0
        matchOffsets = []
        matchCurrent = -1
        return
    }

    const source = document.createDocumentFragment()
    if (highlightable) {
        highlightInto(source, text, language)
        // 语言不可用/高亮失败时 highlightInto 返回 false 但可能已追加部分节点：
        // 清空后按纯文本重渲染，保证“降级不残半截”。
        if (!source.querySelector('.token')) {
            source.textContent = ''
            source.appendChild(document.createTextNode(text))
        }
    } else {
        source.appendChild(document.createTextNode(text))
    }

    const fragments = splitIntoLines(source)
    const textLines = text.split('\n')
    const view = codeView()
    if (view) view.style.setProperty('--code-gutter-digits', String(Math.max(2, String(textLines.length).length)))

    let offset = 0
    fragments.forEach((fragment, index) => {
        const line = document.createElement('span')
        line.className = 'code-line'
        line.dataset.line = String(index + 1)

        const number = document.createElement('span')
        number.className = 'code-line-number'
        number.dataset.line = String(index + 1)
        number.setAttribute('aria-hidden', 'true')

        const content = document.createElement('span')
        content.className = 'code-line-content'
        content.appendChild(fragment)
        // 空行在块级选择里会被浏览器丢掉；非末行补 <br> 让复制保留空行。
        // 末行（文件以 \n 结尾时的末尾空行）不补，否则复制会多一个换行。
        const lineText = textLines[index] ?? ''
        if (!lineText && index < fragments.length - 1) content.appendChild(document.createElement('br'))

        line.appendChild(number)
        line.appendChild(content)
        el.appendChild(line)

        lineMeta.push({ start: offset, end: offset + lineText.length, line, content })
        offset += lineText.length + 1
    })

    state.codeTokenCount = el.querySelectorAll('.token').length
    applyLineNumbers()
    applyCurrentLine(currentLine, false)
    matchOffsets = []
    matchCurrent = -1
}

// ---------- 视图入口 ----------

/** 进入代码视图。opts.language 由 Swift 解析为最终语言 id；allowHighlight=false 走纯文本。 */
export function showCode(text, opts = {}) {
    setMode('code')
    state.codeText = text || ''
    state.codeLanguage = opts.language || ''
    state.codeAllowHighlight = opts.allowHighlight !== false
    if (typeof opts.lineNumbers === 'boolean') state.codeLineNumbers = opts.lineNumbers
    currentLine = -1
    document.body.classList.add('code-mode')
    ensureInteractions()
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
    setMode('markdown')
    state.codeText = ''
    state.codeLanguage = ''
    state.codeTokenCount = 0
    currentLine = -1
    lineMeta = []
    matchOffsets = []
    matchCurrent = -1
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

/**
 * 切换行号显示：只改布局类，不重绘 token、不写文件。
 * 非代码模式 no-op，返回 false；偏好由原生 UserDefaults 持有。
 */
export function setCodeLineNumbers(visible) {
    if (!state.codeMode) return false
    state.codeLineNumbers = !!visible
    applyLineNumbers()
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
        lineNumbers: state.codeLineNumbers,
        currentLine,
    }
}

// ---------- 缩略图只读快照（组件内部导出，只经 assemble 注入 minimapSources） ----------

/** 代码面的只读快照：页面容器 + 已脱敏的代码行 DOM。 */
export function createCodeMinimapSource() {
    const root = codeView()

    function measure() {
        const view = codeView()
        const rect = view?.getBoundingClientRect()
        const contentWidth = Math.max(1, rect?.width || document.documentElement.clientWidth || 1)
        const scrollTop = window.scrollY || document.documentElement.scrollTop || 0
        const docHeight = Math.max(0, document.documentElement.scrollHeight || 0)
        const viewportHeight = Math.max(0, window.innerHeight || document.documentElement.clientHeight || 0)
        return { contentWidth, docHeight, viewportHeight, scrollTop, root: view || null }
    }

    function snapshot() {
        const view = codeView()
        const code = codeElement()
        if (!view || !code) return null
        const style = getComputedStyle(view)
        const zoom = Number.parseFloat(style.zoom) || 1
        const rect = view.getBoundingClientRect()
        const page = document.createElement('div')
        page.className = 'minimap-page minimap-code-page'
        if (!state.codeLineNumbers) page.classList.add('no-line-numbers')
        page.style.width = `${rect.width / zoom}px`
        page.style.zoom = String(zoom)
        page.style.boxSizing = 'border-box'
        page.style.margin = '0'
        page.style.overflow = 'hidden'
        page.style.padding = `${style.paddingTop} ${style.paddingRight} ${style.paddingBottom} ${style.paddingLeft}`
        page.style.background = style.backgroundColor
        page.style.color = style.color
        page.style.fontFamily = style.fontFamily
        page.style.fontSize = style.fontSize
        page.style.lineHeight = style.lineHeight
        page.style.whiteSpace = 'normal'
        page.style.tabSize = '4'
        page.style.setProperty('--code-line-height', style.getPropertyValue('--code-line-height') || '1.55')
        page.style.setProperty('--code-gutter-digits', style.getPropertyValue('--code-gutter-digits') || '2')
        const content = cloneReadonly(code)
        if (!content) return null
        page.append(content)
        return page
    }

    function scrollTo(top) {
        const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
        const target = Math.max(0, Math.min(max, Number(top) || 0))
        window.scrollTo({ top: target, left: 0, behavior: 'auto' })
    }

    return { root, measure, scrollTo, snapshot }
}

// ---------- 代码内查找（文本选区实现，不重建 DOM，避免打断高亮结构） ----------

function textNodes(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    const nodes = []
    let node
    while ((node = walker.nextNode())) nodes.push(node)
    return nodes
}

function lineIndexAt(offset) {
    let low = 0
    let high = lineMeta.length - 1
    while (low <= high) {
        const mid = (low + high) >> 1
        const meta = lineMeta[mid]
        if (offset < meta.start) high = mid - 1
        else if (offset > meta.end) low = mid + 1
        else return mid
    }
    return -1
}

/** 把原文偏移映射到某行的文本节点；空行没有文本节点，返回 null。 */
function pointAt(offset) {
    const index = lineIndexAt(offset)
    if (index < 0) return null
    const meta = lineMeta[index]
    const nodes = textNodes(meta.content)
    if (!nodes.length) return null
    const local = Math.max(0, Math.min(offset - meta.start, meta.end - meta.start))
    let acc = 0
    for (const node of nodes) {
        const len = node.nodeValue.length
        if (local <= acc + len) return { node, offset: Math.max(0, local - acc) }
        acc += len
    }
    const last = nodes[nodes.length - 1]
    return { node: last, offset: last.nodeValue.length }
}

function rangeAt(start, end) {
    const s = pointAt(start)
    const e = pointAt(end)
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
    const index = lineIndexAt(start)
    if (index >= 0) applyCurrentLine(index, false)
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
