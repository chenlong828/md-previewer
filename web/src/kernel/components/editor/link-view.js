// 链接交互：渲染态 <a> + 悬停弹层（编辑 / 访问链接）+ 行内 Markdown 源码编辑。
// 交互参照 Obsidian 的 live preview：点链接原地展开 `[文字](地址)`，Enter/失焦提交，
// Esc 取消；其余正文保持所见即所得。源码解析复用编辑器自身的 parser/serializer，
// 不引入第二套 Markdown 解析。
import { parserCtx, serializerCtx } from '@milkdown/core'
import { linkSchema } from '@milkdown/preset-commonmark'
import { TextSelection } from '@milkdown/prose/state'
import { $view } from '@milkdown/utils'
import { state } from '../../shared/state.js'
import { hostCall } from '../../shared/bus.js'

const LINK_POPUP_DELAY = 120
const LINK_POPUP_HIDE_DELAY = 180
const LINK_EDITING_CLASS = 'md-link-editing'

let linkView = null

export function getLinkView() {
    return (linkView ??= createLinkView())
}

// ---------- 悬停弹层（全页唯一实例） ----------

let popup = null
let popupTarget = null
let showTimer = 0
let hideTimer = 0

function ensurePopup() {
    if (popup) return popup
    popup = document.createElement('div')
    popup.className = 'md-link-popup'
    popup.hidden = true
    popup.setAttribute('role', 'toolbar')
    popup.setAttribute('aria-label', '链接操作')

    const edit = document.createElement('button')
    edit.type = 'button'
    edit.dataset.action = 'edit'
    edit.textContent = '编辑'
    const visit = document.createElement('button')
    visit.type = 'button'
    visit.dataset.action = 'visit'
    visit.textContent = '访问链接'
    popup.append(edit, visit)

    // 弹层按下不抢编辑器焦点/选区；移入弹层时取消收起计时
    popup.addEventListener('mousedown', (event) => {
        event.preventDefault()
        event.stopPropagation()
    })
    popup.addEventListener('mouseenter', () => clearTimeout(hideTimer))
    popup.addEventListener('mouseleave', () => scheduleHide())
    popup.addEventListener('click', (event) => {
        const button = event.target.closest('button[data-action]')
        if (!button || !popupTarget) return
        event.preventDefault()
        event.stopPropagation()
        const target = popupTarget
        hidePopup()
        if (button.dataset.action === 'edit') target.openEdit()
        else if (button.dataset.action === 'visit') target.visit()
    })

    document.body.appendChild(popup)
    return popup
}

function scheduleShow(target) {
    ensurePopup()
    clearTimeout(showTimer)
    clearTimeout(hideTimer)
    showTimer = setTimeout(() => {
        if (!target.dom || !target.dom.isConnected) return
        showPopup(target)
    }, LINK_POPUP_DELAY)
}

function scheduleHide() {
    clearTimeout(showTimer)
    clearTimeout(hideTimer)
    hideTimer = setTimeout(() => hidePopup(), LINK_POPUP_HIDE_DELAY)
}

function showPopup(target) {
    ensurePopup()
    popupTarget = target
    popup.hidden = false
    popup.querySelector('button[data-action="edit"]').disabled = false
    popup.querySelector('button[data-action="visit"]').disabled = !target.href()
    positionPopup(target.dom)
}

function positionPopup(anchor) {
    if (!popup || popup.hidden) return
    const rect = anchor.getBoundingClientRect()
    const width = popup.offsetWidth
    const height = popup.offsetHeight
    let left = rect.left
    let top = rect.bottom + 6
    if (top + height > window.innerHeight - 8) top = rect.top - height - 6
    left = Math.min(Math.max(8, left), Math.max(8, window.innerWidth - width - 8))
    top = Math.min(Math.max(8, top), Math.max(8, window.innerHeight - height - 8))
    popup.style.left = `${Math.round(left)}px`
    popup.style.top = `${Math.round(top)}px`
}

function hidePopup() {
    clearTimeout(showTimer)
    clearTimeout(hideTimer)
    if (popup) popup.hidden = true
    popupTarget = null
}

