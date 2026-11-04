// 会话与文档：建编辑器、装载、取回、基线、主题、缩放、状态查询。
// 持文档级状态（baseDir/theme/zoom/baseline）的唯一写入口。
import { replaceAll } from '@milkdown/utils'

import { state, isCodeMode } from '../../shared/state.js'
import { currentMarkdown } from '../read.js'
import { notify, hostCall } from '../../shared/bus.js'
import { createEditor, toggleSource as applySourceToggle, applyThemeDom, applyMermaidTheme } from '../editor.js'
import { codeInfo as readCodeInfo } from '../code-view.js'
import { applyForLoad, collectImageRefs, restoreForSave } from '../../semantics/markdown.js'
import { renderMarkdown } from '../render.js'

export function createSessionOps(table) {
    return {
            async init(payload = {}) {
                const opts = payload.opts || {}
                state.pluginSet = opts.plugins || 'full'
                state.theme = opts.theme === 'dark' ? 'dark' : 'light'
                if (typeof opts.baseDir === 'string') state.baseDir = opts.baseDir
                applyThemeDom()
                if (!state.editor) await createEditor()
                if (opts.zoom) table.setZoom({ scale: opts.zoom })
                table.setTitle({ title: opts.title || '' })
                if (payload.markdown) await table.setMarkdown({ md: payload.markdown, baseDir: opts.baseDir })
                notify('ready', {})
                return { ok: true }
            },

            /** 装载磁盘 markdown：先问壳每个引用的真实位置，再改写为可加载 URL */

            async setMarkdown(payload = {}) {
                const md = typeof payload.md === 'string' ? payload.md : ''
                const baseDir = typeof payload.baseDir === 'string' ? payload.baseDir : state.baseDir
                let text = md
                if (md.length > 0) {
                    const refs = collectImageRefs(md)
                    if (refs.length > 0) {
                        let resources = {}
                        try {
                            const answer = await hostCall('resolveResources', { refs, baseDir })
                            resources = (answer && answer.resources) || {}
                        } catch (e) {
                            // 壳未实现该请求（v1 适配）：按原文装载，缺失引用保持原样
                            console.warn('resolveResources unavailable; loading as-is', e)
                        }
                        text = applyForLoad(md, { resources })
                    }
                }
                const ok = renderMarkdown(text, { baseDir: payload.baseDir, flush: payload.flush === true })
                return { ok }
            },

            getMarkdown() {
                return { md: currentMarkdown() }
            },

            /** 写盘口径：文档目录内相对化，目录外保留绝对路径 */

            getSaveMarkdown() {
                return { md: restoreForSave(currentMarkdown(), { baseDir: state.baseDir }) }
            },

            markClean() {
                if (state.ready) state.baselineMarkdown = currentMarkdown()
                return { ok: true }
            },

            setBaseDir(payload = {}) {
                state.baseDir = payload.path || ''
                return { ok: true }
            },

            setTitle(payload = {}) {
                document.title = payload.title || 'MDPreview'
                return { ok: true }
            },

            setTheme(payload = {}) {
                const target = payload.theme === 'dark' ? 'dark' : 'light'
                if (target === state.theme) return { ok: true }
                state.theme = target
                applyThemeDom()
                applyMermaidTheme()
                if (state.ready) {
                    // 已渲染的 mermaid 图需要重绘（读当前内容，不用可能过期的镜像）
                    state.editor.action(replaceAll(currentMarkdown()))
                }
                return { ok: true }
            },

            setZoom(payload = {}) {
                const s = Math.min(3, Math.max(0.5, payload.scale))
                state.zoom = s
                document.documentElement.style.setProperty('--app-zoom', String(s))
                return { zoom: s }
            },

            getState() {
                return {
                    ready: state.ready,
                    sourceMode: state.sourceMode,
                    codeMode: isCodeMode(),
                    theme: state.theme,
                    zoom: state.zoom,
                    baseDir: state.baseDir,
                    title: document.title,
                    code: readCodeInfo(),
                }
            },

            toggleSource(payload = {}) {
                // 代码文档没有源码/渲染切换（需求明确「代码恒为纯源码、不支持切换」）
                if (isCodeMode()) return { sourceMode: false }
                return { sourceMode: applySourceToggle(payload.force) }
            },
    }
}
