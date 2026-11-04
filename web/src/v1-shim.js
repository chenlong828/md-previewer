// 迁移期 v1 方法面（T5 收尾删除）：window.mdbridge 供尚未迁到 op 调用的 Swift 站点使用。
// 只做「方法名 → op 处理器」的同步转发，没有消息通道、没有编辑语义。
import { createOps, renderMarkdown } from './kernel/core/ops.js'

export function installV1Shim() {
    const ops = createOps()

    window.mdbridge = {
        async init(markdown, opts = {}) {
            await ops.init({ markdown: markdown || '', opts })
            return 'ok'
        },

        setMarkdown(md, opts = {}, flush = false) {
            // 同步入口：v1 壳用 evaluateJavaScript 直接调用，不能变成 Promise
            renderMarkdown(md, { baseDir: opts && opts.baseDir, flush })
        },

        setCode(text, opts = {}) {
            return ops.setCode({
                text: text || '',
                language: opts.language,
                allowHighlight: opts.allowHighlight,
                lineNumbers: opts.lineNumbers,
            }).ok
        },

        setCodeLanguage(id) { return ops.setCodeLanguage({ id }).ok },
        setCodeLineNumbers(visible) { return ops.setCodeLineNumbers({ visible: !!visible }).ok },
        isCodeMode() { return ops.getState().codeMode },
        codeInfo() { return ops.codeInfo() },
        hasLanguages(ids) { return ops.hasLanguages({ ids: Array.isArray(ids) ? ids : [] }).supported },
        markClean() { return ops.markClean().ok },
        getMarkdown() { return ops.getMarkdown().md },
        setTitle(title) { return ops.setTitle({ title: title || '' }).ok },
        setBaseDir(path) { return ops.setBaseDir({ path: path || '' }).ok },
        setTheme(mode) { ops.setTheme({ theme: mode === 'dark' ? 'dark' : 'light' }) },
        setZoom(scale) { return ops.setZoom({ scale }).zoom },
        getZoom() { return ops.getState().zoom },
        toggleSource(force) { return ops.toggleSource({ force }).sourceMode },
        tableCommand(name) { return ops.tableCommand({ name }).applied },
        focusAt(x, y) { return ops.focusAt({ x, y }) },
        debugFocusTable() { return ops.debugFocusTable().ok },
        tableInfo() { return ops.tableInfo() },
        openFindBar() { return ops.openFindBar().ok },
        closeFindBar() { return ops.closeFindBar().ok },
        findNext() { return ops.findNext().ok },
        findPrev() { return ops.findPrev().ok },
        findInfo() { return ops.findInfo() },
        isSourceMode() { return ops.getState().sourceMode },
        undo() { ops.undo() },
        redo() { ops.redo() },
        hasCommands(names) { return ops.hasCommands({ names: Array.isArray(names) ? names : [] }).results },
        formatCommand(name, payload) { return ops.formatCommand({ name, payload }).applied },
        insertTable(row, col) { return ops.insertTable({ row, col }).ok },
        insertMarkdown(md) { return ops.insertMarkdown({ md }).ok },
        insertImage(src, alt, title) { return ops.insertImage({ src, alt, title }).applied },
        testImagePayload(data) { return ops.testImagePayload({ data }).payload },
        focus() { ops.focus() },
        requestStats() { ops.requestStats() },
        async exportStandaloneHTML() { return (await ops.exportStandaloneHTML()).html },
    }
}
