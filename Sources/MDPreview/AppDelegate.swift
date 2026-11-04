import AppKit
import os.log

/// 菜单 identifier 常量:构建与联动(findMenu/updateMenuItem)共用同一出处,
/// 拼写错误在编译期暴露,不再有裸字符串递归查找。
enum MenuID {
    static let fileMenu = NSUserInterfaceItemIdentifier("fileMenu")
    static let viewMenu = NSUserInterfaceItemIdentifier("viewMenu")
    static let appearanceMenu = NSUserInterfaceItemIdentifier("appearanceMenu")
    static let recentsMenu = NSUserInterfaceItemIdentifier("recentsMenu")
    static let viewSourceMode = NSUserInterfaceItemIdentifier("view.sourceMode")
    static let viewDrawer = NSUserInterfaceItemIdentifier("view.drawer")
    static let viewCodeLineNumbers = NSUserInterfaceItemIdentifier("view.codeLineNumbers")
    static let viewHighlightLanguage = NSUserInterfaceItemIdentifier("view.highlightLanguage")
    static let appearanceAuto = NSUserInterfaceItemIdentifier("appearance.auto")
    static let appearanceLight = NSUserInterfaceItemIdentifier("appearance.light")
    static let appearanceDark = NSUserInterfaceItemIdentifier("appearance.dark")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    /// 所有打开的文档窗口(Typora 模型:单进程多窗口,Dock 图标只有一个)
    private(set) var documents: [DocumentWindowController] = []
    private var recentsMenu: NSMenu?
    private var appearanceObservation: NSKeyValueObservation?
    private var pinnedAppearance: NSAppearance.Name? // nil = 跟随系统
    // 不变量(启动矩阵):CLI 参数路径只由 openFromCommandLineIfNeeded 走一次;
    // application(_:openFile:) 由 LaunchServices 在 applicationDidFinishLaunching
    // 之后送达(AppKit 启动时序保证),argvFileHandled 记录该事实防止 CLI 重复开窗。
    // 防御:个别环境同一文档可能同时经 CLI 与 LaunchServices 双路送达,按标准化 URL 去重。
    private var argvFileHandled = false
    private var cliOpenedURLs: Set<URL> = []
    /// 退出确认流程进行中(挂起 .terminateLater 到 reply 之间)
    private var isTerminateConfirming = false

    private let recentFilesKey = "recentFiles"

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildMenus()
        observeSystemAppearance()
        observeWindowCloseNotifications()

        openFromCommandLineIfNeeded()
        if documents.isEmpty {
            makeEmptyDocument()
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // 由 `open xxx.md` / Finder / LaunchServices 触发 → 新窗口
        argvFileHandled = true
        let url = URL(fileURLWithPath: filename).standardizedFileURL
        if cliOpenedURLs.contains(url) { return true } // 与 CLI 路径双送达时去重
        openInNewWindow(at: url)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && documents.isEmpty {
            makeEmptyDocument()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminateConfirming { return .terminateCancel } // 确认流程已在跑:取消重复请求
        isTerminateConfirming = true
        let dirty = documents.filter { $0.isDirty }
        guard !dirty.isEmpty else {
            isTerminateConfirming = false
            return .terminateNow
        }
        // 保存确认是异步流程(sheet 回调,见 beginConfirmClose):这里挂起退出,
        // 逐窗口串行确认完毕后再 reply。sheet 运行期间 AppKit 会禁用菜单键等价键,
        // 正常路径不会重入;Dock/AppleScript 重复触发由 isTerminateConfirming 挡下。
        beginTerminateConfirmation(pending: dirty)
        return .terminateLater
    }

    /// 逐窗口串行确认;全部可安全关闭后才 reply(true),任一取消/保存失败即 reply(false)
    private func beginTerminateConfirmation(pending: [DocumentWindowController]) {
        var queue = pending
        func confirmNext() {
            guard let next = queue.first else {
                isTerminateConfirming = false
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            queue.removeFirst()
            next.beginConfirmClose(allowCancel: false) { [weak self] confirmed in
                if confirmed {
                    confirmNext()
                } else {
                    self?.isTerminateConfirming = false
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            }
        }
        confirmNext()
    }

    // MARK: - 多窗口管理

    /// 新建空文档窗口
    @discardableResult
    func makeEmptyDocument() -> DocumentWindowController {
        let controller = DocumentWindowController()
        documents.append(controller)
        controller.showWindow(nil)
        return controller
    }

    /// 在新窗口打开文档(目录入参自动路由到目录窗口:
    /// LaunchServices/拖放/文档链接等所有既有调用方统一收敛,不再出现"目录当文件读失败")
    func openInNewWindow(at url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            openDirectoryWindow(at: url)
            return
        }
        let controller = makeEmptyDocument()
        controller.openDocument(at: url)
    }

    /// 新建目录模式窗口:右侧空白编辑器,抽屉展示该目录树
    @discardableResult
    func openDirectoryWindow(at url: URL) -> DocumentWindowController {
        let controller = makeEmptyDocument()
        controller.openDirectory(at: url)
        return controller
    }

    private func observeWindowCloseNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  let controller = window.windowController as? DocumentWindowController else { return }
            self.documents.removeAll { $0 === controller }
        }
    }

