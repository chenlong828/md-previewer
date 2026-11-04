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
                    // e2e 钩子(MDP_IMPORT_IMAGE=<图片路径>):验证 导入→落盘→插入
                    // 全链路再截图(拖放/菜单同一入口)。
                    // MDP_EDIT_IMAGE=1:打开第一张图片的源码编辑块再截图(编辑框视觉/几何验证)。
                    let importPath = ProcessInfo.processInfo.environment["MDP_IMPORT_IMAGE"]
                    let editMode = ProcessInfo.processInfo.environment["MDP_EDIT_IMAGE"] == "1"
                    // MDP_PASTE_IMAGE=<图片路径>:走剪贴板粘贴链路（JS → v2 请求 → 壳落盘 → 内核插入）
                    let pastePath = ProcessInfo.processInfo.environment["MDP_PASTE_IMAGE"]
                    if let pastePath {
                        self.runPasteEndToEnd(pastePath)
                        // 等粘贴往返（请求→落盘→插入）打印完再截图退出
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { self.capture() }
                    } else if importPath != nil || editMode {
                        if let importPath {
                            controller.importImage(at: URL(fileURLWithPath: importPath))
                        }
                        if editMode {
                            controller.evaluateForDiagnostics(
                                "(function(){var d=document.querySelector('.md-image');if(!d)return 'no-image';d.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));var s=d.querySelector('.md-image-src');return JSON.stringify({open:s&&s.style.display!=='none',text:s?s.textContent.slice(0,80):'',width:s?s.clientWidth:0})})()") { r in
                                print("SCREENSHOT editbox:", r ?? "nil")
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.capture() }
                    } else {
                        self.capture()
                    }
                } else if self.waited > 30 {
                    timer.invalidate()
                    self.capture() // 超时也要尽力截图
                }
            }
        }
    }

    /// 粘贴全链路 e2e：构造一次携带图片文件的 paste 事件，验证
    /// JS 识别 → hostCall('importImage') → 壳落盘 → 内核恢复选区插入 的完整往返。
    private func runPasteEndToEnd(_ path: String) {
        guard let controller,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("SCREENSHOT paste: read-failed")
            return
        }
        let base64 = data.base64EncodedString()
        let mime = "image/png"
        let script = """
        (function(){
            var bin = atob('\(base64)');
            var bytes = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            var file = new File([bytes], 'clip.png', {type: '\(mime)'});
            var dt = new DataTransfer();
            dt.items.add(file);
            var target = document.querySelector('.ProseMirror') || document.getElementById('app');
            target.dispatchEvent(new ClipboardEvent('paste', {clipboardData: dt, bubbles: true, cancelable: true}));
            return 'dispatched';
        })()
        """
        controller.evaluateForDiagnostics(script) { r in
            print("SCREENSHOT paste dispatched:", r ?? "nil")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let controller = self.controller else { return }
            controller.evaluateForDiagnostics(
                "JSON.stringify({images: document.querySelectorAll('.md-image').length, src: Array.prototype.map.call(document.querySelectorAll('.md-image img'), function(i){return (i.getAttribute('src')||'').slice(0,160)}), md: (function(){try{return window.__mdKernel ? '' : ''}catch(e){return 'err'}})()})"
            ) { result in
                print("SCREENSHOT paste result:", result ?? "nil")
            }
            // 落盘结果：resource 目录内容
            if let docURL = controller.fileURL {
                let dir = ImageStore.directory(for: docURL)
                let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                print("SCREENSHOT paste resource:", files.sorted())
            }
        }
    }

    private func capture() {
        guard let webView = controller?.webViewIfNeeded else { exit(3) }
        // 诊断:确认 DOM 内容与窗口状态
        controller?.evaluateForDiagnostics(
            "JSON.stringify({mdReady: !!window.__mdKernel, pmLen: (document.querySelector('.ProseMirror')||{innerHTML:''}).innerHTML.length, readyState: document.readyState, theme: document.documentElement.getAttribute('data-theme'), images: Array.prototype.map.call(document.querySelectorAll('.md-image-render img'), function(i){return {src: (i.getAttribute('src')||'').slice(0,120), w: i.naturalWidth, complete: i.complete}})})") { result in
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
