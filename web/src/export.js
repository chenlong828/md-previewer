// 独立 HTML 导出:样式收集与资源内联,产出离线可用的单文件
import { getHTML } from '@milkdown/utils'
import { state } from './state.js'
import { toggleSource } from './editor.js'

async function cssToDataUrl(cssUrl) {
    try {
        const resp = await fetch(cssUrl)
        const buf = await resp.arrayBuffer()
        const ext = cssUrl.split('.').pop().split('?')[0].toLowerCase()
        const mime = { woff2: 'font/woff2', woff: 'font/woff', ttf: 'font/ttf', eot: 'font/eot', svg: 'image/svg+xml', png: 'image/png', gif: 'image/gif', jpg: 'image/jpeg', jpeg: 'image/jpeg' }[ext] || 'application/octet-stream'
        let binary = ''
        const bytes = new Uint8Array(buf)
        for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
        return `data:${mime};base64,${btoa(binary)}`
    } catch (e) {
        return cssUrl
    }
}

async function collectCss() {
    const chunks = []
    for (const sheet of Array.from(document.styleSheets)) {
        try {
            const rules = sheet.cssRules
            if (!rules) continue
            chunks.push(Array.from(rules).map((r) => r.cssText).join('\n'))
        } catch (e) {
            // 跨域样式表读不了 cssRules,用 XHR 兜底
            try {
                const resp = await fetch(sheet.href)
                chunks.push(await resp.text())
            } catch (e2) { /* ignore */ }
        }
    }
    let css = chunks.join('\n\n')
    // 内联资源引用(字体等),让导出的 HTML 离线可用
    const urls = new Set()
    const re = /url\((['"]?)([^'")]+)\1\)/g
    let m
    while ((m = re.exec(css)) !== null) {
        if (!m[2].startsWith('data:')) urls.add(m[2])
    }
    for (const u of urls) {
        const abs = new URL(u, document.baseURI).href
        const data = await cssToDataUrl(abs)
        css = css.split(u).join(data)
    }
    return css
}

export async function exportStandaloneHTML() {
    // 代码文档不提供 HTML 导出(REQ-0009 非目标);Swift 侧菜单同时禁用,这里兜底
    if (state.codeMode) return ''
    const inSource = state.sourceMode
    if (inSource) toggleSource(false)
    const bodyHtml = state.editor.action(getHTML())
    const css = await collectCss()
    const title = document.title || 'Document'
    const html = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title.replace(/[<>&]/g, '')}</title>
<style>
${css}
</style>
</head>
<body class="typora-export">
<div id="write" class="is-mac">
${bodyHtml}
</div>
</body>
</html>`
    if (inSource) toggleSource(true)
    return html
}
