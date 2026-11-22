// 语法注册表测试（Node + jsdom，零 WebView）：Lean 4 是仓库自带的 Prism 语法
// （`src/kernel/components/code/lean-grammar.js`），这里守门两件事——
// 注册表按 id 认得它；高亮产出 typora.css 调色板已有的 token 类且字符原样。
import test from 'node:test'
import assert from 'node:assert/strict'
import { JSDOM } from 'jsdom'

const dom = new JSDOM('<!doctype html><html><body><div id="host"></div></body></html>')
globalThis.document = dom.window.document

const { ensureLanguages, hasLanguage, highlightInto } = await import(
    '../src/kernel/components/code/languages.js'
)

test('languages: 幂等注册后按 id 判定语法', () => {
    ensureLanguages()
    ensureLanguages()
    assert.equal(hasLanguage('lean'), true)
    assert.equal(hasLanguage('lean4'), true) // lean-grammar.js 注册的别名
    assert.equal(hasLanguage('swift'), true) // refractor common 自带的语言不受影响
    assert.equal(hasLanguage('plaintext'), false)
    assert.equal(hasLanguage('auto'), false)
    assert.equal(hasLanguage('no-such-grammar'), false)
})

test('languages: Lean 高亮 token 类在调色板内且文本原样', () => {
    const host = dom.window.document.getElementById('host')
    const source =
        '/- 示例:前 n 个奇数 -/\n@[simp] theorem add_zero (n : Nat) : n + 0 = n := by\n  rfl\n-- 末尾注释\n'

    assert.equal(highlightInto(host, source, 'lean'), true)
    assert.equal(host.textContent, source) // 只切 span，不改字符（含中文）

    const classes = new Set([...host.querySelectorAll('.token')].map((el) => el.className))
    for (const expected of [
        'token comment',
        'token attribute',
        'token keyword',
        'token class-name',
        'token operator',
        'token number',
        'token builtin',
    ]) {
        assert.ok(classes.has(expected), `缺少 ${expected}，实际 ${[...classes].join(', ')}`)
    }
})
