// 词数统计：纯计算 + 节流上报
import { currentMarkdown } from './state.js'
import { notify } from './bus.js'

const CJK_RE = /[\u2E80-\u2FFF\u3040-\u30FF\u31C0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]/

export function computeStats(text) {
    let cjk = 0
    const stripped = text.replace(CJK_RE, (_ch) => { cjk++; return ' ' })
    const latinWords = (stripped.match(/[A-Za-z0-9][A-Za-z0-9'_\-]*/g) || []).length
    return { words: latinWords + cjk, chars: text.length }
}

let statsTimer = null
export function scheduleStats() {
    if (statsTimer) return
    statsTimer = setTimeout(() => {
        statsTimer = null
        // 单一真相源：源码模式读 textarea、渲染模式读编辑器 doc（不读旧镜像）
        notify('stats', computeStats(currentMarkdown()))
    }, 250)
}
