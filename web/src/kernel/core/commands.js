// 命令注册表:名字 → 预设导出的命令插件对象(注册后带 .run(payload) 方法,
// payload 为位置参数形态)。只登记 Swift 侧(@objc 动作)实际转发的命令名——
// 表格行列命令由 tables.js 的 tableCommandImpls 承载,不经此表。
// 双端一致性(JS 注册表存在同名命令)由 selftest 遍历校验。
import {
    turnIntoTextCommand,
    toggleStrongCommand,
    toggleEmphasisCommand,
    toggleInlineCodeCommand,
    toggleLinkCommand,
    wrapInHeadingCommand,
    wrapInBlockquoteCommand,
    wrapInBulletListCommand,
    wrapInOrderedListCommand,
    insertHrCommand,
    createCodeBlockCommand,
    insertImageCommand,
} from '@milkdown/preset-commonmark'
import {
    insertTableCommand,
    toggleStrikethroughCommand,
} from '@milkdown/preset-gfm'

export const commandRegistry = {
    toggleStrongCommand, toggleEmphasisCommand, toggleInlineCodeCommand, toggleLinkCommand,
    wrapInHeadingCommand, wrapInBlockquoteCommand, wrapInBulletListCommand, wrapInOrderedListCommand,
    insertHrCommand, createCodeBlockCommand, turnIntoTextCommand,
    insertTableCommand, toggleStrikethroughCommand,
    // 壳/拖放导入完成后经 op insertImage 转发(插入图片节点,唯一入口)
    insertImageCommand,
}
