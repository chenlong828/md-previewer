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
    private let kernel = KernelClient()
    private let lightKernel = KernelClient()
    /// 等待间隔命名常量(非魔力裸数字:注明依据)
    enum Polling {
        /// 几何收敛轮询间隔:一轮布局+合成至少数帧,0.05s 足以观察到变化
        static let geometryInterval: TimeInterval = 0.05
        /// 几何收敛轮询上限(40 次 ≈ 2s):超大文档兜底
        static let geometryMaxAttempts = 40
    }

    /// 桥消息观测:changed 上报计数(D1 误报守门用)
    private var changedTrueCount = 0
    private var changedTotalCount = 0
    /// 轻量模式检查页(OQ-1)的加载标志
    private var lightBootReceived = false
    private var lightReadyReceived = false

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
        webview = EditorWebView(configuration: EditorWebView.makeConfiguration(testFacade: true))
        webview.frame = window.contentView!.bounds
        webview.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webview)
        window.orderFrontRegardless() // 需要参与渲染,但 app 为 .prohibited 不抢焦点

        kernel.attach(to: webview)
        webview.onKernelMessage = { [weak self] body in
            self?.kernel.receive(body) ?? false
        }
        kernel.onNotification = { [weak self] op, payload in
            self?.handleNotification(op: op, payload: payload)
        }
        kernel.onRequest = { [weak self] op, payload, reply in
            self?.handleKernelRequest(op: op, payload: payload, reply: reply)
        }
        webview.onBridgeMessage = { [weak self] op, payload in
            self?.handleNotification(op: op, payload: payload)
        }

        webview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        // ── 等待页面脚本加载
        waitFor("页面脚本加载(boot)", timeout: 30) { self.bootReceived }

        // ── 初始化编辑器(baseDir 供图片源码编辑框做相对路径换算)
        let pluginSet = ProcessInfo.processInfo.environment["MDP_PLUGINS"] ?? "full"
        let initOpts: [String: Any] = [
            "protocolVersion": KernelClient.protocolVersion,
            "theme": "light", "zoom": 1, "plugins": pluginSet, "baseDir": "/tmp",
        ]
        kernel.send("init", ["markdown": SelftestRunner.sampleMarkdown, "opts": initOpts]) { [weak self] result in
            if case .success(let payload) = result { self?.kernel.recordHandshake(payload) }
        }
        waitFor("编辑器初始化(ready)", timeout: 30) { self.readyReceived }
        // v2 通道自证：握手拿到协议版本与 op 清单，且一次真实 op 往返成立
        // （ready 通知先于 init 响应到达，因此这里等响应落表，不假设顺序）
        waitFor("v2 握手响应", timeout: 10) { !self.kernel.info.isEmpty }
        let handshakeVersion = kernel.info["protocolVersion"] as? Int ?? -1
        let handshakeOps = (kernel.info["ops"] as? [String]) ?? []
        if handshakeVersion == KernelClient.protocolVersion && handshakeOps.contains("getState") {
            pass("v2 握手(protocolVersion=2, ops=\(handshakeOps.count))")
        } else {
            fail("v2 握手(version=\(handshakeVersion), ops=\(handshakeOps.count))")
        }
        var stateRoundTrip = false
        kernel.send("getState") { result in
            if case .success(let payload) = result {
                stateRoundTrip = (payload["theme"] as? String) == "light" && payload["zoom"] != nil
            }
        }
        waitFor("v2 op 往返(getState)", timeout: 10) { stateRoundTrip }
        // 条件轮询替代纯睡:mermaid 异步渲染以 svg 挂载为准
        waitForValue("mermaid svg 异步渲染就绪", timeout: 10,
                     script: "document.querySelectorAll('[data-type=diagram] svg').length",
                     test: { ($0 as? Int ?? 0) >= 1 })

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

        // ── T3 打开文件即脏回归:注入文档后,静止窗内不得上报 dirty=true。
        //    基线由 setMarkdown 同步落定,防抖回调只做比对(红→绿守门:
        //    修复前 pendingBaseline/suppressChange 双机制清零时机不同,漏掉即误报)。
        var t3 = false
        waitForCollect("T3 打开文件即脏回归", timeout: 15) { done in
            self.settleBridge(quiet: 1.2, timeout: 8) // 排空注入前旧事务尾窗
            self.changedTrueCount = 0
            self.changedTotalCount = 0
            self.evaluate("window.mdbridge.setMarkdown(\(JSArgs.string(SelftestRunner.sampleMarkdown)))") { _ in
                self.settleBridge(quiet: 1.2, timeout: 8) // 注入的全部上报到齐
                t3 = self.changedTrueCount == 0
                done()
            }
        }
        if t3 { pass("T3 打开文件即脏回归(注入后零误报)") } else { fail("T3 打开文件即脏回归(dirty=true 报了 \(changedTrueCount) 次)") }

        // ── 桥命令行为抽检:命令经 formatCommand 真实可运行(基线时 wrapInHeadingCommand
        //    未注册 + payload 形态不符,菜单动作静默失败——由双端校验与行为抽检共同守门)。
        //    先用 focusAt 把光标定位到首段,再按 spec 的位置参数形态调用。
        evaluate("(function(){var p=document.querySelector('.ProseMirror p');var r=p.getBoundingClientRect();return JSON.stringify(window.mdbridge.focusAt(r.left+5,r.top+5))})()") { _ in }
        evaluate("window.mdbridge.formatCommand('wrapInHeadingCommand', 2)") { r in
            if (r as? Bool) == true { self.pass("桥命令行为:标题2动作可运行") } else { self.fail("桥命令行为:标题2动作 → \(String(describing: r))") }
        }
        evaluate("window.mdbridge.formatCommand('turnIntoTextCommand')") { r in
            if (r as? Bool) == true { self.pass("桥命令行为:正文动作可运行") } else { self.fail("桥命令行为:正文动作 → \(String(describing: r))") }
        }
        evaluate("window.mdbridge.formatCommand('wrapInHeadingCommand', 1)") { r in
            if (r as? Bool) == true { self.pass("桥命令行为:标题1动作可运行") } else { self.fail("桥命令行为:标题1动作 → \(String(describing: r))") }
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

        // ── D1 单一真相源:源码模式下"模拟保存"取回的内容必须与 textarea 一致
        //    (红→绿守门:修复前 getMarkdown 只读编辑器 doc,追加行取不到)
        var d1a = false
        waitForCollect("D1 源码模式保存取一致内容", timeout: 10) { done in
            self.evaluate("window.mdbridge.toggleSource(true)") { _ in
                self.evaluate(#"(function(){var t=document.getElementById('source-editor');t.value=t.value+"\nsave-consistency-marker";var md=window.mdbridge.getMarkdown();return JSON.stringify({eq:md===t.value,has:md.indexOf("save-consistency-marker")>=0});})()"#) { r in
                    if let json = r as? String,
                       let data = json.data(using: .utf8),
                       let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        d1a = (d["eq"] as? Bool) == true && (d["has"] as? Bool) == true
                    }
                    done()
                }
            }
        }
        if d1a { pass("D1 源码模式保存取一致内容") } else { fail("D1 源码模式保存取一致内容") }

        // ── D1 markClean 基线 = 所见:清理后退出源码模式不得误报脏;随后的真实编辑必须恰上报一次 dirty=true。
        //    listener 回调经 200ms debounce 异步到达,先用"桥消息静止"等旧事务尾窗排空,再分段观测。
        var d1b = false
        waitForCollect("D1 markClean 基线等于所见", timeout: 20) { done in
            self.settleBridge(quiet: 1.2, timeout: 8) // 排空 markClean 之前旧事务的延迟回调
            self.changedTrueCount = 0
            self.changedTotalCount = 0
            self.evaluate("window.mdbridge.markClean()") { _ in
                self.evaluate("window.mdbridge.toggleSource(false)") { _ in
                    self.settleBridge(quiet: 1.2, timeout: 8) // 观测窗:退出源码模式的全部上报到齐
                    let misreport = self.changedTrueCount
                    self.changedTrueCount = 0
                    self.changedTotalCount = 0
                    self.evaluate("window.mdbridge.insertMarkdown('清理后编辑')") { _ in
                        self.evaluate("window.mdbridge.getMarkdown()") { md in
                            let deadline = Date().addingTimeInterval(5)
                            while Date() < deadline && self.changedTotalCount == 0 { self.pumpRunLoop(for: 0.05) }
                            if let s = md as? String,
                               s.contains("save-consistency-marker"), s.contains("清理后编辑"),
                               misreport == 0,
                               self.changedTotalCount == 1, self.changedTrueCount == 1 {
                                d1b = true
                            }
                            done()
                        }
                    }
                }
            }
        }
        if d1b { pass("D1 markClean 基线等于所见") } else { fail("D1 markClean 基线等于所见(误报=\(changedTrueCount)/总=\(changedTotalCount))") }

        // ── D2 导出 HTML 标题接文件名:init/setTitle 传入的值必须出现在 <title>
        //    (exportStandaloneHTML 为 async,页面内 await 后由原生轮询取回)
        var d2 = false
        waitForCollect("D2 导出 HTML 标题", timeout: 10) { done in
            self.evaluate("window.mdbridge.setTitle('SelftestDoc.md')") { _ in
                self.evaluate("void window.mdbridge.exportStandaloneHTML().then(function(html){window.__exportedHTML=html})") { _ in
                    let deadline = Date().addingTimeInterval(5)
                    while Date() < deadline {
                        var html: String?
                        var done2 = false
                        self.webview.evaluateJavaScript("window.__exportedHTML || ''") { result, _ in
                            html = result as? String
                            done2 = true
                        }
                        while !done2 { self.pumpRunLoop(for: 0.05) }
                        if let h = html, h.contains("<title>SelftestDoc.md</title>") {
                            d2 = true
                            break
                        }
                        self.pumpRunLoop(for: 0.1)
                    }
                    done()
                }
            }
        }
        if d2 { pass("D2 导出 HTML 标题") } else { fail("D2 导出 HTML 标题") }

        // ── 主题切换 + 代码高亮 token 调色板契约
        //    调色板唯一真源是 typora.css;按语义组核对实测计算值(色值/背景/阴影),
        //    守住两条规则:深色不得回落成浅色值(未覆盖即回落)、token 不得有背景
        //    (第三方浅色主题带 50% 白底,即 2026-10-24 深色白块缺陷)。
        evaluate("window.mdbridge.setTheme('dark')") { _ in }
        var themeOK = false
        evaluate("document.documentElement.dataset.theme") { r in
            themeOK = (r as? String) == "dark"
        }
        if themeOK { pass("深色主题切换") } else { fail("深色主题切换") }
        checkTokenPalette("深色", colors: SelftestRunner.darkTokenColors)
        evaluate("window.mdbridge.setTheme('light')") { _ in }
        checkTokenPalette("浅色", colors: SelftestRunner.lightTokenColors)

        // ── 代码文档视图(REQ-0009 / SCN-0016):只读高亮面,与 #app 互斥
        //    自动语言 → 切换语言 → 纯文本 → 未知语法回落 → 查找 → 大文件降级 → 退出。
        //    断言按「DOM 形态 + token 数 + 文本原样」三重口径,不依赖具体语法树。
        let codeSample = "func greet(name: String) -> String {\n    let value = 1\n    return \"hi \\(name) \\(value)\"\n}\n"
        // 行号样本:含空行、长行(软换行)、末尾换行(最后空行);行数按 split 口径。
        let longCodeLine = "    let message = \"" + String(repeating: "x", count: 240) + "\""
        // 多行块注释用来守门「跨行 token 按行克隆」；空行/末尾空行用来守门复制保真。
        let lineNumberSample = "import Foundation\n/*\n line one\n line two\n*/\n\nfunc greet(name: String) -> String {\n" + longCodeLine + "\n    return message\n}\n"
        let lineNumberCount = lineNumberSample.split(separator: "\n", omittingEmptySubsequences: false).count

        /// 代码视图 DOM 快照(文本原样性、token 数、显隐关系、桥状态一次取回)
        func codeSnapshot(_ done: @escaping ([String: Any]) -> Void) {
            self.evaluate("""
            JSON.stringify((function(){
                var cv = document.getElementById('code-view');
                var code = cv.querySelector('code');
                var contents = code.querySelectorAll('.code-line-content');
                var numbers = code.querySelectorAll('.code-line-number');
                var sel = window.getSelection();
                return {
                    mode: document.body.classList.contains('code-mode'),
                    appVisible: getComputedStyle(document.getElementById('app')).display !== 'none',
                    tokens: cv.querySelectorAll('.token').length,
                    lang: code.className,
                    // 行结构:逐行文本以 \\n 拼接 = 原文(行号/生成内容不入 textContent)
                    text: Array.prototype.map.call(contents, function(x){return x.textContent}).join('\\n'),
                    lineCount: code.querySelectorAll('.code-line').length,
                    lineNumbersVisible: !cv.classList.contains('no-line-numbers'),
                    gutterDisplay: numbers.length ? getComputedStyle(numbers[0]).display : 'none',
                    firstNumber: numbers.length ? getComputedStyle(numbers[0], '::before').content : '',
                    whiteSpace: contents.length ? getComputedStyle(contents[0]).whiteSpace : '',
                    scrollOverflow: cv.scrollWidth - cv.clientWidth,
                    selected: sel ? sel.toString() : '',
                    info: window.mdbridge.codeInfo()
                };
            })())
            """) { r in
                guard let json = r as? String, let data = json.data(using: .utf8),
                      let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    done([:])
                    return
                }
                done(d)
            }
        }

        var codeOpened = false
        waitForCollect("代码视图 自动语言与高亮", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode(\(JSArgs.string(codeSample)), {\"language\":\"swift\",\"allowHighlight\":true})") { _ in
                codeSnapshot { d in
                    codeOpened = (d["mode"] as? Bool) == true
                        && (d["appVisible"] as? Bool) == false
                        && (d["tokens"] as? Int ?? 0) >= 3
                        && (d["lang"] as? String ?? "").contains("language-swift")
                        && (d["text"] as? String) == codeSample
                    done()
                }
            }
        }
        if codeOpened { pass("代码视图 自动语言与高亮") } else { fail("代码视图 自动语言与高亮") }

        var codeSwitched = false
        waitForCollect("代码视图 切换语言与纯文本", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCodeLanguage('python')") { _ in
                codeSnapshot { d1 in
                    let python = (d1["tokens"] as? Int ?? 0) >= 3
                        && (d1["lang"] as? String ?? "").contains("language-python")
                        && (d1["text"] as? String) == codeSample
                    self.evaluate("window.mdbridge.setCodeLanguage('plaintext')") { _ in
                        codeSnapshot { d2 in
                            let plain = (d2["tokens"] as? Int ?? 0) == 0
                                && (d2["text"] as? String) == codeSample
                                && (d2["mode"] as? Bool) == true
                            codeSwitched = python && plain
                            done()
                        }
                    }
                }
            }
        }
        if codeSwitched { pass("代码视图 切换语言与纯文本") } else { fail("代码视图 切换语言与纯文本") }

        var codeUnknownGrammar = false
        waitForCollect("代码视图 未知语法回落纯文本", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCodeLanguage('no-such-grammar')") { _ in
                codeSnapshot { d in
                    codeUnknownGrammar = (d["tokens"] as? Int ?? -1) == 0
                        && (d["text"] as? String) == codeSample
                        && (d["mode"] as? Bool) == true
                    done()
                }
            }
        }
        if codeUnknownGrammar { pass("代码视图 未知语法回落纯文本") } else { fail("代码视图 未知语法回落纯文本") }

        var codeFind = false
        waitForCollect("代码视图 查找命中与只读退出", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCodeLanguage('swift')") { _ in
                self.evaluate("window.mdbridge.openFindBar()") { _ in
                    self.evaluate("(function(){var i=document.getElementById('find-input');i.value='value';i.dispatchEvent(new Event('input'));return document.getElementById('find-count').textContent;})()") { r1 in
                        let first = (r1 as? String) == "1/2"
                        self.evaluate("window.mdbridge.findNext()") { _ in
                            let second = (self.findCountText() == "2/2")
                            self.evaluate("(function(){var s=window.getSelection();return s.rangeCount>0&&document.getElementById('code-view').contains(s.anchorNode);})()") { sel in
                                let inCode = (sel as? Bool) == true
                                self.evaluate("window.mdbridge.findNext()") { _ in
                                    let wrapped = (self.findCountText() == "1/2")
                                    self.evaluate("window.mdbridge.closeFindBar()") { _ in
                                        codeFind = first && second && inCode && wrapped
                                        done()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if codeFind { pass("代码视图 查找命中与只读退出") } else { fail("代码视图 查找命中与只读退出") }

        var codeLarge = false
        waitForCollect("代码视图 大文件降级纯文本", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode(\(JSArgs.string(codeSample)), {\"language\":\"python\",\"allowHighlight\":false})") { _ in
                codeSnapshot { d1 in
                    let plain = (d1["tokens"] as? Int ?? -1) == 0 && (d1["text"] as? String) == codeSample
                    self.evaluate("window.mdbridge.setCodeLanguage('swift')") { _ in
                        codeSnapshot { d2 in
                            let stillPlain = (d2["tokens"] as? Int ?? -1) == 0
                                && ((d2["info"] as? [String: Any])?["allowHighlight"] as? Bool) == false
                            codeLarge = plain && stillPlain
                            done()
                        }
                    }
                }
            }
        }
        if codeLarge { pass("代码视图 大文件降级纯文本") } else { fail("代码视图 大文件降级纯文本") }

        var codeParity = false
        waitForCollect("代码视图 双端语言清单一致", timeout: 10) { done in
            let ids = FileSupport.codeLanguages.map(\.id)
            let idsJSON = (try? JSONSerialization.data(withJSONObject: ids))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            self.evaluate("JSON.stringify(window.mdbridge.hasLanguages(\(idsJSON)))") { r in
                if let s = r as? String, let data = s.data(using: .utf8),
                   let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] {
                    codeParity = list.sorted() == ids.sorted()
                }
                done()
            }
        }
        if codeParity { pass("代码视图 双端语言清单一致(\(FileSupport.codeLanguages.count) 种)") } else { fail("代码视图 双端语言清单一致") }

        // ── 行号/软换行/当前行/开关(REQ-0010)
        var codeLineNumbers = false
        waitForCollect("代码视图 行号与软换行", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode(\(JSArgs.string(lineNumberSample)), {\"language\":\"swift\",\"allowHighlight\":true,\"lineNumbers\":true})") { _ in
                codeSnapshot { d in
                    let info = d["info"] as? [String: Any]
                    codeLineNumbers = (d["lineCount"] as? Int) == lineNumberCount
                        && (d["text"] as? String) == lineNumberSample
                        && (d["firstNumber"] as? String ?? "").contains("1")
                        && (d["gutterDisplay"] as? String) == "block"
                        && (d["whiteSpace"] as? String) == "pre-wrap"
                        && (d["scrollOverflow"] as? Int ?? 999) <= 1
                        && (d["lineNumbersVisible"] as? Bool) == true
                        && (info?["lineNumbers"] as? Bool) == true
                    done()
                }
            }
        }
        if codeLineNumbers { pass("代码视图 行号与软换行") } else { fail("代码视图 行号与软换行") }

        var codeCurrentLine = false
        waitForCollect("代码视图 当前行点击与查找定位", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode(\(JSArgs.string(codeSample)), {\"language\":\"swift\",\"allowHighlight\":true,\"lineNumbers\":true})") { _ in
                self.evaluate("""
                (function(){
                    var line = document.querySelectorAll('#code-view .code-line')[0];
                    line.dispatchEvent(new MouseEvent('click', {bubbles: true}));
                    var clicked = line.classList.contains('is-current');
                    line.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowDown', bubbles: true}));
                    var arrow = window.mdbridge.codeInfo().currentLine === 1;
                    window.mdbridge.openFindBar();
                    var input = document.getElementById('find-input');
                    input.value = 'return';
                    input.dispatchEvent(new Event('input'));
                    var cur = document.querySelector('#code-view .code-line.is-current');
                    return JSON.stringify({
                        clicked: clicked,
                        arrow: arrow,
                        current: window.mdbridge.codeInfo().currentLine,
                        text: cur ? cur.querySelector('.code-line-content').textContent : '',
                        selected: window.getSelection().toString()
                    });
                })()
                """) { r in
                    var clicked = false
                    if let s = r as? String, let data = s.data(using: .utf8),
                       let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        clicked = (d["clicked"] as? Bool) == true
                            && (d["arrow"] as? Bool) == true
                            && (d["current"] as? Int) == 2
                            && ((d["text"] as? String) ?? "").contains("return")
                            && ((d["selected"] as? String) ?? "").contains("return")
                    }
                    self.evaluate("window.mdbridge.closeFindBar(); window.mdbridge.codeInfo().currentLine") { r2 in
                        codeCurrentLine = clicked && (r2 as? NSNumber)?.intValue == 2
                        done()
                    }
                }
            }
        }
        if codeCurrentLine { pass("代码视图 当前行点击与查找定位") } else { fail("代码视图 当前行点击与查找定位") }

        var codeToggleCopy = false
        waitForCollect("代码视图 行号开关与复制文本", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode(\(JSArgs.string(lineNumberSample)), {\"language\":\"swift\",\"allowHighlight\":true,\"lineNumbers\":true})") { _ in
                self.evaluate("window.mdbridge.setCodeLineNumbers(false)") { rOff in
                    codeSnapshot { dOff in
                        let info = dOff["info"] as? [String: Any]
                        let off = (rOff as? Bool) == true
                            && (dOff["lineNumbersVisible"] as? Bool) == false
                            && (dOff["gutterDisplay"] as? String) == "none"
                            && (info?["lineNumbers"] as? Bool) == false
                        self.evaluate("""
                        (function(){
                            var code = document.querySelector('#code-view code');
                            var blank = document.querySelectorAll('#code-view .code-line')[1];
                            var range = document.createRange();
                            range.selectNodeContents(code);
                            var sel = window.getSelection();
                            sel.removeAllRanges();
                            sel.addRange(range);
                            return JSON.stringify({
                                sel: sel.toString(),
                                blankHeight: blank ? blank.getBoundingClientRect().height : 0
                            });
                        })()
                        """) { sel in
                            var selected = false
                            if let s = sel as? String, let data = s.data(using: .utf8),
                               let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                                selected = (d["sel"] as? String) == lineNumberSample
                                    && (d["blankHeight"] as? Double ?? 0) > 0
                            }
                            self.evaluate("window.mdbridge.setCodeLineNumbers(true)") { rOn in
                                codeSnapshot { dOn in
                                    let on = (rOn as? Bool) == true
                                        && (dOn["lineNumbersVisible"] as? Bool) == true
                                        && (dOn["gutterDisplay"] as? String) == "block"
                                    codeToggleCopy = off && selected && on
                                    done()
                                }
                            }
                        }
                    }
                }
            }
        }
        if codeToggleCopy { pass("代码视图 行号开关与复制文本") } else { fail("代码视图 行号开关与复制文本") }

        var codeEmpty = false
        waitForCollect("代码视图 空文件行号边界", timeout: 10) { done in
            self.evaluate("window.mdbridge.setCode('', {\"language\":\"plaintext\",\"allowHighlight\":false,\"lineNumbers\":true})") { _ in
                codeSnapshot { d in
                    let info = d["info"] as? [String: Any]
                    let empty = (d["lineCount"] as? Int) == 0
                        && (d["text"] as? String) == ""
                        && (d["mode"] as? Bool) == true
                        && (info?["lineCount"] as? Int) == 0
                    self.evaluate("""
                    (function(){
                        var off = window.mdbridge.setCodeLineNumbers(false);
                        var hidden = window.mdbridge.codeInfo().lineNumbers === false;
                        var on = window.mdbridge.setCodeLineNumbers(true);
                        return off && hidden && on;
                    })()
                    """) { r in
                        codeEmpty = empty && (r as? Bool) == true
                        done()
                    }
                }
            }
        }
        if codeEmpty { pass("代码视图 空文件行号边界") } else { fail("代码视图 空文件行号边界") }

        var codeExited = false
        waitForCollect("代码视图 退出代码模式", timeout: 10) { done in
            self.evaluate("window.mdbridge.setMarkdown(\(JSArgs.string(SelftestRunner.sampleMarkdown)))") { _ in
                self.settleBridge(quiet: 0.8, timeout: 5)
                self.evaluate("window.mdbridge.setCodeLineNumbers(false)") { off in
                    codeSnapshot { d in
                        codeExited = (d["mode"] as? Bool) == false
                            && (d["appVisible"] as? Bool) == true
                            && (off as? Bool) == false
                        done()
                    }
                }
            }
        }
        if codeExited { pass("代码视图 退出代码模式") } else { fail("代码视图 退出代码模式") }

        // ── 命令桥
        evaluate("window.mdbridge.insertTable(2,2)") { r in
            if (r as? Bool) == true { self.pass("命令桥 insertTableCommand") } else { self.fail("命令桥 insertTableCommand → \(String(describing: r))") }
        }
        // 条件轮询替代纯睡:insertTable 命令生效以 DOM 表格数为准
        waitForValue("插入表格生效", timeout: 10,
                     script: "document.querySelectorAll('table').length",
                     test: { ($0 as? Int ?? 0) >= 2 })
        evaluate("document.querySelectorAll('table').length") { r in
            if (r as? Int ?? 0) >= 2 { print("SELFTEST table count:", r ?? 0) } else { self.fail("插入表格生效(DOM 复核)") }
        }

        // ── 表格行列操作(断言光标所在表格的 doc 几何)
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
        let actionSet = Set(EditorAction.allCases)
        var registryOK = true
        for spec in EditorCommands.all {
            // responderChain 型命令由响应链处理(WKWebView 实现系统编辑动作),其余由控制器实现
            let ok = spec.responderChain
                ? EditorWebView.instancesRespond(to: spec.selector)
                : DocumentWindowController.instancesRespond(to: spec.selector)
            if !ok { registryOK = false }
        }
        // 结构完整性:规格数与 EditorAction case 数一致(不重不漏),不锚定具体数字
        let specActions = EditorCommands.all.map { $0.action }
        let noDup = Set(specActions).count == specActions.count
        let noMiss = actionSet == Set(specActions)
        if noDup && noMiss && registryOK {
            pass("命令注册表完整(\(EditorCommands.all.count) 条)")
        } else {
            fail("命令注册表完整(\(EditorCommands.all.count) 条,缺失/重复/响应缺失)")
        }

        // ── 桥命令名双端一致性:Swift 注册表携带的 JS 命令名必须存在于 web 注册表且可运行
        do {
            let names = EditorCommands.all.compactMap { $0.jsCommand }
            let arr = names.map { "'\($0)'" }.joined(separator: ",")
            evaluate("JSON.stringify(window.mdbridge.hasCommands([\(arr)]))") { r in
                guard let json = r as? String,
                      let data = json.data(using: .utf8),
                      let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      list.count == names.count,
                      list.allSatisfy({ ($0["ok"] as? Bool) == true }) else {
                    self.fail("桥命令名双端一致 → \(String(describing: r))")
                    return
                }
                self.pass("桥命令名双端一致(\(names.count) 条)")
            }
        }

        // ── Info.plist 扩展名清单与 Swift 唯一来源一致(FileSupport.markdownExtensions)
        assertInfoPlistExtensions()
        assertFileSupport()

        // ── 缩放
        evaluate("window.mdbridge.setZoom(1.25)") { _ in }
        evaluate("getComputedStyle(document.getElementById('app')).zoom") { r in
            let v = (r as? String) ?? "\(r ?? "")"
            if v.contains("1.25") { self.pass("缩放应用") } else { self.fail("缩放应用 → \(v)") }
        }
        evaluate("window.mdbridge.setZoom(1.0)") { _ in }

        // ── 宽度策略:正文 100% 跟随窗体,收缩下限由 CSS 变量 --editor-max-width 声明(不再锚定具体数字)
        evaluate("(function(){var r=document.documentElement;return JSON.stringify({appW:document.getElementById('app').getBoundingClientRect().width,vw:r.clientWidth,minW:parseFloat(getComputedStyle(document.getElementById('app')).minWidth),declared:parseFloat(getComputedStyle(r).getPropertyValue('--editor-max-width'))})})()") { r in
            guard let json = r as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appW = dict["appW"] as? Double,
                  let vw = dict["vw"] as? Double,
                  let minW = dict["minW"] as? Double,
                  let declared = dict["declared"] as? Double else {
                self.fail("宽度策略读取 → \(String(describing: r))")
                return
            }
            let fillsWindow = appW >= vw - 1.5
            // zoom 复位为 1 后,#app 的实际 min-width 应等于变量声明值
            let floorOk = declared > 0 && abs(minW - declared) < 1.5
            if fillsWindow && floorOk { self.pass("宽度策略(100%+CSS变量下限)") } else { self.fail("宽度策略 → appW=\(appW) vw=\(vw) minW=\(minW) declared=\(declared)") }
        }

        // ── 文档内查找
        evaluate("window.mdbridge.openFindBar()") { _ in }
        evaluate("(function(){var i=document.getElementById('find-input');i.value='公式';i.dispatchEvent(new Event('input'));return true})()") { _ in }
        // 条件轮询替代纯睡:查找计数以 find-count 文本出现为准
        waitForValue("查找计数就绪", timeout: 10,
                     script: "document.getElementById('find-count').textContent || ''",
                     test: { ($0 as? String ?? "").contains("/") })
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

        // ── PDF 导出能力(几何就绪信号驱动,替代固定延时;W5-T2)
        var pdfOK = false
        var smallPdfBytes = 0
        var smallHeight: Double = 0
        waitForCollect("PDF 导出", timeout: 25) { done in
            self.waitForScrollHeightSettled { settledH in
                guard let h = settledH, h > 100 else { done(); return }
                smallHeight = h
                self.webview.translatesAutoresizingMaskIntoConstraints = true
                self.webview.frame = NSRect(x: 0, y: 0, width: 1000, height: CGFloat(h))
                // 收敛后让一拍合成器完成 raster,下一次 RunLoop tick 截取
                DispatchQueue.main.async {
                    let config = WKPDFConfiguration()
                    config.rect = self.webview.bounds
                    self.webview.createPDF(configuration: config) { result in
                        switch result {
                        case .success(let data):
                            smallPdfBytes = data.count
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

        // ── 大文档 PDF 完整性:注入 30 份样例,几何收敛后截取,内容高度与字节数都须成规模。
        //    守门:修复前固定 0.35s 延时在慢渲染(mermaid 多图)下会截缺内容。
        var bigOK = false
        waitForCollect("大文档 PDF 完整性", timeout: 60) { done in
            let big = Array(repeating: SelftestRunner.sampleMarkdown, count: 30).joined()
            self.evaluate("window.mdbridge.setMarkdown(\(JSArgs.string(big)))") { _ in
                self.waitForScrollHeightSettled { settledH in
                    guard let h = settledH, h > smallHeight * 4 else { done(); return }
                    self.webview.frame = NSRect(x: 0, y: 0, width: 1000, height: CGFloat(h))
                    DispatchQueue.main.async {
                        let config = WKPDFConfiguration()
                        config.rect = self.webview.bounds
                        self.webview.createPDF(configuration: config) { result in
                            if case .success(let data) = result {
                                print("SELFTEST big pdf bytes:", data.count, "height:", Int(h))
                                bigOK = data.count > smallPdfBytes
                            } else if case .failure(let error) = result {
                                print("SELFTEST big pdf error:", error.localizedDescription)
                            }
                            // 恢复标准样例,后续检查不受影响
                            self.evaluate("window.mdbridge.setMarkdown(\(JSArgs.string(SelftestRunner.sampleMarkdown)))") { _ in
                                self.webview.translatesAutoresizingMaskIntoConstraints = false
                                self.window?.contentView?.layoutSubtreeIfNeeded()
                                done()
                            }
                        }
                    }
                }
            }
        }
        if bigOK { pass("大文档 PDF 完整性") } else { fail("大文档 PDF 完整性") }

        // ── 图片落盘导入与资源 GC（路径改写已入内核，见 web 侧黄金对拍与装载改写自检）
        testImageStore()
        testImageCleanup()

        // ── 文件抽屉目录扫描(过滤/剪枝/防环/防深)
        testDirectoryTree()

        // ── 图片节点渲染/编辑框/插入桥(点击编辑与 Esc 还原的 web 行为往返)
        testImageNodeView()

        // ── 图片编辑框窄窗口几何(关键视口:编辑列收缩下限生效时不破布局)
        testImageEditBoxNarrowWindow()

        // ── 列表序列化:Tab 嵌套每级 4 空格(标准 Tab 等价缩进),首行标记紧凑。
        //    红→绿守门:修复前 listItemIndent:'one' 每级只缩 2 空格。
        testListIndent()

        // ── 装载改写/保存口径端到端：内核改写 + 壳作答 + 内核还原（R9 的运行时证据）
        testKernelRewrite()

        // ── OQ-1/pluginSet 配置可达性:_init 必须先解析 opts 再建编辑器,
        //    no-diagram 轻量模式真正生效(mermaid 围栏保持代码块、math 仍加载)。
        //    修复前 opts 在创建之后才赋值,条件分支不可达,这里恒红。
        runPluginSetCheck()

        print("SELFTEST \(failed ? "FAILED" : "PASSED")")
        exit(failed ? 1 : 0)
    }

    /// 轮询一个 JS 取值直到满足判据(条件等待,非纯睡):每拍发起 evaluate 并在本拍
    /// 内排空其完成回调,判据不满足则下一拍。Q1 纯睡反模式的替换件。
    private func waitForValue(_ name: String, timeout: TimeInterval, script: String, test: @escaping (Any?) -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var result: Any?
            var completed = false
            webview.evaluateJavaScript(script) { r, _ in
                result = r
                completed = true
            }
            while !completed && Date() < deadline { pumpRunLoop(for: 0.05) }
            if completed && test(result) { pass(name); return }
            pumpRunLoop(for: 0.05)
        }
        fail(name)
    }

    /// 与生产同口径的几何就绪信号:连续两次测得相同 scrollHeight 视为布局收敛。
    /// 返回收敛时的内容高度;超限未收敛返回 nil(W5-T2 就绪信号替代固定延时)。
    private func waitForScrollHeightSettled(
        attempts: Int = Polling.geometryMaxAttempts, last: Double? = nil,
        _ completion: @escaping (Double?) -> Void
    ) {
        guard attempts > 0 else { completion(nil); return }
        evaluate("Math.max(document.documentElement.scrollHeight)") { r in
            let current = (r as? NSNumber)?.doubleValue ?? 0
            if let last, abs(current - last) < 0.5 {
                completion(current)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Polling.geometryInterval) {
                self.waitForScrollHeightSettled(attempts: attempts - 1, last: current, completion)
            }
        }
    }

    /// 装载改写与保存口径的端到端：相对引用→file://（内核经 resolveResources 问壳），
    /// 保存时再还原成相对路径。这是 R9「语义单点在 web」在真实壳里的运行时证据。
    private func testKernelRewrite() {
        var loadOK = false
        var saveOK = false
        waitForCollect("装载改写(内核改写+壳作答)", timeout: 20) { done in
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mdp-v2-rewrite-\(UInt32.random(in: 0..<UInt32.max))", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent("img"), withIntermediateDirectories: true)
            // 只要文件存在即可（NodeView 是否解码成功不影响 src 断言）
            try? Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: dir.appendingPathComponent("img/k.png"))
            self.kernel.send("setMarkdown", ["md": "![k](img/k.png)", "baseDir": dir.path]) { result in
                let ok = (try? result.get())?["ok"] as? Bool ?? false
                self.evaluate("(function(){var i=document.querySelector('.md-image img');return i?i.getAttribute('src'):''})()") { r in
                    let src = r as? String ?? ""
                    loadOK = ok && src.hasPrefix("file://") && src.hasSuffix("img/k.png")
                    self.kernel.send("getSaveMarkdown") { saved in
                        let md = (try? saved.get())?["md"] as? String ?? ""
                        saveOK = md.contains("![k](img/k.png)") && !md.contains("file://")
                        // 恢复标准样例，后续检查不受影响
                        self.kernel.send("setMarkdown", ["md": SelftestRunner.sampleMarkdown, "baseDir": "/tmp"]) { _ in
                            done()
                        }
                    }
                }
            }
        }
        if loadOK { pass("装载改写(内核改写+壳作答)") } else { fail("装载改写(内核改写+壳作答)") }
        if saveOK { pass("保存口径(内核还原相对路径)") } else { fail("保存口径(内核还原相对路径)") }
    }

    /// v2 通知统一入口（boot/ready/changed/jserror 与旧桥同名同形状）
    private func handleNotification(op: String, payload: [String: Any]) {
        if op == "boot" { bootReceived = true }
        if op == "ready" { readyReceived = true }
        if op == "changed" {
            changedTotalCount += 1
            if (payload["dirty"] as? Bool) ?? true { changedTrueCount += 1 }
        }
        if op == "jserror" {
            let msg = payload["message"] as? String ?? "?"
            let stack = payload["stack"] as? String ?? ""
            print("WEB-JS-ERROR: \(msg)\n\(stack.prefix(1200))")
        }
    }

    /// 内核发起的请求：自检场景的文档在 /tmp，资源问答按缺省作答（引用保持原文）
    private func handleKernelRequest(
        op: String,
        payload: [String: Any],
        reply: @escaping (Result<[String: Any], KernelClient.KernelError>) -> Void
    ) {
        switch op {
        case "resolveResources":
            let refs = payload["refs"] as? [String] ?? []
            let basePath = payload["baseDir"] as? String
            var resources: [String: Any] = [:]
            for ref in refs {
                var paths: [String] = []
                var url: Any = NSNull()
                if let basePath {
                    let literal = URL(fileURLWithPath: basePath, isDirectory: true)
                        .appendingPathComponent(ref).standardizedFileURL
                    let decodedRef = ref.split(separator: "/", omittingEmptySubsequences: false)
                        .map { $0.removingPercentEncoding ?? String($0) }
                        .joined(separator: "/")
                    let decoded = URL(fileURLWithPath: basePath, isDirectory: true)
                        .appendingPathComponent(decodedRef).standardizedFileURL
                    if FileManager.default.fileExists(atPath: literal.path) {
                        paths.append(literal.path)
                        url = literal.absoluteString
                    }
                    if decoded.path != literal.path, FileManager.default.fileExists(atPath: decoded.path) {
                        paths.append(decoded.path)
                    }
                }
                resources[ref] = [
                    "url": url,
                    "exists": !paths.isEmpty,
                    "isImage": true,
                    "paths": paths,
                ]
            }
            reply(.success(["resources": resources]))
        case "importImage":
            reply(.success(["ok": false]))
        default:
            reply(.failure(KernelClient.KernelError(code: "unknown_op", message: "自检未实现 \(op)")))
        }
    }

    /// 第二个页面实例验证 plugins 配置真实生效(OQ-1 选 a:保留轻量模式能力)
    private func runPluginSetCheck() {
        guard let pageURL = WebLocator.indexURL() else {
            fail("OQ-1 轻量模式检查(找不到页面资源)")
            return
        }
        let lightWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let lightWebview = EditorWebView(configuration: EditorWebView.makeConfiguration(testFacade: true))
        lightWebview.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        lightWebview.autoresizingMask = [.width, .height]
        lightWindow.contentView?.addSubview(lightWebview)
        lightWindow.orderFrontRegardless()
        lightKernel.attach(to: lightWebview)
        lightWebview.onKernelMessage = { [weak self] body in
            self?.lightKernel.receive(body) ?? false
        }
        lightKernel.onNotification = { [weak self] op, _ in
            guard let self else { return }
            if op == "boot" { self.lightBootReceived = true }
            if op == "ready" { self.lightReadyReceived = true }
        }
        lightKernel.onRequest = { [weak self] op, payload, reply in
            self?.handleKernelRequest(op: op, payload: payload, reply: reply)
        }
        lightWebview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        waitFor("OQ-1 轻量页脚本加载", timeout: 30) { self.lightBootReceived }
        let lightMD = "# 轻量\n\n```mermaid\ngraph LR\n  A --> B\n```\n\n$E = mc^2$\n"
        let lightOpts: [String: Any] = [
            "protocolVersion": KernelClient.protocolVersion,
            "theme": "light", "zoom": 1, "plugins": "no-diagram",
        ]
        lightKernel.send("init", ["markdown": lightMD, "opts": lightOpts]) { _ in }
        waitFor("OQ-1 轻量初始化(ready)", timeout: 30) { self.lightReadyReceived }

        var diagramOff = false
        var mathOn = false
        evaluate(#"(function(){return JSON.stringify({dg:!!document.querySelector('[data-type=diagram]'),k:document.querySelectorAll('.katex').length})})()"#, on: lightWebview) { r in
            if let json = r as? String,
               let data = json.data(using: .utf8),
               let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                diagramOff = (d["dg"] as? Bool) == false
                mathOn = (d["k"] as? Int ?? 0) >= 1
            }
        }
        if diagramOff && mathOn {
            pass("OQ-1 pluginSet 轻量模式生效")
        } else {
            fail("OQ-1 pluginSet 轻量模式生效(关闭图表=\(diagramOff),公式=\(mathOn))")
        }
        lightWindow.close()
    }

    /// Info.plist 的 CFBundleTypeExtensions 必须与 FileSupport.markdownExtensions 一致
    private func assertInfoPlistExtensions() {
        guard let plistURL = WebLocator.repoInfoPlistURL(),
              let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]],
              let exts = docTypes.first?["CFBundleTypeExtensions"] as? [String] else {
            fail("Info.plist 扩展名一致(解析失败:仅开发模式可断言)")
            return
        }
        if exts.sorted() == FileSupport.markdownExtensions.sorted() {
            pass("Info.plist 扩展名一致(\(exts.count) 项)")
        } else {
            fail("Info.plist 扩展名一致 → plist=\(exts.sorted()) code=\(FileSupport.markdownExtensions.sorted())")
        }
    }

    /// FileSupport:语言表与扩展名判定的纯 Swift 断言(未知扩展名是 SCN-0016 的反例)
    private func assertFileSupport() {
        let cases: [(String, DocumentKind)] = [
            ("a.md", .markdown),
            ("a.MARKDOWN", .markdown),
            ("a.swift", .code(language: "swift")),
            ("a.PY", .code(language: "python")),
            ("a.tsx", .code(language: "tsx")),
            ("a.xml", .code(language: "xml")),
            ("a.plist", .code(language: "xml")),
            ("a.rs", .code(language: "rust")),
            ("app.dockerfile", .code(language: "docker")),
            ("a.mk", .code(language: "makefile")),
        ]
        var mismatches: [String] = []
        for (name, expected) in cases {
            let actual = FileSupport.kind(for: URL(fileURLWithPath: "/tmp/\(name)"))
            if actual != expected {
                mismatches.append("\(name)=\(String(describing: actual))")
            }
        }
        if mismatches.isEmpty {
            pass("代码视图 语言表覆盖扩展名(\(cases.count) 项)")
        } else {
            fail("代码视图 语言表覆盖扩展名 → \(mismatches)")
        }
        if FileSupport.kind(for: URL(fileURLWithPath: "/tmp/a.unknownext")) == nil {
            pass("代码视图 未知扩展名不装载")
        } else {
            fail("代码视图 未知扩展名不装载")
        }
        let allMarkdown = FileSupport.markdownExtensions.allSatisfy {
            FileSupport.kind(for: URL(fileURLWithPath: "/tmp/x.\($0)")) == .markdown
        }
        if allMarkdown, !FileSupport.markdownExtensions.isEmpty {
            pass("代码视图 Markdown 扩展名恒走 Markdown")
        } else {
            fail("代码视图 Markdown 扩展名恒走 Markdown")
        }
        let ids = FileSupport.codeLanguages.map(\.id)
        let idsUnique = Set(ids).count == ids.count
        let allHaveExtensions = FileSupport.codeLanguages.allSatisfy { !$0.extensions.isEmpty }
        if idsUnique, allHaveExtensions, !FileSupport.openableUTTypes.isEmpty {
            pass("代码视图 语言 id 唯一且类型可构造(\(FileSupport.openableUTTypes.count) 个 UTType)")
        } else {
            fail("代码视图 语言 id 唯一且类型可构造")
        }
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

    // MARK: - 代码高亮 token 调色板契约

    /// 组名 = typora.css 的调色板变量名,成员 = 该组选择器覆盖的 token 类。
    /// 分组语义与 CSS 一一对应:同组在浅/深两主题中共用一个变量。
    private static let tokenGroups: [String: [String]] = [
        "--tok-comment": ["comment", "prolog", "doctype", "cdata"],
        "--tok-punctuation": ["punctuation"],
        "--tok-property": ["property", "tag", "deleted"],
        "--tok-number": ["number", "boolean", "constant", "symbol"],
        "--tok-selector": ["selector"],
        "--tok-string": ["string", "char", "builtin", "inserted", "attr-name"],
        "--tok-operator": ["operator", "entity", "url"],
        "--tok-keyword": ["keyword", "atrule"],
        "--tok-attr-value": ["attr-value"],
        "--tok-function": ["function", "class-name"],
        "--tok-regex": ["regex"],
        "--tok-important": ["important"],
        "--tok-variable": ["variable"],
    ]

    /// 期望色值 = typora.css 两张变量表的展开(浅色取自 Prism 默认主题,
    /// 深色为 Nord 调色板)。改色必须同步这里,否则断言失败——这是有意为之。
    private static let lightTokenColors: [String: String] = [
        "--tok-comment": "rgb(112, 128, 144)",
        "--tok-punctuation": "rgb(153, 153, 153)",
        "--tok-property": "rgb(153, 0, 85)",
        "--tok-number": "rgb(153, 0, 85)",
        "--tok-selector": "rgb(102, 153, 0)",
        "--tok-string": "rgb(102, 153, 0)",
        "--tok-operator": "rgb(154, 110, 58)",
        "--tok-keyword": "rgb(0, 119, 170)",
        "--tok-attr-value": "rgb(0, 119, 170)",
        "--tok-function": "rgb(221, 74, 104)",
        "--tok-regex": "rgb(238, 153, 0)",
        "--tok-important": "rgb(238, 153, 0)",
        "--tok-variable": "rgb(238, 153, 0)",
    ]

    private static let darkTokenColors: [String: String] = [
        "--tok-comment": "rgb(127, 140, 152)",
        "--tok-punctuation": "rgb(192, 197, 206)",
        "--tok-property": "rgb(191, 97, 106)",
        "--tok-number": "rgb(208, 135, 112)",
        "--tok-selector": "rgb(180, 142, 173)",
        "--tok-string": "rgb(163, 190, 140)",
        "--tok-operator": "rgb(129, 161, 193)",
        "--tok-keyword": "rgb(180, 142, 173)",
        "--tok-attr-value": "rgb(163, 190, 140)",
        "--tok-function": "rgb(136, 192, 208)",
        "--tok-regex": "rgb(163, 190, 140)",
        "--tok-important": "rgb(180, 142, 173)",
        "--tok-variable": "rgb(208, 135, 112)",
    ]

    /// 合成 span 覆盖每个 token 类(不依赖具体语言的语法产出),同时回报
    /// 真实渲染样本里带背景/阴影的 token 数。
    private static let paletteProbeJS = """
    (function () {
        var classes = ['comment', 'prolog', 'doctype', 'cdata', 'punctuation', 'property',
            'tag', 'boolean', 'number', 'constant', 'symbol', 'deleted', 'selector',
            'attr-name', 'string', 'char', 'builtin', 'inserted', 'operator', 'entity',
            'url', 'atrule', 'attr-value', 'keyword', 'function', 'class-name', 'regex',
            'important', 'variable', 'bold', 'italic'];
        var host = document.createElement('div');
        host.style.cssText = 'position:absolute;left:-9999px;top:0';
        document.body.appendChild(host);
        var out = {};
        classes.forEach(function (c) {
            var s = document.createElement('span');
            s.className = 'token ' + c;
            s.textContent = 'x';
            host.appendChild(s);
            var cs = getComputedStyle(s);
            out[c] = { color: cs.color, bg: cs.backgroundColor, shadow: cs.textShadow };
        });
        host.remove();
        var tokens = Array.prototype.slice.call(document.querySelectorAll('.md-editor-view .token'));
        out.__rendered = {
            count: tokens.length,
            withBg: tokens.filter(function (e) {
                return getComputedStyle(e).backgroundColor !== 'rgba(0, 0, 0, 0)';
            }).length,
            shadowed: tokens.filter(function (e) {
                return getComputedStyle(e).textShadow !== 'none';
            }).length,
        };
        return JSON.stringify(out);
    })()
    """

    // MARK: - 路径改写测试

    /// 文件抽屉目录扫描用例(lazy 单层装载):md 过滤与扩展名清单、隐藏条目、
    /// 符号链接防环、node_modules/包整棵跳过、排序(文件夹在前)、lazy 装载态、
    /// 父链与已装载层定位、根不可读报错。
    private func testDirectoryTree() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/tmp/selftest-tree-\(getpid())")
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        func mkdir(_ rel: String) throws {
            try fm.createDirectory(at: root.appendingPathComponent(rel), withIntermediateDirectories: true)
        }
        func put(_ rel: String) {
            fm.createFile(atPath: root.appendingPathComponent(rel).path, contents: Data("# t\n".utf8))
        }
        do {
            try mkdir("sub")
            try mkdir("sub/deep")
            try mkdir("empty") // 无 md 目录:lazy 下照常显示(不做后代剪枝)
            try mkdir("web/node_modules/pkg") // 依赖目录 → 整棵跳过
            try mkdir("MyApp.app/Contents") // 包目录 → 整棵跳过(Finder 同款不透明语义)
            put("a.md")
            put("main.py") // 代码文件 → 进树(REQ-0009:抽屉也列出可读代码)
            put("b.txt") // 非 md/非代码 → 排除
            put(".hidden.md") // 隐藏 → 排除
            put("sub/c.md")
            put("sub/e.txt")
            put("sub/deep/d.markdown")
            put("web/keep.md")
            put("web/node_modules/pkg/README.md")
            put("MyApp.app/Contents/inside.md")
            try fm.createSymbolicLink(
                at: root.appendingPathComponent("loop"),
                withDestinationURL: root) // 符号链接 → 不跟随(防环)

            let rootLevel = try DirectoryTree.scanLevel(of: root)
            let subNode = rootLevel.children.first { $0.name == "sub" }
            if rootLevel.childrenLoaded,
               subNode?.childrenLoaded == false, subNode?.children.isEmpty == true {
                pass("目录扫描-lazy 根层装载,子目录未装载")
            } else {
                fail("目录扫描-lazy 装载态不符")
            }
            let rootNames = rootLevel.children.map(\.name)
            if rootNames == ["empty", "sub", "web", "a.md", "main.py"] {
                pass("目录扫描-单层过滤与排序(无md目录保留/包跳过/得 \(rootNames))")
            } else {
                fail("目录扫描-单层过滤与排序 → \(rootNames),期望 [empty, sub, web, a.md, main.py]")
            }
            let webLevel = try DirectoryTree.scanLevel(of: root.appendingPathComponent("web"))
            if webLevel.children.map(\.name) == ["keep.md"] {
                pass("目录扫描-node_modules 整棵跳过(内部 md 不进树)")
            } else {
                fail("目录扫描-node_modules 跳过 → \(webLevel.children.map(\.name))")
            }
            // 子层惰性装载:逐层 readdir
            let subLevel = try DirectoryTree.scanLevel(of: root.appendingPathComponent("sub"))
            let deepNode = subLevel.children.first { $0.name == "deep" }
            let deepLevel = deepNode.flatMap { try? DirectoryTree.scanLevel(of: $0.url) }
            if subLevel.children.map(\.name) == ["deep", "c.md"],
               deepLevel?.children.map(\.name) == ["d.markdown"] {
                pass("目录扫描-子层装载与深层 md 扩展名(.markdown)")
            } else {
                fail("目录扫描-子层装载 → sub=\(subLevel.children.map(\.name)) deep=\(deepLevel?.children.map(\.name) ?? [])")
            }
            // 父链回填 + descendant 只及已装载层(模拟 attachChildren 的回填)
            if let subNode {
                subNode.children = subLevel.children
                for child in subNode.children { child.parent = subNode }
                if rootLevel.descendant(at: root.appendingPathComponent("sub/c.md")) != nil,
                   rootLevel.descendant(at: root.appendingPathComponent("sub/deep/d.markdown")) == nil,
                   rootLevel.descendant(at: root.appendingPathComponent("b.txt")) == nil {
                    pass("目录扫描-descendant 只及已装载层")
                } else {
                    fail("目录扫描-descendant 定位范围不符")
                }
            }
        } catch {
            fail("目录扫描-建树失败 \(error)")
        }
        // 锚点链:文件系统根 → 指定目录(末项为自身),抽屉下拉框的父级目录来源
        let deep = URL(fileURLWithPath: "/tmp/mdp-anchor-demo/level1/level2")
        let chain = DirectoryTree.ancestorChain(of: deep)
        let names = chain.map(\.name)
        if names == ["/", "tmp", "mdp-anchor-demo", "level1", "level2"],
           chain.first?.url.path == "/", chain.last?.url.path == deep.standardizedFileURL.path {
            pass("锚点链-根到锚点完整父级序列(\(names.count) 项)")
        } else {
            fail("锚点链-序列不符 → \(names)")
        }
        let shallow = DirectoryTree.ancestorChain(of: URL(fileURLWithPath: "/"))
        if shallow.count == 1, shallow[0].name == "/" {
            pass("锚点链-根目录自身单项")
        } else {
            fail("锚点链-根目录 → \(shallow.count) 项")
        }

        // 根不可读 → 抛错(调用方展示空态,不静默装空树)
        do {
            _ = try DirectoryTree.scanLevel(of: URL(fileURLWithPath: "/tmp/selftest-nonexist-\(getpid())"))
            fail("目录扫描-根不可读应抛错")
        } catch {
            pass("目录扫描-根不可读抛错")
        }
    }

    // MARK: - 图片落盘导入测试

    private func testImageStore() {
        let fm = FileManager.default
        let docURL = URL(fileURLWithPath: "/tmp/selftest-store-\(getpid())/文档.md")
        let srcDir = URL(fileURLWithPath: "/tmp/selftest-store-src-\(getpid())")
        defer {
            try? fm.removeItem(at: docURL.deletingLastPathComponent())
            try? fm.removeItem(at: srcDir)
        }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        do {
            let a = try ImageStore.import(.blob(png, mime: "image/png"), docURL: docURL)
            if a.fileName == "img_001.png", fm.fileExists(atPath: a.url.path) {
                pass("图片落盘-剪贴板位图(img_001.png)")
            } else { fail("图片落盘-剪贴板位图 → \(a.fileName)") }

            let b = try ImageStore.import(.blob(Data([1, 2]), mime: "image/jpeg"), docURL: docURL)
            if b.fileName == "img_002.jpg" {
                pass("图片落盘-序号递增按 mime 定扩展名")
            } else { fail("图片落盘-序号递增 → \(b.fileName)") }

            try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
            let src = srcDir.appendingPathComponent("照片.jpg")
            fm.createFile(atPath: src.path, contents: png)
            let c = try ImageStore.import(.file(src), docURL: docURL)
            let d = try ImageStore.import(.file(src), docURL: docURL)
            if c.fileName == "照片.jpg", d.fileName == "照片-2.jpg" {
                pass("图片落盘-文件导入保留原名,冲突加后缀")
            } else { fail("图片落盘-文件导入 → \(c.fileName) / \(d.fileName)") }

            let expectDir = docURL.deletingLastPathComponent()
                .appendingPathComponent("resource", isDirectory: true)
                .appendingPathComponent("文档", isDirectory: true)
            if a.url.deletingLastPathComponent() == expectDir {
                pass("图片落盘-目录布局 resource/<md文件名>")
            } else { fail("图片落盘-目录布局 → \(a.url.path)") }

            let txt = srcDir.appendingPathComponent("a.txt")
            fm.createFile(atPath: txt.path, contents: Data([1]))
            do {
                _ = try ImageStore.import(.file(txt), docURL: docURL)
                fail("图片落盘-非图片拒绝(未拒绝)")
            } catch {
                pass("图片落盘-非图片拒绝")
            }

            // 缺陷复现(红→绿守门):目录可写但不可列举(chmod 0o300,缺 r 位)时,
            // 列目录若被静默当空目录,img 序号回绕到 001,.atomic 写盘会覆盖
            // 既有 img_001.png。正确行为:列目录失败原样抛错,拒绝导入。
            do {
                try fm.setAttributes([.posixPermissions: 0o300], ofItemAtPath: expectDir.path)
                do {
                    _ = try ImageStore.import(.blob(Data([7, 7, 7]), mime: "image/png"), docURL: docURL)
                    fail("图片落盘-不可列举目录拒绝(未拒绝,存在覆盖风险)")
                } catch {
                    pass("图片落盘-不可列举目录拒绝(防覆盖)")
                }
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: expectDir.path)
                if (try? Data(contentsOf: a.url)) == png {
                    pass("图片落盘-不可列举时既有图片未被覆盖")
                } else {
                    fail("图片落盘-不可列举时既有图片未被覆盖")
                }
            } catch {
                fail("图片落盘-不可列举目录用例异常 → \(error)")
            }
        } catch {
            fail("图片落盘异常 → \(error)")
        }
    }

    // MARK: - 资源目录 GC(关闭时清理未引用图片)

    /// 清理判定全形态覆盖:相对/`<>`包裹(含空格)/%20 编码 file:///手写
    /// 绝对 file:// 均保护;围栏内同名写法不保护;非图片文件不动;
    /// 引用清空图片全删;无其他文件时目录与 resource/ 连带移除。
    private func testImageCleanup() {
        let fm = FileManager.default
        let docURL = URL(fileURLWithPath: "/tmp/selftest-gc-\(getpid())/文档.md")
        let dir = ImageStore.directory(for: docURL)
        defer { try? fm.removeItem(at: docURL.deletingLastPathComponent()) }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            func put(_ name: String, _ bytes: [UInt8]) throws {
                try Data(bytes).write(to: dir.appendingPathComponent(name))
            }
            try put("img_001.png", [0x89, 0x50])
            try put("orphan.png", [0x89, 0x50])
            try put("keep me.jpg", [0xFF, 0xD8])
            try put("abs ref.png", [0x89, 0x50])
            try put("dot ref.png", [0x89, 0x50])
            try put("notes.txt", [0x74])

            let base = docURL.deletingLastPathComponent().path
            let md = """
                正文引用 ![一](resource/文档/img_001.png)

                包裹引用 ![二](<resource/文档/keep me.jpg>)

                编码引用 ![三](file://\(base)/resource/文档/abs%20ref.png)

                点前缀引用 ![四](./resource/文档/dot%20ref.png)

                ```
                围栏里写 ![x](resource/文档/orphan.png) 不算引用
                ```
                """
            // 引用集合来自内核（getResourceRefs）：装载同一篇文档后取集合，再让 GC 做差集
            var referencedPaths: Set<String> = []
            waitForCollect("资源清理-取引用集合", timeout: 20) { done in
                self.kernel.send("setMarkdown", ["md": md, "baseDir": base]) { _ in
                    self.kernel.send("getResourceRefs") { refs in
                        referencedPaths = Set((try? refs.get())?["paths"] as? [String] ?? [])
                        done()
                    }
                }
            }
            let removed1 = try ImageStore.cleanUnreferenced(docURL: docURL, referenced: referencedPaths)
            if removed1 == ["orphan.png"],
               referencedPaths.count == 4,
               fm.fileExists(atPath: dir.appendingPathComponent("img_001.png").path),
               fm.fileExists(atPath: dir.appendingPathComponent("keep me.jpg").path),
               fm.fileExists(atPath: dir.appendingPathComponent("abs ref.png").path),
               fm.fileExists(atPath: dir.appendingPathComponent("dot ref.png").path),
               fm.fileExists(atPath: dir.appendingPathComponent("notes.txt").path) {
                pass("资源清理-孤儿删除且被引用/非图片保留(集合=\(referencedPaths.count))")
            } else {
                fail("资源清理-孤儿删除且被引用/非图片保留 → 删=\(removed1) 集合=\(referencedPaths.count)")
            }

            // 引用清空:图片全删,非图片文件撑住目录
            let removed2 = try ImageStore.cleanUnreferenced(docURL: docURL, referenced: [])
            if removed2.sorted() == ["abs ref.png", "dot ref.png", "img_001.png", "keep me.jpg"].sorted(),
               fm.fileExists(atPath: dir.appendingPathComponent("notes.txt").path) {
                pass("资源清理-引用清空图片全删,非图片撑住目录")
            } else {
                fail("资源清理-引用清空图片全删,非图片撑住目录 → 删=\(removed2)")
            }

            // 无任何文件:目录与 resource/ 连带移除(不留空壳)
            try fm.removeItem(at: dir.appendingPathComponent("notes.txt"))
            _ = try ImageStore.cleanUnreferenced(docURL: docURL, referenced: [])
            let resourceRoot = docURL.deletingLastPathComponent().appendingPathComponent("resource")
            if !fm.fileExists(atPath: dir.path), !fm.fileExists(atPath: resourceRoot.path) {
                pass("资源清理-空目录与resource连带移除")
            } else {
                fail("资源清理-空目录与resource连带移除")
            }

            // 无资源目录:调用安全无副作用(新建未保存/首次打开文档路径)
            let bareDoc = URL(fileURLWithPath: "/tmp/selftest-gc-\(getpid())/bare.md")
            let removed3 = try ImageStore.cleanUnreferenced(docURL: bareDoc, referenced: [])
            if removed3.isEmpty, !fm.fileExists(atPath: ImageStore.directory(for: bareDoc).path) {
                pass("资源清理-无目录安全跳过")
            } else {
                fail("资源清理-无目录安全跳过 → \(removed3)")
            }
            // 恢复编辑器的基准目录：后续图片用例假设 baseDir=/tmp
            waitForCollect("资源清理-恢复基准目录", timeout: 10) { done in
                self.kernel.send("setBaseDir", ["path": "/tmp"]) { _ in done() }
            }
        } catch {
            fail("资源清理用例异常 → \(error)")
        }
    }

    // MARK: - 图片节点渲染与编辑框(web 行为往返)

    private func testImageNodeView() {
        // 注入带图文档并断言 NodeView 生效(渲染 img + 预置隐藏编辑框)
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("![原图](x.png)")))") { _ in }
        evaluate(#"(function(){var d=document.querySelector('.md-image');var s=d?d.querySelector('.md-image-src'):null;return JSON.stringify({img:d?d.querySelectorAll('img').length:0,form:!!s,hidden:!!s&&s.style.display==='none'})})()"#) { r in
            guard let json = r as? String,
                  let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                  (d["img"] as? Int) == 1, (d["form"] as? Bool) == true,
                  (d["hidden"] as? Bool) == true else {
                self.fail("图片 NodeView 渲染 → \(String(describing: r))")
                return
            }
            self.pass("图片 NodeView 渲染")
        }
        // 点击 → 源码编辑块出现,内容与文件写法同构(相对路径按 baseDir 还原)
        evaluate(#"(function(){var d=document.querySelector('.md-image');d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));var s=d.querySelector('.md-image-src');return JSON.stringify({shown:s&&s.style.display!=='none',text:s?s.textContent:''})})()"#) { r in
            guard let json = r as? String,
                  let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                  (d["shown"] as? Bool) == true,
                  d["text"] as? String == "![原图](x.png)" else {
                self.fail("图片点击进源码编辑块 → \(String(describing: r))")
                return
            }
            self.pass("图片点击进源码编辑块")
        }
        // 改源码 + Enter 提交 → doc 更新(三字段同块编辑)
        evaluate(#"(function(){var s=document.querySelector('.md-image-src');s.textContent='![新描述](file:///tmp/img-a.png "标题T")';s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));return window.mdbridge.getMarkdown()})()"#) { r in
            if let md = r as? String,
               md.contains("![新描述](file:///tmp/img-a.png"), md.contains("标题T") {
                self.pass("图片源码编辑提交生效")
            } else { self.fail("图片源码编辑提交生效 → \(String(describing: r))") }
        }
        // file:// 源码展示时按 baseDir 相对化还原
        evaluate(#"(function(){var d=document.querySelector('.md-image');d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));return d.querySelector('.md-image-src').textContent})()"#) { r in
            if let text = r as? String, text == "![新描述](img-a.png \"标题T\")" {
                self.pass("源码编辑块相对化展示")
            } else { self.fail("源码编辑块相对化展示 → \(String(describing: r))") }
        }
        // 解析不出图片语法的提交还原不动(Esc 同理)
        evaluate(#"(function(){var s=document.querySelector('.md-image-src');s.textContent='![x](broken.png';s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));return window.mdbridge.getMarkdown()})()"#) { r in
            if let md = r as? String, md.contains("file:///tmp/img-a.png"), !md.contains("broken.png") {
                self.pass("非法源码提交还原")
            } else { self.fail("非法源码提交还原 → \(String(describing: r))") }
        }
        // 清空源码提交 = 删除图片
        evaluate(#"(function(){var d=document.querySelector('.md-image');d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));var s=d.querySelector('.md-image-src');s.textContent='';s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));return window.mdbridge.getMarkdown()})()"#) { r in
            if let md = r as? String, !md.contains("img-a.png") {
                self.pass("清空源码删除图片")
            } else { self.fail("清空源码删除图片 → \(String(describing: r))") }
        }
        // 中文路径解码展示 + 相对路径提交回规范 file://(%20 编码)
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("![编](file:///tmp/%E4%B8%AD%E6%96%87/a.png)")))") { _ in }
        evaluate(#"(function(){var d=document.querySelector('.md-image');d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));var s=d.querySelector('.md-image-src');var shown=s.textContent;s.textContent='![改](dir two/b.png)';s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));return JSON.stringify({shown:shown,md:window.mdbridge.getMarkdown()})})()"#) { r in
            guard let json = r as? String,
                  let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                  d["shown"] as? String == "![编](中文/a.png)",
                  let md = d["md"] as? String,
                  md.contains("![改](file:///tmp/dir%20two/b.png)") else {
                self.fail("图片路径解码展示与回解析 → \(String(describing: r))")
                return
            }
            self.pass("图片路径解码展示与回解析")
        }
        // insertImage 桥:光标在正文段落时插入图片节点
        evaluate("(function(){var p=document.querySelector('.ProseMirror p');var r=p.getBoundingClientRect();return JSON.stringify(window.mdbridge.focusAt(r.left+5,r.top+5))})()") { _ in }
        evaluate("window.mdbridge.insertImage('file:///tmp/ins.png','别名','')") { r in
            if (r as? Bool) == true { self.pass("insertImage 桥插入") } else { self.fail("insertImage 桥插入 → \(String(describing: r))") }
        }
        evaluate("window.mdbridge.getMarkdown()") { r in
            if let md = r as? String, md.contains("![别名](file:///tmp/ins.png)") {
                self.pass("insertImage 桥内容生效")
            } else { self.fail("insertImage 桥内容生效 → \(String(describing: r))") }
        }
        // 剪贴板载荷识别:截图 blob / 图片路径文本 / 普通文本不误判
        evaluate(#"(function(){var f=new File([new Uint8Array([1,2,3])],'shot.png',{type:'image/png'});var r1=window.mdbridge.testImagePayload({files:[f],getData:function(){return ''}});var r2=window.mdbridge.testImagePayload({files:[],getData:function(k){return k==='text/plain'?'/tmp/x y/a.jpg':''}});var r3=window.mdbridge.testImagePayload({files:[],getData:function(){return '普通文本见 a.png'}});return JSON.stringify({k1:r1&&r1.kind,k2:r2&&r2.kind,none:r3===null})})()"#) { r in
            guard let json = r as? String,
                  let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                  d["k1"] as? String == "blob", d["k2"] as? String == "file",
                  (d["none"] as? Bool) == true else {
                self.fail("剪贴板图片载荷识别 → \(String(describing: r))")
                return
            }
            self.pass("剪贴板图片载荷识别")
        }
    }

    // MARK: - 图片编辑框窄窗口几何

    /// 窄窗口下的关键视口验证。宽度策略是设计契约:正文列收缩下限 860px
    /// (--editor-max-width),窄窗页面横向滚动属预期行为;编辑块在此前提下
    /// 仍须满足:可打开、宽度不超正文栏、长路径在块内换行、页面横向溢出
    /// 不超过 #app 的 min-width 下限(长路径不得加剧溢出)。
    /// min-width 取计算样式而非复制常量,避免与 typora.css 双源。
    private func testImageEditBoxNarrowWindow() {
        let longName = "narrow-" + String(repeating: "long-image-file-name-", count: 5) + "img.png"
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("![窄窗](file:///tmp/\(longName))")))") { _ in }
        window.setContentSize(NSSize(width: 480, height: 600))
        defer { window.setContentSize(NSSize(width: 1000, height: 800)) }
        // 条件等待(非纯睡):视口真实收窄且编辑块已打开,再测几何
        waitForValue("窄窗-窗口收窄且编辑块可打开", timeout: 5,
            script: #"(function(){var d=document.querySelector('.md-image');if(!d)return 'no-node';d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));var s=d.querySelector('.md-image-src');return JSON.stringify({open:!!s&&s.style.display!=='none',vw:window.innerWidth})})()"#,
            test: { value in
                guard let json = value as? String,
                      let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                      (d["open"] as? Bool) == true,
                      let vw = (d["vw"] as? NSNumber)?.doubleValue, vw > 0, vw < 500 else { return false }
                return true
            })
        evaluate(#"(function(){var d=document.querySelector('.md-image');var s=d.querySelector('.md-image-src');var app=document.getElementById('app');return JSON.stringify({srcScroll:s.scrollWidth,srcClient:s.clientWidth,srcRight:s.getBoundingClientRect().right,appRight:app.getBoundingClientRect().right,doc:document.documentElement.scrollWidth,appMin:parseFloat(getComputedStyle(app).minWidth)})})()"#) { r in
            guard let json = r as? String,
                  let d = (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!)) as? [String: Any],
                  let srcScroll = (d["srcScroll"] as? NSNumber)?.doubleValue,
                  let srcClient = (d["srcClient"] as? NSNumber)?.doubleValue,
                  let srcRight = (d["srcRight"] as? NSNumber)?.doubleValue,
                  let appRight = (d["appRight"] as? NSNumber)?.doubleValue,
                  let doc = (d["doc"] as? NSNumber)?.doubleValue,
                  let appMin = (d["appMin"] as? NSNumber)?.doubleValue else {
                self.fail("窄窗-编辑块几何(数据缺失 → \(String(describing: r)))")
                return
            }
            if srcScroll <= srcClient + 0.5 && srcRight <= appRight + 0.5 && doc <= appMin + 0.5 {
                self.pass("窄窗-编辑块不溢出(长路径换行/不超正文栏/页面溢出≤min-width)")
            } else {
                self.fail("窄窗-编辑块不溢出 → 换行 \(srcScroll)/\(srcClient),块右 \(srcRight)/\(appRight),页面 \(doc)/\(appMin)")
            }
        }
    }

    // MARK: - 列表序列化缩进(每级 4 空格)

    /// 列表 Tab 嵌套的序列化宽度:每级 4 空格、首行标记紧凑(`- a` 而非 `-   a`)。
    /// 端到端走真实 Tab 键(合成 KeyboardEvent → Milkdown listItemKeymap 的 SinkListItem);
    /// 另断言多级嵌套与任务列表复选框不被自定义 handler 吞掉。
    /// 红→绿:修复前 `listItemIndent: 'one'` 只缩 2 空格;`listItemIndent: 'tab'`
    /// 则会把首行补成 `-   a`,两条断言同时守住。
    private func testListIndent() {
        // 1) 端到端:光标落在第二项行首,按 Tab 后序列化必须是 4 空格嵌套
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("- alpha\n- beta\n- gamma\n")))") { _ in }
        // 选区设置与 Tab 派发放进页面定时器:ProseMirror 需要一拍把 DOM 选区同步进 State
        evaluate("""
        (function () {
            window.__listIndentTab = null;
            setTimeout(function () {
                var view = document.querySelector('.ProseMirror');
                view.focus();
                var items = document.querySelectorAll('.ProseMirror li');
                var p = items[1].querySelector('p') || items[1];
                var range = document.createRange();
                range.setStart(p.firstChild, 0);
                range.collapse(true);
                var sel = getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
                setTimeout(function () {
                    view.dispatchEvent(new KeyboardEvent('keydown', {
                        key: 'Tab', code: 'Tab', keyCode: 9, which: 9,
                        bubbles: true, cancelable: true
                    }));
                    setTimeout(function () {
                        window.__listIndentTab = window.mdbridge.getMarkdown();
                    }, 150);
                }, 150);
            }, 150);
        })()
        """) { _ in }

        var tabMarkdown: String?
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            var value: Any?
            evaluate("window.__listIndentTab || ''") { value = $0 }
            if let md = value as? String, !md.isEmpty {
                tabMarkdown = md
                break
            }
            pumpRunLoop(for: 0.1)
        }
        if let md = tabMarkdown {
            let nested = md.contains("- alpha\n    - beta\n- gamma")
            let compact = !md.contains("-   alpha")
            if nested && compact {
                pass("列表 Tab 嵌套-每级 4 空格且首行紧凑")
            } else {
                fail("列表 Tab 嵌套-缩进 → \(md.debugDescription)")
            }
        } else {
            fail("列表 Tab 嵌套-未取到序列化结果")
        }

        // 2) 多级嵌套:2 空格旧文件注入后,输出按保存口径规范化为 4/8 空格
        var multi = ""
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("- a\n  - b\n    - c\n")))") { _ in }
        evaluate("window.mdbridge.getMarkdown()") { multi = ($0 as? String) ?? "" }
        if multi.contains("- a\n    - b\n        - c") {
            pass("列表多级嵌套-4/8 空格")
        } else {
            fail("列表多级嵌套-缩进 → \(multi.debugDescription)")
        }

        // 3) 任务列表复选框:自定义 listItem handler 必须复刻 GFM 语义,不得吞掉 [x]
        var task = ""
        evaluate("window.mdbridge.setMarkdown(\(JSArgs.string("- [x] done\n  - [ ] nested\n")))") { _ in }
        evaluate("window.mdbridge.getMarkdown()") { task = ($0 as? String) ?? "" }
        if task.contains("- [x] done\n    - [ ] nested") {
            pass("任务列表复选框与 4 空格缩进")
        } else {
            fail("任务列表复选框 → \(task.debugDescription)")
        }
    }

    // MARK: - 基础设施(全部走 RunLoop 泵送)

    /// token 调色板契约:逐组核对「成员类的色值 == 组色值」,并要求所有 token
    /// 无背景、无阴影;同时核对真实渲染样本。任一不符列出前 6 条差异。
    private func checkTokenPalette(_ label: String, colors: [String: String]) {
        var probe: [String: Any] = [:]
        evaluate(SelftestRunner.paletteProbeJS) { result in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                probe = dict
            }
        }
        guard !probe.isEmpty else {
            fail("\(label) token 调色板:探针无数据")
            return
        }
        var bad: [String] = []
        for (group, expected) in colors.sorted(by: { $0.key < $1.key }) {
            for cls in SelftestRunner.tokenGroups[group] ?? [] {
                guard let entry = probe[cls] as? [String: Any] else {
                    bad.append("\(cls)=无数据")
                    continue
                }
                if (entry["color"] as? String) != expected {
                    bad.append("\(cls)=\(entry["color"] ?? "?")≠\(expected)")
                }
                if (entry["bg"] as? String) != "rgba(0, 0, 0, 0)" {
                    bad.append("\(cls) 有背景 \(entry["bg"] ?? "?")")
                }
                if (entry["shadow"] as? String) != "none" {
                    bad.append("\(cls) 有阴影 \(entry["shadow"] ?? "?")")
                }
            }
        }
        if let rendered = probe["__rendered"] as? [String: Any] {
            let count = rendered["count"] as? Int ?? 0
            let withBg = rendered["withBg"] as? Int ?? 0
            let shadowed = rendered["shadowed"] as? Int ?? 0
            if count < 3 { bad.append("渲染样本 token 数=\(count)") }
            if withBg != 0 { bad.append("渲染样本 \(withBg) 个 token 带背景") }
            if shadowed != 0 { bad.append("渲染样本 \(shadowed) 个 token 带阴影") }
        } else {
            bad.append("渲染样本无数据")
        }
        if bad.isEmpty {
            pass("\(label) token 调色板(\(colors.count) 组 \((SelftestRunner.tokenGroups.values.flatMap { $0 }).count) 类无背景/无阴影,色值一致)")
        } else {
            fail("\(label) token 调色板 → " + bad.prefix(6).joined(separator: "、"))
        }
    }

    private func evaluate(_ js: String, on target: EditorWebView? = nil, completion: ((Any?) -> Void)? = nil) {
        var finished = false
        var output: Any?
        (target ?? webview).evaluateJavaScript(js) { result, error in
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
        if !finished { fail(name) }
    }

    /// 同步读取查找栏计数(label 文本),用于「输入即命中/循环切换」这类同步断言
    private func findCountText() -> String {
        var text = ""
        var finished = false
        webview.evaluateJavaScript("document.getElementById('find-count').textContent") { result, _ in
            text = (result as? String) ?? ""
            finished = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { pumpRunLoop(for: 0.02) }
        return text
    }

    /// 等待桥消息静止:changed 上报经 web 端 200ms debounce 异步到达,
    /// 断言前用"连续 quiet 秒无新上报"确认旧事务尾窗已排空(条件等待,非纯睡)。
    private func settleBridge(quiet: TimeInterval, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCount = changedTotalCount
        var lastChange = Date()
        while Date() < deadline {
            pumpRunLoop(for: 0.05)
            if changedTotalCount != lastCount {
                lastCount = changedTotalCount
                lastChange = Date()
            }
            if Date().timeIntervalSince(lastChange) >= quiet { return }
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

