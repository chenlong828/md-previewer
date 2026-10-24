// 列表 markdown 序列化:每级嵌套缩进 4 空格(Tab 等价的标准缩进),首行标记保持紧凑。
//
// 为什么不用 mdast 的 `listItemIndent: 'tab'`:该模式会把首行标记也补到 4 列
// (`-   a`、`1.  a`),不是标准形态;`'one'` 则按"内容列"只缩 2 空格。
// mdast 没有"首行紧凑 + 续行 4 空格"的现成选项,故用 handlers.listItem 覆盖。
//
// 覆盖的代价:GFM 任务列表的复选框由 mdast-util-gfm-task-list-item 注册的
// listItem handler 输出,覆盖后在选项层会被顶掉——因此这里复刻它的复选框语义
// (`node.checked` → `[x]` / `[ ]`),否则保存会把复选框吞掉。
//
// 尺寸规则:`max(4, 标记宽 + 1)`。`- ` / `1. ` 取 4;`100. ` 取 5,
// 保证续行不低于内容列,CommonMark 解析层级不变。

/// 任务列表复选框 + 4 空格缩进的 listItem 序列化。
export function fourSpaceListItem(node, parent, state, info) {
    const head = node.children && node.children[0]
    const checkable = typeof node.checked === 'boolean' && head && head.type === 'paragraph'
    const checkbox = '[' + (node.checked ? 'x' : ' ') + '] '
    const tracker = state.createTracker(info)
    if (checkable) tracker.move(checkbox)
    let value = indentFourSpaces(node, parent, state, checkable ? { ...info, ...tracker.current() } : info)
    if (checkable) {
        value = value.replace(/^(?:[*+-]|\d+\.)([\r\n]| {1,3})/, ($0) => $0 + checkbox)
    }
    return value
}

function indentFourSpaces(node, parent, state, info) {
    // 无序列表取当前 bullet;有序列表由父列表 start + 序号拼出 `1.` 这类标记
    let bullet = state.bulletCurrent === undefined ? '-' : state.bulletCurrent
    if (parent && parent.type === 'list' && parent.ordered) {
        const start = typeof parent.start === 'number' && parent.start > -1 ? parent.start : 1
        const step = state.options.incrementListMarker === false ? 0 : parent.children.indexOf(node)
        bullet = String(start + step) + bullet
    }
    const size = Math.max(4, bullet.length + 1)
    const tracker = state.createTracker(info)
    tracker.move(bullet + ' ')
    tracker.shift(size)
    const exit = state.enter('listItem')
    const value = state.indentLines(
        state.containerFlow(node, tracker.current()),
        (line, index, blank) => {
            if (index === 0) return (blank ? bullet : bullet + ' ') + line
            return (blank ? '' : ' '.repeat(size)) + line
        },
    )
    exit()
    return value
}
