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
        webview = EditorWebView(configuration: EditorWebView.makeConfiguration())
        webview.frame = window.contentView!.bounds
        webview.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webview)
        window.orderFrontRegardless() // 需要参与渲染,但 app 为 .prohibited 不抢焦点

        webview.onBridgeMessage = { [weak self] op, payload in
            guard let self else { return }
            if op == "boot" { self.bootReceived = true }
            if op == "ready" { self.readyReceived = true }
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

        webview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        // ── 等待页面脚本加载
        waitFor("页面脚本加载(boot)", timeout: 30) { self.bootReceived }

        // ── 初始化编辑器
        let pluginSet = ProcessInfo.processInfo.environment["MDP_PLUGINS"] ?? "full"
        let optsJSON = "{\"theme\":\"light\",\"zoom\":1,\"plugins\":\"\(pluginSet)\"}"
        evaluate("void window.mdbridge.init(\(JSArgs.string(SelftestRunner.sampleMarkdown)), \(optsJSON))") { _ in }
        waitFor("编辑器初始化(ready)", timeout: 30) { self.readyReceived }
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

        // ── Info.plist 扩展名清单与 Swift 唯一来源一致(AppDelegate.markdownExtensions)
        assertInfoPlistExtensions()

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

        // ── Swift 侧图片路径改写
        testPathRewriter()

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
        let lightWebview = EditorWebView(configuration: EditorWebView.makeConfiguration())
        lightWebview.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        lightWebview.autoresizingMask = [.width, .height]
        lightWindow.contentView?.addSubview(lightWebview)
        lightWindow.orderFrontRegardless()
        lightWebview.onBridgeMessage = { [weak self] op, _ in
            guard let self else { return }
            if op == "boot" { self.lightBootReceived = true }
            if op == "ready" { self.lightReadyReceived = true }
        }
        lightWebview.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        waitFor("OQ-1 轻量页脚本加载", timeout: 30) { self.lightBootReceived }
        let lightMD = "# 轻量\n\n```mermaid\ngraph LR\n  A --> B\n```\n\n$E = mc^2$\n"
        let lightOpts = "{\"theme\":\"light\",\"zoom\":1,\"plugins\":\"no-diagram\"}"
        evaluate("void window.mdbridge.init(\(JSArgs.string(lightMD)), \(lightOpts))", on: lightWebview) { _ in }
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

    /// Info.plist 的 CFBundleTypeExtensions 必须与 AppDelegate.markdownExtensions 一致
    private func assertInfoPlistExtensions() {
        guard let plistURL = WebLocator.repoInfoPlistURL(),
              let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]],
              let exts = docTypes.first?["CFBundleTypeExtensions"] as? [String] else {
            fail("Info.plist 扩展名一致(解析失败:仅开发模式可断言)")
            return
        }
        if exts.sorted() == AppDelegate.markdownExtensions.sorted() {
            pass("Info.plist 扩展名一致(\(exts.count) 项)")
        } else {
            fail("Info.plist 扩展名一致 → plist=\(exts.sorted()) code=\(AppDelegate.markdownExtensions.sorted())")
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

