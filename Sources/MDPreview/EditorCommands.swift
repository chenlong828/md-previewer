import AppKit

/// 菜单与右键菜单共用的命令定义(命令模式):编辑器动作与文档级动作共用同一份注册表。
/// 新增命令只需:① 在此声明 case;② 在 EditorCommands.all 登记规格;③ 控制器实现 @objc 动作。
enum EditorAction: Equatable, CaseIterable {
    case undo, redo
    case cut, copy, paste, selectAll
    case find, findNext, findPrev
    case copyFilePath
    case toggleSource
    case bold, italic, strikethrough, inlineCode, link
    case heading1, heading2, heading3, bodyText
    case quote, bulletList, orderedList
    case codeBlock, mathBlock
    case insertTable, insertHr
    case rowAbove, rowBelow, colLeft, colRight
    case deleteRow, deleteColumn, deleteTable
}

/// 单条命令规格:标题、动作、快捷键、可用条件与菜单归属。
struct EditorCommandSpec {
    let action: EditorAction
    let title: String
    let selector: Selector
    /// 菜单栏快捷键(右键菜单不展示快捷键)
    var key: String = ""
    var modifiers: NSEvent.ModifierFlags = []
    /// 仅当光标位于表格内时可用
    var requiresTable: Bool = false
    /// 是否出现在右键菜单
    var inContextMenu: Bool = false
    /// true:走 responder 链(剪切/拷贝/粘贴等系统编辑动作,输入框焦点时也能正确生效);
    /// false:由 DocumentWindowController 显式处理
    var responderChain: Bool = false
    /// 只读代码文档下是否可用(代码视图无编辑面:仅拷贝/全选/查找可保留)。
    /// 默认 false——新增命令不写 true 就不会误在代码文档里出现。
    var availableInCode: Bool = false
    /// web 端命令名:格式组为 formatCommand 参数,表格组为 tableCommand 参数。
    /// nil 表示走控制器专用处理(撤销/重做/查找/源码模式/数学块/插入表格)。
    /// 双端一致性(JS 注册表存在同名命令)由 selftest 遍历校验。
    var jsCommand: String? = nil
    /// formatCommand 的 payload(milkdown 命令为位置参数形态:标题级别是数字)
    var jsPayload: Any? = nil
}

