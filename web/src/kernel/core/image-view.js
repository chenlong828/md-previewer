// 图片 NodeView
// 正常渲染 <img>;点击切换为源码编辑块——与 mermaid 图同一交互模式:
// 整块框起、宽度为编辑器 100%、长路径自动换行,内容是该图的 markdown 源码
// ![alt](path "title")。失焦/Enter 解析提交,Esc 还原;地址清空即删除图片
// (可撤销)。路径换算与文件保持同构:显示时 file:// 相对 baseDir 还原为
// 原始写法,提交时相对路径按 baseDir 解析回规范 file:// URL(%20 编码,
// 与 Swift 加载改写同口径)。
import { $view } from '@milkdown/utils'
import { imageSchema } from '@milkdown/preset-commonmark'
import { state } from '../shared/state.js'

let imageView = null

export function getImageView() {
    return (imageView ??= createImageView())
}

function createImageView() {
    return $view(imageSchema.node, () => (node, view, getPos) => {
        const dom = document.createElement('span')
        dom.className = 'md-image'
        dom.dataset.type = 'image'

        const imgWrap = document.createElement('span')
        imgWrap.className = 'md-image-render'
        const img = document.createElement('img')
        imgWrap.appendChild(img)

        const srcArea = document.createElement('div')
        srcArea.className = 'md-image-src'
        srcArea.contentEditable = 'true'
        srcArea.spellcheck = false
        srcArea.style.display = 'none'

        dom.appendChild(imgWrap)
        dom.appendChild(srcArea)

        let latest = node
        let editing = false

        // ---------- 源码形态与解析 ----------

        /** file:// URL → 展示路径:baseDir 内相对化(还原原始写法),否则给解码后的绝对路径 */
        function displayPath(src) {
            if (!/^file:\/\//i.test(src)) return src
            let decoded = src
            try { decoded = decodeURIComponent(src) } catch (e) { /* 序列不合法则原样展示 */ }
            const path = decoded.replace(/^file:\/\//i, '')
            if (state.baseDir && path.startsWith(state.baseDir + '/')) {
                return path.slice(state.baseDir.length + 1)
            }
            return path
        }

        function wrapIfNeeded(path) {
            return /[\s()]/.test(path) ? `<${path}>` : path
        }

        /** 当前节点 → 源码文本(与文件中的写法同构) */
        function sourceText() {
            const a = latest.attrs
            const title = a.title ? ` "${a.title}"` : ''
            return `![${a.alt || ''}](${wrapIfNeeded(displayPath(a.src || ''))}${title})`
        }

        /** 源码文本 → 节点 attrs;空文本 → null(删除图片);解析不出图片语法 → undefined(还原) */
        function parseSource(text) {
            const t = (text || '').replace(/\n/g, '').trim() // 编辑区只有软换行,硬换行视作误触合并
            if (!t) return null
            const m = /^!\[([^\]]*)\]\((.*)\)$/.exec(t)
            if (!m) return undefined
            const alt = m[1]
            let inner = m[2].trim()
            let title = ''
            const tm = /^(.*\S)\s+("([^"]*)"|'([^']*)')$/.exec(inner)
            if (tm) {
                inner = tm[1].trim()
                title = tm[3] !== undefined ? tm[3] : tm[4]
            }
            let path = inner
            if (path.startsWith('<') && path.endsWith('>')) path = path.slice(1, -1).trim()
            if (!path) return undefined
            return { src: resolvePath(path), alt, title }
        }

        /** 输入路径 → 规范 URL:带 scheme 原样;相对按 baseDir 解析;分段编码与 Swift 同口径 */
        function resolvePath(path) {
            if (/^[a-z][a-z0-9+.-]*:/i.test(path)) return path
            const base = (state.baseDir || '').replace(/\/+$/, '')
            const abs = path.startsWith('/') ? path : (base ? `${base}/${path}` : '')
            if (!abs) return path // 无基准目录(未保存文档):保持输入原样
            return 'file://' + abs.split('/').map(encodeURIComponent).join('/')
        }

        // ---------- 渲染与编辑 ----------

        const syncFromNode = () => {
            if (latest.attrs.src) img.setAttribute('src', latest.attrs.src)
            else img.removeAttribute('src')
            img.alt = latest.attrs.alt || ''
            img.title = latest.attrs.title || latest.attrs.alt || ''
        }
        syncFromNode()

        const commit = () => {
            const pos = typeof getPos === 'function' ? getPos() : getPos
            if (pos == null) return
            const parsed = parseSource(srcArea.textContent)
            if (parsed === undefined) return // 非图片语法:还原不动
            if (parsed === null) {
                view.dispatch(view.state.tr.delete(pos, pos + latest.nodeSize))
                return
            }
            const next = { ...latest.attrs, ...parsed }
            const same = next.src === latest.attrs.src
                && next.alt === latest.attrs.alt
                && next.title === latest.attrs.title
            if (!same) view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, next))
        }

        const enterEdit = () => {
            if (editing) return
            editing = true
            dom.classList.add('editing')
            srcArea.textContent = sourceText()
            srcArea.style.display = ''
            imgWrap.style.display = 'none'
            setTimeout(() => srcArea.focus(), 0)
        }

        const exitEdit = (apply) => {
            if (!editing) return
            editing = false
            dom.classList.remove('editing')
            srcArea.style.display = 'none'
            imgWrap.style.display = ''
            if (apply) commit()
            view.focus()
        }

        // 失焦即提交;Esc 还原(hide 引起的次生 blur 由 editing 守卫拦截)
        srcArea.addEventListener('blur', () => {
            if (editing) exitEdit(true)
        })
        srcArea.addEventListener('keydown', (event) => {
            // 输入法组合中的 Enter 是确认候选词,不是提交
            if (event.isComposing) { event.stopPropagation(); return }
            if (event.key === 'Escape') {
                event.preventDefault()
                exitEdit(false)
            } else if (event.key === 'Enter') {
                event.preventDefault()
                exitEdit(true)
            }
            event.stopPropagation()
        })
        dom.addEventListener('mousedown', () => {
            if (editing) return
            enterEdit()
        })

        return {
            dom,
            update(updatedNode) {
                latest = updatedNode
                if (!editing) syncFromNode()
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
