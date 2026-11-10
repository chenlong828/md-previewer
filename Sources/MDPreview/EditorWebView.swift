import AppKit
import WebKit

/// 承载 Milkdown 编辑器的 WebView。
/// JS → Swift：v2 帧经 window.__mdHostChannel.post（JSON 字符串）→ messageHandlers.mdbridge；
/// Swift → JS：v2 帧经 evaluateJavaScript 投递到 window.__mdKernel.receive（见 KernelClient）。
final class EditorWebView: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    /// 收到来自 web 的消息 (op, payload)：仅旧式字典帧会走到这里
    var onBridgeMessage: ((String, [String: Any]) -> Void)?
    /// v2 帧入口：返回 true 表示已由 KernelClient 消费（不再走旧处理器）
    var onKernelMessage: ((Any) -> Bool)?
    var onDocumentLinkActivated: ((URL) -> Void)?
    var onPageReady: (() -> Void)?
    /// 拖入的是图片文件时交控制器导入(其余文件仍走开新窗)
    var onImageFileDropped: ((URL) -> Void)?
    /// 由控制器异步提供右键菜单(先定位光标再构建);返回 nil 时本次不弹菜单
    var contextMenuHandler: ((_ x: CGFloat, _ y: CGFloat, _ done: @escaping (NSMenu?) -> Void) -> Void)?
    /// 菜单呈现方式(默认系统弹出);自检替换为捕获器,避免进入阻塞式菜单跟踪
    var presentContextMenu: ((NSMenu, NSEvent, NSView) -> Void)?
    // 全局/局部事件监视器句柄集中管理:窗口关闭或实例释放时统一移除,
    // 避免多窗口下事件穿越 N 个已废弃监视器(审计 #20)。
    private var eventMonitors: [Any] = []

    /// - Parameter testFacade: 自检/截图环境装 v1 方法面（供既有自检脚本调用），产品不装
    static func makeConfiguration(testFacade: Bool = false) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        if testFacade {
            config.userContentController.addUserScript(WKUserScript(
                source: "window.__MDP_TEST__ = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        // v2 传输通道：必须在 bundle 求值前注入（内核缺 channel 会显式失败）
        config.userContentController.addUserScript(WKUserScript(
            source: KernelClient.installScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // 消息处理在 init 中注册(需要回填弱引用代理的 target)
        // 编辑器无需持久化站点数据(纯本地文档工具),用内存存储避免写用户目录
        config.websiteDataStore = .nonPersistent()
        // 本地图片访问通过 loadFileURL(_:allowingReadAccessTo:) 授予,
        // 不使用未公开的 KVC key(在新版 WebKit 上会直接崩溃)
        return config
    }

    init(configuration: WKWebViewConfiguration = EditorWebView.makeConfiguration()) {
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        uiDelegate = self
        // 编辑器不使用前后退导航手势(单页应用,手势会与文本编辑误触冲突)
        allowsBackForwardNavigationGestures = false
        // 在实际生效的 configuration 上注册消息处理;
        // 用弱引用代理避免 WKUserContentController 强持有 WebView 造成循环引用
        let proxy = WKContentProxy()
        proxy.target = self
        configuration.userContentController.add(proxy, name: "mdbridge")
        // 彻底覆盖系统右键菜单:按下与抬起都在编辑器区域内时吞掉事件,
        // 抬起后先定位光标(异步查询表格状态),再弹应用自定义菜单
        addMonitor(for: .rightMouseDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.hitTest(event.locationInWindow) != nil else { return event }
            return nil
        }
        addMonitor(for: .rightMouseUp) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.hitTest(event.locationInWindow) != nil,
                  let handler = self.contextMenuHandler else { return event }
            let page = self.pagePoint(forWindowPoint: event.locationInWindow)
            handler(page.x, page.y) { [weak self] menu in
                guard let self, let menu else { return }
                if let present = self.presentContextMenu {
                    present(menu, event, self)
                } else {
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                }
            }
            return nil
        }
    }

    /// 事件窗口坐标 → 网页视口坐标(CSS 像素,左上原点)。
    /// WKWebView 是 flipped 视图:convert 已把窗口的左下原点换成视口左上原点,
    /// 再按 bounds.height 翻转一次会把 y 镜像到视口中线——右键点第 1 行却定位到
    /// 倒数行/表格外,行列命令因此作用在错误行(2026-11-10 修复)。
    func pagePoint(forWindowPoint point: NSPoint) -> NSPoint {
        let p = convert(point, from: nil)
        return NSPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// addLocalMonitorForEvents 返回可空句柄:非空才入册,deinit 时成对移除
    private func addMonitor(for type: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> NSEvent?) {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: type, handler: handler) {
            eventMonitors.append(monitor)
        }
    }

    deinit {
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors = []
    }

    // MARK: - JS 消息代理中转

    func relayMessage(_ body: Any) {
        if onKernelMessage?(body) == true { return }
        guard let dict = body as? [String: Any], let op = dict["op"] as? String else { return }
        onBridgeMessage?(op, dict)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "mdbridge" { relayMessage(message.body) }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPageReady?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if url.isFileURL {
                let ext = url.pathExtension.lowercased()
                // 可打开清单唯一来源:FileSupport(与打开面板/抽屉/Info.plist 同源);
                // 代码文件与 Markdown 同样在应用内开新窗口,其余交给系统默认应用。
                if FileSupport.isOpenable(url) || ext.isEmpty {
                    onDocumentLinkActivated?(url)
                    decisionHandler(.cancel)
                    return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate(右键菜单等默认行为)

extension EditorWebView: WKUIDelegate {
    /// 允许 JS confirm/alert 使用系统原生对话框
    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }
}

/// 把消息转发给真实 WebView 的轻量代理
/// (WKUserContentController 对 handler 是强引用,用中间对象避免 WebView 自引用循环)
final class WKContentProxy: NSObject, WKScriptMessageHandler {
    weak var target: EditorWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.relayMessage(message.body)
    }
}
