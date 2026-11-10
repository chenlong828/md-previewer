// 语义套件 C 组（core）：内核在 Node + jsdom 里跑完整编辑器，零 WebView、零 Swift。
// 这组测试就是「Windows 壳可参照」的证据：core 的 op 只依赖 DOM 与总线。
import test from 'node:test'
import assert from 'node:assert/strict'

import { bootCore, notificationsOf } from './support/dom.js'

const DOC = '# 标题\n\n正文一。\n\n![图](img/a.png)\n\n| a | b |\n| - | - |\n| 1 | 2 |\n'

test('core 组：jsdom 内核（无 WebView）', async (t) => {
    const core = await bootCore({ files: ['img/a.png', 'img/a b.png'] })
    const { ops } = core

    await t.test('init 建编辑器并上报 ready', async () => {
        const result = await ops.init({ markdown: DOC, opts: { theme: 'light', baseDir: core.baseDir } })
        assert.deepEqual(result, { ok: true })
        assert.equal(ops.getState().ready, true)
        assert.equal(notificationsOf(core.notifications, 'ready').length, 1)
    })

    await t.test('缩略图：init 应用偏好，setMinimapVisible/minimapInfo 经端口工作', () => {
        const initial = ops.minimapInfo()
        assert.equal(initial.started, false)
        assert.equal(initial.pref, true)
        assert.equal(initial.surface, 'markdown')

        assert.deepEqual(ops.setMinimapVisible({ visible: false }), { visible: false, effective: false })
        assert.equal(ops.minimapInfo().pref, false)
        ops.setMinimapVisible({ visible: true })
        assert.equal(ops.minimapInfo().pref, true)
    })

    await t.test('装载改写：经壳作答把相对引用改写为可加载 URL', () => {
        const md = ops.getMarkdown().md
        assert.match(md, /!\[图\]\(file:\/\/\/virtual\/base\/img\/a\.png\)/)
        assert.deepEqual(core.hostCalls.at(-1).op, 'resolveResources')
    })

    await t.test('保存口径：目录内引用还原为相对路径', () => {
        const saved = ops.getSaveMarkdown()
        assert.match(saved.md, /!\[图\]\(img\/a\.png\)/)
        assert.doesNotMatch(saved.md, /file:\/\//)
    })

    await t.test('模式状态机：代码视图与源码模式互斥，装载 markdown 退出代码视图', async () => {
        ops.setCode({ text: 'const a = 1\n', language: 'javascript' })
        assert.equal(ops.getState().codeMode, true)
        assert.equal(ops.toggleSource({ force: true }).sourceMode, false)

        await ops.setMarkdown({ md: DOC })
        assert.equal(ops.getState().codeMode, false)
        assert.equal(ops.getState().sourceMode, false)
    })

    await t.test('脏口径：装载后基线对齐，插入内容后 changed(dirty=true)', async () => {
        await ops.setMarkdown({ md: '# 干净\n' })
        ops.insertMarkdown({ md: '\n新增一行\n' })
        // editor 的 markdownUpdated 是异步回调：等一拍
        await new Promise((resolve) => setTimeout(resolve, 260))
        const changed = notificationsOf(core.notifications, 'changed')
        assert.ok(changed.length > 0, 'changed 应至少上报一次')
        assert.equal(changed.at(-1).dirty, true)
    })

    await t.test('统计口径：requestStats 读当前内容（源码模式下读 textarea）', () => {
        ops.requestStats()
        const stats = notificationsOf(core.notifications, 'stats').at(-1)
        assert.ok(stats && stats.chars > 0 && stats.words > 0)
    })

    await t.test('资源引用收集：宁多保护（两口径同时存在都进集合）', async () => {
        await ops.setMarkdown({ md: DOC })
        assert.deepEqual((await ops.getResourceRefs()).paths, [`${core.baseDir}/img/a.png`])
        // 字面写法不存在的编码引用：只要解码后存在，也不能被当成无引用
        await ops.setMarkdown({ md: '![x](img/a%20b.png)\n' })
        assert.deepEqual((await ops.getResourceRefs()).paths, [`${core.baseDir}/img/a b.png`])
    })

    await t.test('诊断 op：命令表、表格信息、图片载荷识别', async () => {
        await ops.setMarkdown({ md: DOC })
        const commands = ops.hasCommands({ names: ['toggleStrongCommand', 'notACommand'] })
        assert.equal(commands.results[0].ok, true)
        assert.equal(commands.results[1].ok, false)
        assert.equal(ops.testImagePayload({ data: { files: [] } }).payload, null)
        assert.deepEqual(ops.debugFocusTable().ok, true)
        const info = ops.tableInfo()
        assert.equal(info.inTable, true)
        assert.equal(info.rows, 2)
    })

    await t.test('表格行列：插入后光标进入新行/新列（连续操作沿同向累积）', async () => {
        await ops.setMarkdown({ md: '| H1 | H2 |\n| --- | --- |\n| A1 | A2 |\n' })
        const geo = () => {
            const info = ops.tableInfo()
            return { rows: info.rows, cols: info.cols, row: info.row, col: info.col }
        }
        assert.equal(ops.debugFocusTable().ok, true)
        assert.deepEqual(geo(), { rows: 2, cols: 2, row: 0, col: 0 })

        assert.equal(ops.tableCommand({ name: 'insertRowBelow' }).applied, true)
        assert.deepEqual(geo(), { rows: 3, cols: 2, row: 1, col: 0 })
        // 第二次插入必须相对新行(而非原行)发生,否则两次“下方插入”会反向堆叠
        assert.equal(ops.tableCommand({ name: 'insertRowBelow' }).applied, true)
        assert.deepEqual(geo(), { rows: 4, cols: 2, row: 2, col: 0 })
        // 删除的是刚插入的新行,原数据行保留
        assert.equal(ops.tableCommand({ name: 'deleteRow' }).applied, true)
        assert.deepEqual(geo(), { rows: 3, cols: 2, row: 2, col: 0 })

        assert.equal(ops.tableCommand({ name: 'insertColRight' }).applied, true)
        assert.deepEqual(geo(), { rows: 3, cols: 3, row: 2, col: 1 })
        assert.equal(ops.tableCommand({ name: 'insertColRight' }).applied, true)
        assert.deepEqual(geo(), { rows: 3, cols: 4, row: 2, col: 2 })
    })

    await t.test('代码视图信息与语言表', () => {
        ops.setCode({ text: 'x\n', language: 'javascript' })
        const info = ops.codeInfo()
        assert.equal(info.mode, true)
        assert.equal(info.language, 'javascript')
        assert.deepEqual(ops.hasLanguages({ ids: ['javascript', 'no-such-lang'] }).supported, ['javascript'])
    })

    t.after(() => core.cleanup())
})
