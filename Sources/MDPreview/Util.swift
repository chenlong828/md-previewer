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

enum ImagePathRewriter {
    /// 宽松捕获 `![alt](inner)`:inner 惰性匹配到第一个 `)`,允许一层平衡括号
    /// (如 `file(1).png`);alt 内不允许 `]`(与 CommonMark 一致的既有限制)
    private static let imagePattern = try! NSRegularExpression(
        pattern: "(!\\[[^\\]]*\\]\\()((?:[^()]|\\([^()]*\\))*?)\\)",
        options: [])

    /// inner 尾部带引号标题:`path "title"` 或 `path 'title'`
    private static let titlePattern = try! NSRegularExpression(
        pattern: "^\\s*(.*?)\\s+(\"[^\"]*\"|'[^']*')\\s*$",
        options: [])

    /// 对一行内所有 `![alt](path "title")` 应用 transform,重组整行。
    /// transform 返回 nil 表示「不必改写」,整段保持原文(不做无害重组,
    /// 避免把 `<带空格路径>` 等合法写法规范化掉)。
    private static func replaceImages(
        in line: String, transform: (_ rawPath: String, _ title: String) -> String?
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
            let innerRange = match.range(at: 2)
            guard let inner = splitInner(ns.substring(with: innerRange)) else { continue }
            guard let newPath = transform(inner.path, inner.title) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            result += ns.substring(with: match.range(at: 1))
            result += wrappedIfNeeded(newPath)
            if !inner.title.isEmpty { result += " \"\(inner.title)\"" }
            result += ")"
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// 拆 inner 为 (path, title):`<>` 包裹目的地优先,其次尾部引号标题,
    /// 否则整体为路径(可含空格)。解析不出合法形态返回 nil(保持原文)。
    static func splitInner(_ inner: String) -> (path: String, title: String)? {
        let s = inner
        if s.hasPrefix("<") {
            guard let close = s.firstIndex(of: ">") else { return nil }
            let path = String(s[s.index(after: s.startIndex)..<close])
            if path.isEmpty { return nil }
            let rest = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return (path, "") }
            guard let title = unquoted(rest) else { return nil }
            return (path, title)
        }
        if let m = titlePattern.firstMatch(
            in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)),
           m.range(at: 1).location != NSNotFound, m.range(at: 2).location != NSNotFound {
            let ns = s as NSString
            let path = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let title = unquoted(ns.substring(with: m.range(at: 2))) ?? ""
            guard !path.isEmpty else { return nil }
            return (path, title)
        }
        let path = s.trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : (path, "")
    }

    /// 剥掉成对引号;非纯引号串返回 nil
    private static func unquoted(_ s: String) -> String? {
        guard s.count >= 2 else { return nil }
        let first = s.first!, last = s.last!
        guard first == last, first == "\"" || first == "'" else { return nil }
        return String(s.dropFirst().dropLast())
    }

    // MARK: load / save

    static func forLoad(_ markdown: String, baseURL: URL) -> String {
        mapLinesOutsideFences(markdown) { line in
            replaceImages(in: line) { rawPath, _ in
                resolveForLoad(rawPath, baseURL: baseURL)
            }
        }
    }

    static func forSave(_ markdown: String, baseURL: URL) -> String {
        mapLinesOutsideFences(markdown) { line in
            replaceImages(in: line) { rawPath, _ in
                resolveForSave(rawPath, baseURL: baseURL)
            }
        }
    }

    // MARK: 引用收集(资源清理判定用)

    /// 收集文档内所有能指向本地文件的图片引用(文件系统绝对路径集合,
    /// 已做路径规范化),供 ImageStore 关闭清理判定「被引用」。行规则与
    /// 图片语法解析与改写器共用同一实现(围栏内不算引用),不复制第二份。
    /// 引用形态按两种口径都算保护,宁多保护不误删:
    /// - 改写器口径:目的地原样(含字面 %XX、./ 前缀),文件真实存在;
    /// - CommonMark 口径:目的地按 %XX 解码后指向的另一真实文件。
    static func referencedLocalImagePaths(in markdown: String, baseURL: URL) -> Set<String> {
        var paths = Set<String>()
        mapLinesOutsideFences(markdown) { line in
            replaceImages(in: line) { rawPath, _ in
                let trimmed = rawPath.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("file://") {
                    paths.insert(percentDecodedPath(String(trimmed.dropFirst("file://".count))).standardizedFilePath)
                } else if !isRemoteDestination(trimmed) {
                    if let resolved = resolveForLoad(rawPath, baseURL: baseURL),
                       let url = URL(string: resolved), url.isFileURL {
                        paths.insert(url.standardizedFileURL.path)
                    }
                    let absPath = trimmed.hasPrefix("/")
                        ? trimmed
                        : baseURL.appendingPathComponent(trimmed).path
                    for candidate in [absPath, percentDecodedPath(absPath)] {
                        if FileManager.default.fileExists(atPath: candidate) {
                            paths.insert(candidate.standardizedFilePath)
                        }
                    }
                }
                return nil
            }
            return line
        }
        return paths
    }

    /// file:// 之后的部分 → 文件系统路径:手工分段百分号解码。
    /// 不用 URL(string:):实测(2026-10-20,selftest 资源清理用例)它对
    /// 「未编码非 ASCII + 合法 %XX 混排」会把合法 %XX 再转义成 %25XX
    /// (%20→%2520),解码后与真实文件名错位;分段解码对已编码/未编码/
    /// 文件名含字面 % 三种形态都得到正确路径。
    private static func percentDecodedPath(_ afterScheme: String) -> String {
        afterScheme.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.removingPercentEncoding ?? String($0) }
            .joined(separator: "/")
    }

    // MARK: helpers

    private static func wrappedIfNeeded(_ path: String) -> String {
        path.contains(" ") || path.contains("(") || path.contains(")")
            ? "<\(path)>" : path
    }

    /// 远程/数据/锚点/空目的地:不参与本地路径改写,也不算本地文件引用。
    /// scheme 规则的唯一来源,resolveForLoad 与引用收集器共用。
    private static func isRemoteDestination(_ trimmed: String) -> Bool {
        trimmed.isEmpty || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("data:") || trimmed.hasPrefix("#")
    }

    /// 相对/根相对路径 → 绝对 file:// URL(百分号编码,空格→%20,
    /// 消除 CommonMark 目的地不容空格的问题)。远程/data/锚点/缺失文件
    /// 返回 nil,原文保持不动。
    private static func resolveForLoad(_ raw: String, baseURL: URL) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if isRemoteDestination(trimmed) || trimmed.hasPrefix("file://") {
            return nil
        }
        let abs: URL
        if trimmed.hasPrefix("/") {
            abs = URL(fileURLWithPath: trimmed)
        } else {
            abs = baseURL.appendingPathComponent(trimmed)
        }
        // 文件不存在则保持原文(交由编辑器显示为破图或纯文本)
        return FileManager.default.fileExists(atPath: abs.path) ? abs.absoluteString : nil
    }

    /// file:// URL → 文档目录内相对路径(保留原始空格写法);
    /// 目录外的绝对路径保留绝对写法(空格/括号由 wrappedIfNeeded 包裹)。
    private static func resolveForSave(_ raw: String, baseURL: URL) -> String? {
        guard raw.hasPrefix("file://") else { return nil }
        // 与 referencedLocalImagePaths 同一解码口径:URL(string:) 对混排
        // 内容会再转义合法 %XX(见 percentDecodedPath 注释)
        let path = percentDecodedPath(String(raw.dropFirst("file://".count)))
        let base = baseURL.path
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return path
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

private extension String {
    /// 文件系统路径规范化(消解 ./ 与冗余段),与资源目录列举路径同口径比较
    var standardizedFilePath: String {
        URL(fileURLWithPath: self).standardizedFileURL.path
    }
}
