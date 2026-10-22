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
    /// 页面/编辑器尚未就绪或注入进行中时暂存的待打开请求,就绪/装载完成后自动补载;
    /// reanchor 记录来源(抽屉双击不重锚,其余以文件所在目录重锚)
    private struct PendingOpen {
        let url: URL
        let reanchor: Bool
    }
    private var pendingOpen: PendingOpen?
    /// 保存确认弹窗进行中(防止重复弹窗)
    private var isConfirmingClose = false

    private var webView: EditorWebView!
    var webViewIfNeeded: EditorWebView? { webView }
    private var statusLabel: NSTextField!
    private var zoomLabel: NSTextField!
    private var stateLabel: NSTextField!

    // MARK: - 状态栏(字段拆分:词数区/缩放区/状态区,同一渲染函数统一落值)
    // 双职责 label(平时词数、缩放时临时占比)会让两类信息互相覆盖回退;
    // 拆字段后各信息持久驻留,不再需要"临时显示再恢复"的时序补丁。
    private var wordStatsText = "就绪" { didSet { renderStatusBar() } }
    private var zoomText = "" { didSet { renderStatusBar() } }
    private var stateText = "" { didSet { renderStatusBar() } }

    private func renderStatusBar() {
        statusLabel.stringValue = wordStatsText
        zoomLabel.stringValue = zoomText
        stateLabel.stringValue = stateText
    }
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastKnownFileAttributes: (modificationDate: Date, size: Int)?
    private var pendingExportPDF = false

    // MARK: - 文件抽屉与目录模式
    // 抽屉可见性全局记忆(UserDefaults);目录模式无文档,右侧空白,抽屉为唯一导航面。
    private(set) var isDrawerVisible = false
    private(set) var directoryMode = false
    /// 目录模式的扫描根(文件模式的根 = fileURL 所在目录,不落此字段)
    private var drawerRootURL: URL?
    private var drawerView: FileDrawerView!
    private var drawerWidthConstraint: NSLayoutConstraint!
    /// 抽屉当前宽度(拖拽可调):开合动画与窗口宽度收敛都以此为准,
    /// 收起时不变、展开时复原;初值取自全局记忆(缺省 240)
    private var drawerWidth = FileDrawerView.rememberedWidth
    /// 拖拽起点宽度(拖动中只按「起点宽度 + 位移」计算,不随中间值累积漂移)
    private var drawerResizeStartWidth: CGFloat = 0
    /// 拖拽调宽时正文最小宽度:再宽就会把编辑器挤成不可用宽度,夹取上界据此二次收紧
    private static let minEditorWidthForDrawerResize: CGFloat = 320
    private var drawerDivider: DrawerResizeDivider!

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
        // 左侧文件抽屉:默认收起(宽度 0 且隐藏),开合由 toggleDrawer 单点驱动
        drawerView = FileDrawerView()
        drawerView.translatesAutoresizingMaskIntoConstraints = false
        drawerView.onOpenFile = { [weak self] url in
            self?.openDocument(at: url, reanchor: false) // 抽屉来源保持锚点
        }
        drawerView.onAnchorSelected = { [weak self] url in
            self?.anchorDrawer(at: url)
        }
        container.addSubview(drawerView)
        drawerWidthConstraint = drawerView.widthAnchor.constraint(equalToConstant: 0)
        drawerView.isHidden = true

        container.addSubview(webView)

        // 抽屉/编辑器边界的拖拽分隔条:透明热区跨边界各 4pt,透出两侧内容,
        // 只画 1pt 分界线;加在 webView 之后 → 位于两者之上,按下即进入调宽
        drawerDivider = DrawerResizeDivider()
        drawerDivider.translatesAutoresizingMaskIntoConstraints = false
        drawerDivider.isHidden = true
        drawerDivider.onDragBegan = { [weak self] in self?.beginDrawerResize() }
        drawerDivider.onDragMoved = { [weak self] dx in self?.updateDrawerResize(by: dx) }
        drawerDivider.onDragEnded = { [weak self] in self?.endDrawerResize() }
        container.addSubview(drawerDivider)

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

        zoomLabel = NSTextField(labelWithString: "")
        zoomLabel.font = NSFont.systemFont(ofSize: 11)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.alignment = .right
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false

        stateLabel = NSTextField(labelWithString: "")
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.alignment = .right
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBar.addSubview(statusLabel)
        statusBar.addSubview(zoomLabel)
        statusBar.addSubview(stateLabel)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            drawerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            drawerView.topAnchor.constraint(equalTo: container.topAnchor),
            drawerView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            drawerWidthConstraint,

            // 分隔条中心钉在抽屉右缘:热区左右各占 4pt,两侧内容都不留缝
            drawerDivider.centerXAnchor.constraint(equalTo: drawerView.trailingAnchor),
            drawerDivider.widthAnchor.constraint(equalToConstant: DrawerResizeDivider.hotZoneHalfWidth * 2),
            drawerDivider.topAnchor.constraint(equalTo: container.topAnchor),
            drawerDivider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            webView.leadingAnchor.constraint(equalTo: drawerView.trailingAnchor),
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

            zoomLabel.trailingAnchor.constraint(equalTo: stateLabel.leadingAnchor, constant: -16),
            zoomLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
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
        // 拖入图片文件:导入 resource/ 目录并插入引用(.md 等其余文件仍是开新窗)
        webView.onImageFileDropped = { [weak self] url in
            self?.importImage(at: url)
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let url = WebLocator.indexURL() {
            // 允许读取整个文件系统内的本地图片(file:// 渲染 markdown 里的图片)
            webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            stateText = "错误:找不到编辑器资源(web/dist)"
        }
        // 恢复的窗框可能超屏(跨屏拖动/外接屏拔除):先收敛一次
        clampWindowFrameToScreen()
        // 抽屉可见性跨窗口恢复;目录模式的展开由 openDirectory 显式驱动
        if UserDefaults.standard.bool(forKey: "fileDrawerVisible"), !isDrawerVisible {
            setDrawerVisible(true, animated: false)
        }
    }

    // MARK: - 打开文档

    /// 打开文档。reanchor 语义:抽屉双击传 false(保持锚点,文件必在锚点子树内,
    /// 这是「锚定祖先目录后跨多层打开」的关键);其余来源(⌘O/最近使用/CLI/拖放/
    /// 文档链接)默认 true——以文件所在目录为锚点。
    func openDocument(at url: URL, reanchor: Bool = true) {
        if isDirty {
            // 脏文档覆盖打开前统一走保存确认(保存/取消/不保存),与关闭/抽屉双击同一路径;
            // 「不保存」即放弃修改后继续打开,不再出现静默丢弃语义的旧模态
            beginConfirmClose(allowCancel: true) { [weak self] confirmed in
                guard confirmed else { return }
                self?.openDocument(at: url, reanchor: reanchor) // 确认后 isDirty 已清,重入直通装载
            }
            return
        }
        let target = url.standardizedFileURL
        // 未就绪(命令行/Finder 启动时页面可能尚未加载完):只记 URL 不读内容,
        // 读文件动作只在就绪补载时发生一次——消除双读 TOCTOU 与大文件双读。
        guard isReady, !isLoadingContent else {
            pendingOpen = PendingOpen(url: target, reanchor: reanchor)
            return
        }
        // 读取编码仅用于探测显示;输出恒定 UTF-8(承诺见 README 已知边界)
        guard let (text, _) = TextFile.read(at: target) else {
            let alert = NSAlert()
            alert.messageText = "无法读取文件"
            alert.informativeText = target.path
            alert.runModal()
            return
        }
        directoryMode = false
        // 锚定契约:非抽屉来源(或越界防御)以文件所在目录重锚;抽屉来源保持锚点
        if reanchor || !isWithinDrawerRoot(target) {
            drawerRootURL = target.deletingLastPathComponent()
        }
        fileURL = target
        isDirty = false
        updateTitle()
        updateStateLabel()
        AppDelegate.shared?.addRecentFile(target)
        injectMarkdown(text, docURL: target)
        if isDrawerVisible { refreshDrawer() }
    }

    /// 目录模式:只装载目录不装载文档。右侧走既有空文档路径(init('')/注入空文本),
    /// 抽屉为唯一导航面;再次打开文件经 openDocument 自然退出目录模式。
    func openDirectory(at url: URL) {
        if isDirty {
            beginConfirmClose(allowCancel: true) { [weak self] confirmed in
                guard confirmed else { return }
                self?.openDirectory(at: url)
            }
            return
        }
        let target = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        // 编辑器未就绪/注入进行中:与 openDocument 同一暂存机制,补载时按目录分派
        guard isReady, !isLoadingContent else {
            pendingOpen = PendingOpen(url: target, reanchor: true)
            return
        }
        fileMonitor?.cancel()
        fileMonitor = nil
        directoryMode = true
        drawerRootURL = target
        fileURL = nil
        isDirty = false
        updateTitle()
        updateStateLabel()
        if isDrawerVisible {
            refreshDrawer()
        } else {
            setDrawerVisible(true, animated: false)
        }
        // 编辑器就绪后以空文档覆盖(从文件窗口切到目录模式时清空右侧)
        if isReady {
            injectMarkdown("", docURL: target)
        }
    }

    /// 将已读取的文本注入编辑器——加载与外部变更重载的唯一入口(仅限编辑器就绪后调用)。
    /// 两路径唯一历史差异(是否重启文件监视)按"重启"收敛:重载后以磁盘现状为新基线。
    /// docURL 是图片相对路径的唯一解析基准(此前 openDocument 传文件 URL、
    /// forceReload 传目录,前者解析出 doc.md/resource/... 恒不存在 → 图片全不显示)。
    private func injectMarkdown(_ text: String, docURL: URL) {
        isLoadingContent = true
        let rewritten = ImagePathRewriter.forLoad(text, baseURL: docURL.deletingLastPathComponent())
        // baseDir 供图片源码编辑框做 相对路径⇄绝对 file:// 的同构换算
        let optsJSON = (try? JSONSerialization.data(
            withJSONObject: ["baseDir": docURL.deletingLastPathComponent().path],
            options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        callJS("window.mdbridge.setMarkdown(\(JSArgs.string(rewritten)), \(optsJSON))") { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingContent = false
                self.isDirty = false
                self.updateTitle()
                self.updateStateLabel()
                self.startFileMonitor()
                // 装载完成后立即排空暂存的打开请求。此前只靠 ready 桥消息补载,
                // 而 ready 仅发生一次:装载中(⌘O/抽屉双击)到达的请求会永久滞留。
                self.drainPendingOpen()
            }
        }
    }

    /// 统一补载暂存的打开请求:按目录/文件分派(与 openDirectory/openDocument 同一入口)
    private func drainPendingOpen() {
        guard let pending = pendingOpen else { return }
        pendingOpen = nil
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: pending.url.path, isDirectory: &isDir), isDir.boolValue {
            openDirectory(at: pending.url)
        } else {
            openDocument(at: pending.url, reanchor: pending.reanchor)
        }
    }

    /// 编辑器加载完成后注入初始内容(空文档)
    private func pushInitialContent() {
        let opts: [String: Any] = [
            "theme": AppDelegate.shared?.currentThemeJS() ?? "light",
            "zoom": UserDefaults.standard.double(forKey: "editorZoom").takingIfPositive() ?? 1.0,
            // 文件名传给 web 层作为 document.title(HTML 导出标题的来源);无文件名时 web 层兜底 "MDPreview"
            // 目录模式传目录名
            "title": directoryMode ? (drawerRootURL?.lastPathComponent ?? "") : (fileURL?.lastPathComponent ?? ""),
        ]
        let optsJSON = (try? JSONSerialization.data(withJSONObject: opts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        callJS("window.mdbridge.init('', \(optsJSON))") { result in
            // isReady 的唯一赋值点在桥消息 "ready" 分支(含暂存文档补载);
            // 这里只留诊断日志。init 的 evaluateJavaScript 完成与 ready 消息到达
            // 谁先谁后都安全:补载动作只在桥分支发生,openDocument 自带守卫。
            os_log(.info, "editor init callback: %{public}@", "\(result ?? "")")
        }
    }

    // MARK: - 时序契约

    /// 非魔力裸数字的用点必须有命名常量与依据。防抖是合理模式,裸数字不是。
    enum Timing {
        /// 外部写入防抖窗口:编辑器保存为整文件原子写,0.4s 足以跳过写入窗口,
        /// 又能屏蔽 FSEvents 对同一文件的连发(实测 R6 场景 0.3s 内可达 3 次)。
        static let fileMonitorDebounce: TimeInterval = 0.4
        /// PDF 前几何收敛轮询间隔:一轮布局+合成至少数帧,0.05s 足以观察到变化且总时延可控。
        static let geometryPollInterval: TimeInterval = 0.05
        /// 几何收敛轮询上限(40 次 ≈ 2s):超大文档兜底,之后尽力截取。
        static let geometryPollMaxAttempts = 40
        /// 抽屉开合动画时长:与窗口 setFrame 动画(~0.2s)同量级,视觉同步不脱节。
        static let drawerAnimationDuration: TimeInterval = 0.22
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
                    // 另存为后文档目录变化,同步 web 层的图片路径换算基准
                    self.callJS("window.mdbridge.setBaseDir(\(JSArgs.string(url.deletingLastPathComponent().path)))") { _ in }
                    self.updateTitle()
                    self.updateStateLabel()
                    self.startFileMonitor()
                    self.finishCloseRequest(success: true)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "保存失败"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    self.finishCloseRequest(success: false)
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
            // 全仓唯一 isReady 赋值点
            isReady = true
            updateStateLabel()
            drainPendingOpen()
        case "changed":
            if isLoadingContent { return }
            let dirty = (payload["dirty"] as? Bool) ?? true
            setDirty(dirty)
        case "stats":
            let words = payload["words"] as? Int ?? 0
            let chars = payload["chars"] as? Int ?? 0
            wordStatsText = "\(words) 词 · \(chars) 字符"
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
        case "importImage":
            handleImportImage(payload)
        default:
            break
        }
    }

    // MARK: - 图片导入(粘贴请求 / 拖放 / 插入菜单 共用的偶发路径)
    // 偶发路径独立成路:落盘失败只弹窗,不进编辑主路径,不拖垮编辑器。

    /// web 粘贴拦截后的落盘请求:blob(剪贴板位图字节)或 file(本地图片路径)。
    /// 完成后回灌 mdbridge.onImageImported(requestId, {ok, src}) — 失败也回灌
    /// (ok:false,web 只清挂起表,提示由原生弹窗负责)。
    private func handleImportImage(_ payload: [String: Any]) {
        guard let requestId = payload["requestId"] as? String else { return }
        // 回灌统一出口:成功携带 src;失败只置 ok:false,提示由原生负责
        func reply(_ imported: ImageStore.Imported?) {
            var body: [String: Any] = ["ok": imported != nil]
            if let imported { body["src"] = imported.url.absoluteString }
            let json = (try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false}"
            callJS("window.mdbridge.onImageImported(\(JSArgs.string(requestId)), \(json))")
        }
        guard let fileURL else {
            promptSaveBeforeImagePaste()
            reply(nil)
            return
        }
        do {
            let imported: ImageStore.Imported
            if let base64 = payload["data"] as? String, payload["kind"] as? String == "blob" {
                guard let data = Data(base64Encoded: base64) else {
                    throw ImageStore.ImportError.emptyData
                }
                imported = try ImageStore.import(
                    .blob(data, mime: payload["mime"] as? String), docURL: fileURL)
            } else if let rawPath = payload["path"] as? String {
                imported = try ImageStore.import(.file(imageURL(fromPathText: rawPath)), docURL: fileURL)
            } else {
                throw ImageStore.ImportError.emptyData
            }
            reply(imported)
        } catch {
            alertImportFailure(error)
            reply(nil)
        }
    }

    /// 文本形态的图片路径(file:// URL / 绝对路径 / ~/ 相对)→ 文件 URL
    private func imageURL(fromPathText raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url
        }
        var path = trimmed
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        }
        return URL(fileURLWithPath: path)
    }

    /// 导入一张既有图片文件(拖入编辑器 / 插入菜单入口)并在光标处插入引用
    func importImage(at url: URL) {
        guard isReady else { return }
        guard fileURL != nil else {
            promptSaveBeforeImagePaste()
            return
        }
        do {
            let imported = try ImageStore.import(.file(url.standardizedFileURL), docURL: fileURL!)
            callJS("window.mdbridge.insertImage(\(JSArgs.string(imported.url.absoluteString)), \"\", \"\")")
        } catch {
            alertImportFailure(error)
        }
    }

    private func promptSaveBeforeImagePaste() {
        let alert = NSAlert()
        alert.messageText = "请先保存文档"
        alert.informativeText = "插入图片需要先保存文档,图片将存入文档旁的 resource/ 目录。"
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func alertImportFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "导入图片失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// 格式 → 插入图片…:文件选择器选中后走统一导入路径
    @objc func insertImageAction(_ sender: Any?) {
        guard isReady else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(at: url)
    }

    // MARK: - 编辑命令转发

    func editorUndo() { callJS("window.mdbridge.undo()") }
    func editorRedo() { callJS("window.mdbridge.redo()") }
    func formatCommand(_ name: String, payload: Any? = nil) {
        let payloadJS: String
        if let payload = payload {
            // fragmentsAllowed:标量 payload(如标题级别数字)也合法
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]),
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

    /// 按注册表把动作转发到 web 命令(JS 命令名由 spec 携带,双端一致由 selftest 校验):
    /// 表格组走 tableCommand,其余走 formatCommand
    func performEditorAction(_ action: EditorAction) {
        guard let spec = EditorCommands.spec(for: action), let js = spec.jsCommand else { return }
        if spec.requiresTable {
            tableCommand(js)
        } else {
            formatCommand(js, payload: spec.jsPayload)
        }
    }
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

    @objc func insertRowAboveAction(_ sender: Any?) { performEditorAction(.rowAbove) }
    @objc func insertRowBelowAction(_ sender: Any?) { performEditorAction(.rowBelow) }
    @objc func insertColLeftAction(_ sender: Any?) { performEditorAction(.colLeft) }
    @objc func insertColRightAction(_ sender: Any?) { performEditorAction(.colRight) }
    @objc func deleteRowAction(_ sender: Any?) { performEditorAction(.deleteRow) }
    @objc func deleteColumnAction(_ sender: Any?) { performEditorAction(.deleteColumn) }
    @objc func deleteTableAction(_ sender: Any?) { performEditorAction(.deleteTable) }

    // MARK: - 缩放

    private var zoomScale: Double {
        get { UserDefaults.standard.double(forKey: "editorZoom").takingIfPositive() ?? 1.0 }
        set {
            UserDefaults.standard.set(newValue, forKey: "editorZoom")
            // 夹取(0.5–3)归 web 端 mdbridge.setZoom 单点负责,此处透传并采用其返回的有效值
            callJS("window.mdbridge.setZoom(\(newValue))") { [weak self] result in
                guard let effective = result as? Double else { return }
                self?.zoomText = String(format: "缩放 %.0f%%", effective * 100)
                // 直接让 web 端重报词数以恢复状态栏(消息通道自带节流,无固定延时)
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

    /// 截图前 WebView 几何就绪信号:连续两次测得相同内容高度即视为渲染/布局收敛。
    /// 以就绪信号替代固定延时——mermaid/katex 渲染慢的机器不再可能导出缺内容。
    private func waitForWebViewGeometrySettled(
        attempts: Int, last: CGFloat? = nil, _ completion: @escaping () -> Void
    ) {
        guard attempts > 0 else { completion(); return } // 兜底:迟迟不收敛也尽力截取
        callJS("Math.max(document.documentElement.scrollHeight)") { [weak self] result in
            guard let self else { return }
            let current = CGFloat((result as? Double) ?? 0)
            if let last, abs(current - last) < 0.5 {
                // 收敛后再让一拍合成器完成 raster,下一次 RunLoop tick 即可截取
                DispatchQueue.main.async { completion() }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.geometryPollInterval) {
                self.waitForWebViewGeometrySettled(attempts: attempts - 1, last: current, completion)
            }
        }
    }

    private func capturePDF(height: CGFloat) {
        guard window?.contentView != nil else { return }
        let originalFrame = webView.frame
        let width = originalFrame.width
        // 临时把 WebView 拉高到内容高度,确保全部内容参与渲染
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        waitForWebViewGeometrySettled(attempts: Timing.geometryPollMaxAttempts) { [weak self] in
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
        let name = directoryMode ? (drawerRootURL?.lastPathComponent ?? "未命名")
                                 : (fileURL?.lastPathComponent ?? "未命名")
        window.title = name
        window.representedURL = directoryMode ? drawerRootURL : fileURL
        window.isDocumentEdited = isDirty
        // web 层 document.title 与文件名保持同步(导出 HTML 的 <title> 取自它);
        // web 未就绪时不推送,初始标题由 pushInitialContent 的 opts 携带
        if isReady {
            callJS("window.mdbridge.setTitle(\(JSArgs.string(name)))")
        }
    }

    private func updateStateLabel() {
        if sourceModeCached {
            stateText = "源码模式"
        } else if isReady {
            stateText = isDirty ? "已修改" : "就绪"
        } else {
            stateText = "加载中…"
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.fileMonitorDebounce) { [weak self] in
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

    /// 外部变更后的重载:与加载共用注入入口
    private func forceReload(from url: URL) {
        guard let (text, _) = TextFile.read(at: url) else { return }
        injectMarkdown(text, docURL: url)
    }

    // MARK: - 关闭 / 退出确认

    /// 统一维护脏标记(避免状态漂移)
    private func setDirty(_ dirty: Bool) {
        guard isDirty != dirty else { return }
        isDirty = dirty
        updateTitle()
        updateStateLabel()
    }

    /// 异步保存确认:确认弹窗以 sheet 呈现,期间只有确认流程本身在等回调,
    /// 主循环不被泵送——消灭"泵主循环等异步保存"模式下的重入窗口
    /// (⌘W/菜单/拖放不会再嵌套进保存与打开路径)。
    /// completion(true) 仅在「窗口可安全关闭」时回调:保存路径等写入完成后再回调。
    /// allowCancel=false 用于退出流程(仅 保存/不保存 两项)。
    func beginConfirmClose(allowCancel: Bool = true, completion: @escaping (Bool) -> Void) {
        guard isDirty else { completion(true); return }
        guard !isConfirmingClose else { completion(false); return } // 弹窗期间忽略重复请求
        isConfirmingClose = true

        let alert = NSAlert()
        alert.messageText = "是否保存对「\(fileURL?.lastPathComponent ?? "未命名")」的更改?"
        alert.informativeText = "如果不保存就关闭,所有更改将会丢失。"
        alert.addButton(withTitle: "保存")
        if allowCancel { alert.addButton(withTitle: "取消") }
        alert.addButton(withTitle: "不保存")
        alert.alertStyle = .warning

        guard let window else {
            isConfirmingClose = false
            completion(false)
            return
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isConfirmingClose = false
            switch response {
            case .alertFirstButtonReturn:
                // 保存异步进行:挂起关闭回调,由保存完成回调续做
                self.closeCompletion = completion
                self.saveDocument()
            case .alertSecondButtonReturn where !allowCancel:
                // 退出流程的「不保存」
                self.setDirty(false)
                completion(true)
            case .alertThirdButtonReturn:
                // 「不保存」:放弃修改
                self.setDirty(false)
                completion(true)
            default:
                completion(false)
            }
        }
    }

    /// 关闭请求的挂起回调:保存成功→可安全关闭;失败→留在窗口由用户重试
    private var closeCompletion: ((Bool) -> Void)?

    private func finishCloseRequest(success: Bool) {
        guard let completion = closeCompletion else { return }
        closeCompletion = nil
        completion(success && !isDirty)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 退出流程的逐窗口询问也走 beginConfirmClose(allowCancel: false),
        // 这里不做 isTerminating 旁路:队列等待期间手动 ⌘W 脏窗口仍必须弹确认,
        // 否则会静默丢改动;同一窗口的重复请求由 isConfirmingClose 吞掉。
        guard isDirty else { return true }
        guard !isConfirmingClose else { return false } // 确认弹窗进行中,吞掉本次请求
        // 返回 false 阻止立即关闭;sheet 确认结果回调里续做关闭
        beginConfirmClose(allowCancel: true) { [weak self] confirmed in
            guard confirmed else { return }
            self?.window?.performClose(nil) // isDirty 已清,重入 windowShouldClose 直通关闭
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        cleanOrphanResources()
    }

    /// 关闭时清理资源目录死链图片(撤销粘贴孤儿/正文删除引用的残留)。
    /// 此刻磁盘内容已是权威终态(保存/放弃决策已在 windowShouldClose 完成),
    /// 判定与执行细节单点在 ImageStore.cleanUnreferenced。清理是偶发慢路径,
    /// 失败只记日志,不打断关闭。
    private func cleanOrphanResources() {
        guard let fileURL else { return } // 新建未保存文档:无资源目录,无清理对象
        guard let (text, _) = TextFile.read(at: fileURL) else {
            os_log(.error, "资源清理:文档读取失败 %{public}@", fileURL.path)
            return
        }
        do {
            let removed = try ImageStore.cleanUnreferenced(docURL: fileURL, markdown: text)
            if !removed.isEmpty {
                os_log(.info, "资源清理:%{public}@ 移除 %{public}@", fileURL.lastPathComponent, removed.joined(separator: ", "))
            }
        } catch {
            os_log(.error, "资源清理失败 %{public}@ → %{public}@", fileURL.lastPathComponent, "\(error)")
        }
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
        case #selector(toggleDrawerAction(_:)):
            return true // 抽屉开合不依赖编辑器就绪
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

    /// 文件 → 打开文件夹…:当前窗口切入目录模式(右侧空白,抽屉导航)
    @objc func openFolderAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDirectory(at: url)
    }

    @objc func saveDocumentAction(_ sender: Any?) { saveDocument(sender) }
    @objc func saveDocumentAsAction(_ sender: Any?) { saveDocumentAs(sender) }

    @objc func revealInFinderAction(_ sender: Any?) {
        guard let url = directoryMode ? drawerRootURL : fileURL else { return }
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

    @objc func toggleBoldAction(_ sender: Any?) { performEditorAction(.bold) }
    @objc func toggleItalicAction(_ sender: Any?) { performEditorAction(.italic) }
    @objc func toggleStrikethroughAction(_ sender: Any?) { performEditorAction(.strikethrough) }
    @objc func toggleInlineCodeAction(_ sender: Any?) { performEditorAction(.inlineCode) }
    @objc func toggleLinkAction(_ sender: Any?) { performEditorAction(.link) }
    @objc func heading1Action(_ sender: Any?) { performEditorAction(.heading1) }
    @objc func heading2Action(_ sender: Any?) { performEditorAction(.heading2) }
    @objc func heading3Action(_ sender: Any?) { performEditorAction(.heading3) }
    @objc func bodyTextAction(_ sender: Any?) { performEditorAction(.bodyText) }
    @objc func blockquoteAction(_ sender: Any?) { performEditorAction(.quote) }
    @objc func bulletListAction(_ sender: Any?) { performEditorAction(.bulletList) }
    @objc func orderedListAction(_ sender: Any?) { performEditorAction(.orderedList) }
    @objc func codeBlockAction(_ sender: Any?) { performEditorAction(.codeBlock) }
    @objc func mathBlockAction(_ sender: Any?) {
        callJS("window.mdbridge.insertMarkdown(\(JSArgs.string("$$\n\n$$")))") { [weak self] _ in
            self?.focusEditor()
        }
    }
    @objc func hrAction(_ sender: Any?) { performEditorAction(.insertHr) }
    @objc func insertTableAction(_ sender: Any?) { insertTable() }

    // MARK: - 文件抽屉(开合/窗口宽度收敛/根目录解析)

    /// 抽屉开合唯一入口:视图菜单/快捷键驱动;可见性与窗口宽度在此单点维护
    func toggleDrawer() {
        setDrawerVisible(!isDrawerVisible)
    }

    @objc func toggleDrawerAction(_ sender: Any?) {
        toggleDrawer()
    }

    func setDrawerVisible(_ visible: Bool, animated: Bool = true) {
        guard isDrawerVisible != visible else { return }
        isDrawerVisible = visible
        UserDefaults.standard.set(visible, forKey: "fileDrawerVisible")
        if visible {
            drawerView.isHidden = false
            refreshDrawer()
        }
        // 开合按「当前宽度」(拖拽可调、跨窗记忆),不再用常量
        let target: CGFloat = visible ? drawerWidth : 0
        let delta: CGFloat = visible ? drawerWidth : -drawerWidth
        if visible {
            drawerDivider.isHidden = false
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Timing.drawerAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                drawerWidthConstraint.animator().constant = target
            }, completionHandler: { [weak self] in
                guard let self, !self.isDrawerVisible else { return }
                self.drawerView.isHidden = true
                self.drawerDivider.isHidden = true
            })
        } else {
            drawerWidthConstraint.constant = target
            drawerView.isHidden = !visible
            drawerDivider.isHidden = !visible
        }
        // 窗口同步调整:向左伸出 drawerWidth;伸出超屏则整体收敛到屏幕宽度
        adjustWindowWidthForDrawer(delta: delta, animated: animated)
        AppDelegate.shared?.refreshViewMenuState()
    }

    // MARK: - 抽屉宽度拖拽

    /// 拖拽起点:记下当前宽度(后续位移都相对它计算)
    private func beginDrawerResize() {
        drawerResizeStartWidth = drawerWidth
    }

    /// 拖拽中:新宽度 = 起点宽度 + 水平位移,夹取在 [抽屉下界, min(抽屉上界, 窗体宽 - 正文最小宽)];
    /// 只改约束不改窗口宽度——拖拽是「抽屉与正文之间重新分配空间」
    private func updateDrawerResize(by dx: CGFloat) {
        guard isDrawerVisible, let contentView = window?.contentView else { return }
        let upperBound = max(FileDrawerView.minWidth,
                             min(FileDrawerView.maxWidth,
                                 contentView.bounds.width - Self.minEditorWidthForDrawerResize))
        let clamped = min(max(drawerResizeStartWidth + dx, FileDrawerView.minWidth), upperBound)
        drawerWidth = clamped
        drawerWidthConstraint.constant = clamped
        contentView.layoutSubtreeIfNeeded() // 拖动过程中即时重排,松手前就能看到两侧宽度
    }

    /// 拖拽结束:落盘宽度(读取侧 rememberedWidth 负责越界兜底),窗口宽度不动
    private func endDrawerResize() {
        UserDefaults.standard.set(drawerWidth, forKey: FileDrawerView.widthDefaultsKey)
    }

    /// 抽屉开合的窗口宽度收敛:
    /// 展开 → 优先向左伸出 drawerWidth(编辑器内容宽度不变);伸出后超出屏幕可视
    /// 宽度则整体收敛到屏幕宽度(右缘保持,编辑器压缩)——「向外伸出,超屏收敛」。
    /// 收起 → 右缘保持,宽度缩回 drawerWidth(下限窗口最小宽度)。
    private func adjustWindowWidthForDrawer(delta: CGFloat, animated: Bool) {
        guard let window else { return }
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        if delta > 0 {
            let proposedWidth = frame.width + delta
            if proposedWidth <= visible.width {
                frame.origin.x = max(visible.minX, frame.minX - delta)
                frame.size.width = proposedWidth
            } else {
                let rightEdge = min(frame.maxX, visible.maxX)
                frame.size.width = min(visible.width, max(window.minSize.width, proposedWidth))
                frame.origin.x = max(visible.minX, rightEdge - frame.size.width)
            }
        } else {
            let oldWidth = frame.width
            frame.size.width = max(window.minSize.width, frame.width + delta)
            frame.origin.x += oldWidth - frame.size.width
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
        }
        window.setFrame(frame, display: true, animate: animated)
    }

    /// 启动/恢复时窗框超屏的一次性收敛(跨屏拖动、外接屏拔除后的残留窗框)
    private func clampWindowFrameToScreen() {
        guard let window else { return }
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        guard frame.width > visible.width || frame.minX < visible.minX || frame.maxX > visible.maxX else { return }
        frame.size.width = min(frame.width, visible.width)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        window.setFrame(frame, display: false)
    }

    /// 抽屉扫描根(锚定目录):目录模式 = 打开的目录;文件模式 = 最近一次锚定
    /// (抽屉双击不重锚,⌘O/外部打开以文件所在目录重锚);无 = nil
    private func currentDrawerRoot() -> URL? {
        drawerRootURL ?? fileURL?.deletingLastPathComponent()
    }

    /// 目标是否在当前锚点子树内
    private func isWithinDrawerRoot(_ url: URL) -> Bool {
        guard let root = drawerRootURL else { return false }
        let p = url.standardizedFileURL.path
        let r = root.standardizedFileURL.path
        return p == r || p.hasPrefix(r + "/")
    }

    /// 锚点下拉框选择:把某父级目录锚定为抽屉根(仅改树根;目录模式下窗口标题跟随锚点)
    func anchorDrawer(at url: URL) {
        let target = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        drawerRootURL = target
        refreshDrawer()
        if directoryMode { updateTitle() }
    }

    /// 抽屉内容刷新(打开文件/切换根后调用):load 内部对同根只重扫
    private func refreshDrawer() {
        guard let root = currentDrawerRoot() else { return }
        drawerView.load(root: root)
        if let fileURL { drawerView.select(url: fileURL) }
    }

    /// 诊断/自检用:抽屉视图访问(与 webViewIfNeeded 同一口径的受控暴露)
    var drawerForDiagnostics: FileDrawerView? { drawerView }

    /// 诊断/自检用:抽屉选中定位(lazy 下触发祖先链同步装载)
    func selectForDiagnostics(url: URL) {
        drawerView.select(url: url)
    }

    /// 诊断/自检用:当前锚定目录
    var anchorRootForDiagnostics: URL? { drawerRootURL }

    /// 诊断/自检用:抽屉当前宽度(拖拽调整后的有效值,开合与窗口收敛都按它)
    var drawerWidthForDiagnostics: CGFloat { drawerWidth }

    /// 诊断/自检用:模拟在边界拖拽 dx(与真实拖拽同一入口:起点 → 位移 → 收尾)
    func simulateDrawerResizeForDiagnostics(dx: CGFloat) {
        beginDrawerResize()
        updateDrawerResize(by: dx)
        endDrawerResize()
    }

    // MARK: - 拖放文件

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
            // 图片文件不是要打开的文档:导入 resource/ 并在光标处插入引用
            if ImageStore.isImageFile(first) {
                onImageFileDropped?(first)
                return true
            }
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
