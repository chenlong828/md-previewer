import AppKit
import WebKit

// 截图模式:--screenshot <output.png> [input.md]
// 进程内通过 WKWebView.takeSnapshot 捕获渲染结果,无需屏幕录制权限。
final class ScreenshotRunner: NSObject {
    private var controller: DocumentWindowController?
    private var outputPath = ""
    private var waited = 0.0
    private var phase: Phase = .waitReady
    private var openedDocument = false

    private enum Phase { case waitReady, waitLoaded }

    func run(output: String, input: String?) {
        outputPath = output

        guard let controller = (NSApp.delegate as? AppDelegate)?.currentDocument else {
            FileHandle.standardError.write("screenshot: no document controller\n".data(using: .utf8)!)
            exit(2)
        }
        self.controller = controller

        // 阶段1:等编辑器就绪 → 打开文档 → 阶段2:等内容渲染 → 截图
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.waited += 0.1
            switch self.phase {
            case .waitReady:
                if controller.isReady {
                    if let input {
                        controller.openDocument(at: URL(fileURLWithPath: input))
                    }
                    self.openedDocument = true
                    self.phase = .waitLoaded
                    self.waited = 0
                } else if self.waited > 30 {
                    timer.invalidate()
                    FileHandle.standardError.write("screenshot: editor not ready in 30s\n".data(using: .utf8)!)
                    exit(7)
                }
            case .waitLoaded:
                // 内容注入完成 + 额外 3.5s 给 mermaid/katex 异步渲染
                if controller.isReady && !controller.isLoadingContent && self.waited >= 3.5 {
                    timer.invalidate()
                    self.capture()
                } else if self.waited > 30 {
                    timer.invalidate()
                    self.capture() // 超时也要尽力截图
                }
            }
        }
    }

    private func capture() {
        guard let webView = controller?.webViewIfNeeded else { exit(3) }
        // 诊断:确认 DOM 内容与窗口状态
        controller?.evaluateForDiagnostics(
            "JSON.stringify({mdReady: !!window.mdbridge, pmLen: (document.querySelector('.ProseMirror')||{innerHTML:''}).innerHTML.length, readyState: document.readyState, theme: document.documentElement.getAttribute('data-theme')})") { result in
            print("SCREENSHOT dom:", result ?? "nil")
        }
        if let win = controller?.window {
            print("SCREENSHOT window: visible=\(win.isVisible) occluded=\(win.occlusionState.contains(.visible)) main=\(win.isMainWindow)")
        }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self else { return }
            guard let image else {
                FileHandle.standardError.write("screenshot failed: \(error?.localizedDescription ?? "?")\n".data(using: .utf8)!)
                exit(4)
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write("screenshot: png encode failed\n".data(using: .utf8)!)
                exit(5)
            }
            do {
                try png.write(to: URL(fileURLWithPath: self.outputPath))
                print("SCREENSHOT saved: \(self.outputPath) (\(png.count) bytes)")
                exit(0)
            } catch {
                FileHandle.standardError.write("screenshot: write failed \(error)\n".data(using: .utf8)!)
                exit(6)
            }
        }
    }
}
