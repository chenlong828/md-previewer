import Foundation

// MARK: - 文本读取(编码探测)

enum TextFile {
    /// 读取文本文件:优先 UTF-8,失败时回退 GB18030(中文环境友好)
    static func read(at url: URL) -> (text: String, encodingName: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.isEmpty { return ("", "UTF-8") }
        if let s = String(data: data, encoding: .utf8) {
            return (s, "UTF-8")
        }
        let gbEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gbEncoding)) {
            return (s, "GB18030")
        }
        // 最后兜底:损失性解码
        return (String(decoding: data, as: UTF8.self), "UTF-8(有损)")
    }

    static func write(_ text: String, to url: URL) throws {
        var out = text
        if !out.hasSuffix("\n") { out += "\n" }
        try out.data(using: .utf8)?.write(to: url, options: [.atomic])
    }
}

// MARK: - 本地图片路径改写
// 所见即所得渲染需要绝对可访问的图片 URL;保存时还原为原文写法。
// 解析刻意宽松(仿 Typora):允许目的地里出现空格与一层平衡括号——
// wechat-offline 等工具导出的文档常写 `![a](dir with space/img.jpg)`,
// 严格 CommonMark 会把这行判成纯文本,改写器必须先于解析器接住它。
// 只处理围栏代码块之外的行,避免破坏代码示例。

enum JSArgs {
    /// 将字符串安全地编码为 JS 字面量(JSON + U+2028/2029 转义)
    static func string(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        var json = String(data: data ?? Data(), encoding: .utf8) ?? "\"\""
        json = json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return json
    }
}

// MARK: - 资源定位(编辑器与自检共用,全仓唯一 #filePath 依赖点)

enum WebLocator {
    /// 编辑器页面入口:打包后取 Bundle 资源,开发模式(swift run)回退仓库内 web/dist
    static func indexURL() -> URL? {
        if let res = Bundle.main.resourceURL {
            let u = res.appendingPathComponent("web/index.html")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        let repo = repoRootURL()?.appendingPathComponent("web/dist/index.html")
        return repo.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// 仓库根目录(仅开发模式有意义;由本文件路径上溯三级,全仓唯一的 #filePath 用点)
    static func repoRootURL() -> URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 仓库内 resources/Info.plist(仅 selftest 一致性断言使用)
    static func repoInfoPlistURL() -> URL? {
        repoRootURL()?.appendingPathComponent("resources/Info.plist")
    }
}

private extension String {
    /// 文件系统路径规范化(消解 ./ 与冗余段),与资源目录列举路径同口径比较
    var standardizedFilePath: String {
        URL(fileURLWithPath: self).standardizedFileURL.path
    }
}