if (typeof window !== 'undefined') {
    // 页面滚动/缩放后锚点位置失效，直接收起，避免弹层悬空
    window.addEventListener('scroll', () => hidePopup(), true)
    window.addEventListener('resize', () => hidePopup())
}

// ---------- 链接 MarkView ----------

function createLinkView() {
    ensurePopup()
    return $view(linkSchema.mark, (ctx) => (mark, view) => {
        const dom = document.createElement('a')
        dom.className = 'md-link'
        dom.setAttribute('rel', 'noopener noreferrer')

        const content = document.createElement('span')
        content.className = 'md-link-content'
        dom.appendChild(content)

        const src = document.createElement('span')
        src.className = 'md-link-src'
        src.contentEditable = 'true'
        src.spellcheck = false
        src.setAttribute('role', 'textbox')
        src.setAttribute('aria-label', '链接源码')
        dom.appendChild(src)

        let latestMark = mark
        let editing = false
        let run = null
        let sourceAtEntry = ''
        let pressPoint = null

        const target = {
            dom,
            href: () => String(latestMark.attrs.href || ''),
            openEdit: () => enterEdit(null),
            visit: () => visitLink(latestMark.attrs.href, view),
        }

        function refresh() {
            const href = latestMark.attrs.href || ''
            if (href) dom.setAttribute('href', href)
            else dom.removeAttribute('href')
            if (latestMark.attrs.title) dom.title = latestMark.attrs.title
            else dom.removeAttribute('title')
        }
        refresh()

        function positionAtContent() {
            try {
                return view.posAtDOM(content, 0)
            } catch (error) {
                return null
            }
        }

        function enterEdit(event) {
            if (editing || !view.state) return
            const pos = positionAtContent()
            if (pos == null) return
            const nextRun = findLinkRun(view.state, pos)
            if (!nextRun) return
            const source = sourceForState(ctx, view.state, nextRun)
            if (!source) return
            const labelOffset = event ? labelOffsetAtPoint(content, event.clientX, event.clientY) : null
            editing = true
            run = nextRun
            sourceAtEntry = source
            src.textContent = source
            dom.classList.add(LINK_EDITING_CLASS)
            hidePopup()
            const caret = sourceCaret(source, labelOffset)
            setTimeout(() => {
                if (!editing) return
                try { src.focus({ preventScroll: true }) } catch (error) { src.focus() }
                selectSource(src, caret)
            }, 0)
        }

        function exitEdit(apply) {
            if (!editing) return
            const raw = normalizeSource(src.textContent)
            const original = sourceAtEntry
            // 先清 DOM 再落 editing=false：DOM 变更由 ignoreMutation 吃掉，
            // 避免 ProseMirror 把源码编辑层的增删当成正文变更重新解析。
            src.textContent = ''
            dom.classList.remove(LINK_EDITING_CLASS)
            editing = false
            if (apply && raw !== original) commitSource(ctx, view, run, raw)
            // 提交失败也把焦点还给编辑器：源码层已隐藏，不能让焦点留在不可见节点上
            try { view.focus() } catch (error) { /* 编辑器已销毁 */ }
        }

        // 拖拽选择文字时不进源码编辑（仍阻止链接导航），避免选字被单击抢走
        dom.addEventListener('mousedown', (event) => {
            if (editing) return
            pressPoint = { x: event.clientX, y: event.clientY }
        })

        // 渲染态点击：不导航；Command+单击直接访问，普通单击展开源码
        dom.addEventListener('click', (event) => {
            if (editing) {
                event.preventDefault()
                event.stopPropagation()
                return
            }
            if (src.contains(event.target)) return
            const dragged = pressPoint
                && Math.hypot(event.clientX - pressPoint.x, event.clientY - pressPoint.y) > 4
            pressPoint = null
            event.preventDefault()
            event.stopPropagation()
            if (dragged) return
            hidePopup()
            if (event.metaKey) {
                visitLink(latestMark.attrs.href, view)
                return
            }
            enterEdit(event)
        })

        dom.addEventListener('mouseenter', () => {
            if (editing) return
            scheduleShow(target)
        })
        dom.addEventListener('mouseleave', () => scheduleHide())

        // 源码编辑层：隔离所有事件，避免 ProseMirror 处理输入/快捷键
        src.addEventListener('mousedown', (event) => event.stopPropagation())
        src.addEventListener('click', (event) => {
            event.preventDefault()
            event.stopPropagation()
        })
        src.addEventListener('blur', () => {
            if (editing) exitEdit(true)
        })
        src.addEventListener('input', (event) => event.stopPropagation())
        // 输入法组合/预输入事件也不交给 ProseMirror，否则中文输入会被当成正文编辑
        for (const type of ['compositionstart', 'compositionupdate', 'compositionend', 'beforeinput']) {
            src.addEventListener(type, (event) => event.stopPropagation())
        }
        src.addEventListener('keydown', (event) => {
            if (event.isComposing) {
                event.stopPropagation()
                return
            }
            if (event.key === 'Escape') {
                event.preventDefault()
                event.stopPropagation()
                exitEdit(false)
            } else if (event.key === 'Enter') {
                event.preventDefault()
                event.stopPropagation()
                exitEdit(true)
            } else {
                event.stopPropagation()
            }
        })
        src.addEventListener('keyup', (event) => event.stopPropagation())
        src.addEventListener('paste', (event) => {
            event.preventDefault()
            event.stopPropagation()
            const text = (event.clipboardData || window.clipboardData)?.getData('text/plain') || ''
            if (text) insertPlainText(src, text.replace(/\r?\n/g, ' '))
        })

        return {
            dom,
            contentDOM: content,
            update(nextMark) {
                latestMark = nextMark
                if (!editing) refresh()
                return true
            },
            ignoreMutation(mutation) {
                return editing && dom.contains(mutation.target)
            },
            destroy() {
                editing = false
                if (popupTarget === target) hidePopup()
            },
        }
    })
}

