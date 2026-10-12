import AppKit
import os.log
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    /// 所有打开的文档窗口(Typora 模型:单进程多窗口,Dock 图标只有一个)
    private(set) var documents: [DocumentWindowController] = []
    /// 退出流程进行中:抑制各窗口的二次保存询问
    private(set) var isTerminating = false
    private var recentsMenu: NSMenu?
    private var appearanceObservation: NSKeyValueObservation?
    private var pinnedAppearance: NSAppearance.Name? // nil = 跟随系统
    private var argvFileHandled = false

    static let markdownUTTypes: [UTType] = {
        var types: [UTType] = []
        for ext in ["md", "markdown", "mdown", "mkdn", "mdtext", "mdwn"] {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types.isEmpty ? [.plainText] : types
    }()

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
        openInNewWindow(at: URL(fileURLWithPath: filename))
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
        isTerminating = true
        let dirty = documents.filter { $0.isDirty }
        guard !dirty.isEmpty else { return .terminateNow }
        // 每个有修改的窗口询问一次;isTerminating 抑制 windowShouldClose 的重复弹窗
        for controller in dirty {
            if !controller.confirmClose(allowCancel: true) {
                isTerminating = false
                return .terminateCancel
            }
        }
        return .terminateNow
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

    /// 在新窗口打开文档
    func openInNewWindow(at url: URL) {
        let controller = makeEmptyDocument()
        controller.openDocument(at: url)
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
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                argvFileHandled = true
                openInNewWindow(at: url.standardizedFileURL)
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

    func refreshAppearanceMenuState() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "auto"
        updateMenuItem(in: "appearanceMenu", id: "appearance.auto", selected: saved == "auto")
        updateMenuItem(in: "appearanceMenu", id: "appearance.light", selected: saved == "light")
        updateMenuItem(in: "appearanceMenu", id: "appearance.dark", selected: saved == "dark")
    }

    func refreshViewMenuState() {
        let inSource = currentDocument?.inSourceMode ?? false
        updateMenuItem(in: "viewMenu", id: "view.sourceMode", selected: inSource)
    }

    private func updateMenuItem(in menuId: String, id: String, selected: Bool) {
        guard let menu = NSApp.mainMenu, let submenu = findMenu(named: menuId, in: menu) else { return }
        for item in submenu.items where item.identifier?.rawValue == id {
            item.state = selected ? .on : .off
        }
    }

    private func findMenu(named id: String, in menu: NSMenu) -> NSMenu? {
        for item in menu.items {
            if item.identifier?.rawValue == id, let sub = item.submenu { return sub }
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
        openInNewWindow(at: url)
    }

    @objc private func clearRecentFiles(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
        rebuildRecentsMenu()
    }

    // MARK: - 菜单构建

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "recentsMenu" { rebuildRecentsMenu() }
    }

    private func buildMenus() {
        let main = NSMenu()

        // ─── App 菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "MDPreview")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 MDPreview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 MDPreview", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 MDPreview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ─── 文件
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        fileMenu.identifier = NSUserInterfaceItemIdentifier("fileMenu")
        fileMenu.addItem(withTitle: "新建", action: #selector(newDocumentAction(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "打开…", action: #selector(DocumentWindowController.openDocumentAction(_:)), keyEquivalent: "o")
        let recentsItem = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
        let recents = NSMenu(title: "打开最近使用")
        recents.identifier = NSUserInterfaceItemIdentifier("recentsMenu")
        recents.delegate = self
        recentsItem.submenu = recents
        recentsMenu = recents
        fileMenu.addItem(recentsItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "保存", action: #selector(DocumentWindowController.saveDocumentAction(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "另存为…", action: #selector(DocumentWindowController.saveDocumentAsAction(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "在 Finder 中显示", action: #selector(DocumentWindowController.revealInFinderAction(_:)), keyEquivalent: "r")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "导出 PDF…", action: #selector(DocumentWindowController.exportPDFAction(_:)), keyEquivalent: "e")
        let exportHTML = fileMenu.addItem(withTitle: "导出 HTML…", action: #selector(DocumentWindowController.exportHTMLAction(_:)), keyEquivalent: "h")
        exportHTML.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "打印…", action: #selector(DocumentWindowController.printDocumentAction(_:)), keyEquivalent: "p")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // ─── 编辑
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        // 命令注册表统一驱动(与右键菜单共用定义)
        EditorCommands.append([.undo, .redo], to: editMenu)
        editMenu.addItem(.separator())
        EditorCommands.append([.cut, .copy, .paste, .selectAll], to: editMenu)
        editMenu.addItem(.separator())
        EditorCommands.append([.find, .findNext, .findPrev], to: editMenu)

        // ─── 格式
        let formatItem = NSMenuItem()
        main.addItem(formatItem)
        let formatMenu = NSMenu(title: "格式")
        formatItem.submenu = formatMenu

        // 命令注册表统一驱动(与右键菜单共用定义)
        EditorCommands.append([.bold, .italic, .strikethrough, .inlineCode, .link], to: formatMenu)
        formatMenu.addItem(.separator())
        EditorCommands.append([.heading1, .heading2, .heading3, .bodyText], to: formatMenu)
        formatMenu.addItem(.separator())
        EditorCommands.append([.quote, .bulletList, .orderedList], to: formatMenu)
        formatMenu.addItem(.separator())
        EditorCommands.append([.codeBlock, .mathBlock, .insertTable], to: formatMenu)
        // 表格子菜单:同一注册表
        let tableItem = NSMenuItem(title: "表格", action: nil, keyEquivalent: "")
        let tableMenu = NSMenu(title: "表格")
        tableItem.submenu = tableMenu
        EditorCommands.append([.rowAbove, .rowBelow, .colLeft, .colRight], to: tableMenu)
        tableMenu.addItem(.separator())
        EditorCommands.append([.deleteRow, .deleteColumn, .deleteTable], to: tableMenu)
        formatMenu.addItem(tableItem)
        if let hr = EditorCommands.menuItem(for: .insertHr) { formatMenu.addItem(hr) }

        // ─── 视图
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        viewItem.submenu = viewMenu
        viewMenu.identifier = NSUserInterfaceItemIdentifier("viewMenu")

        let zoomIn = viewMenu.addItem(withTitle: "放大", action: #selector(DocumentWindowController.zoomInAction(_:)), keyEquivalent: "+")
        zoomIn.keyEquivalentModifierMask = [.command]
        let zoomOut = viewMenu.addItem(withTitle: "缩小", action: #selector(DocumentWindowController.zoomOutAction(_:)), keyEquivalent: "-")
        zoomOut.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(withTitle: "实际大小", action: #selector(DocumentWindowController.zoomResetAction(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        let sourceItem = viewMenu.addItem(withTitle: "源码模式", action: #selector(DocumentWindowController.toggleSourceModeAction(_:)), keyEquivalent: "/")
        sourceItem.identifier = NSUserInterfaceItemIdentifier("view.sourceMode")
        viewMenu.addItem(.separator())
        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "外观")
        appearanceMenu.identifier = NSUserInterfaceItemIdentifier("appearanceMenu")
        appearanceItem.submenu = appearanceMenu
        viewMenu.addItem(appearanceItem)
        let auto = appearanceMenu.addItem(withTitle: "跟随系统", action: #selector(appearanceAutoAction(_:)), keyEquivalent: "")
        auto.identifier = NSUserInterfaceItemIdentifier("appearance.auto")
        auto.target = self
        let light = appearanceMenu.addItem(withTitle: "浅色", action: #selector(appearanceLightAction(_:)), keyEquivalent: "")
        light.identifier = NSUserInterfaceItemIdentifier("appearance.light")
        light.target = self
        let dark = appearanceMenu.addItem(withTitle: "深色", action: #selector(appearanceDarkAction(_:)), keyEquivalent: "")
        dark.identifier = NSUserInterfaceItemIdentifier("appearance.dark")
        dark.target = self

        // ─── 窗口
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

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
