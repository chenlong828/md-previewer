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
} else {
    NSApplication.shared.run()
}
