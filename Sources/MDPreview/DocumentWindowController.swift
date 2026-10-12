import AppKit
import os.log
import UniformTypeIdentifiers
import WebKit

/// 单文档窗口控制器:管理 WKWebView 编辑器、文件读写、脏状态、文件监视、导出等。
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private(set) var fileURL: URL?
    private(set) var isDirty = false
    var isReady = false
    var isLoadingContent = false
    /// 页面/编辑器尚未就绪时暂存的待打开文档,就绪后自动补载
    private var pendingOpenURL: URL?
    /// 保存确认弹窗进行中(防止重复弹窗)
    private var isConfirmingClose = false

    /// 诊断:内部状态摘要
    func debugSummary() -> String {
        "url=\(fileURL?.lastPathComponent ?? "nil") ready=\(isReady) loading=\(isLoadingContent) dirty=\(isDirty)"
    }

    private var webView: EditorWebView!
    var webViewIfNeeded: EditorWebView? { webView }
    private var statusLabel: NSTextField!
    private var stateLabel: NSTextField!
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastKnownFileAttributes: (modificationDate: Date, size: Int)?
    private var savedEncodingName = "UTF-8"
    private var pendingExportPDF = false

    static let markdownExtensions = ["md", "markdown", "mdown", "mkdn", "mdown", "mdtext", "mdwn", "txt"]

    // MARK: - 初始化

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "未命名"
        window.minSize = NSSize(width: 480, height: 320)
        window.isRestorable = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupContent() {
        guard let window = window else { return }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))

        webView = EditorWebView(configuration: EditorWebView.makeConfiguration())
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.onBridgeMessage = { [weak self] op, payload in
            self?.handleBridgeMessage(op: op, payload: payload)
        }
        webView.onPageReady = { [weak self] in
            self?.pushInitialContent()
        }
        webView.onDocumentLinkActivated = { url in
            AppDelegate.shared?.openInNewWindow(at: url)
        }
        container.addSubview(webView)

        // 底部状态栏
        let statusBar = NSVisualEffectView()
        statusBar.material = .titlebar
        statusBar.blendingMode = .withinWindow
        statusBar.state = .active
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        stateLabel = NSTextField(labelWithString: "")
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.alignment = .right
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBar.addSubview(statusLabel)
        statusBar.addSubview(stateLabel)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            stateLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            stateLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])

        window.contentView = container
        shouldCascadeWindows = true
        window.setFrameAutosaveName("MDPreviewMainWindow")
        window.center()

        webView.registerForDraggedTypes([.fileURL, .URL])
        webView.contextMenuHandler = { [weak self] x, y, done in
            guard let self else { done(nil); return }
            // 先把光标移到点击处(同步返回该处是否在表格内),再构建菜单
            let js = "JSON.stringify(window.mdbridge.focusAt(\(x), \(y)))"
            callJS(js) { result in
                var inTable = false
                if let json = result as? String,
                   let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any] {
                    inTable = (d["inTable"] as? Bool) ?? false
                }
                DispatchQueue.main.async {
                    done(self.buildContextMenu(inTable: inTable))
                }
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        let url = indexPageURL()
        if let url = url {
            // 允许读取整个文件系统内的本地图片(file:// 渲染 markdown 里的图片)
            webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            stateLabel.stringValue = "错误:找不到编辑器资源(web/dist)"
        }
    }

    private func indexPageURL() -> URL? {
        if let located = WebLocator.indexURL() { return located }
        // 开发模式 (swift run) 的兜底:仓库内 web/dist
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("web/dist/index.html")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    // MARK: - 打开文档

    func openDocument(at url: URL) {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "当前文档尚未保存"
            alert.informativeText = "打开新文件将丢弃未保存的修改。"
            alert.addButton(withTitle: "丢弃并打开")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        guard let (text, encodingName) = TextFile.read(at: url) else {
            let alert = NSAlert()
            alert.messageText = "无法读取文件"
            alert.informativeText = url.path
            alert.runModal()
            return
        }
        fileURL = url.standardizedFileURL
        savedEncodingName = encodingName
        isDirty = false
        updateTitle()
        updateStateLabel()
        AppDelegate.shared?.addRecentFile(url)
        // 编辑器未就绪(命令行/Finder 启动时页面可能尚未加载完):暂存,就绪后补载
        guard isReady, !isLoadingContent else {
            pendingOpenURL = fileURL
            return
        }
        loadMarkdownContent(text, baseURL: fileURL!)
    }

    /// 将已读取的文本注入编辑器(仅限编辑器就绪后调用)
    private func loadMarkdownContent(_ text: String, baseURL: URL) {
        isLoadingContent = true
        let rewritten = ImagePathRewriter.forLoad(text, baseURL: baseURL)
        callJS("window.mdbridge.setMarkdown(\(JSArgs.string(rewritten)))") { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingContent = false
                self.isDirty = false
                self.updateTitle()
                self.updateStateLabel()
                self.startFileMonitor()
            }
        }
    }

    /// 编辑器加载完成后注入初始内容(空文档)
    private func pushInitialContent() {
        let opts: [String: Any] = [
            "theme": AppDelegate.shared?.currentThemeJS() ?? "light",
            "zoom": UserDefaults.standard.double(forKey: "editorZoom").takingIfPositive() ?? 1.0,
            "title": "",
        ]
        let optsJSON = (try? JSONSerialization.data(withJSONObject: opts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        callJS("window.mdbridge.init('', \(optsJSON))") { [weak self] result in
            DispatchQueue.main.async {
                self?.isReady = true
                self?.updateStateLabel()
                os_log(.info, "editor ready: %{public}@", "\(result ?? "")")
                // 补载启动时因页面未就绪而暂存的文档
                if let pending = self?.pendingOpenURL {
                    self?.pendingOpenURL = nil
                    self?.openDocument(at: pending)
                }
            }
        }
    }

    // MARK: - 保存

    func saveDocument(_ sender: Any? = nil) {
        if fileURL == nil {
            saveDocumentAs(sender)
            return
        }
        save(to: fileURL!)
    }

    @objc func saveDocumentAs(_ sender: Any? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = AppDelegate.markdownUTTypes
        panel.nameFieldStringValue = (fileURL?.lastPathComponent) ?? "未命名.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        save(to: url)
    }

    private func save(to url: URL) {
        guard isReady else { return }
        isLoadingContent = true
        fetchMarkdown { [weak self] markdown in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingContent = false
                let restored = ImagePathRewriter.forSave(markdown, baseURL: url.deletingLastPathComponent())
                do {
                    try TextFile.write(restored, to: url)
                    self.isDirty = false
                    self.callJS("window.mdbridge.markClean()")
                    self.updateTitle()
                    self.updateStateLabel()
                    self.startFileMonitor()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "保存失败"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func fetchMarkdown(_ completion: @escaping (String) -> Void) {
        callJS("window.mdbridge.getMarkdown()") { result in
            completion((result as? String) ?? "")
        }
    }

    // MARK: - JS 桥

    private func callJS(_ script: String, completion: ((Any?) -> Void)? = nil) {
        webView.evaluateJavaScript(script) { result, error in
            if let error = error as NSError?,
               error.domain != "WebKitErrorDomain" || error.code != 0 {
                os_log(.error, "JS error: %{public}@ for %{private}@",
                       error.localizedDescription, String(script.prefix(120)))
            }
            completion?(result)
        }
    }

    /// 供 AppDelegate 推送主题等全局设置
    func callJSPublic(_ script: String) {
        callJS(script)
    }

    /// 诊断用:执行 JS 并取回结果
    func evaluateForDiagnostics(_ script: String, completion: ((Any?) -> Void)? = nil) {
        callJS(script, completion: completion)
    }

    private func handleBridgeMessage(op: String, payload: [String: Any]) {
        switch op {
        case "boot":
            break // 页面脚本加载完成,等 didFinish 后 pushInitialContent
        case "ready":
            isReady = true
            updateStateLabel()
        case "changed":
            if isLoadingContent { return }
            let dirty = (payload["dirty"] as? Bool) ?? true
            setDirty(dirty)
        case "stats":
            let words = payload["words"] as? Int ?? 0
            let chars = payload["chars"] as? Int ?? 0
            statusLabel.stringValue = "\(words) 词 · \(chars) 字符"
        case "sourceMode":
            sourceModeCached = (payload["value"] as? Bool) ?? false
            AppDelegate.shared?.refreshViewMenuState()
            updateStateLabel()
        case "selinfo":
            inTableCached = (payload["inTable"] as? Bool) ?? false
        case "jserror":
            let msg = payload["message"] as? String ?? "?"
            let where_ = payload["where"] as? String ?? ""
            let stack = payload["stack"] as? String ?? ""
            print("WEB-JS-ERROR: \(msg) @ \(where_)\n\(stack)")
        default:
            break
        }
    }

    // MARK: - 编辑命令转发

    func editorUndo() { callJS("window.mdbridge.undo()") }
    func editorRedo() { callJS("window.mdbridge.redo()") }
    func formatCommand(_ name: String, payload: Any? = nil) {
        let payloadJS: String
        if let payload = payload {
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let json = String(data: data, encoding: .utf8) {
                payloadJS = json
            } else {
                payloadJS = "undefined"
            }
        } else {
            payloadJS = "undefined"
        }
        callJS("window.mdbridge.formatCommand(\(JSArgs.string(name)), \(payloadJS))")
    }
    func insertTable() { callJS("window.mdbridge.insertTable(3,3)") }
    func toggleSourceMode() {
        callJS("window.mdbridge.toggleSource()") { [weak self] result in
            DispatchQueue.main.async {
                if let v = result as? Bool { self?.sourceModeCached = v }
                self?.updateStateLabel()
                AppDelegate.shared?.refreshViewMenuState()
            }
        }
    }
    var inSourceMode: Bool { sourceModeCached }
    private var sourceModeCached = false
    /// 光标是否在表格内(由 web 端 selinfo 消息维护,用于右键菜单/菜单校验)
    private(set) var inTableCached = false

    func focusEditor() { callJS("window.mdbridge.focus()") }

    // MARK: - 文档内查找

    func openFindBar() { callJS("window.mdbridge.openFindBar()") }
    func findNext() { callJS("window.mdbridge.findNext()") }
    func findPrev() { callJS("window.mdbridge.findPrev()") }

    @objc func findAction(_ sender: Any?) { openFindBar() }
    @objc func findNextAction(_ sender: Any?) { findNext() }
    @objc func findPrevAction(_ sender: Any?) { findPrev() }

    // MARK: - 右键菜单(只保留已实现的功能)

    private func buildContextMenu(inTable: Bool) -> NSMenu {
        let menu = NSMenu()
        // 分组与菜单栏共用同一份命令注册表;表格组仅在光标位于表格内时出现
        let groups: [[EditorAction]] = [
            [.undo, .redo],
            [.cut, .copy, .paste, .selectAll],
            [.find, .toggleSource],
            [.bold, .italic, .inlineCode, .strikethrough],
            [.insertTable, .insertHr],
            [.rowAbove, .rowBelow, .colLeft, .colRight],
            [.deleteRow, .deleteColumn, .deleteTable],
        ]
        for group in groups {
            let items = group.compactMap { action -> NSMenuItem? in
                guard let spec = EditorCommands.spec(for: action), spec.inContextMenu else { return nil }
                if spec.requiresTable && !inTable { return nil }
                return EditorCommands.menuItem(for: action, contextTarget: self)
            }
            guard !items.isEmpty else { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            items.forEach(menu.addItem)
        }
        return menu
    }

    // MARK: - 表格行列操作

    func tableCommand(_ name: String) {
        callJS("window.mdbridge.tableCommand(\(JSArgs.string(name)))")
    }

    @objc func insertRowAboveAction(_ sender: Any?) { tableCommand("insertRowAbove") }
    @objc func insertRowBelowAction(_ sender: Any?) { tableCommand("insertRowBelow") }
    @objc func insertColLeftAction(_ sender: Any?) { tableCommand("insertColLeft") }
    @objc func insertColRightAction(_ sender: Any?) { tableCommand("insertColRight") }
    @objc func deleteRowAction(_ sender: Any?) { tableCommand("deleteRow") }
    @objc func deleteColumnAction(_ sender: Any?) { tableCommand("deleteColumn") }
    @objc func deleteTableAction(_ sender: Any?) { tableCommand("deleteTable") }

    // MARK: - 缩放

    private var zoomScale: Double {
        get { UserDefaults.standard.double(forKey: "editorZoom").takingIfPositive() ?? 1.0 }
        set {
            let clamped = min(3.0, max(0.5, newValue))
            UserDefaults.standard.set(clamped, forKey: "editorZoom")
            callJS("window.mdbridge.setZoom(\(clamped))")
            statusLabel.stringValue = String(format: "缩放 %.0f%%", clamped * 100)
            // 让 web 端重新上报词数,恢复状态栏
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.callJS("window.mdbridge.requestStats()")
            }
        }
    }

    func zoomIn() { zoomScale = zoomScale * 1.1 }
    func zoomOut() { zoomScale = zoomScale / 1.1 }
    func zoomReset() { zoomScale = 1.0 }

    // MARK: - 打印 / 导出

    func printDocument() {
        callJS("window.print()")
    }

    func exportPDF() {
        guard isReady, !pendingExportPDF else { return }
        pendingExportPDF = true
        inSourceModeIf { inSource in
            self.measureAndCapturePDF(inSource: inSource)
        }
    }

    private func inSourceModeIf(_ handler: @escaping (Bool) -> Void) {
        callJS("window.mdbridge.isSourceMode()") { result in
            handler((result as? Bool) ?? false)
        }
    }

    private func measureAndCapturePDF(inSource: Bool) {
        let bodySel = inSource ? "document.getElementById('source-editor')" : "document.getElementById('app')"
        let script = """
        (function() {
            var el = \(bodySel);
            var r = document.documentElement;
            return JSON.stringify({
                w: Math.max(el.scrollWidth, r.clientWidth),
                h: Math.max(el.scrollHeight, r.scrollHeight)
            });
        })()
        """
        callJS(script) { [weak self] result in
            guard let self else { return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let dims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let h = dims["h"] as? Double, h > 0
            else {
                self.pendingExportPDF = false
                return
            }
            self.capturePDF(height: min(CGFloat(h), 20000))
        }
    }

    private func capturePDF(height: CGFloat) {
        guard window?.contentView != nil else { return }
        let originalFrame = webView.frame
        let width = originalFrame.width
        // 临时把 WebView 拉高到内容高度,确保全部内容参与渲染
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let config = WKPDFConfiguration()
            config.rect = self.webView.bounds
            self.webView.createPDF(configuration: config) { [weak self] result in
                guard let self else { return }
                // 恢复布局
                self.webView.translatesAutoresizingMaskIntoConstraints = false
                self.window?.contentView?.layoutSubtreeIfNeeded()
                self.pendingExportPDF = false

                switch result {
                case .success(let data):
                    self.saveExportedData(data, nameExtension: "pdf", allowed: [.pdf])
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "导出 PDF 失败"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    func exportHTML() {
        guard isReady else { return }
        callJS("window.mdbridge.exportStandaloneHTML()") { [weak self] result in
            DispatchQueue.main.async {
                guard let html = result as? String else {
                    let alert = NSAlert()
                    alert.messageText = "导出 HTML 失败"
                    alert.runModal()
                    return
                }
                self?.saveExportedData(Data(html.utf8), nameExtension: "html", allowed: [.html])
            }
        }
    }

    private func saveExportedData(_ data: Data, nameExtension: String, allowed: [UTType]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowed
        var base = (fileURL?.deletingPathExtension().lastPathComponent) ?? "未命名"
        base += ".\(nameExtension)"
        panel.nameFieldStringValue = base
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - 状态更新

    func updateTitle() {
        guard let window else { return }
        let name = fileURL?.lastPathComponent ?? "未命名"
        window.title = name
        window.representedURL = fileURL
        window.isDocumentEdited = isDirty
    }

    private func updateStateLabel() {
        if sourceModeCached {
            stateLabel.stringValue = "源码模式"
        } else if isReady {
            stateLabel.stringValue = isDirty ? "已修改" : "就绪"
        } else {
            stateLabel.stringValue = "加载中…"
        }
    }

    // MARK: - 文件监视

    private func startFileMonitor() {
        fileMonitor?.cancel()
        fileMonitor = nil
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        lastKnownFileAttributes = fileAttributes()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.fileChangedOnDisk()
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileMonitor = source
    }

    private func fileAttributes() -> (modificationDate: Date, size: Int)? {
        guard let url = fileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int else { return nil }
        return (date, size)
    }

    private func fileChangedOnDisk() {
        // 防抖:等待写入完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            guard let attrs = self.fileAttributes(),
                  let last = self.lastKnownFileAttributes else {
                self.lastKnownFileAttributes = self.fileAttributes()
                return
            }
            self.lastKnownFileAttributes = attrs
            guard attrs.modificationDate != last.modificationDate || attrs.size != last.size else { return }
            if self.isDirty {
                let alert = NSAlert()
                alert.messageText = "文件已在磁盘上被修改"
                alert.informativeText = (self.fileURL?.lastPathComponent ?? "") + " 被其他程序修改,同时本地有未保存的修改。"
                alert.addButton(withTitle: "保留我的修改")
                alert.addButton(withTitle: "重新加载")
                if alert.runModal() == .alertSecondButtonReturn {
                    if let url = self.fileURL { self.forceReload(from: url) }
                } else {
                    self.startFileMonitor()
                }
            } else if let url = self.fileURL {
                self.forceReload(from: url)
            }
        }
    }

    private func forceReload(from url: URL) {
        guard let (text, encodingName) = TextFile.read(at: url) else { return }
        savedEncodingName = encodingName
        isLoadingContent = true
        let rewritten = ImagePathRewriter.forLoad(text, baseURL: url.deletingLastPathComponent())
        callJS("window.mdbridge.setMarkdown(\(JSArgs.string(rewritten)))") { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLoadingContent = false
                self?.isDirty = false
                self?.updateTitle()
                self?.updateStateLabel()
            }
        }
    }

    // MARK: - 关闭 / 退出确认

    /// 统一维护脏标记(避免状态漂移)
    private func setDirty(_ dirty: Bool) {
        guard isDirty != dirty else { return }
        isDirty = dirty
        updateTitle()
        updateStateLabel()
    }

    /// 询问保存当前修改;返回 true 表示可以继续关闭(已保存或放弃),false 表示取消。
    /// allowCancel=false 用于退出流程(仅 保存/不保存 两项)。
    func confirmClose(allowCancel: Bool = true) -> Bool {
        guard isDirty else { return true }
        guard !isConfirmingClose else { return false } // 弹窗期间忽略重复关闭请求
        isConfirmingClose = true
        defer { isConfirmingClose = false }

        let alert = NSAlert()
        alert.messageText = "是否保存对「\(fileURL?.lastPathComponent ?? "未命名")」的更改?"
        alert.informativeText = "如果不保存就关闭,所有更改将会丢失。"
        alert.addButton(withTitle: "保存")
        if allowCancel { alert.addButton(withTitle: "取消") }
        alert.addButton(withTitle: "不保存")
        alert.alertStyle = .warning
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            saveDocument()
            // 同步等待保存完成(isDirty 由保存回调清除)
            let deadline = Date().addingTimeInterval(5)
            while isDirty && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            return !isDirty
        case .alertThirdButtonReturn:
            // 「不保存」:放弃修改
            setDirty(false)
            return true
        default:
            // 「取消」;退出流程无取消项(第二按钮即「不保存」)
            return !allowCancel && response == .alertSecondButtonReturn
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 退出流程已在 applicationShouldTerminate 中逐窗口询问过
        if AppDelegate.shared?.isTerminating == true { return true }
        return confirmClose(allowCancel: true)
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // 注册表命令统一校验(菜单栏与右键菜单共用)
        if let spec = EditorCommands.all.first(where: { $0.selector == menuItem.action }) {
            if spec.action == .toggleSource {
                menuItem.state = sourceModeCached ? .on : .off
            }
            if spec.requiresTable && !inTableCached { return false }
            return isReady
        }
        switch menuItem.action {
        case #selector(saveDocumentAs(_:)):
            return isReady
        default:
            return isReady
        }
    }

    // MARK: - 菜单动作 (@objc)

    @objc func openDocumentAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppDelegate.markdownUTTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(at: url)
    }

    @objc func saveDocumentAction(_ sender: Any?) { saveDocument(sender) }
    @objc func saveDocumentAsAction(_ sender: Any?) { saveDocumentAs(sender) }

    @objc func revealInFinderAction(_ sender: Any?) {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func exportPDFAction(_ sender: Any?) { exportPDF() }
    @objc func exportHTMLAction(_ sender: Any?) { exportHTML() }
    @objc func printDocumentAction(_ sender: Any?) { printDocument() }

    @objc func undoAction(_ sender: Any?) { editorUndo() }
    @objc func redoAction(_ sender: Any?) { editorRedo() }

    @objc func toggleSourceModeAction(_ sender: Any?) { toggleSourceMode() }

    @objc func zoomInAction(_ sender: Any?) { zoomIn() }
    @objc func zoomOutAction(_ sender: Any?) { zoomOut() }
    @objc func zoomResetAction(_ sender: Any?) { zoomReset() }

    @objc func toggleBoldAction(_ sender: Any?) { formatCommand("toggleStrongCommand") }
    @objc func toggleItalicAction(_ sender: Any?) { formatCommand("toggleEmphasisCommand") }
    @objc func toggleStrikethroughAction(_ sender: Any?) { formatCommand("toggleStrikethroughCommand") }
    @objc func toggleInlineCodeAction(_ sender: Any?) { formatCommand("toggleInlineCodeCommand") }
    @objc func toggleLinkAction(_ sender: Any?) { formatCommand("toggleLinkCommand") }
    @objc func heading1Action(_ sender: Any?) { formatCommand("wrapInHeadingCommand", payload: ["level": 1]) }
    @objc func heading2Action(_ sender: Any?) { formatCommand("wrapInHeadingCommand", payload: ["level": 2]) }
    @objc func heading3Action(_ sender: Any?) { formatCommand("wrapInHeadingCommand", payload: ["level": 3]) }
    @objc func bodyTextAction(_ sender: Any?) { formatCommand("turnIntoTextCommand") }
    @objc func blockquoteAction(_ sender: Any?) { formatCommand("wrapInBlockquoteCommand") }
    @objc func bulletListAction(_ sender: Any?) { formatCommand("wrapInBulletListCommand") }
    @objc func orderedListAction(_ sender: Any?) { formatCommand("wrapInOrderedListCommand") }
    @objc func codeBlockAction(_ sender: Any?) { formatCommand("createCodeBlockCommand") }
    @objc func mathBlockAction(_ sender: Any?) {
        callJS("window.mdbridge.insertMarkdown(\(JSArgs.string("$$\n\n$$")))") { [weak self] _ in
            self?.focusEditor()
        }
    }
    @objc func hrAction(_ sender: Any?) { formatCommand("insertHrCommand") }
    @objc func insertTableAction(_ sender: Any?) { insertTable() }

    // MARK: - 拖放文件

    func setSourceModeCached(_ value: Bool) {
        sourceModeCached = value
        updateStateLabel()
    }
}

// MARK: - 拖放支持

extension EditorWebView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFilePayload(sender) { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        if let first = urls.first {
            AppDelegate.shared?.openInNewWindow(at: first)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func hasFilePayload(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                                options: [.urlReadingFileURLsOnly: true])
        else { return [] }
        return items.compactMap { $0 as? URL }
    }
}

// MARK: - 小工具

private extension Double {
    func takingIfPositive() -> Double? {
        return self > 0 ? self : nil
    }
}
