import AppKit
import WebKit

/// 承载 Milkdown 编辑器的 WebView。
/// JS → Swift 通过 window.webkit.messageHandlers.mdbridge.postMessage({op:..., ...})
/// Swift → JS 通过 evaluateJavaScript 调用 window.mdbridge 上的方法。
final class EditorWebView: WKWebView, WKScriptMessageHandler, WKNavigationDelegate {
    /// 收到来自 web 的消息 (op, payload)
    var onBridgeMessage: ((String, [String: Any]) -> Void)?
    var onDocumentLinkActivated: ((URL) -> Void)?
    var onPageReady: (() -> Void)?
    /// 由控制器异步提供右键菜单(先定位光标再构建);返回 nil 时本次不弹菜单
    var contextMenuHandler: ((_ x: CGFloat, _ y: CGFloat, _ done: @escaping (NSMenu?) -> Void) -> Void)?
    private var localEventMonitor: Any?

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
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
        // 让 WebKit 的编辑行为(剪切/粘贴/撤销)走系统菜单响应链
        allowsBackForwardNavigationGestures = false
        // 在实际生效的 configuration 上注册消息处理;
        // 用弱引用代理避免 WKUserContentController 强持有 WebView 造成循环引用
        let proxy = WKContentProxy()
        proxy.target = self
        configuration.userContentController.add(proxy, name: "mdbridge")
        // 彻底覆盖系统右键菜单:按下与抬起都在编辑器区域内时吞掉事件,
        // 抬起后先定位光标(异步查询表格状态),再弹应用自定义菜单
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.hitTest(event.locationInWindow) != nil else { return event }
            return nil
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  self.hitTest(event.locationInWindow) != nil,
                  let handler = self.contextMenuHandler else { return event }
            let p = self.convert(event.locationInWindow, from: nil)
            let pageY = self.bounds.height - p.y
            handler(p.x, pageY) { [weak self] menu in
                guard let self, let menu else { return }
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return nil
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - JS 消息代理中转

    func relayMessage(_ body: Any) {
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
                // 扩展名清单唯一来源:AppDelegate.markdownExtensions(与打开面板/Info.plist 同源)
                if AppDelegate.markdownExtensions.contains(ext) || ext.isEmpty {
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
