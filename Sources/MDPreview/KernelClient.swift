import Foundation
import os.log
import WebKit

/// 内核 v2 客户端：单通道、请求-响应按 id 关联、通知单向、超时兜底。
/// 对应 JS 侧 kernel/transport/channel.js 与 kernel/contract/*；Windows 壳照此实现即可
/// （协议形状见 doc/works/2026-11-04-kernel-v2/spec-delta.md §3）。
final class KernelClient {
    struct KernelError: Error {
        let code: String
        let message: String
    }

    static let protocolVersion = 2

    /// 必须在内核 bundle 求值前注入（transport 缺 channel 就会显式失败，不静默降级）
    static let installScript = """
    (function () {
        window.__mdHostChannel = Object.freeze({
            post: function (json) {
                window.webkit.messageHandlers.mdbridge.postMessage(json);
            }
        });
    })();
    """

    private weak var webView: WKWebView?
    private var seq = 0
    private var pending: [String: (completion: (Result<[String: Any], KernelError>) -> Void, timeout: DispatchWorkItem)] = [:]

    /// 内核通知（boot/ready/changed/stats/sourceMode/selinfo/jserror）
    var onNotification: ((String, [String: Any]) -> Void)?
    /// 内核发起的请求（resolveResources / importImage），实现方必须 reply 一次
    var onRequest: ((String, [String: Any], @escaping (Result<[String: Any], KernelError>) -> Void) -> Void)?

    /// 握手结果：kernelVersion / protocolVersion / ops[]
    private(set) var info: [String: Any] = [:]

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    /// 握手成功后记录内核自述（kernelVersion / protocolVersion / ops）
    func recordHandshake(_ payload: [String: Any]) {
        info = payload
    }

    // MARK: - 发出请求

    func send(
        _ op: String,
        _ payload: [String: Any] = [:],
        timeout: TimeInterval = 10,
        completion: ((Result<[String: Any], KernelError>) -> Void)? = nil
    ) {
        seq += 1
        let id = "s\(seq)"
        if let completion {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let entry = self.pending.removeValue(forKey: id) else { return }
                entry.completion(.failure(KernelError(code: "timeout", message: "op \(op) 超时")))
            }
            pending[id] = (completion, work)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        }
        deliver(["v": Self.protocolVersion, "op": op, "id": id, "payload": payload])
    }

    // MARK: - 接收内核帧

    /// 返回 true 表示这帧属于 v2 通道（已消费），false 交给旧处理器
    @discardableResult
    func receive(_ body: Any) -> Bool {
        guard let frame = Self.frame(from: body) else { return false }
        let id = frame["id"] as? String
        if let id, frame["ok"] != nil || frame["error"] != nil {
            settleResponse(id: id, frame: frame)
            return true
        }
        guard let op = frame["op"] as? String else {
            report(.failure(KernelError(code: "bad_payload", message: "v2 帧缺少 op")))
            return true
        }
        let payload = frame["payload"] as? [String: Any] ?? [:]
        if let id {
            handleRequest(id: id, op: op, payload: payload)
        } else {
            onNotification?(op, payload)
        }
        return true
    }

    /// postMessage 既可能是 v2 帧的 JSON 字符串，也可能是旧式字典；只认 v==2
    private static func frame(from body: Any) -> [String: Any]? {
        if let dict = body as? [String: Any] {
            return (dict["v"] as? Int) == protocolVersion ? dict : nil
        }
        guard let text = body as? String,
              let data = text.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (dict["v"] as? Int) == protocolVersion else { return nil }
        return dict
    }

    private func settleResponse(id: String, frame: [String: Any]) {
        guard let entry = pending.removeValue(forKey: id) else {
            os_log(.error, "kernel: response for unknown request id %{public}@", id)
            return
        }
        entry.timeout.cancel()
        if frame["ok"] as? Bool == true {
            entry.completion(.success(frame["payload"] as? [String: Any] ?? [:]))
            return
        }
        let error = frame["error"] as? [String: Any] ?? [:]
        entry.completion(.failure(KernelError(
            code: error["code"] as? String ?? "internal",
            message: error["message"] as? String ?? "内核请求失败"
        )))
    }

    private func handleRequest(id: String, op: String, payload: [String: Any]) {
        guard let onRequest else {
            respond(id: id, error: KernelError(code: "unknown_op", message: "壳未实现请求 \(op)"))
            return
        }
        onRequest(op, payload) { [weak self] result in
            switch result {
            case .success(let payload): self?.respond(id: id, payload: payload)
            case .failure(let error): self?.respond(id: id, error: error)
            }
        }
    }

    private func respond(id: String, payload: [String: Any]) {
        deliver(["v": Self.protocolVersion, "id": id, "ok": true, "payload": payload])
    }

    private func respond(id: String, error: KernelError) {
        deliver(["v": Self.protocolVersion, "id": id, "ok": false, "error": ["code": error.code, "message": error.message]])
    }

    private func report(_ failure: Result<[String: Any], KernelError>) {
        if case .failure(let error) = failure {
            os_log(.error, "kernel: %{public}@", error.message)
        }
    }

    // MARK: - 投递到 JS

    private func deliver(_ frame: [String: Any]) {
        guard let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: frame, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__mdKernel && window.__mdKernel.receive(\(Self.jsLiteral(json)));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    os_log(.error, "kernel deliver failed: %{public}@", String(describing: error))
                }
            }
        }
    }

    /// JSON 字符串 → JS 字符串字面量（含引号与转义）
    private static func jsLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}
