// core 组测试的宿主替身：用 jsdom 提供 DOM，用内存里的「假壳」回答 resolveResources/importImage。
// 这是 Windows 壳的参照物之一——core 的全部 op 不需要 WebView，也不感知宿主平台。
import { JSDOM } from 'jsdom'

const FIXTURE_HTML = `<!doctype html><html><body>
<div id="app"></div>
<textarea id="source-editor"></textarea>
<div id="code-view" tabindex="0"></div>
<input id="find-input"><span id="find-count"></span>
<button id="find-next"></button><button id="find-prev"></button><button id="find-close"></button>
</body></html>`

function defineGlobals(win) {
    // Milkdown/ProseMirror 直接引用裸全局（addEventListener 等），必须逐项落到 globalThis
    const passThrough = [
        'window', 'document', 'navigator', 'location', 'history', 'CSS',
        'HTMLElement', 'Element', 'Node', 'NodeList', 'Event', 'EventTarget', 'CustomEvent',
        'KeyboardEvent', 'MouseEvent', 'ClipboardEvent', 'Selection', 'Range',
        'DOMParser', 'XMLSerializer', 'MutationObserver', 'Image',
        'FileReader', 'Blob', 'File', 'btoa', 'atob',
        'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame',
    ]
    for (const key of passThrough) {
        if (win[key] === undefined) continue
        Object.defineProperty(globalThis, key, { value: win[key], configurable: true, writable: true })
    }
    globalThis.window = win
    globalThis.document = win.document
    globalThis.addEventListener = win.addEventListener.bind(win)
    globalThis.removeEventListener = win.removeEventListener.bind(win)
    globalThis.dispatchEvent = win.dispatchEvent.bind(win)
    globalThis.matchMedia = win.matchMedia
        || (() => ({ matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {} }))
    // jsdom 未实现的观察器：内核只用它们做布局感知，测试里空实现即可
    globalThis.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
    globalThis.IntersectionObserver = class { observe() {} unobserve() {} disconnect() {} }
}

/**
 * 启动一个内存内核：DOM=jsdom，壳=answers（同步/异步均可）。
 * 返回 { ops, notifications, answers, window, document, cleanup }。
 */
export async function bootCore({ baseDir = '/virtual/base', files = [], answers = {} } = {}) {
    const dom = new JSDOM(FIXTURE_HTML, { pretendToBeVisual: true, url: `file://${baseDir}/doc.md` })
    defineGlobals(dom.window)

    const notifications = []
    const hostCalls = []
    const fileSet = new Set(files)

    // 假壳：以 files 为准回答资源解析（字面写法存在 → 可加载 URL；两口径存在 → 全部候选路径）
    const resolveResources = ({ refs = [] } = {}) => {
        const resources = {}
        for (const ref of refs) {
            const literal = `${baseDir}/${ref}`
            const decoded = `${baseDir}/${decodeURIComponent(ref.replaceAll('%25', '%'))}`
            const literalExists = fileSet.has(literal.slice(baseDir.length + 1))
            const decodedExists = decoded !== literal && fileSet.has(decoded.slice(baseDir.length + 1))
            const paths = []
            if (literalExists) paths.push(literal)
            if (decodedExists) paths.push(decoded)
            resources[ref] = {
                url: literalExists ? `file://${literal}` : null,
                exists: literalExists,
                isImage: true,
                paths,
            }
        }
        return { resources }
    }

    const { bindBus } = await import('../../src/kernel/shared/bus.js')
    bindBus({
        notify: (op, payload) => notifications.push({ op, payload }),
        callHost: async (op, payload) => {
            hostCalls.push({ op, payload })
            const handler = answers[op]
            if (handler) return handler(payload)
            if (op === 'resolveResources') return resolveResources(payload)
            if (op === 'importImage') return { ok: true, src: 'img_001.png', alt: '', title: '' }
            throw new Error(`fake shell: unsupported host call ${op}`)
        },
    })

    const { createKernelOps } = await import('../../src/kernel/assemble.js')
    const ops = createKernelOps({ fresh: true }).ops

    return {
        ops,
        notifications,
        hostCalls,
        window: dom.window,
        document: dom.window.document,
        baseDir,
        cleanup: () => { dom.window.close() },
    }
}

/** 收集某类通知的 payload 列表 */
export function notificationsOf(notifications, op) {
    return notifications.filter((item) => item.op === op).map((item) => item.payload)
}
