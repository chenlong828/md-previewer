// 代码高亮语法注册表:代码视图（code-view.js）与编辑器围栏代码块共用同一个
// refractor 单例与注册表。Swift 侧 FileSupport.codeLanguages 的 id 必须在此可高亮，
// 由 selftest「代码视图 双端语言清单一致」守门。
//
// refractor 主入口（common）已注册 62 种常用语言（c/cpp/swift/python/js/ts/go/rust/
// java/kotlin/php/sql/bash/yaml/json/markup(xml,html,svg)/ini/diff/lua/perl/r/…），
// 这里只补它没有的语法；新增语言时先查 refractor/lang 是否已随 common 提供。
import { refractor } from 'refractor'
import dart from 'refractor/dart'
import docker from 'refractor/docker'
import graphql from 'refractor/graphql'
import scala from 'refractor/scala'
import toml from 'refractor/toml'
import powershell from 'refractor/powershell'
import haskell from 'refractor/haskell'
import groovy from 'refractor/groovy'
import protobuf from 'refractor/protobuf'
import elixir from 'refractor/elixir'
import jsx from 'refractor/jsx'
import tsx from 'refractor/tsx'
import cmake from 'refractor/cmake'
import vim from 'refractor/vim'

const extraLanguages = [
    dart, docker, graphql, scala, toml, powershell, haskell, groovy,
    protobuf, elixir, jsx, tsx, cmake, vim,
]

let ensured = false

/** 幂等注册：编辑器创建与代码视图首次渲染都会调用，重复调用无副作用。 */
export function ensureLanguages() {
    if (ensured) return
    ensured = true
    for (const language of extraLanguages) {
        try {
            refractor.register(language)
        } catch (e) {
            // 已注册（与 editor.js 的插件初始化顺序有关）时忽略
        }
    }
}

/** id 是否为可高亮语法；plaintext/auto 不是语法。 */
export function hasLanguage(id) {
    if (!id || id === 'plaintext' || id === 'auto') return false
    ensureLanguages()
    return refractor.registered(id)
}

/** hast 节点 → DOM（只搬 tagName/className/文本；不拼 innerHTML，天然转义）。 */
function hastToDOM(node) {
    if (node.type === 'text') return document.createTextNode(node.value || '')
    const el = document.createElement(node.tagName || 'span')
    const className = node.properties && node.properties.className
    if (className) {
        el.className = Array.isArray(className) ? className.join(' ') : String(className)
    }
    for (const child of node.children || []) el.appendChild(hastToDOM(child))
    return el
}

/**
 * 把 text 按 id 语法高亮后追加进 container。
 * 返回 false 表示语言不可用或高亮失败（调用方回落纯文本，不抛错）。
 */
export function highlightInto(container, text, id) {
    if (!hasLanguage(id)) return false
    let tree
    try {
        tree = refractor.highlight(text, id)
    } catch (e) {
        return false
    }
    const fragment = document.createDocumentFragment()
    for (const child of tree.children || []) fragment.appendChild(hastToDOM(child))
    container.appendChild(fragment)
    return true
}
