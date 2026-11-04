// v1 过渡层（T5 切换后整文件删除）：window.mdbridge 是 Swift 壳当前调用的入口。
// 方法体全部委托 kernel/core/ops.js 的 op 处理器，这里只做「v1 返回值形状 ↔ v2 payload」的转换，
// 不再持有任何编辑语义——避免第二份实现。
import { post } from './v1-channel.js'
import { bindBus } from './kernel/core/bus.js'
import { createOps, renderMarkdown } from './kernel/core/ops.js'
import { state } from './kernel/core/state.js'

// v1 适配：把内核总线接到 window.webkit 通道；hostCall 用 requestId 关联响应。
const importPending = new Map()
let importSeq = 0
bindBus({
    notify: (op, payload) => {
        if (op === 'boot') {
            post({ op: 'boot' })
            return
        }
        post({ op, ...payload })
    },
    callHost: (op, payload) => new Promise((resolve, reject) => {
        if (op === 'importImage') {
            importSeq += 1
            const requestId = `img-${importSeq}`
            importPending.set(requestId, { resolve, reject })
            post({ op, requestId, ...payload })
            return
        }
        if (op === 'resolveResources') {
            // v1 壳已在装载前自行改写图片路径；这里回答「无资源」，缺失引用按原文保留（与旧行为一致）
            resolve({ resources: {} })
            return
        }
        reject(new Error(`v1 adapter: unsupported host call ${op}`))
    }),
})

const ops = createOps()

window.mdbridge = {
    async init(markdown, opts = {}) {
        try {
            await ops.init({ markdown: markdown || '', opts })
            return 'ok'
        } catch (e) {
            post({
                op: 'jserror',
                message: 'init failed: ' + (e && e.message ? e.message : String(e)),
                stack: e && e.stack ? String(e.stack) : '',
            })
            throw e
        }
    },

    // 同步入口：v1 壳用 evaluateJavaScript 直接调用，不能变成 Promise
    setMarkdown(md, opts = {}, flush = false) {
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

    setCodeLanguage(id) {
        return ops.setCodeLanguage({ id }).ok
    },

    setCodeLineNumbers(visible) {
        return ops.setCodeLineNumbers({ visible: !!visible }).ok
    },

    isCodeMode() {
        return ops.getState().codeMode
    },

    codeInfo() {
        return ops.codeInfo()
    },

    hasLanguages(ids) {
        return ops.hasLanguages({ ids: Array.isArray(ids) ? ids : [] }).supported
    },

    markClean() {
        return ops.markClean().ok
    },

    getMarkdown() {
        return ops.getMarkdown().md
    },

    setTitle(title) {
        return ops.setTitle({ title: title || '' }).ok
    },

    setBaseDir(path) {
        return ops.setBaseDir({ path: path || '' }).ok
    },

    setTheme(mode) {
        ops.setTheme({ theme: mode === 'dark' ? 'dark' : 'light' })
    },

    setZoom(scale) {
        return ops.setZoom({ scale }).zoom
    },

    getZoom() {
        return ops.getState().zoom
    },

    toggleSource(force) {
        return ops.toggleSource({ force }).sourceMode
    },

    tableCommand(name) {
        return ops.tableCommand({ name }).applied
    },

    focusAt(x, y) {
        return ops.focusAt({ x, y })
    },

    debugFocusTable() {
        return ops.debugFocusTable().ok
    },

    tableInfo() {
        return ops.tableInfo()
    },

    openFindBar() {
        return ops.openFindBar().ok
    },

    closeFindBar() {
        return ops.closeFindBar().ok
    },

    findNext() {
        return ops.findNext().ok
    },

    findPrev() {
        return ops.findPrev().ok
    },

    findInfo() {
        return ops.findInfo()
    },

    isSourceMode() {
        return state.sourceMode
    },

    undo() {
        ops.undo()
    },

    redo() {
        ops.redo()
    },

    /** 诊断：校验命令名是否已注册且可运行（selftest 双端一致性校验） */
    hasCommands(names) {
        return ops.hasCommands({ names: Array.isArray(names) ? names : [] }).results
    },

    formatCommand(name, payload) {
        return ops.formatCommand({ name, payload }).applied
    },

    insertTable(row, col) {
        return ops.insertTable({ row, col }).ok
    },

    insertMarkdown(md) {
        return ops.insertMarkdown({ md }).ok
    },

    insertImage(src, alt, title) {
        return ops.insertImage({ src, alt, title }).applied
    },

    /** 粘贴图片导入回灌：兑现 hostCall('importImage') 的响应（选区快照在 core 内闭环） */
    onImageImported(requestId, payload) {
        const entry = importPending.get(requestId)
        if (!entry) return false
        importPending.delete(requestId)
        entry.resolve(payload || {})
        return true
    },

    /** 测试辅助：剪贴板图片载荷识别（blob=截图位图 / file=本地图片路径） */
    testImagePayload(data) {
        return ops.testImagePayload({ data }).payload
    },

    focus() {
        ops.focus()
    },

    requestStats() {
        ops.requestStats()
    },

    async exportStandaloneHTML() {
        return (await ops.exportStandaloneHTML()).html
    },
}
