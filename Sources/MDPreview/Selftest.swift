import AppKit
import WebKit
import os.log

/// 无头自检:`MDPreview --selftest`
/// 加载真实编辑器页面,注入样例文档,验证 katex/mermaid/表格/代码高亮渲染、
/// markdown 往返、源码模式、主题切换、PDF 导出与图片路径改写。
/// 注意:全部等待都基于主线程 RunLoop 泵送,绝不能用信号量阻塞主线程
/// (WKWebView 的完成回调也在主线程,阻塞会死锁)。
final class SelftestRunner: NSObject {
    private var failed = false
    private var webview: EditorWebView!
    private var window: NSWindow!
    private var bootReceived = false
    private var readyReceived = false

    static let sampleMarkdown = #"""
# 自检文档 Heading One

**加粗** *斜体* ~~删除线~~ `inline code` [链接](https://example.com)

## 表格

| 功能 | 状态 |
| ---- | :--: |
| GFM 表格 | 通过 |

## 数学公式

行内 $E = mc^2$ 公式,块级:

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$

## Mermaid 图

```mermaid
graph LR
  A[开始] --> B{判断}
  B -->|是| C[结束]
  B -->|否| A
```

## 代码块

```swift
func greet() -> String {
    return "hello, world"
}
```

## 任务列表

- [x] 已完成项
- [ ] 未完成项

> 这是一段引用文字

结束分割线:

---

"""#

    func run() {
        guard let pageURL = WebLocator.indexURL() else {
            fail("找不到 web/dist/index.html,请先运行 web 构建")
            exit(1)
        }
        print("SELFTEST page: \(pageURL.path)")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        webview = EditorWebView(configuration: EditorWebView.makeConfiguration())
        webview.frame = window.contentView!.bounds
        webview.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webview)
        window.orderFrontRegardless() // 需要参与渲染,但 app 为 .prohibited 不抢焦点

        webview.onBridgeMessage = { [weak self] op, payload in
            guard let self else { return }
            if op == "boot" { self.bootReceived = true }
            if op == "ready" { self.readyReceived = true }
            if op == "jserror" {
                let msg = payload["message"] as? String ?? "?"
                let stack = payload["stack"] as? String ?? ""
                print("WEB-JS-ERROR: \(msg)\n\(stack.prefix(1200))")
            }
        }

        webview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        // ── 等待页面脚本加载
        waitFor("页面脚本加载(boot)", timeout: 30) { self.bootReceived }

        // ── 初始化编辑器
        let pluginSet = ProcessInfo.processInfo.environment["MDP_PLUGINS"] ?? "full"
        let optsJSON = "{\"theme\":\"light\",\"zoom\":1,\"plugins\":\"\(pluginSet)\"}"
        evaluate("void window.mdbridge.init(\(JSArgs.string(SelftestRunner.sampleMarkdown)), \(optsJSON))") { _ in }
        waitFor("编辑器初始化(ready)", timeout: 30) { self.readyReceived }
        sleepOrUntil(timeout: 2.5) { false } // 给 mermaid 一点异步渲染时间

        // ── 任务列表与表格诊断
        self.evaluate("(function(){var li=document.querySelector('li[data-item-type=task]');return li?JSON.stringify({outer:li.outerHTML.slice(0,200),attrs:JSON.stringify(li.dataset)}):'no-task-li'})()") { r in
            print("SELFTEST task:", r ?? "nil")
        }
        self.evaluate("(function(){var md=window.mdbridge.getMarkdown();var i=md.indexOf('|');return JSON.stringify(md.slice(i>=0?i:0,(i>=0?i:0)+120))})()") { r in
            print("SELFTEST table-md:", r ?? "nil")
        }

        // ── mermaid 节点诊断
        self.evaluate("(function(){var d=document.querySelector('[data-type=diagram]');return d?JSON.stringify({svg:!!d.querySelector('svg'),html:d.innerHTML.slice(0,150)}):'no-diagram-node'})()") { r in
            print("SELFTEST diagram:", r ?? "nil")
        }

        // ── 渲染断言
        var checks: [String: Any] = [:]
        waitForCollect("初始渲染断言", timeout: 15) { done in
            self.evaluate(SelftestRunner.checksJS) { result in
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (dict["mermaidSvg"] as? Int ?? 0) >= 1 {
                    checks = dict
                    done()
                }
            }
        }

        let expect: [(String, String, (Any) -> Bool)] = [
            ("ProseMirror 编辑器挂载", "prosemirror", { $0 as? Bool == true }),
            ("H1/H2 标题渲染", "h1", { ($0 as? Int ?? 0) >= 1 }),
            ("表格渲染", "table", { $0 as? Bool == true }),
            ("KaTeX 公式渲染", "katex", { ($0 as? Int ?? 0) >= 2 }),
            ("Prism 代码高亮", "token", { ($0 as? Int ?? 0) >= 3 }),
            ("任务列表渲染", "taskChecked", { ($0 as? Int ?? 0) >= 2 }),
            ("引用块渲染", "blockquote", { $0 as? Bool == true }),
            ("分割线渲染", "hr", { ($0 as? Int ?? 0) >= 1 }),
            ("链接渲染", "link", { ($0 as? Int ?? 0) >= 1 }),
            ("Mermaid 图表渲染", "mermaidSvg", { ($0 as? Int ?? 0) >= 1 }),
        ]
        for (name, key, test) in expect {
            guard let value = checks[key] else {
                fail("\(name): 无数据")
                continue
            }
            if test(value) { pass(name) } else { fail("\(name): 值=\(value)") }
        }

        // ── markdown 往返
        var roundtrip = ""
        waitForCollect("markdown 往返", timeout: 10) { done in
            self.evaluate("window.mdbridge.getMarkdown()") { result in
                if let s = result as? String, !s.isEmpty {
                    roundtrip = s
                    done()
                }
            }
        }
        for marker in ["Heading One", "| 功能", "$$", "mermaid", "graph LR", "[x]", ">"] {
            if roundtrip.contains(marker) { pass("往返包含 \(marker)") } else { fail("往返缺少 \(marker)") }
        }

        // ── 源码模式
        var sourceOK = false
        waitForCollect("源码模式显示原文", timeout: 10) { done in
            self.evaluate("window.mdbridge.toggleSource(true)") { _ in
                self.evaluate("(function(){var t=document.getElementById('source-editor');return JSON.stringify({visible:t.offsetHeight>0,len:t.value.length})})()") { r2 in
                    if let json = r2 as? String,
                       let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                       (d["visible"] as? Bool) == true, (d["len"] as? Int ?? 0) > 100 {
                        sourceOK = true
                    }
                    done()
                }
            }
        }
        if sourceOK { pass("源码模式显示原文") } else { fail("源码模式显示原文") }

        // ── 源码模式编辑 → 退出 → 内容回写
        var editOK = false
        waitForCollect("源码模式编辑回写", timeout: 10) { done in
            self.evaluate(#"(function(){var t=document.getElementById('source-editor');t.value=t.value+"\n追加行";return window.mdbridge.toggleSource(false);})()"#) { _ in
                self.evaluate("window.mdbridge.getMarkdown()") { r in
                    if let md = r as? String, md.contains("追加行") { editOK = true }
                    done()
                }
            }
        }
        if editOK { pass("源码模式编辑回写") } else { fail("源码模式编辑回写") }

        // ── 主题切换
        evaluate("window.mdbridge.setTheme('dark')") { _ in }
        var themeOK = false
        evaluate("document.documentElement.dataset.theme") { r in
            themeOK = (r as? String) == "dark"
        }
        if themeOK { pass("深色主题切换") } else { fail("深色主题切换") }
        evaluate("window.mdbridge.setTheme('light')") { _ in }

        // ── 命令桥
        evaluate("window.mdbridge.insertTable(2,2)") { r in
            if (r as? Bool) == true { self.pass("命令桥 insertTableCommand") } else { self.fail("命令桥 insertTableCommand → \(String(describing: r))") }
        }
        sleepOrUntil(timeout: 1.0) { false }
        evaluate("document.querySelectorAll('table').length") { r in
            if (r as? Int ?? 0) >= 2 { self.pass("插入表格生效") } else { self.fail("插入表格生效") }
        }

        // ── 表格行列操作(断言光标所在表格的 doc 几何)
        evaluate("window.webkit.messageHandlers.mdbridge.postMessage({op:'jslog', msg:'DIRECT-TEST-OK'})") { _ in }
        func expectTableGeo(_ rows: Int, _ cols: Int, _ name: String) {
            evaluate("JSON.stringify(window.mdbridge.tableInfo())") { r in
                if let json = r as? String,
                   let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                   (d["inTable"] as? Bool) == true, d["rows"] as? Int == rows, d["cols"] as? Int == cols {
                    self.pass(name)
                } else { self.fail(name + " → \(r ?? "nil")") }
            }
        }
        evaluate("window.mdbridge.insertTable(3,3)") { r in
            if (r as? Bool) == true { self.pass("表格-插入命令") } else { self.fail("表格-插入命令 → \(String(describing: r))") }
        }
        expectTableGeo(3, 3, "表格-初始几何")
        evaluate("window.mdbridge.tableCommand('insertRowBelow')") { r in
            if (r as? Bool) == true { self.pass("表格-插入行命令") } else { self.fail("表格-插入行命令 → \(String(describing: r))") }
        }
        expectTableGeo(4, 3, "表格-插入行生效")
        evaluate("window.mdbridge.tableCommand('insertColRight')") { r in
            if (r as? Bool) == true { self.pass("表格-插入列命令") } else { self.fail("表格-插入列命令 → \(String(describing: r))") }
        }
        expectTableGeo(4, 4, "表格-插入列生效")
        evaluate("window.mdbridge.tableCommand('deleteRow')") { r in
            if (r as? Bool) == true { self.pass("表格-删除行命令") } else { self.fail("表格-删除行命令 → \(String(describing: r))") }
        }
        expectTableGeo(3, 4, "表格-删除行生效")
        evaluate("window.mdbridge.tableCommand('deleteColumn')") { r in
            if (r as? Bool) == true { self.pass("表格-删除列命令") } else { self.fail("表格-删除列命令 → \(String(describing: r))") }
        }
        expectTableGeo(3, 3, "表格-删除列生效")

        // ── 插入的行必须是空行(不复制原有内容)
        evaluate("window.mdbridge.debugFocusTable()") { r in
            if (r as? Bool) == true { self.pass("表格-定位首表") } else { self.fail("表格-定位首表 → \(String(describing: r))") }
        }
        evaluate("window.mdbridge.tableCommand('insertRowBelow')") { _ in }
        evaluate("window.mdbridge.getMarkdown()") { r in
            if let md = r as? String,
               md.contains("| <br /> | <br /> |"),
               md.contains("GFM 表格") {
                self.pass("表格-新行为空")
            } else { self.fail("表格-新行为空") }
        }
        evaluate("window.mdbridge.undo()") { _ in }

        // ── 命令注册表完整性(菜单栏与右键菜单共用同一份定义)
        var registryOK = true
        for spec in EditorCommands.all {
            // responderChain 型命令由响应链处理(WKWebView 实现系统编辑动作),其余由控制器实现
            let ok = spec.responderChain
                ? EditorWebView.instancesRespond(to: spec.selector)
                : DocumentWindowController.instancesRespond(to: spec.selector)
            if !ok { registryOK = false }
        }
        if EditorCommands.all.count >= 30, registryOK {
            pass("命令注册表完整(\(EditorCommands.all.count) 条)")
        } else {
            fail("命令注册表完整(\(EditorCommands.all.count) 条,响应缺失)")
        }

        // ── 缩放
        evaluate("window.mdbridge.setZoom(1.25)") { _ in }
        evaluate("getComputedStyle(document.getElementById('app')).zoom") { r in
            let v = (r as? String) ?? "\(r ?? "")"
            if v.contains("1.25") { self.pass("缩放应用") } else { self.fail("缩放应用 → \(v)") }
        }
        evaluate("window.mdbridge.setZoom(1.0)") { _ in }

        // ── 宽度策略:100% 跟随窗体,下限 860px
        evaluate("JSON.stringify({appW: document.getElementById('app').getBoundingClientRect().width, vw: document.documentElement.clientWidth, minW: getComputedStyle(document.getElementById('app')).minWidth})") { r in
            guard let json = r as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appW = dict["appW"] as? Double,
                  let vw = dict["vw"] as? Double,
                  let minW = dict["minW"] as? String else {
                self.fail("宽度策略读取 → \(String(describing: r))")
                return
            }
            let fillsWindow = appW >= vw - 1.5
            let minOk = minW.contains("860")
            if fillsWindow && minOk { self.pass("宽度策略(100%+860下限)") } else { self.fail("宽度策略 → appW=\(appW) vw=\(vw) minW=\(minW)") }
        }

        // ── 文档内查找
        evaluate("window.mdbridge.openFindBar()") { _ in }
        evaluate("(function(){var i=document.getElementById('find-input');i.value='公式';i.dispatchEvent(new Event('input'));return true})()") { _ in }
        sleepOrUntil(timeout: 1.0) { false }
        evaluate("document.getElementById('find-count').textContent") { r in
            let v = (r as? String) ?? ""
            let parts = v.split(separator: "/").compactMap { Int($0) }
            if parts.count == 2, parts[0] >= 1, parts[1] >= parts[0] { self.pass("查找命中计数(\(v))") } else { self.fail("查找命中计数 → \(v)") }
        }
        evaluate("window.mdbridge.findNext(); document.getElementById('find-count').textContent") { r in
            let v = (r as? String) ?? ""
            if v == "2/2" { self.pass("查找下一处(\(v))") } else { self.fail("查找下一处 → \(v)") }
        }
        evaluate("JSON.stringify({cur: !!document.querySelector('.md-find-current'), total: document.querySelectorAll('.md-find-match').length})") { r in
            guard let json = r as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = dict["cur"] as? Bool, cur,
                  let total = dict["total"] as? Int, total >= 2 else {
                self.fail("查找高亮 → \(String(describing: r))")
                return
            }
            self.pass("查找高亮与定位(\(total) 处)")
        }
        evaluate("window.mdbridge.closeFindBar(); document.body.classList.contains('finding') ? 'open' : 'closed'") { r in
            if (r as? String) == "closed" { self.pass("查找栏关闭") } else { self.fail("查找栏关闭 → \(String(describing: r))") }
        }

        // ── PDF 导出能力
        var pdfOK = false
        waitForCollect("PDF 导出", timeout: 25) { done in
            self.evaluate("document.documentElement.scrollHeight") { hResult in
                guard let h = (hResult as? NSNumber)?.doubleValue, h > 100 else {
                    done()
                    return
                }
                self.webview.translatesAutoresizingMaskIntoConstraints = true
                self.webview.frame = NSRect(x: 0, y: 0, width: 1000, height: CGFloat(h))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let config = WKPDFConfiguration()
                    config.rect = self.webview.bounds
                    self.webview.createPDF(configuration: config) { result in
                        switch result {
                        case .success(let data):
                            pdfOK = data.count > 10_000
                            print("SELFTEST pdf bytes:", data.count)
                        case .failure(let error):
                            print("SELFTEST pdf error:", error.localizedDescription)
                            pdfOK = false
                        }
                        done()
                    }
                }
            }
        }
        if pdfOK { pass("PDF 导出") } else { fail("PDF 导出") }

        // ── Swift 侧图片路径改写
        testPathRewriter()

        print("SELFTEST \(failed ? "FAILED" : "PASSED")")
        exit(failed ? 1 : 0)
    }

    private static let checksJS = """
    (function() {
        return JSON.stringify({
            prosemirror: !!document.querySelector('.ProseMirror'),
            h1: document.querySelectorAll('h1').length,
            h2: document.querySelectorAll('h2').length,
            table: !!document.querySelector('table'),
            katex: document.querySelectorAll('.katex').length,
            token: document.querySelectorAll('.token').length,
            taskChecked: document.querySelectorAll('li[data-item-type="task"][data-checked]').length,
            blockquote: !!document.querySelector('blockquote'),
            hr: document.querySelectorAll('hr').length,
            link: document.querySelectorAll('a[href="https://example.com"]').length,
            mermaidSvg: document.querySelectorAll('[data-type="diagram"] svg').length
        });
    })()
    """

    // MARK: - 路径改写测试

    private func testPathRewriter() {
        let baseURL = URL(fileURLWithPath: "/tmp/selftest-doc-\(getpid())")
        let fm = FileManager.default
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let imgPath = baseURL.appendingPathComponent("pic.png").path
        fm.createFile(atPath: imgPath, contents: Data([1, 2, 3]))

        let md = "![图](pic.png)\n\n```swift\nlet s = \"![x](fake.png)\"\n```\n"
        let rewritten = ImagePathRewriter.forLoad(md, baseURL: baseURL)
        if rewritten.contains(baseURL.appendingPathComponent("pic.png").absoluteString) {
            pass("图片路径改写(加载)")
        } else {
            fail("图片路径改写(加载) → \(rewritten)")
        }
        if rewritten.contains("![x](fake.png)") {
            pass("代码围栏不受改写影响")
        } else {
            fail("代码围栏不受改写影响 → \(rewritten)")
        }

        let saved = ImagePathRewriter.forSave(rewritten, baseURL: baseURL)
        if saved.contains("![图](pic.png)") {
            pass("图片路径还原(保存)")
        } else {
            fail("图片路径还原(保存) → \(saved)")
        }

        let missing = ImagePathRewriter.forLoad("![m](not-there.png)", baseURL: baseURL)
        if missing.contains("not-there.png") && !missing.contains("file://") {
            pass("缺失文件保持原样")
        } else {
            fail("缺失文件保持原样 → \(missing)")
        }
        try? fm.removeItem(at: baseURL)
    }

    // MARK: - 基础设施(全部走 RunLoop 泵送)

    private func evaluate(_ js: String, completion: ((Any?) -> Void)? = nil) {
        var finished = false
        var output: Any?
        webview.evaluateJavaScript(js) { result, error in
            if let error { print("SELFTEST-JS-ERR:", error.localizedDescription, js.prefix(200)) }
            output = result
            finished = true
        }
        let deadline = Date().addingTimeInterval(15)
        while !finished && Date() < deadline { pumpRunLoop(for: 0.05) }
        if !finished { os_log(.error, "selftest JS timeout: %{private}@", String(js.prefix(120))) }
        completion?(output)
    }

    private func waitFor(_ name: String, timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { pass(name); return }
            pumpRunLoop(for: 0.1)
        }
        fail(name)
    }

    /// done 通过置位 finished 标志结束等待
    private func waitForCollect(_ name: String, timeout: TimeInterval, poll: @escaping (_ done: @escaping () -> Void) -> Void) {
        var finished = false
        poll { finished = true }
        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            pumpRunLoop(for: 0.05)
        }
        _ = name
    }

    private func sleepOrUntil(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !condition() {
            pumpRunLoop(for: 0.1)
        }
    }

    private func pumpRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(interval))
    }

    private func pass(_ name: String) { print("PASS  \(name)") }
    private func fail(_ name: String) {
        failed = true
        print("FAIL  \(name)")
    }
}

/// web 资源定位(编辑器与自检共用)
enum WebLocator {
    static func indexURL() -> URL? {
        if let res = Bundle.main.resourceURL {
            let u = res.appendingPathComponent("web/index.html")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        let repoCandidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("web/dist/index.html"),
        ]
        for c in repoCandidates where FileManager.default.fileExists(atPath: c.path) { return c }
        return nil
    }
}
