// 只读 DOM 快照：把内容面复制成可安全挂进缩略图的副本。
// 这里只处理 DOM 安全与 SVG 引用重写，不认识 Markdown/代码语义。

const REMOVE_TAGS = new Set([
    'SCRIPT', 'NOSCRIPT', 'IFRAME', 'OBJECT', 'EMBED', 'VIDEO', 'AUDIO',
    'BUTTON', 'TEXTAREA', 'SELECT', 'OPTION',
])

const EDITING_CLASSES = [
    'ProseMirror-gapcursor',
    'ProseMirror-focused',
    'ProseMirror-selectednode',
    'selectedCell',
    'column-resize-handle',
    'table-controller',
    'image-resize-handle',
    'mermaid-toolbar',
    'diagram-toolbar',
    'is-current',
    'find-match',
    'find-current',
]

const REF_ATTRS = new Set([
    'href', 'xlink:href', 'aria-labelledby', 'aria-describedby',
    'clip-path', 'mask', 'filter', 'marker-start', 'marker-mid', 'marker-end',
])

let snapshotSeq = 0

function isSvgElement(element) {
    return element.tagName?.toLowerCase() === 'svg' || !!element.closest?.('svg')
}

function rewriteRefs(value, ids) {
    let next = String(value)
    for (const [oldId, newId] of ids) {
        next = next.split(`url(#${oldId})`).join(`url(#${newId})`)
        next = next.split(`#${oldId}`).join(`#${newId}`)
    }
    return next
}

/**
 * 克隆内容并变成只读副本。
 * - 去掉脚本、交互控件、编辑态 class 与 contenteditable；
 * - 保留任务列表 checkbox 的视觉，但全部 disabled；
 * - SVG 内部 id 加本次快照前缀，并重写 href/url(#id)/style 中的引用；
 * - SVG 外的 id 全部移除，避免与原页面重复。
 */
export function cloneReadonly(root) {
    if (!root?.cloneNode) return null
    const clone = root.cloneNode(true)
    const prefix = `mdp-thumb-${++snapshotSeq}-`
    const all = [clone, ...Array.from(clone.querySelectorAll?.('*') || [])]

    for (const element of all) {
        if (element.nodeType !== 1) continue
        const tag = String(element.tagName || '').toUpperCase()
        if (element !== clone && REMOVE_TAGS.has(tag)) {
            element.remove()
            continue
        }
        for (const attr of Array.from(element.attributes || [])) {
            const name = attr.name.toLowerCase()
            if (name.startsWith('on') || name === 'srcdoc' || name === 'formaction' || name === 'ping') {
                element.removeAttribute(attr.name)
            }
            if ((name === 'href' || name === 'src' || name === 'xlink:href')
                && /^\s*(?:javascript|vbscript|data:text\/html)/i.test(attr.value)) {
                element.removeAttribute(attr.name)
            }
        }
        element.removeAttribute('contenteditable')
        element.removeAttribute('tabindex')
        element.removeAttribute('autofocus')
        element.removeAttribute('draggable')
        element.removeAttribute('spellcheck')
        if (tag === 'A') {
            element.removeAttribute('href')
            element.removeAttribute('target')
            element.removeAttribute('download')
        }
        if (tag === 'INPUT') {
            const type = (element.getAttribute('type') || '').toLowerCase()
            if (type !== 'checkbox' && type !== 'radio') {
                element.remove()
                continue
            }
            element.disabled = true
            element.tabIndex = -1
        }
        for (const className of EDITING_CLASSES) element.classList?.remove(className)
    }

    const svgIds = new Map()
    for (const element of all) {
        if (element.nodeType !== 1 || !element.id || !isSvgElement(element)) continue
        const oldId = element.id
        const newId = `${prefix}${oldId}`
        svgIds.set(oldId, newId)
        element.id = newId
    }

    for (const element of all) {
        if (element.nodeType !== 1) continue
        const tag = String(element.tagName || '').toUpperCase()
        for (const attr of Array.from(element.attributes || [])) {
            if (attr.name === 'id') continue
            const name = attr.name.toLowerCase()
            if (name === 'aria-labelledby' || name === 'aria-describedby') {
                const next = attr.value.split(/\s+/).map((id) => svgIds.get(id) || id).join(' ')
                if (next !== attr.value) element.setAttribute(attr.name, next)
                continue
            }
            if (!REF_ATTRS.has(name) && !attr.value.includes('url(#') && !attr.value.includes('#')) {
                continue
            }
            const next = rewriteRefs(attr.value, svgIds)
            if (next !== attr.value) element.setAttribute(attr.name, next)
        }
        if (tag === 'STYLE' && svgIds.size) {
            element.textContent = rewriteRefs(element.textContent || '', svgIds)
        }
    }

    for (const element of all) {
        if (element.nodeType !== 1 || !element.id) continue
        if (!isSvgElement(element)) element.removeAttribute('id')
    }

    clone.setAttribute('aria-hidden', 'true')
    return clone
}
