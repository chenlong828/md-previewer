// 查找：查找栏开合、上/下一个、命中信息。
import { editorViewCtx } from '@milkdown/core'

import { state, isCodeMode } from '../../shared/state.js'
import { use } from '../../shared/ports.js'
import { findKey, findUI, openFindBar, closeFindBar, stepFind } from '../../components/find/index.js'

export function createFindOps(_table) {
    return {
            openFindBar() {
                openFindBar()
                return { ok: true }
            },

            closeFindBar() {
                closeFindBar()
                return { ok: true }
            },

            findNext() {
                stepFind(1)
                return { ok: true }
            },

            findPrev() {
                stepFind(-1)
                return { ok: true }
            },

            findInfo() {
                const active = document.body.classList.contains('finding')
                if (isCodeMode()) return { active, query: findUI.query, count: use('searchSurface').codeFindCount() }
                return {
                    active,
                    query: findUI.query,
                    // count 恒为数字；-1 表示编辑器未就绪
                    count: state.sourceMode ? findUI.srcMatches.length : (state.ready ? (() => {
                        try {
                            return state.editor.action((ctx) => {
                                const st = findKey.getState(ctx.get(editorViewCtx).state)
                                return st ? st.matches.length : 0
                            })
                        } catch (e) { return -1 }
                    })() : -1),
                }
            },
    }
}
