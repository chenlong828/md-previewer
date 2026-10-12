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
// 只处理围栏代码块之外的行,避免破坏代码示例。

enum ImagePathRewriter {
    private static let imagePattern = try! NSRegularExpression(
        pattern: "(!\\[[^\\]]*\\]\\()\\s*(<[^>]*>|[^)\\s]+)\\s*(\"[^\"]*\")?\\s*\\)",
        options: [])

    static func forLoad(_ markdown: String, baseURL: URL) -> String {
        mapLinesOutsideFences(markdown) { line in
            replaceImages(in: line) { rawPath, title in
                let resolved = resolveForLoad(rawPath, baseURL: baseURL)
                let titleSeg = title.isEmpty ? "" : " \"\(title)\""
                return wrappedIfNeeded(resolved) + titleSeg
            }
        }
    }

    static func forSave(_ markdown: String, baseURL: URL) -> String {
        mapLinesOutsideFences(markdown) { line in
            replaceImages(in: line) { rawPath, title in
                let restored = resolveForSave(rawPath, baseURL: baseURL)
                let titleSeg = title.isEmpty ? "" : " \"\(title)\""
                return wrappedIfNeeded(restored) + titleSeg
            }
        }
    }

    /// 对一行内所有 `![alt](path "title")` 应用 transform,重组整行
    private static func replaceImages(
        in line: String, transform: (_ rawPath: String, _ title: String) -> String
    ) -> String {
        let ns = line as NSString
        let matches = imagePattern.matches(
            in: line, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return line }
        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            guard full.location != NSNotFound, full.location + full.length <= ns.length else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            let prefix = ns.substring(with: match.range(at: 1))
            var rawPath = match.range(at: 2).location == NSNotFound
                ? "" : ns.substring(with: match.range(at: 2))
            if rawPath.hasPrefix("<") && rawPath.hasSuffix(">") {
                rawPath = String(rawPath.dropFirst().dropLast())
            }
            var title = match.range(at: 3).location == NSNotFound
                ? "" : ns.substring(with: match.range(at: 3))
            if title.hasPrefix("\"") && title.hasSuffix("\"") {
                title = String(title.dropFirst().dropLast())
            }
            result += prefix + transform(rawPath, title) + ")"
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: helpers

    private static func wrappedIfNeeded(_ path: String) -> String {
        path.contains(" ") || path.contains("(") || path.contains(")")
            ? "<\(path)>" : path
    }

    private static func resolveForLoad(_ raw: String, baseURL: URL) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty
            || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("data:") || trimmed.hasPrefix("file://")
            || trimmed.hasPrefix("#") {
            return raw
        }
        let abs: URL
        if trimmed.hasPrefix("/") {
            abs = URL(fileURLWithPath: trimmed)
        } else {
            abs = baseURL.appendingPathComponent(trimmed)
        }
        // 文件不存在则原样保留(交由编辑器显示为普通文本)
        return FileManager.default.fileExists(atPath: abs.path) ? abs.absoluteString : raw
    }

    private static func resolveForSave(_ raw: String, baseURL: URL) -> String {
        guard raw.hasPrefix("file://"), let url = URL(string: raw) else { return raw }
        let path = url.path
        let base = baseURL.path
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return path // 目录外的绝对路径保留为绝对路径
    }

    /// 逐行处理,跳过 ``` / ~~~ 围栏内的内容
    private static func mapLinesOutsideFences(
        _ markdown: String, transform: (String) -> String
    ) -> String {
        var inFence = false
        var fenceMarker: Character = "`"
        var result: [String] = []
        result.reserveCapacity(markdown.count / 32 + 8)
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inFence {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence = true
                    fenceMarker = trimmed.first ?? "`"
                    result.append(line)
                    continue
                }
                result.append(transform(line))
            } else {
                // 围栏结束行:仅由同一字符组成的行(``` / ~~~ / ````)
                if trimmed.hasPrefix(String(fenceMarker)),
                   trimmed.allSatisfy({ $0 == fenceMarker }) {
                    inFence = false
                }
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }
}

// MARK: - JS 参数安全传递

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