    // MARK: - 命令行参数打开

    private func openFromCommandLineIfNeeded() {
        guard !argvFileHandled else { return }
        let args = CommandLine.arguments.dropFirst()
        for arg in args where !arg.hasPrefix("-") {
            let path = arg.hasPrefix("~/")
                ? NSString(string: "~/").expandingTildeInPath + arg.dropFirst() : arg
            var isDir: ObjCBool = false
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                argvFileHandled = true
                if isDir.boolValue {
                    openDirectoryWindow(at: url.standardizedFileURL)
                } else {
                    let target = url.standardizedFileURL
                    cliOpenedURLs.insert(target)
                    openInNewWindow(at: target)
                }
                return
            }
        }
    }

    // MARK: - 窗口注册

    var currentDocument: DocumentWindowController? {
        if let key = NSApp.keyWindow?.windowController as? DocumentWindowController { return key }
        if let main = NSApp.mainWindow?.windowController as? DocumentWindowController { return main }
        return documents.last
    }

    // MARK: - 外观 / 主题

    private func observeSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.pushThemeToWeb()
            }
        }
    }

    func currentThemeJS() -> String {
        let effective = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
        return effective == .darkAqua ? "dark" : "light"
    }

    private func pushThemeToWeb() {
        let theme = currentThemeJS()
        for controller in documents {
            controller.callJSPublic("window.mdbridge.setTheme(\(JSArgs.string(theme)))")
        }
    }

    /// 行号偏好变更后广播所有代码窗口;Markdown 窗口由控制器自行 no-op。
    func applyCodeLineNumbersToAllDocuments() {
        for controller in documents {
            controller.applyCodeLineNumbersPreference()
        }
    }

    func setAppearanceMode(_ mode: String) {
        switch mode {
        case "light": pinnedAppearance = NSAppearance.Name.aqua
        case "dark": pinnedAppearance = NSAppearance.Name.darkAqua
        default: pinnedAppearance = nil
        }
        NSApp.appearance = pinnedAppearance.flatMap { NSAppearance(named: $0) }
        UserDefaults.standard.set(mode, forKey: "appearanceMode")
        pushThemeToWeb()
        refreshAppearanceMenuState()
    }

    /// 外观三态联动表:(菜单, 菜单项, 存储值)。刷新与勾选全部按表驱动。
    private static let appearanceItems: [(menu: NSUserInterfaceItemIdentifier, item: NSUserInterfaceItemIdentifier, mode: String)] = [
        (MenuID.appearanceMenu, MenuID.appearanceAuto, "auto"),
        (MenuID.appearanceMenu, MenuID.appearanceLight, "light"),
        (MenuID.appearanceMenu, MenuID.appearanceDark, "dark"),
    ]

    func refreshAppearanceMenuState() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "auto"
        for entry in Self.appearanceItems {
            updateMenuItem(in: entry.menu, id: entry.item, selected: saved == entry.mode)
        }
    }

    func refreshViewMenuState() {
        let inSource = currentDocument?.inSourceMode ?? false
        updateMenuItem(in: MenuID.viewMenu, id: MenuID.viewSourceMode, selected: inSource)
        updateMenuItem(in: MenuID.viewMenu, id: MenuID.viewDrawer, selected: currentDocument?.isDrawerVisible ?? false)
        updateMenuItem(in: MenuID.viewMenu, id: MenuID.viewCodeLineNumbers, selected: DocumentWindowController.codeLineNumbersVisible)
    }

    private func updateMenuItem(in menuId: NSUserInterfaceItemIdentifier, id: NSUserInterfaceItemIdentifier, selected: Bool) {
        guard let menu = NSApp.mainMenu, let submenu = findMenu(named: menuId, in: menu) else { return }
        for item in submenu.items where item.identifier == id {
            item.state = selected ? .on : .off
        }
    }

    private func findMenu(named id: NSUserInterfaceItemIdentifier, in menu: NSMenu) -> NSMenu? {
        for item in menu.items {
            if item.identifier == id, let sub = item.submenu { return sub }
            if let sub = item.submenu, let found = findMenu(named: id, in: sub) { return found }
        }
        return nil
    }

    // MARK: - 最近文件

    func addRecentFile(_ url: URL) {
        var recents = recentFiles()
        recents.removeAll { $0.absoluteString == url.absoluteString }
        recents.insert(url, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        UserDefaults.standard.set(recents.map { $0.absoluteString }, forKey: recentFilesKey)
        rebuildRecentsMenu()
    }

    private func recentFiles() -> [URL] {
        guard let list = UserDefaults.standard.stringArray(forKey: recentFilesKey) else { return [] }
        return list.compactMap { URL(string: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func rebuildRecentsMenu() {
        guard let menu = recentsMenu else { return }
        menu.removeAllItems()
        let recents = recentFiles()
        if recents.isEmpty {
            let item = NSMenuItem(title: "无最近文件", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (index, url) in recents.enumerated() {
                let item = NSMenuItem(
                    title: url.lastPathComponent + "  —  " + url.deletingLastPathComponent().path,
                    action: #selector(openRecentFile(_:)),
                    keyEquivalent: index < 9 ? String(index + 1) : "")
                item.keyEquivalentModifierMask = [.command, .option]
                item.representedObject = url
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "清空菜单", action: #selector(clearRecentFiles(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openInCurrentWindowOrNew(at: url)
    }

    /// 程序内菜单打开动作的统一语义:当前窗口覆盖打开(与抽屉双击/⌘O 一致),
    /// 无文档窗口时才新建窗口。Finder/命令行等外部打开仍走 openInNewWindow(多窗口模型)。
    func openInCurrentWindowOrNew(at url: URL) {
        if let current = currentDocument {
            current.openDocument(at: url)
        } else {
            openInNewWindow(at: url)
        }
    }

    @objc private func clearRecentFiles(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
        rebuildRecentsMenu()
    }

    // MARK: - 菜单构建

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier == MenuID.recentsMenu { rebuildRecentsMenu() }
        if menu.identifier == MenuID.viewHighlightLanguage { updateHighlightLanguageMenu(menu) }
    }

    /// 「高亮语言」子菜单:仅代码文档可用,勾选当前选择(自动/纯文本/语言 id 三者之一)。
    /// 菜单项状态在开菜单时统一刷新(用户可能用 ⌘/ 或换文件改变过状态)。
    private func updateHighlightLanguageMenu(_ menu: NSMenu) {
        guard let doc = currentDocument else {
            for item in menu.items where !item.isSeparatorItem { item.isEnabled = false }
            return
        }
        let isCode = doc.isCodeDocument
        let selected = doc.highlightMenuSelection
        for item in menu.items where !item.isSeparatorItem {
            item.isEnabled = isCode
            item.state = (item.representedObject as? String) == selected ? .on : .off
        }
    }

    /// 追加一个子菜单并在其中构建菜单项(消除逐级声明的样板嵌套)
    @discardableResult
    private static func appendSubmenu(
        _ title: String, to parent: NSMenu, id: NSUserInterfaceItemIdentifier? = nil, _ build: (NSMenu) -> Void
    ) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        menu.identifier = id
        parent.addItem(item)
        build(menu)
        return menu
    }

    private func buildMenus() {
        let main = NSMenu()

        // ─── App 菜单
        Self.appendSubmenu("MDPreview", to: main) { menu in
            menu.addItem(withTitle: "关于 MDPreview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "隐藏 MDPreview", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            let hideOthers = menu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            hideOthers.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 MDPreview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }

        // ─── 文件
        Self.appendSubmenu("文件", to: main, id: MenuID.fileMenu) { menu in
            menu.addItem(withTitle: "新建", action: #selector(self.newDocumentAction(_:)), keyEquivalent: "n")
            menu.addItem(withTitle: "打开…", action: #selector(DocumentWindowController.openDocumentAction(_:)), keyEquivalent: "o")
            let openFolder = menu.addItem(withTitle: "打开文件夹…", action: #selector(DocumentWindowController.openFolderAction(_:)), keyEquivalent: "o")
            openFolder.keyEquivalentModifierMask = [.command, .shift]
            let recentsItem = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
            let recents = NSMenu(title: "打开最近使用")
            recents.identifier = MenuID.recentsMenu
            recents.delegate = self
            recentsItem.submenu = recents
            self.recentsMenu = recents
            menu.addItem(recentsItem)
            menu.addItem(.separator())
            menu.addItem(withTitle: "保存", action: #selector(DocumentWindowController.saveDocumentAction(_:)), keyEquivalent: "s")
            let saveAs = menu.addItem(withTitle: "另存为…", action: #selector(DocumentWindowController.saveDocumentAsAction(_:)), keyEquivalent: "s")
            saveAs.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(.separator())
            menu.addItem(withTitle: "在 Finder 中显示", action: #selector(DocumentWindowController.revealInFinderAction(_:)), keyEquivalent: "r")
            menu.addItem(.separator())
            menu.addItem(withTitle: "导出 PDF…", action: #selector(DocumentWindowController.exportPDFAction(_:)), keyEquivalent: "e")
            let exportHTML = menu.addItem(withTitle: "导出 HTML…", action: #selector(DocumentWindowController.exportHTMLAction(_:)), keyEquivalent: "h")
            exportHTML.keyEquivalentModifierMask = [.command, .shift]
            menu.addItem(withTitle: "打印…", action: #selector(DocumentWindowController.printDocumentAction(_:)), keyEquivalent: "p")
            menu.addItem(.separator())
            menu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        }

        // ─── 编辑
        Self.appendSubmenu("编辑", to: main) { menu in
            // 命令注册表统一驱动(与右键菜单共用定义)
            EditorCommands.append([.undo, .redo], to: menu)
            menu.addItem(.separator())
            EditorCommands.append([.cut, .copy, .paste, .selectAll], to: menu)
            menu.addItem(.separator())
            EditorCommands.append([.find, .findNext, .findPrev], to: menu)
        }

        // ─── 格式
        Self.appendSubmenu("格式", to: main) { menu in
            // 命令注册表统一驱动(与右键菜单共用定义)
            EditorCommands.append([.bold, .italic, .strikethrough, .inlineCode, .link], to: menu)
            menu.addItem(.separator())
            EditorCommands.append([.heading1, .heading2, .heading3, .bodyText], to: menu)
            menu.addItem(.separator())
            EditorCommands.append([.quote, .bulletList, .orderedList], to: menu)
            menu.addItem(.separator())
            EditorCommands.append([.codeBlock, .mathBlock, .insertTable], to: menu)
            // 表格子菜单:同一注册表
            let tableItem = NSMenuItem(title: "表格", action: nil, keyEquivalent: "")
            let tableMenu = NSMenu(title: "表格")
            tableItem.submenu = tableMenu
            EditorCommands.append([.rowAbove, .rowBelow, .colLeft, .colRight], to: tableMenu)
            tableMenu.addItem(.separator())
            EditorCommands.append([.deleteRow, .deleteColumn, .deleteTable], to: tableMenu)
            menu.addItem(tableItem)
            if let hr = EditorCommands.menuItem(for: .insertHr) { menu.addItem(hr) }
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "插入图片…",
                action: #selector(DocumentWindowController.insertImageAction(_:)),
                keyEquivalent: "")
        }

        // ─── 视图
        Self.appendSubmenu("视图", to: main, id: MenuID.viewMenu) { menu in
            let zoomIn = menu.addItem(withTitle: "放大", action: #selector(DocumentWindowController.zoomInAction(_:)), keyEquivalent: "+")
            zoomIn.keyEquivalentModifierMask = [.command]
            let zoomOut = menu.addItem(withTitle: "缩小", action: #selector(DocumentWindowController.zoomOutAction(_:)), keyEquivalent: "-")
            zoomOut.keyEquivalentModifierMask = [.command]
            menu.addItem(withTitle: "实际大小", action: #selector(DocumentWindowController.zoomResetAction(_:)), keyEquivalent: "0")
            menu.addItem(.separator())
            let sourceItem = menu.addItem(withTitle: "源码模式", action: #selector(DocumentWindowController.toggleSourceModeAction(_:)), keyEquivalent: "/")
            sourceItem.identifier = MenuID.viewSourceMode
            menu.addItem(.separator())
            // 行号开关:代码文档专用(REQ-0010)。全局偏好,勾选状态由 validateMenuItem
            // 与 refreshViewMenuState 同步;Markdown 文档置灰。
            let lineNumberItem = menu.addItem(
                withTitle: "显示行号",
                action: #selector(DocumentWindowController.toggleCodeLineNumbersAction(_:)),
                keyEquivalent: "")
            lineNumberItem.identifier = MenuID.viewCodeLineNumbers
            // 高亮语言子菜单:代码文档专用(REQ-0009)。勾选状态由 menuNeedsUpdate 刷新,
            // 关闭自动置灰以避免 AppKit 默认校验覆盖我们的状态。
            Self.appendSubmenu("高亮语言", to: menu, id: MenuID.viewHighlightLanguage) { languageMenu in
                languageMenu.autoenablesItems = false
                languageMenu.delegate = self
                let auto = languageMenu.addItem(
                    withTitle: "自动（按扩展名）",
                    action: #selector(DocumentWindowController.setHighlightLanguageAction(_:)),
                    keyEquivalent: "")
                auto.representedObject = FileSupport.autoLanguageID
                let plain = languageMenu.addItem(
                    withTitle: "纯文本",
                    action: #selector(DocumentWindowController.setHighlightLanguageAction(_:)),
                    keyEquivalent: "")
                plain.representedObject = FileSupport.plainTextID
                languageMenu.addItem(.separator())
                for language in FileSupport.codeLanguages.sorted(by: {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }) {
                    let item = languageMenu.addItem(
                        withTitle: language.displayName,
                        action: #selector(DocumentWindowController.setHighlightLanguageAction(_:)),
                        keyEquivalent: "")
                    item.representedObject = language.id
                }
            }
            menu.addItem(.separator())
            let drawerItem = menu.addItem(withTitle: "文件抽屉", action: #selector(DocumentWindowController.toggleDrawerAction(_:)), keyEquivalent: "\\")
            drawerItem.identifier = MenuID.viewDrawer
            menu.addItem(.separator())
            Self.appendSubmenu("外观", to: menu, id: MenuID.appearanceMenu) { appearance in
                let auto = appearance.addItem(withTitle: "跟随系统", action: #selector(AppDelegate.appearanceAutoAction(_:)), keyEquivalent: "")
                auto.identifier = MenuID.appearanceAuto
                auto.target = self
                let light = appearance.addItem(withTitle: "浅色", action: #selector(AppDelegate.appearanceLightAction(_:)), keyEquivalent: "")
                light.identifier = MenuID.appearanceLight
                light.target = self
                let dark = appearance.addItem(withTitle: "深色", action: #selector(AppDelegate.appearanceDarkAction(_:)), keyEquivalent: "")
                dark.identifier = MenuID.appearanceDark
                dark.target = self
            }
        }

        // ─── 窗口
        Self.appendSubmenu("窗口", to: main) { menu in
            menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            menu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        }

        NSApp.mainMenu = main
        rebuildRecentsMenu()
        refreshAppearanceMenuState()
    }

    @objc private func newDocumentAction(_ sender: Any?) {
        makeEmptyDocument()
    }

    // MARK: - 外观菜单动作

    @objc private func appearanceAutoAction(_ sender: NSMenuItem) { setAppearanceMode("auto") }
    @objc private func appearanceLightAction(_ sender: NSMenuItem) { setAppearanceMode("light") }
    @objc private func appearanceDarkAction(_ sender: NSMenuItem) { setAppearanceMode("dark") }
}
