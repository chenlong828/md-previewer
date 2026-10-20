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
        doc.evaluateForDiagnostics("window.mdbridge.debugFocusTable()") { _ in }
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

        // 再次打开另一文件:仍同窗覆盖(菜单/抽屉统一的 openDocument 路径)
        if let fileB {
            doc.openDocument(at: fileB)
            let openedB = waitForFileURL(fileB, timeout: 8.0)
            report(openedB, "第二次打开同窗覆盖(fileURL=\(doc.fileURL?.lastPathComponent ?? "nil"))")
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

        // 收起抽屉:窗宽缩回 drawerWidth(下限 minSize)
        let widthBeforeCollapse = doc.window?.frame.width ?? 0
        doc.toggleDrawer()
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.5))
        report(!doc.isDrawerVisible, "抽屉收起")
        if let window = doc.window {
            let expectedAfter = max(window.minSize.width, widthBeforeCollapse - FileDrawerView.width)
            report(abs(window.frame.width - expectedAfter) < 1.0, "收起后窗宽=\(expectedAfter)(实际 \(window.frame.width))")
        }
        finish()
    }
    NSApplication.shared.run()
} else {
    NSApplication.shared.run()
}
