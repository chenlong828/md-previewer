import Foundation
import UniformTypeIdentifiers

/// 文档种类：决定同一窗口走哪条装载/渲染路径。
/// - markdown：Milkdown 所见即所得（可编辑、可保存、有脏标记）
/// - code：只读高亮源码视图（无脏标记、无保存）
enum DocumentKind: Equatable {
    case markdown
    case code(language: String)
}

/// 一个可高亮的代码语言。`id` 与 web 侧语法表（`web/src/languages.js`）是同一标识，
/// 由 selftest 的「双端语言清单一致」断言守门。
struct CodeLanguage: Equatable {
    let id: String
    let displayName: String
    let extensions: [String]
}

/// 文件种类与代码语言的**唯一来源**：打开面板、抽屉过滤、文档内链接拦截、
/// 打开分派、高亮语言菜单、Info.plist 一致性断言都从这里派生。
/// 新增语言只改 `codeLanguages` + web 语法注册表，不在别处复制清单。
enum FileSupport {
    /// Markdown 扩展名（原 AppDelegate.markdownExtensions，全仓单点）
    static let markdownExtensions = ["md", "markdown", "mdown", "mkdn", "mdtext", "mdwn"]

    /// 「高亮语言」菜单的两个伪 id：auto = 按扩展名，plaintext = 关闭高亮。
    /// 两者都不进入扩展名映射，也不会由 `kind(for:)` 返回。
    static let autoLanguageID = "auto"
    static let plainTextID = "plaintext"

    /// 代码语言表。扩展名小写、不带点；同一扩展名只允许归属一个语言
    /// （`h` 归 C，`mm` 归 Objective-C）。
    static let codeLanguages: [CodeLanguage] = [
        CodeLanguage(id: "swift", displayName: "Swift", extensions: ["swift"]),
        CodeLanguage(id: "objectivec", displayName: "Objective-C", extensions: ["m", "mm"]),
        CodeLanguage(id: "c", displayName: "C", extensions: ["c", "h"]),
        CodeLanguage(id: "cpp", displayName: "C++", extensions: ["cpp", "cc", "cxx", "hpp", "hxx", "hh"]),
        CodeLanguage(id: "csharp", displayName: "C#", extensions: ["cs"]),
        CodeLanguage(id: "java", displayName: "Java", extensions: ["java"]),
        CodeLanguage(id: "kotlin", displayName: "Kotlin", extensions: ["kt", "kts"]),
        CodeLanguage(id: "go", displayName: "Go", extensions: ["go"]),
        CodeLanguage(id: "rust", displayName: "Rust", extensions: ["rs"]),
        CodeLanguage(id: "python", displayName: "Python", extensions: ["py", "pyw"]),
        CodeLanguage(id: "ruby", displayName: "Ruby", extensions: ["rb"]),
        CodeLanguage(id: "php", displayName: "PHP", extensions: ["php"]),
        CodeLanguage(id: "javascript", displayName: "JavaScript", extensions: ["js", "mjs", "cjs"]),
        CodeLanguage(id: "typescript", displayName: "TypeScript", extensions: ["ts", "mts", "cts"]),
        CodeLanguage(id: "jsx", displayName: "JSX", extensions: ["jsx"]),
        CodeLanguage(id: "tsx", displayName: "TSX", extensions: ["tsx"]),
        CodeLanguage(id: "dart", displayName: "Dart", extensions: ["dart"]),
        CodeLanguage(id: "scala", displayName: "Scala", extensions: ["scala", "sc"]),
        CodeLanguage(id: "haskell", displayName: "Haskell", extensions: ["hs"]),
        CodeLanguage(id: "elixir", displayName: "Elixir", extensions: ["ex", "exs"]),
        CodeLanguage(id: "lua", displayName: "Lua", extensions: ["lua"]),
        CodeLanguage(id: "perl", displayName: "Perl", extensions: ["pl", "pm"]),
        CodeLanguage(id: "r", displayName: "R", extensions: ["r"]),
        CodeLanguage(id: "bash", displayName: "Shell", extensions: ["sh", "bash", "zsh", "ksh"]),
        CodeLanguage(id: "powershell", displayName: "PowerShell", extensions: ["ps1", "psm1", "psd1"]),
        CodeLanguage(id: "sql", displayName: "SQL", extensions: ["sql"]),
        CodeLanguage(id: "html", displayName: "HTML", extensions: ["html", "htm", "xhtml"]),
        CodeLanguage(id: "xml", displayName: "XML", extensions: ["xml", "plist", "svg", "xsd", "xsl", "xslt"]),
        CodeLanguage(id: "css", displayName: "CSS", extensions: ["css"]),
        CodeLanguage(id: "scss", displayName: "SCSS", extensions: ["scss"]),
        CodeLanguage(id: "sass", displayName: "Sass", extensions: ["sass"]),
        CodeLanguage(id: "less", displayName: "Less", extensions: ["less"]),
        CodeLanguage(id: "json", displayName: "JSON", extensions: ["json"]),
        CodeLanguage(id: "yaml", displayName: "YAML", extensions: ["yaml", "yml"]),
        CodeLanguage(id: "toml", displayName: "TOML", extensions: ["toml"]),
        CodeLanguage(id: "ini", displayName: "INI", extensions: ["ini", "cfg", "conf"]),
        CodeLanguage(id: "diff", displayName: "Diff", extensions: ["diff", "patch"]),
        CodeLanguage(id: "graphql", displayName: "GraphQL", extensions: ["graphql", "gql"]),
        CodeLanguage(id: "protobuf", displayName: "Protocol Buffers", extensions: ["proto"]),
        CodeLanguage(id: "groovy", displayName: "Groovy", extensions: ["groovy", "gradle"]),
        CodeLanguage(id: "docker", displayName: "Dockerfile", extensions: ["dockerfile"]),
        CodeLanguage(id: "makefile", displayName: "Makefile", extensions: ["mk"]),
        CodeLanguage(id: "cmake", displayName: "CMake", extensions: ["cmake"]),
        CodeLanguage(id: "vim", displayName: "Vim script", extensions: ["vim"]),
    ]