enum EditorCommands {
    static let all: [EditorCommandSpec] = [
        EditorCommandSpec(action: .undo, title: "撤销", selector: #selector(DocumentWindowController.undoAction(_:)), key: "z", modifiers: .command, inContextMenu: true),
        EditorCommandSpec(action: .redo, title: "重做", selector: #selector(DocumentWindowController.redoAction(_:)), key: "z", modifiers: [.command, .shift], inContextMenu: true),
        EditorCommandSpec(action: .cut, title: "剪切", selector: #selector(NSText.cut(_:)), key: "x", modifiers: .command, inContextMenu: true, responderChain: true),
        EditorCommandSpec(action: .copy, title: "拷贝", selector: #selector(NSText.copy(_:)), key: "c", modifiers: .command, inContextMenu: true, responderChain: true, availableInCode: true),
        EditorCommandSpec(action: .paste, title: "粘贴", selector: #selector(NSText.paste(_:)), key: "v", modifiers: .command, inContextMenu: true, responderChain: true),
        EditorCommandSpec(action: .selectAll, title: "全选", selector: #selector(NSText.selectAll(_:)), key: "a", modifiers: .command, inContextMenu: true, responderChain: true, availableInCode: true),
        EditorCommandSpec(action: .find, title: "查找…", selector: #selector(DocumentWindowController.findAction(_:)), key: "f", modifiers: .command, inContextMenu: true, availableInCode: true),
        EditorCommandSpec(action: .findNext, title: "查找下一个", selector: #selector(DocumentWindowController.findNextAction(_:)), key: "g", modifiers: .command, availableInCode: true),
        EditorCommandSpec(action: .findPrev, title: "查找上一个", selector: #selector(DocumentWindowController.findPrevAction(_:)), key: "g", modifiers: [.command, .shift], availableInCode: true),
        EditorCommandSpec(action: .copyFilePath, title: "拷贝文件路径到剪贴板", selector: #selector(DocumentWindowController.copyFilePathAction(_:)), inContextMenu: true, availableInCode: true),
        EditorCommandSpec(action: .toggleSource, title: "源码模式", selector: #selector(DocumentWindowController.toggleSourceModeAction(_:)), key: "/", modifiers: .command, inContextMenu: true),
        EditorCommandSpec(action: .bold, title: "加粗", selector: #selector(DocumentWindowController.toggleBoldAction(_:)), key: "b", modifiers: .command, inContextMenu: true, jsCommand: "toggleStrongCommand"),
        EditorCommandSpec(action: .italic, title: "斜体", selector: #selector(DocumentWindowController.toggleItalicAction(_:)), key: "i", modifiers: .command, inContextMenu: true, jsCommand: "toggleEmphasisCommand"),
        EditorCommandSpec(action: .strikethrough, title: "删除线", selector: #selector(DocumentWindowController.toggleStrikethroughAction(_:)), key: "x", modifiers: [.command, .shift], inContextMenu: true, jsCommand: "toggleStrikethroughCommand"),
        EditorCommandSpec(action: .inlineCode, title: "行内代码", selector: #selector(DocumentWindowController.toggleInlineCodeAction(_:)), key: "c", modifiers: [.command, .shift], inContextMenu: true, jsCommand: "toggleInlineCodeCommand"),
        EditorCommandSpec(action: .link, title: "链接…", selector: #selector(DocumentWindowController.toggleLinkAction(_:)), key: "k", modifiers: .command, jsCommand: "toggleLinkCommand"),
        EditorCommandSpec(action: .heading1, title: "标题 1", selector: #selector(DocumentWindowController.heading1Action(_:)), key: "1", modifiers: .command, jsCommand: "wrapInHeadingCommand", jsPayload: 1),
        EditorCommandSpec(action: .heading2, title: "标题 2", selector: #selector(DocumentWindowController.heading2Action(_:)), key: "2", modifiers: .command, jsCommand: "wrapInHeadingCommand", jsPayload: 2),
        EditorCommandSpec(action: .heading3, title: "标题 3", selector: #selector(DocumentWindowController.heading3Action(_:)), key: "3", modifiers: .command, jsCommand: "wrapInHeadingCommand", jsPayload: 3),
        EditorCommandSpec(action: .bodyText, title: "正文", selector: #selector(DocumentWindowController.bodyTextAction(_:)), key: "0", modifiers: .command, jsCommand: "turnIntoTextCommand"),
        EditorCommandSpec(action: .quote, title: "引用", selector: #selector(DocumentWindowController.blockquoteAction(_:)), key: "b", modifiers: [.command, .shift], jsCommand: "wrapInBlockquoteCommand"),
        EditorCommandSpec(action: .bulletList, title: "无序列表", selector: #selector(DocumentWindowController.bulletListAction(_:)), key: "7", modifiers: [.command, .shift], jsCommand: "wrapInBulletListCommand"),
        EditorCommandSpec(action: .orderedList, title: "有序列表", selector: #selector(DocumentWindowController.orderedListAction(_:)), key: "8", modifiers: [.command, .shift], jsCommand: "wrapInOrderedListCommand"),
        EditorCommandSpec(action: .codeBlock, title: "代码块", selector: #selector(DocumentWindowController.codeBlockAction(_:)), key: "c", modifiers: [.command, .option], jsCommand: "createCodeBlockCommand"),
        EditorCommandSpec(action: .mathBlock, title: "数学公式块", selector: #selector(DocumentWindowController.mathBlockAction(_:)), key: "m", modifiers: [.command, .option]),
        EditorCommandSpec(action: .insertTable, title: "插入表格", selector: #selector(DocumentWindowController.insertTableAction(_:)), key: "t", modifiers: [.command, .option], inContextMenu: true),
        EditorCommandSpec(action: .insertHr, title: "分割线", selector: #selector(DocumentWindowController.hrAction(_:)), key: "-", modifiers: [.command, .shift], inContextMenu: true, jsCommand: "insertHrCommand"),
        EditorCommandSpec(action: .rowAbove, title: "在上方插入行", selector: #selector(DocumentWindowController.insertRowAboveAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "insertRowAbove"),
        EditorCommandSpec(action: .rowBelow, title: "在下方插入行", selector: #selector(DocumentWindowController.insertRowBelowAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "insertRowBelow"),
        EditorCommandSpec(action: .colLeft, title: "在左侧插入列", selector: #selector(DocumentWindowController.insertColLeftAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "insertColLeft"),
        EditorCommandSpec(action: .colRight, title: "在右侧插入列", selector: #selector(DocumentWindowController.insertColRightAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "insertColRight"),
        EditorCommandSpec(action: .deleteRow, title: "删除所在行", selector: #selector(DocumentWindowController.deleteRowAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "deleteRow"),
        EditorCommandSpec(action: .deleteColumn, title: "删除所在列", selector: #selector(DocumentWindowController.deleteColumnAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "deleteColumn"),
        EditorCommandSpec(action: .deleteTable, title: "删除表格", selector: #selector(DocumentWindowController.deleteTableAction(_:)), requiresTable: true, inContextMenu: true, jsCommand: "deleteTable"),
    ]

    static func spec(for action: EditorAction) -> EditorCommandSpec? {
        all.first { $0.action == action }
    }

    /// 构建 NSMenuItem。
    /// - contextTarget 非 nil 时(右键菜单)显式指定 target;responderChain 型命令保持 nil 走响应链。
    /// - 菜单栏调用传 contextTarget = nil,由 responder 链路由到当前文档窗口。
    static func menuItem(for action: EditorAction, contextTarget: AnyObject? = nil) -> NSMenuItem? {
        guard let spec = spec(for: action) else { return nil }
        let item = NSMenuItem(title: spec.title, action: spec.selector, keyEquivalent: spec.key)
        item.keyEquivalentModifierMask = spec.modifiers
        if let target = contextTarget, !spec.responderChain {
            item.target = target
        }
        return item
    }

    /// 把一组命令追加到菜单(自动跳过缺失项);菜单栏调用,target 由响应链路由
    static func append(_ actions: [EditorAction], to menu: NSMenu) {
        for action in actions {
            if let item = menuItem(for: action) {
                menu.addItem(item)
            }
        }
    }
}