// ---------- 链接区间与源码 ----------

function sameLink(a, b) {
    return !!a && !!b
        && a.type === b.type
        && String(a.attrs.href || '') === String(b.attrs.href || '')
        && String(a.attrs.title || '') === String(b.attrs.title || '')
}

/**
 * 找出 pos 所在文本块里与 pos 相交的连续链接 mark 区间。
 * 返回 {from, to, mark}；pos 不在链接上时返回该文本块最后一个 run（无则 null）。
 */
function findLinkRun(state, pos) {
    const linkType = state.schema.marks.link
    if (!linkType) return null
    const safe = Math.max(0, Math.min(pos, state.doc.content.size))
    let $pos
    try { $pos = state.doc.resolve(safe) } catch (error) { return null }

    if (!$pos.parent.isTextblock) {
        for (let depth = $pos.depth; depth > 0; depth--) {
            if ($pos.node(depth).isTextblock) {
                $pos = state.doc.resolve($pos.before(depth) + 1)
                break
            }
        }
    }
    if (!$pos.parent.isTextblock) return null

    const start = $pos.start()
    const end = $pos.end()
    let current = null
    let found = null
    state.doc.nodesBetween(start, end, (node, nodePos) => {
        if (!node.isText) return true
        const mark = linkType.isInSet(node.marks)
        if (!mark) {
            current = null
            return true
        }
        if (!current || !sameLink(current.mark, mark)) {
            current = { from: nodePos, to: nodePos + node.nodeSize, mark }
        } else {
            current.to = nodePos + node.nodeSize
        }
        if (safe >= current.from && safe <= current.to) found = current
        return true
    })
    return found || current
}

function sourceForState(ctx, editorState, linkRun) {
    try {
        const content = editorState.doc.slice(linkRun.from, linkRun.to).content
        const paragraph = editorState.schema.nodes.paragraph.create(null, content)
        const doc = editorState.schema.nodes.doc.create(null, [paragraph])
        return String(ctx.get(serializerCtx)(doc)).trim()
    } catch (error) {
        console.warn('link source serialize failed', error)
        return ''
    }
}

function normalizeSource(text) {
    return String(text || '').replace(/\r\n?/g, '\n').trim()
}

