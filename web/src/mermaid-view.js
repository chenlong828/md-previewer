// Mermaid 图表 NodeView
// plugin-diagram@7.7 只提供 schema 与 remark 转换,SVG 渲染需按官方 recipe 提供 nodeView。
// 交互仿 Typora:正常显示渲染图;点选节点进入源码编辑,失焦提交并重绘。
import { $view } from '@milkdown/utils'
import { diagramSchema } from '@milkdown/plugin-diagram'
import mermaid from 'mermaid'

let mermaidView = null

export function getMermaidView() {
    return (mermaidView ??= createMermaidView())
}

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
