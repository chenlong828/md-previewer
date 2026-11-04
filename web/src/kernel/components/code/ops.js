// 代码面：只读源码视图、语言与行号、代码内查找重放。
import { state } from '../../shared/state.js'
import { use } from '../../shared/ports.js'
import {
    showCode, setCodeLanguage as applyCodeLanguage, setCodeLineNumbers as applyCodeLineNumbers,
    codeInfo as readCodeInfo,
} from './code-view.js'
import { hasLanguage } from './languages.js'

export function createCodeOps(_table) {
    return {
            setCode(payload = {}) {
                if (!state.ready) return { ok: false }
                if (state.sourceMode) use('editorSurface').setSourceMode(false)
                showCode(payload.text || '', {
                    language: typeof payload.language === 'string' ? payload.language : 'plaintext',
                    allowHighlight: payload.allowHighlight !== false,
                    lineNumbers: typeof payload.lineNumbers === 'boolean' ? payload.lineNumbers : undefined,
                })
                if (document.body.classList.contains('finding') && use('findService').findUI.query) {
                    use('findService').runFind(use('findService').findUI.query, { caseSensitive: use('findService').findUI.caseSensitive })
                }
                return { ok: true }
            },

            setCodeLanguage(payload = {}) {
                const ok = applyCodeLanguage(typeof payload.id === 'string' ? payload.id : 'plaintext')
                if (ok && document.body.classList.contains('finding') && use('findService').findUI.query) {
                    use('findService').runFind(use('findService').findUI.query, { caseSensitive: use('findService').findUI.caseSensitive })
                }
                return { ok }
            },

            setCodeLineNumbers(payload = {}) {
                return { ok: applyCodeLineNumbers(payload.visible === true) }
            },

            codeInfo() {
                return readCodeInfo()
            },

            hasLanguages(payload = {}) {
                const ids = Array.isArray(payload.ids) ? payload.ids : []
                return { supported: ids.filter((id) => hasLanguage(id)) }
            },
    }
}
