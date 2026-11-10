import AppKit

// MDPreview — Typora 风格的 macOS Markdown 所见即所得编辑器
// 架构: Swift/AppKit 壳 + WKWebView 渲染编辑 (Milkdown/KaTeX/Mermaid/Prism)

let args = CommandLine.arguments
let isSelftest = args.contains("--selftest")
let screenshotIndex = args.firstIndex(of: "--screenshot")

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(isSelftest ? .prohibited : .regular)

if isSelftest {
    SelftestRunner().run()
} else if let screenshotIndex, screenshotIndex + 1 < args.count {
    NSApp.activate(ignoringOtherApps: true)
    let runner = ScreenshotRunner()
    // 先完成启动(创建窗口),再执行截图流程
    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        let output = args[screenshotIndex + 1]
        let input = screenshotIndex + 2 < args.count && !args[screenshotIndex + 2].hasPrefix("-")
            ? args[screenshotIndex + 2] : nil
        runner.run(output: output, input: input)
    }
    NSApplication.shared.run()
} else if args.contains("--multiwindow-test") {
    NSApp.activate(ignoringOtherApps: true)
    // 用 --fileA= / --fileB= 传参,避免 LaunchServices 把裸参数当文档 openFile 送达
    func flagValue(_ name: String) -> String? {
        for a in args.dropFirst() where a.hasPrefix(name + "=") {
            return String(a.dropFirst(name.count + 1))
        }
        return nil
    }
    let fileA = flagValue("--fileA")
    let fileB = flagValue("--fileB")
    func doc1() -> DocumentWindowController? { AppDelegate.shared?.documents.first }

    // 统一前缀输出 + PASS/FAIL 判定,退出码 0=全部通过 / 1=存在失败
    var failures: [String] = []
    func report(_ ok: Bool, _ label: String) {
        print("[MULTIWINDOW] \(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures.append(label) }
    }
    func finish() {
        let docs = AppDelegate.shared?.documents ?? []
        let titles = docs.compactMap { $0.window?.title }
        let dirtyFlags = docs.map { $0.isDirty }
        print("[MULTIWINDOW] info count=\(docs.count) titles=\(titles) dirty=\(dirtyFlags)")
        report(docs.count == 2, "窗口数量为 2(实际 \(docs.count))")
        report(Set(titles).count == 2, "窗口标题不重复")
        // 文档右键菜单:Markdown 与代码文档都应出现「拷贝文件路径」与「用 Finder 打开到指定位置」
        let menus = docs.map { $0.buildContextMenu(inTable: false) }
        let copyPathItems = menus.compactMap { menu in
            menu.items.first { $0.title == "拷贝文件路径到剪贴板" }
        }
        let revealItems = menus.compactMap { menu in
            menu.items.first { $0.title == "用 Finder 打开到指定位置" }
        }
        let hasCopyPath = copyPathItems.count == docs.count
            && copyPathItems.allSatisfy { $0.target != nil && $0.action != nil }
        let hasReveal = revealItems.count == docs.count
            && revealItems.allSatisfy { $0.target != nil && $0.action != nil }
        report(hasCopyPath, "文档右键菜单含拷贝文件路径(\(copyPathItems.count)/\(docs.count))")
        report(hasReveal, "文档右键菜单含 Finder 定位(\(revealItems.count)/\(docs.count))")
        let longMenu = docs.first?.buildContextMenu(inTable: true) ?? NSMenu()
        let copyIndex = longMenu.items.firstIndex { $0.title == "拷贝文件路径到剪贴板" }
        let revealIndex = longMenu.items.firstIndex { $0.title == "用 Finder 打开到指定位置" }
        let findIndex = longMenu.items.firstIndex { $0.title == "查找…" }
        report(copyIndex != nil && revealIndex != nil && findIndex != nil
                && copyIndex! < revealIndex! && revealIndex! < findIndex!,
               "Finder 定位位于拷贝路径之后(索引 \(copyIndex ?? -1)/\(revealIndex ?? -1))")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MDPreviewCopyFilePath-\(getpid())"))
        pasteboard.clearContents()
        let expectedPath = fileA.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let copied = docs.first?.copyFilePath(to: pasteboard) ?? false
        let copiedValue = pasteboard.string(forType: .string)
        pasteboard.releaseGlobally()
        report(copied && copiedValue == expectedPath, "右键拷贝文件路径(\(copiedValue ?? "nil"))")
        // Finder 定位:用注入闭包断言传入 URL,测试不真的拉起 Finder
        let expectedReveal = fileA.map { [URL(fileURLWithPath: $0).standardizedFileURL] } ?? []
        var revealedURLs: [URL] = []
        let revealed = docs.first?.revealInFinder(using: { revealedURLs = $0 }) ?? false
        report(revealed && revealedURLs == expectedReveal,
               "右键在 Finder 中定位文件(\(revealedURLs.first?.path ?? "nil"))")
        // 反例:未保存文档没有文件路径,菜单不出现这两项,调用也不得清空剪贴板或拉起 Finder
        if let empty = AppDelegate.shared?.makeEmptyDocument() {
            let emptyMenu = empty.buildContextMenu(inTable: false)
            let hasEmptyCopyItem = emptyMenu.items.contains { $0.title == "拷贝文件路径到剪贴板" }
            let hasEmptyRevealItem = emptyMenu.items.contains { $0.title == "用 Finder 打开到指定位置" }
            let sentinelBoard = NSPasteboard(name: NSPasteboard.Name("MDPreviewCopyFilePathEmpty-\(getpid())"))
            sentinelBoard.clearContents()
            sentinelBoard.setString("sentinel", forType: .string)
            let emptyCopied = empty.copyFilePath(to: sentinelBoard)
            let sentinel = sentinelBoard.string(forType: .string)
            sentinelBoard.releaseGlobally()
            var emptyRevealed = false
            let emptyReveal = empty.revealInFinder(using: { _ in emptyRevealed = true })
            report(!hasEmptyCopyItem && !hasEmptyRevealItem && !emptyCopied
                    && sentinel == "sentinel" && !emptyReveal && !emptyRevealed,
                   "未保存文档不显示/不拷贝/不定位")
            empty.window?.close()
        } else {
            report(false, "未保存文档窗口可创建")
        }
        exit(failures.isEmpty ? 0 : 1)
    }

    // 0.8s:把 fileA 装入首个窗口(走未就绪暂存路径,由 ready 分支补载);2.0s:fileB 开新窗口
    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        if let fileA, let first = AppDelegate.shared?.documents.first {
            first.openDocument(at: URL(fileURLWithPath: fileA))
        }
    }
    if let fileB {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            AppDelegate.shared?.openInNewWindow(at: URL(fileURLWithPath: fileB))
        }
    }

    // 3.0s:定位首个窗口光标到表格内,轮询等待 selinfo 上报 inTableCached 翻转(等信号而非盲等);
    // 随后连续执行行列操作,每步报告右键菜单依赖的 inTableCached 状态
    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
        guard let doc = doc1() else {
            report(false, "首个文档窗口存在")
            exit(1)
        }
        doc.debugFocusTableForDiagnostics()
        // 轮询等待 selinfo 上报 inTableCached 翻转为 true(等信号而非盲等)
        var waited = 0.0
        while !doc.inTableCached && waited < 5.0 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
            waited += 0.2
        }
        report(doc.inTableCached, "定位表格(inTable=true)")

        // 依次执行行列操作;每步执行后留出 settle 泵让 selinfo 上报刷新,再报告状态
        let ops: [(String, String)] = [
            ("insertRowBelow", "插入行后仍在表格内"),
            ("insertColRight", "插入列后仍在表格内"),
            ("deleteRow", "删除行后仍在表格内"),
            ("deleteColumn", "删除列后仍在表格内"),
        ]
        for (op, label) in ops {
            report(doc.inTableCached, label)
            guard doc.inTableCached else { break }
            doc.tableCommand(op)
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
        }
        finish()
    }
    NSApplication.shared.run()
} else if args.contains("--context-menu-test") {
    NSApp.activate(ignoringOtherApps: true)
    // 真实右键链路的回归门:合成右键事件 → EditorWebView 坐标换算 → focusAt →
    // 构建右键菜单 → 执行菜单项,按「被点那一行的文本」断言作用行。
    // 菜单不真正弹出(实现注入 presentContextMenu 捕获),避免进入阻塞式菜单跟踪。
    var failures: [String] = []
    func report(_ ok: Bool, _ label: String) {
        print("[CONTEXTMENU] \(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures.append(label) }
    }
    func finish() {
        try? FileManager.default.removeItem(at: dir)
        exit(failures.isEmpty ? 0 : 1)
    }
    func pump(_ interval: TimeInterval = 0.05) {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(interval))
    }

    // 受控文档:表头 + 3 行正文,单元格文本唯一,便于按文本定位目标行
    let markdown = """
    # 表格右键定位

    | 列一 | 列二 |
    | --- | --- |
    | R1C1 | R1C2 |
    | R2C1 | R2C2 |
    | R3C1 | R3C2 |
    """
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mdp-context-menu-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let docURL = dir.appendingPathComponent("context-menu.md")
    try? markdown.write(to: docURL, atomically: true, encoding: .utf8)

    var controller: DocumentWindowController?
    var webView: EditorWebView?
    var menuCapture: ((NSMenu) -> Void)?

    func js(_ script: String) -> Any? {
        guard let controller else { return nil }
        var result: Any?
        var done = false
        controller.evaluateForDiagnostics(script) { value in
            result = value
            done = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !done && Date() < deadline { pump() }
        return result
    }

    /// 单元格几何(视口 CSS 像素)与文本:按文本找右键目标
    func cellGeometry() -> [[[String: Any]]]? {
        let script = """
        (function(){
            var t = document.querySelector('.ProseMirror table');
            if (!t) return 'no-table';
            return JSON.stringify(Array.prototype.map.call(t.rows, function(r){
                return Array.prototype.map.call(r.cells, function(c){
                    var b = c.getBoundingClientRect();
                    return {text: (c.textContent || '').trim(), x: b.left + b.width / 2, y: b.top + b.height / 2,
                            left: b.left, top: b.top, right: b.right, bottom: b.bottom};
                });
            }));
        })()
        """
        guard let json = js(script) as? String,
              let data = json.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[[String: Any]]] else { return nil }
        return rows
    }

    /// 合成右键并等待菜单被捕获(菜单构建是 focusAt 请求-响应之后的异步回调)。
    /// atTopLeftPadding = true 时点在单元格左上内边距(贴着边框),验证边缘点击也定位到该单元格。
    func rightClick(cellText: String, atTopLeftPadding: Bool = false, timeout: TimeInterval = 5) -> NSMenu? {
        guard let controller, let webView, let window = controller.window,
              let rows = cellGeometry(),
              let cell = rows.flatMap({ $0 }).first(where: { ($0["text"] as? String) == cellText }),
              let x = cell["x"] as? Double, let y = cell["y"] as? Double else { return nil }
        let clickX = atTopLeftPadding ? ((cell["left"] as? Double ?? x) + 3) : x
        let clickY = atTopLeftPadding ? ((cell["top"] as? Double ?? y) + 3) : y
        // 视口 CSS 像素 → 窗口坐标(WKWebView 为 flipped 视图,页面原点在视图左上)
        let windowPoint = webView.convert(NSPoint(x: clickX, y: clickY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 1)
        }
        var captured: NSMenu?
        menuCapture = { menu in captured = menu }
        if let down = event(.rightMouseDown) { NSApp.sendEvent(down) }
        if let up = event(.rightMouseUp) { NSApp.sendEvent(up) }
        var waited = 0.0
        while captured == nil && waited < timeout { pump(0.05); waited += 0.05 }
        menuCapture = nil
        return captured
    }

    /// 当前 DOM 光标所在行(0 起算;-1 = 不在表格内)
    func caretRow() -> Int {
        let script = """
        (function(){
            var sel = document.getSelection();
            if (!sel || !sel.anchorNode) return -1;
            var n = sel.anchorNode;
            if (n.nodeType === 3) n = n.parentNode;
            var tr = n && n.closest ? n.closest('tr') : null;
            return tr ? tr.rowIndex : -1;
        })()
        """
        return js(script) as? Int ?? -1
    }

    func rowTexts() -> [[String]] {
        let script = """
        (function(){
            var t = document.querySelector('.ProseMirror table');
            return t ? JSON.stringify(Array.prototype.map.call(t.rows, function(r){
                return Array.prototype.map.call(r.cells, function(c){ return (c.textContent || '').trim(); });
            })) : '[]';
        })()
        """
        guard let json = js(script) as? String,
              let data = json.data(using: .utf8),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String]] else { return [] }
        return rows
    }

    /// 直接执行菜单项(等价点击):走 DocumentWindowController 的同一 action
    func invokeMenu(_ menu: NSMenu?, _ title: String) -> Bool {
        guard let item = menu?.items.first(where: { $0.title == title }),
              let action = item.action else { return false }
        NSApp.sendAction(action, to: item.target, from: item)
        return true
    }

    /// 表格命令经桥异步执行:轮询目标 DOM 结果,不用固定延时赌时序
    func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        var waited = 0.0
        while !condition() && waited < timeout { pump(0.05); waited += 0.05 }
        return condition()
    }

    func containsText(_ rows: [[String]], _ text: String) -> Bool {
        rows.contains { $0.contains(text) }
    }

    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        guard let first = AppDelegate.shared?.documents.first, let wv = first.webViewIfNeeded else {
            report(false, "文档窗口存在")
            finish()
            return
        }
        controller = first
        webView = wv
        wv.presentContextMenu = { menu, _, _ in
            let capture = menuCapture
            menuCapture = nil
            capture?(menu)
        }
        first.openDocument(at: docURL)
        var waited = 0.0
        while (!first.isReady || first.isLoadingContent) && waited < 15 { pump(0.1); waited += 0.1 }
        report(first.isReady && !first.isLoadingContent, "受控文档装载")
        first.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pump(0.5)

        guard let geometry = cellGeometry(),
              geometry.count == 4, geometry[1].contains(where: { ($0["text"] as? String) == "R1C1" }) else {
            report(false, "受控表格渲染(4 行,含 R1C1)")
            finish()
            return
        }
        report(true, "受控表格渲染(4 行,含 R1C1)")

        // 1) 右键第 1 行:光标必须落在第 1 行;「在下方插入行」把空行插在它后面
        if let menu = rightClick(cellText: "R1C1") {
            let hasRowItems = menu.items.contains { $0.title == "在下方插入行" }
            let row = caretRow()
            report(hasRowItems, "右键表格内出现行列菜单")
            report(row == 1, "右键第 1 行 → 光标在第 1 行(实际 \(row))")
            let invoked = invokeMenu(menu, "在下方插入行")
            let grew = waitUntil { rowTexts().count == 5 }
            let rows = rowTexts()
            let newRowEmpty = rows.count > 2 && rows[2].allSatisfy { $0.isEmpty }
            report(invoked && grew
                    && rows[1].contains("R1C1") && newRowEmpty && rows[3].contains("R2C1"),
                   "右键第 1 行「在下方插入行」→ 新空行紧随第 1 行(行数 \(rows.count))")
            let after = caretRow()
            report(after == 2, "插入行后光标进入新行(实际 \(after))")
        } else {
            report(false, "右键第 1 行弹出菜单")
        }

        // 2) 右键第 2 行(插入空行后为第 3 行):删除只作用于该行
        if let menu = rightClick(cellText: "R2C1") {
            let row = caretRow()
            report(row == 3, "右键第 2 行 → 光标在该行(实际 \(row))")
            let invoked = invokeMenu(menu, "删除所在行")
            let gone = waitUntil { !containsText(rowTexts(), "R2C1") }
            let rows = rowTexts()
            report(invoked && gone && containsText(rows, "R1C1") && containsText(rows, "R3C1"),
                   "右键第 2 行「删除所在行」→ 只删除第 2 行(行数 \(rows.count))")
        } else {
            report(false, "右键第 2 行弹出菜单")
        }

        // 3) 右键第 3 行:删除后第 1 行仍在
        if let menu = rightClick(cellText: "R3C1") {
            let row = caretRow()
            report(row == 3, "右键第 3 行 → 光标在该行(实际 \(row))")
            let invoked = invokeMenu(menu, "删除所在行")
            let gone = waitUntil { !containsText(rowTexts(), "R3C1") }
            let rows = rowTexts()
            report(invoked && gone && containsText(rows, "R1C1"),
                   "右键第 3 行「删除所在行」→ 只删除第 3 行(行数 \(rows.count))")
        } else {
            report(false, "右键第 3 行弹出菜单")
        }

        // 3b) 边缘点击:点在单元格左上内边距(贴边框)也必须定位到该行,不能落到相邻行
        if let menu = rightClick(cellText: "R1C1", atTopLeftPadding: true) {
            let row = caretRow()
            report(row == 1, "右键第 1 行左上内边距 → 光标仍在该行(实际 \(row))")
            _ = menu // 菜单已构建即可;不执行删除,保留表格供列用例
        } else {
            report(false, "右键第 1 行左上内边距弹出菜单")
        }

        // 4) 列定位共用同一坐标入口:右键第 2 列删除列,只移除该列
        if let menu = rightClick(cellText: "R1C2") {
            let invoked = invokeMenu(menu, "删除所在列")
            let shrunk = waitUntil { rowTexts().first.map { $0.count == 1 } ?? false }
            let rows = rowTexts()
            report(invoked && shrunk && rows[1] == ["R1C1"],
                   "右键第 2 列「删除所在列」→ 只移除第 2 列(第 1 行 \(rows.count > 1 ? rows[1] : []))")
        } else {
            report(false, "右键第 2 列弹出菜单")
        }

        finish()
    }
    NSApplication.shared.run()
} else if args.contains("--drawer-test") {
    NSApp.activate(ignoringOtherApps: true)
    // 文件抽屉/目录模式集成自检。参数与 multiwindow-test 同款 flag 形式:
    // --dir=<目录> --fileA=<目录内文件1> --fileB=<目录内文件2>
    func flagValue(_ name: String) -> String? {
        for a in args.dropFirst() where a.hasPrefix(name + "=") {
            return String(a.dropFirst(name.count + 1))
        }
        return nil
    }
    let dirFlag = flagValue("--dir")
    let fileA = flagValue("--fileA").map { URL(fileURLWithPath: $0) }
    let fileB = flagValue("--fileB").map { URL(fileURLWithPath: $0) }
    let fileC = flagValue("--fileC").map { URL(fileURLWithPath: $0) } // 锚点之外的文件(验证重锚契约)

    var failures: [String] = []
    func report(_ ok: Bool, _ label: String) {
        print("[DRAWER] \(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures.append(label) }
    }
    func finish() {
        let docs = AppDelegate.shared?.documents ?? []
        print("[DRAWER] info count=\(docs.count) title=\(docs.first?.window?.title ?? "-") fileURL=\(docs.first?.fileURL?.path ?? "nil") dirMode=\(docs.first?.directoryMode ?? false) ready=\(docs.first?.isReady ?? false) loading=\(docs.first?.isLoadingContent ?? false) dirty=\(docs.first?.isDirty ?? false)")
        exit(failures.isEmpty ? 0 : 1)
    }
    // 确定性:清除上次运行的窗框记忆(NSWindow 框架自动保存在 "NSWindow Frame <name>")
    // 与抽屉可见性记忆,消除跨运行的宽度断言污染
    UserDefaults.standard.removeObject(forKey: "NSWindow Frame MDPreviewMainWindow")
    UserDefaults.standard.removeObject(forKey: "MDPreviewMainWindow")
    UserDefaults.standard.removeObject(forKey: "fileDrawerVisible")
    UserDefaults.standard.removeObject(forKey: FileDrawerView.widthDefaultsKey) // 宽度记忆:断言从默认宽度起算

    // 0.8s:默认窗口就绪后切入目录模式再断言(等待树装载用轮询,非盲等)
    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        guard let dirFlag else { report(false, "缺少 --dir 参数"); finish(); return }
        let dirURL = URL(fileURLWithPath: dirFlag).standardizedFileURL
        guard let doc = AppDelegate.shared?.documents.first else {
            report(false, "目录窗口存在")
            finish()
            return
        }
        // 与「文件 → 打开文件夹…」同一路径:当前窗口切入目录模式
        doc.openDirectory(at: dirURL)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
        report(AppDelegate.shared?.documents.count == 1, "目录模式仅 1 个窗口")
        // 锚点下拉框:父级链条目数与 DirectoryTree.ancestorChain 一致
        let expectedChain = DirectoryTree.ancestorChain(of: dirURL).count
        report(doc.drawerForDiagnostics?.anchorItemCountForDiagnostics == expectedChain,
               "锚点下拉框条目=父级链(\(doc.drawerForDiagnostics?.anchorItemCountForDiagnostics ?? -1)/\(expectedChain))")
        // 锚点菜单的 Finder 文件夹图标(用户可见承诺)与头部宽度账(控件铺满抽屉宽扣除按钮)
        if let drawer = doc.drawerForDiagnostics {
            report(drawer.anchorMenuItemsHaveIconsForDiagnostics, "锚点菜单每条都带 Finder 文件夹图标")
            let levels = drawer.anchorMenuIndentationLevelsForDiagnostics
            report(levels == Array(0..<levels.count),
                   "锚点菜单逐级递进缩进(实际 \(levels))")
            let frames = drawer.headerFramesForDiagnostics
            let spacing = FileDrawerView.HeaderMetrics.spacing
            let drawerWidth = drawer.frame.width
            report(abs(frames.control.minX) < 0.5, "锚点控件贴抽屉左缘(实际 \(frames.control.minX))")
            report(abs(frames.control.maxX - (frames.home.minX - spacing)) < 0.5,
                   "锚点控件右缘=Home 按钮左缘-\(spacing)(实际 \(frames.control.maxX))")
            report(abs(frames.home.maxX - (frames.refresh.minX - spacing)) < 0.5,
                   "Home 按钮右缘=刷新按钮左缘-\(spacing)(实际 \(frames.home.maxX))")
            report(abs(frames.refresh.maxX - (drawerWidth - FileDrawerView.HeaderMetrics.trailingInset)) < 0.5,
                   "刷新按钮贴抽屉右缘(实际 \(frames.refresh.maxX)/\(drawerWidth))")
            let expectedControlWidth = drawerWidth - frames.home.width - frames.refresh.width
                - 2 * spacing - FileDrawerView.HeaderMetrics.trailingInset
            report(abs(frames.control.width - expectedControlWidth) < 0.5,
                   "锚点控件宽度=抽屉宽-两个按钮-间距(期望 \(expectedControlWidth) 实际 \(frames.control.width))")
        }
        // lazy 点击展开链路回归(用户实测曾失效):点三角→取数同步装载→子行出现
        if let clickURL = flagValue("--clickExpand").map({ URL(fileURLWithPath: $0) }) {
            let childRows = doc.drawerForDiagnostics?.debugExpandByClick(url: clickURL) ?? -1
            report(childRows > 0, "点击展开装载子层(子行数 \(childRows))")
            if let clickExpect = flagValue("--clickExpect").map({ URL(fileURLWithPath: $0) }) {
                report(doc.drawerForDiagnostics?.debugTreeContains(clickExpect) ?? false,
                       "点击展开后子层在树中(\(clickExpect.lastPathComponent))")
            }
        }
        report(doc.directoryMode, "目录模式标志(directoryMode=true)")
        report(doc.fileURL == nil, "目录模式无文档(fileURL=nil)")
        report(doc.isDrawerVisible, "目录模式抽屉展开")
        report(doc.window?.title == dirURL.lastPathComponent, "窗口标题=目录名(得 \(doc.window?.title ?? "-"))")

        // 等待抽屉树装载(后台扫描异步回填)
        var waited = 0.0
        while (doc.drawerForDiagnostics?.rowCountForDiagnostics ?? 0) == 0 && waited < 5.0 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
            waited += 0.1
        }
        report((doc.drawerForDiagnostics?.rowCountForDiagnostics ?? 0) > 0, "抽屉树装载(\(doc.drawerForDiagnostics?.rowCountForDiagnostics ?? 0) 行)")
        // 真实仓库根验证(--expect):lazy 下树包含断言在打开深层文件
        // (选中链同步装载)之后评估,见下文 expect 断言

        // 窗口宽度收敛断言:初始 1000pt + 抽屉 240pt,超出屏幕可视宽度则收敛到屏宽
        if let window = doc.window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let expected = min(1000 + FileDrawerView.width, visible.width)
            let actual = window.frame.width
            report(abs(actual - expected) < 1.0, "展开后窗宽=\(expected)(实际 \(actual))")
        } else {
            report(false, "窗口/屏幕可用,可断言宽度")
        }

        // 抽屉双击 → 同窗覆盖打开(不是新实例);装载完成回调可能延迟,轮询等待
        func waitForFileURL(_ target: URL, timeout: TimeInterval) -> Bool {
            var waited = 0.0
            while doc.fileURL != target.standardizedFileURL && waited < timeout {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
                waited += 0.1
            }
            return doc.fileURL == target.standardizedFileURL
        }
        guard let fileA else { finish(); return }
        doc.drawerForDiagnostics?.debugOpenByDoubleClick(url: fileA)
        let openedA = waitForFileURL(fileA, timeout: 8.0)
        report(AppDelegate.shared?.documents.count == 1, "双击打开后仍 1 个窗口(同窗覆盖)")
        report(openedA, "fileURL=双击目标")
        report(!doc.directoryMode, "已退出目录模式")
        report(doc.window?.title == fileA.lastPathComponent, "标题=文件名(得 \(doc.window?.title ?? "-"))")
        report(doc.anchorRootForDiagnostics == dirURL, "抽屉双击保持锚点(不重锚到文件所在层)")

        // 子层文件经树打开(先选中装载祖先链,再走抽屉回调):锚点保持为原锚点
        if let fileB {
            doc.selectForDiagnostics(url: fileB)
            doc.drawerForDiagnostics?.debugOpenByDoubleClick(url: fileB)
            let openedB = waitForFileURL(fileB, timeout: 8.0)
            report(openedB, "树打开子层文件同窗覆盖(fileURL=\(doc.fileURL?.lastPathComponent ?? "nil"))")
            report(doc.anchorRootForDiagnostics == dirURL, "树打开子层文件保持锚点(跨多层浏览)")
        }

        // 非抽屉来源打开锚点外文件:锚点重锚为文件所在目录(外部/⌘O/最近使用契约)
        if let fileC {
            doc.openDocument(at: fileC)
            let openedC = waitForFileURL(fileC, timeout: 8.0)
            report(openedC && doc.anchorRootForDiagnostics == fileC.deletingLastPathComponent().standardizedFileURL,
                   "非抽屉打开锚点外文件重锚到文件所在目录")
            // 锚点下拉框选回原目录(走 onAnchorSelected 同一路径)
            doc.drawerForDiagnostics?.debugAnchor(to: dirURL)
            let chainBack = DirectoryTree.ancestorChain(of: dirURL).count
            report(doc.anchorRootForDiagnostics == dirURL
                   && doc.drawerForDiagnostics?.anchorItemCountForDiagnostics == chainBack,
                   "下拉框重锚回原目录(条目数 \(doc.drawerForDiagnostics?.anchorItemCountForDiagnostics ?? -1))")
        }

        // ⌘O 菜单动作解析诊断:无 target 菜单项的派发以 key window 响应链为起点,
        // key window 的 windowController 是当前控制器即等价于菜单动作落在当前窗口
        doc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.3))
        if NSApp.keyWindow != nil {
            report(NSApp.keyWindow?.windowController === doc, "⌘O 动作经响应链解析到当前窗口控制器(key window)")
        } else {
            print("[DRAWER] SKIP ⌘O 响应链断言(无 key window)")
        }

        // lazy 树包含断言:expect 文件经打开/选中链装载后应在已装载子树中
        // (回归哨兵:曾因 eager 预算被 node_modules 耗尽导致深层目录缺失)
        if let expect = flagValue("--expect").map({ URL(fileURLWithPath: $0) }) {
            doc.selectForDiagnostics(url: expect)
            report(doc.drawerForDiagnostics?.debugTreeContains(expect) ?? false,
                   "树包含 \(expect.lastPathComponent)(\(expect.deletingLastPathComponent().lastPathComponent)/)")
        }

        // 「打开最近使用」底层语义:当前窗口覆盖打开(菜单动作 openRecentFile 经此 helper)
        doc.openDocument(at: fileA) // 先切回 fileA,再经 helper 打开 fileB 验证同窗
        let _ = waitForFileURL(fileA, timeout: 8.0)
        if let fileB {
            AppDelegate.shared?.openInCurrentWindowOrNew(at: fileB)
            let opened = waitForFileURL(fileB, timeout: 8.0)
            report(opened && AppDelegate.shared?.documents.count == 1,
                   "openInCurrentWindowOrNew 当前窗口覆盖打开(菜单打开语义)")
        }

        // Home 按钮:一键回到当前用户 Home 目录(与锚点菜单选择同一重锚路径;
        // 已在 Home 时置灰)。菜单条目在后台重扫回填,轮询等信号而非盲等
        if let drawer = doc.drawerForDiagnostics {
            let homeTarget = drawer.homeTargetForDiagnostics
            let homeChain = DirectoryTree.ancestorChain(of: homeTarget).count
            drawer.debugHomePress()
            var waitedHome = 0.0
            while drawer.anchorItemCountForDiagnostics != homeChain && waitedHome < 3.0 {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
                waitedHome += 0.1
            }
            report(doc.anchorRootForDiagnostics == homeTarget, "Home 按钮重锚到 Home 目录")
            report(drawer.anchorItemCountForDiagnostics == homeChain,
                   "Home 锚点菜单=Home 父级链(\(drawer.anchorItemCountForDiagnostics)/\(homeChain))")
            report(!drawer.homeButtonEnabledForDiagnostics, "已在 Home 时 Home 按钮置灰")
        }

        // 边界拖拽调宽:宽度随位移变化、窗口宽度不动、收起按当前宽度缩回
        if let window = doc.window, doc.isDrawerVisible {
            let windowWidthBeforeResize = window.frame.width
            doc.simulateDrawerResizeForDiagnostics(dx: 80)
            let resizedWidth = doc.drawerWidthForDiagnostics
            let expectedWidth = FileDrawerView.width + 80
            report(abs(resizedWidth - expectedWidth) < 0.5,
                   "拖拽后抽屉宽度=\(expectedWidth)(实际 \(resizedWidth))")
            report(abs(window.frame.width - windowWidthBeforeResize) < 0.5,
                   "拖拽调整不改变窗口宽度(实际 \(window.frame.width))")
            report(abs((doc.drawerForDiagnostics?.frame.width ?? 0) - resizedWidth) < 1.0,
                   "抽屉视图宽度与拖拽宽度一致")
            // 越界夹取:大幅拖拽被夹在上界内
            doc.simulateDrawerResizeForDiagnostics(dx: 5000)
            report(doc.drawerWidthForDiagnostics <= max(FileDrawerView.maxWidth, FileDrawerView.minWidth),
                   "拖拽越界夹取上界(实际 \(doc.drawerWidthForDiagnostics))")
            // 拖回基准宽度,后续收起断言用固定值
            doc.simulateDrawerResizeForDiagnostics(dx: -(doc.drawerWidthForDiagnostics - FileDrawerView.width))
            report(abs(doc.drawerWidthForDiagnostics - FileDrawerView.width) < 0.5,
                   "拖回默认宽度(实际 \(doc.drawerWidthForDiagnostics))")
            report(abs((UserDefaults.standard.double(forKey: FileDrawerView.widthDefaultsKey) - FileDrawerView.width)) < 0.5,
                   "拖拽结束落盘 fileDrawerWidth")

            // 边界命中测试:边界处的点击必须落在分隔条上(不被 webView 吃掉);
            // 真实事件拖动只在窗口为 key 时有效(非 key 窗口的首次点击按 AppKit 语义
            // 被激活逻辑吞掉,不是产品缺陷——无头环境常拿不到 key window,故 SKIP)
            if let contentView = window.contentView, let dividerHost = doc.drawerForDiagnostics {
                let boundary = NSPoint(x: dividerHost.frame.maxX, y: contentView.bounds.midY)
                report(contentView.hitTest(boundary) is DrawerResizeDivider,
                       "边界命中测试落在分隔条上(实际 \(String(describing: contentView.hitTest(boundary))))")
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
                if window.isKeyWindow {
                    let startWidth = doc.drawerWidthForDiagnostics
                    let inWindow = contentView.convert(boundary, to: nil)
                    func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent? {
                        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 1, clickCount: 1, pressure: 1)
                    }
                    if let down = mouse(.leftMouseDown, inWindow),
                       let drag = mouse(.leftMouseDragged, NSPoint(x: inWindow.x + 40, y: inWindow.y)),
                       let up = mouse(.leftMouseUp, NSPoint(x: inWindow.x + 40, y: inWindow.y)) {
                        window.sendEvent(down)
                        window.sendEvent(drag)
                        window.sendEvent(up)
                        report(abs(doc.drawerWidthForDiagnostics - (startWidth + 40)) < 1.0,
                               "边界按下拖动真实事件生效(期望 \(startWidth + 40) 实际 \(doc.drawerWidthForDiagnostics))")
                        doc.simulateDrawerResizeForDiagnostics(dx: -(doc.drawerWidthForDiagnostics - FileDrawerView.width))
                    }
                } else {
                    print("[DRAWER] SKIP 真实事件拖动(无 key window,首次点击被激活逻辑吞掉)")
                }
            }
        }

        // 收起抽屉:窗宽缩回当前抽屉宽度(下限 minSize)
        let widthBeforeCollapse = doc.window?.frame.width ?? 0
        doc.toggleDrawer()
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
        report(!doc.isDrawerVisible, "抽屉收起")
        if let window = doc.window {
            let expectedAfter = max(window.minSize.width, widthBeforeCollapse - doc.drawerWidthForDiagnostics)
            report(abs(window.frame.width - expectedAfter) < 1.0, "收起后窗宽=\(expectedAfter)(实际 \(window.frame.width))")
        }
        finish()
    }
    NSApplication.shared.run()
} else {
    NSApplication.shared.run()
}