    /// 扩展名 → 语言 id（初始化时展开一次，运行期只读）。
    private static let extensionToLanguage: [String: String] = {
        var map: [String: String] = [:]
        for language in codeLanguages {
            for ext in language.extensions {
                map[ext.lowercased()] = language.id
            }
        }
        return map
    }()

    /// Markdown 文档类型（保存面板与 Info.plist 断言用）
    static let markdownUTTypes: [UTType] = {
        var types: [UTType] = []
        for ext in markdownExtensions {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types.isEmpty ? [.plainText] : types
    }()

    /// 打开面板允许的类型：Markdown + 代码扩展名。
    /// 用 `conformingTo: .sourceCode` 构造：直接 `UTType(filenameExtension:)` 会把
    /// `ts` 误判成 `public.mpeg-2-transport-stream`，且 `go`/`rs`/`kt` 等无系统声明
    /// 的扩展名只有带 conformance 才能得到可匹配的 dynamic 类型（2026-11-04 实测）。
    static let openableUTTypes: [UTType] = {
        var types = markdownUTTypes
        for ext in extensionToLanguage.keys.sorted() {
            guard let type = UTType(filenameExtension: ext, conformingTo: .sourceCode) else { continue }
            if !types.contains(type) { types.append(type) }
        }
        return types
    }()

    // MARK: - 判定

    /// 文件 → 文档种类。扩展名大小写不敏感；未知扩展名返回 nil（调用方拒绝装载，
    /// 不按 Markdown 解析——后者会把代码当 md 渲染成一段纯文本）。
    static func kind(for url: URL) -> DocumentKind? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if markdownExtensions.contains(ext) { return .markdown }
        if let id = extensionToLanguage[ext] { return .code(language: id) }
        return nil
    }

    static func isOpenable(_ url: URL) -> Bool {
        kind(for: url) != nil
    }

    /// 语言显示名；未知 id 原样返回（不编造）。
    static func displayName(forLanguageID id: String) -> String {
        if id == autoLanguageID { return "自动" }
        if id == plainTextID { return "纯文本" }
        return codeLanguages.first { $0.id == id }?.displayName ?? id
    }

    /// 有效语言：手动选择优先；未选择时用扩展名推导的语言。
    static func effectiveLanguage(automatic: String, override: String?) -> String {
        override ?? automatic
    }
}
