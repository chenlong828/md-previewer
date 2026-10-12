// 依赖卫生校验(安装后自动跑,也可 node check-deps.mjs 手动跑):
// 1) dependencies 禁止出现独立 prosemirror-* 包——ProseMirror 统一从 @milkdown/prose
//    取用(bridge.js undo/redo、main.js 样式),双来源会引入两份 ProseMirror 运行时。
// 2) node_modules/@milkdown/* 下的嵌套拷贝必须逐个在白名单内(嵌套拷贝 = 版本漂移;
//    唯一白名单:plugin-math@7.5.9 混版策略自带的 @milkdown/utils@7.5.9 与
//    @milkdown/exception@7.5.9,见 package.json //milkdown-versions 字段)。
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(fileURLToPath(import.meta.url))
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const offenders = Object.keys(pkg.dependencies ?? {}).filter((k) => k.startsWith('prosemirror-'))
if (offenders.length > 0) {
    console.error(`[check-deps] 禁止独立 prosemirror-* 依赖: ${offenders.join(', ')}(统一从 @milkdown/prose 取用)`)
    process.exit(1)
}
const allowedNested = new Set([
    '@milkdown/plugin-math/node_modules/@milkdown/utils',
    '@milkdown/plugin-math/node_modules/@milkdown/exception',
])
const milkdown = join(root, 'node_modules', '@milkdown')
if (existsSync(milkdown)) {
    for (const name of readdirSync(milkdown)) {
        const nested = join(milkdown, name, 'node_modules')
        if (!existsSync(nested)) continue
        for (const scope of readdirSync(nested)) {
            const entries = readdirSync(join(nested, scope)).map((n) => `@milkdown/${name}/node_modules/${scope}/${n}`)
            for (const entry of entries) {
                if (!allowedNested.has(entry)) {
                    console.error(`[check-deps] 白名单外嵌套拷贝: ${entry}(版本漂移风险)`)
                    process.exit(1)
                }
            }
        }
    }
}
console.log('[check-deps] OK: 无独立 prosemirror-* 依赖,无嵌套拷贝')
