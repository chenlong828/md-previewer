import Foundation
import UniformTypeIdentifiers

// MARK: - 图片落盘导入
// 剪贴板截图与既有图片文件(粘贴路径/拖放/插入菜单)统一落到
// <文档目录>/resource/<md文件名>/,与 wechat-offline 导出文档的
// resource/<文章名>/img_NNN.jpg 布局一致。
// 目录与命名约定(resource/、img_NNN 序号、同名冲突后缀)只定义在此,
// 消费方(控制器)只拿结果 file:// URL,不感知约定细节。

enum ImageStore {
    /// 导入来源:剪贴板位图字节(无文件名)或既有图片文件
    enum Payload {
        case blob(Data, mime: String?)
        case file(URL)
    }

    struct Imported {
        /// 落盘后的绝对 file URL(直接作为 image 节点 src,保存时由
        /// 内核写盘口径还原为相对路径)
        let url: URL
        let fileName: String
    }

    enum ImportError: LocalizedError {
        case notAnImage
        case emptyData
        case unknownMime

        var errorDescription: String? {
            switch self {
            case .notAnImage: return "不是可识别的图片文件"
            case .emptyData: return "剪贴板中没有图片数据"
            case .unknownMime: return "无法识别的图片格式"
            }
        }
    }

    /// web 侧预筛用的扩展名提示(Swift 侧权威判定是 UTType,不依赖此表)
    static let filenameHintExtensions = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg",
        "tif", "tiff", "heic", "heif", "avif",
    ]

    static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// 导入并落盘。失败抛错,由调用方决定提示方式;文件系统错误(目录不可
    /// 列举/不可写等)一律原样抛出,绝不静默降级——序号命名依赖目录列举,
    /// 静默当空目录会让 img 序号回绕、.atomic 写盘覆盖既有图片(见 selftest
    /// 「图片落盘-不可列举目录拒绝」用例)。
    static func `import`(_ payload: Payload, docURL: URL) throws -> Imported {
        let dir = directory(for: docURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        switch payload {
        case let .blob(data, mime):
            guard !data.isEmpty else { throw ImportError.emptyData }
            let ext = extensionForMime(mime) ?? "png"
            let name = try nextSequenceName(ext: ext, in: dir)
            let target = dir.appendingPathComponent(name)
            try data.write(to: target, options: [.atomic])
            return Imported(url: target, fileName: name)
        case let .file(src):
            guard isImageFile(src), FileManager.default.fileExists(atPath: src.path) else {
                throw ImportError.notAnImage
            }
            let name = try uniqueName(prefer: src.lastPathComponent, in: dir)
            let target = dir.appendingPathComponent(name)
            try FileManager.default.copyItem(at: src, to: target)
            return Imported(url: target, fileName: name)
        }
    }

    /// 文档旁的图片资源目录:<docDir>/resource/<md文件名去扩展名>
    static func directory(for docURL: URL) -> URL {
        docURL.deletingLastPathComponent()
            .appendingPathComponent("resource", isDirectory: true)
            .appendingPathComponent(docURL.deletingPathExtension().lastPathComponent, isDirectory: true)
    }

    // MARK: 关闭清理(资源 GC)

    /// 清理资源目录里未被文档引用的图片。触发点唯一:文档关闭
    /// (windowWillClose),此刻磁盘内容是权威终态(保存/放弃决策均已完成);
    /// 撤销粘贴的孤儿文件由此在关闭时清除(撤销不立即删盘——重做会指向
    /// 已删文件变破图)。
    ///
    /// 判定:引用集合由内核提供（getResourceRefs，围栏内不算引用，两口径宁多保护）；
    /// 本函数只做「集合差 + 删盘」，不再解析 markdown。只清理 UTType 判定为图片的文件,
    /// 非图片文件(未来附件/用户手放杂物)一律不动。目录清空则连同 `resource/<md文件名>/`
    /// 移除,`resource/` 随之为空亦移除。失败原样抛错,由调用方记日志、不打断关闭。
    /// 返回被删除的文件名(供日志与自检断言)。
    @discardableResult
    static func cleanUnreferenced(docURL: URL, referenced: Set<String>) throws -> [String] {
        let dir = directory(for: docURL)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        var deleted: [String] = []
        for item in try existingFiles(in: dir) {
            let url = dir.appendingPathComponent(item)
            guard isImageFile(url) else { continue } // 非图片文件不动
            guard !referenced.contains(url.standardizedFileURL.path) else { continue }
            try FileManager.default.removeItem(at: url)
            deleted.append(item)
        }
        if try existingFiles(in: dir).isEmpty {
            try FileManager.default.removeItem(at: dir)
            let resourceRoot = dir.deletingLastPathComponent()
            if try existingFiles(in: resourceRoot).isEmpty {
                try FileManager.default.removeItem(at: resourceRoot)
            }
        }
        return deleted
    }

    // MARK: 命名

    /// 剪贴板位图命名:img_NNN.ext,序号取目录内 img_ 最大序号 +1(从 001 起)
    private static func nextSequenceName(ext: String, in dir: URL) throws -> String {
        var maxSeq = 0
        for item in try existingFiles(in: dir) {
            guard item.hasPrefix("img_"),
                  let dot = item.firstIndex(of: "."),
                  let seq = Int(item[item.index(item.startIndex, offsetBy: 4)..<dot]),
                  seq > maxSeq else { continue }
            maxSeq = seq
        }
        return String(format: "img_%03d.%@", maxSeq + 1, ext)
    }

    /// 既有文件导入命名:保留原文件名;冲突时追加 -2、-3…
    private static func uniqueName(prefer name: String, in dir: URL) throws -> String {
        let existing = Set(try existingFiles(in: dir))
        guard existing.contains(name) else { return name }
        let nsName = name as NSString
        let stem = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        var n = 2
        while existing.contains("\(stem)-\(n).\(ext)") { n += 1 }
        return "\(stem)-\(n).\(ext)"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}

/// 目录列举失败原样抛错(权限缺失等),不静默当空目录——调用方的序号/
/// 冲突命名依赖真实目录内容,静默空表会导致命名回绕、覆盖既有文件。
private func existingFiles(in dir: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path)
}

private func extensionForMime(_ mime: String?) -> String? {
    guard let mime, !mime.isEmpty else { return nil }
    // 常见位图显式映射:UTType 对 image/jpeg 给出 "jpeg",统一为更常见的 jpg
    switch mime.lowercased() {
    case "image/jpeg", "image/jpg": return "jpg"
    case "image/png": return "png"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    case "image/bmp": return "bmp"
    default: return UTType(mimeType: mime)?.preferredFilenameExtension
    }
}
