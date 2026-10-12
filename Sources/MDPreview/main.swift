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
    // 0.8s:把 fileA 装入首个窗口(走未就绪暂存路径);2.0s:fileB 开新窗口;4s 输出
    Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
        if let fileA, let first = AppDelegate.shared?.documents.first {
            first.openDocument(at: URL(fileURLWithPath: fileA))
        }
    }
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
        if let fileB { AppDelegate.shared?.openInNewWindow(at: URL(fileURLWithPath: fileB)) }
    }
    // 3.0s:插入表格(光标落入新表);随后连续执行行列操作,观察右键菜单依赖的 inTableCached
    func doc1() -> DocumentWindowController? { AppDelegate.shared?.documents.first }
    Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
        doc1()?.evaluateForDiagnostics("window.mdbridge.debugFocusTable()") { _ in }
    }
    Timer.scheduledTimer(withTimeInterval: 3.6, repeats: false) { _ in
        print("TABLEMENU after-insert inTable=\(doc1()?.inTableCached ?? false)")
        doc1()?.tableCommand("insertRowBelow")
    }
    Timer.scheduledTimer(withTimeInterval: 4.1, repeats: false) { _ in
        print("TABLEMENU after-addRow inTable=\(doc1()?.inTableCached ?? false)")
        doc1()?.tableCommand("insertColRight")
    }
    Timer.scheduledTimer(withTimeInterval: 4.6, repeats: false) { _ in
        print("TABLEMENU after-addCol inTable=\(doc1()?.inTableCached ?? false)")
        doc1()?.tableCommand("deleteRow")
    }
    Timer.scheduledTimer(withTimeInterval: 5.1, repeats: false) { _ in
        print("TABLEMENU after-delRow inTable=\(doc1()?.inTableCached ?? false)")
        doc1()?.tableCommand("deleteColumn")
    }
    Timer.scheduledTimer(withTimeInterval: 5.6, repeats: false) { _ in
        print("TABLEMENU after-delCol inTable=\(doc1()?.inTableCached ?? false)")
        let docs = AppDelegate.shared?.documents ?? []
        let titles = docs.compactMap { $0.window?.title }
        let dirtyFlags = docs.map { $0.isDirty }
        print("MULTIWINDOW count=\(docs.count)")
        print("MULTIWINDOW titles=\(titles)")
        print("MULTIWINDOW dirty=\(dirtyFlags)")
        print("MULTIWINDOW verdict=\(docs.count == 2 && Set(titles).count == 2 ? "OK" : "CHECK")")
        exit(0)
    }
    NSApplication.shared.run()
} else {
    NSApplication.shared.run()
}