/** 提交源码：解析成功则替换原链接区间；空源码删除链接；失败不改文档。 */
function commitSource(ctx, view, linkRun, raw) {
    if (!linkRun) return false
    const current = view.state
    if (linkRun.from < 0 || linkRun.to > current.doc.content.size || linkRun.from > linkRun.to) {
        return false
    }
    if (!raw) {
        view.dispatch(current.tr.delete(linkRun.from, linkRun.to).scrollIntoView())
        return true
    }
    let parsed
    try {
        parsed = ctx.get(parserCtx)(raw)
    } catch (error) {
        console.warn('link source parse failed', error)
        return false
    }
    if (!parsed || parsed.childCount !== 1) return false
    const block = parsed.firstChild
    if (!block || block.type !== current.schema.nodes.paragraph) return false
    const existing = current.doc.slice(linkRun.from, linkRun.to).content
    if (existing.eq(block.content)) return true
    try {
        const tr = current.tr.replaceWith(linkRun.from, linkRun.to, block.content)
        const caret = Math.min(linkRun.from + block.content.size, tr.doc.content.size)
        tr.setSelection(TextSelection.near(tr.doc.resolve(caret)))
        view.dispatch(tr.scrollIntoView())
        return true
    } catch (error) {
        console.warn('link source commit failed', error)
        return false
    }
}

// ---------- 光标/选区与访问 ----------

/** 点击点 → 链接渲染文字里的字符偏移（拿不到则返回 null） */
function labelOffsetAtPoint(content, x, y) {
    if (!x && !y) return null
    let range = null
    if (typeof document.caretRangeFromPoint === 'function') {
        range = document.caretRangeFromPoint(x, y)
    } else if (typeof document.caretPositionFromPoint === 'function') {
        const caret = document.caretPositionFromPoint(x, y)
        if (caret?.offsetNode) {
            range = document.createRange()
            range.setStart(caret.offsetNode, caret.offset)
            range.collapse(true)
        }
    }
    if (!range || !content.contains(range.startContainer)) return null
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT)
    let total = 0
    let node
    while ((node = walker.nextNode())) {
        if (node === range.startContainer) return total + range.startOffset
        total += node.data.length
    }
    return null
}

/** 链接文字偏移 → 源码偏移：源码以 `[` 开头时，文字从第 2 个字符开始 */
function sourceCaret(source, labelOffset) {
    if (labelOffset == null || !source.startsWith('[')) return null
    return Math.max(0, Math.min(source.length, labelOffset + 1))
}

function selectSource(src, caret) {
    const selection = window.getSelection()
    if (!selection) return
    const range = document.createRange()
    const text = src.firstChild
    if (caret != null && text && text.nodeType === Node.TEXT_NODE) {
        range.setStart(text, Math.max(0, Math.min(caret, text.data.length)))
        range.collapse(true)
    } else {
        range.selectNodeContents(src)
    }
    selection.removeAllRanges()
    selection.addRange(range)
}

function insertPlainText(src, text) {
    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0 || !src.contains(selection.anchorNode)) {
        src.textContent += text
        return
    }
    const range = selection.getRangeAt(0)
    range.deleteContents()
    const node = document.createTextNode(text)
    range.insertNode(node)
    range.setStartAfter(node)
    range.collapse(true)
    selection.removeAllRanges()
    selection.addRange(range)
}

function visitLink(href, view) {
    const target = String(href || '').trim()
    if (!target) return
    if (target.startsWith('#')) {
        scrollToAnchor(view, target)
        return
    }
    const payload = { href: target }
    if (state.baseDir) payload.baseDir = state.baseDir
    hostCall('openLink', payload).catch((error) => {
        console.warn('openLink failed', error)
    })
}

function slugifyHeading(text) {
    return String(text || '').trim().toLowerCase()
        .replace(/[^\p{L}\p{N}\s-]/gu, '')
        .replace(/\s+/g, '-')
}

function scrollToAnchor(view, href) {
    let raw = href.slice(1)
    try { raw = decodeURIComponent(raw) } catch (error) { /* 保持原样 */ }
    const headings = Array.from(view.dom.querySelectorAll('h1, h2, h3, h4, h5, h6'))
    if (!raw) {
        window.scrollTo({ top: 0, behavior: 'smooth' })
        return
    }
    const wanted = slugifyHeading(raw)
    const hit = headings.find((heading) => slugifyHeading(heading.textContent) === wanted)
    if (hit) hit.scrollIntoView({ block: 'start', behavior: 'smooth' })
}
