// 临时对拍工具（不属于产品代码）：用现行 Swift 实现（Sources/MDPreview/Util.swift）
// 为给定用例产出 forLoad / forSave / referencedLocalImagePaths 的黄金输出。
// 用法：swiftc Sources/MDPreview/Util.swift tools/semantics-dump/main.swift -o /tmp/semantics-dump
//       /tmp/semantics-dump < cases.json > golden.json
// 迁移完成后本目录随之删除（语义单点在内核 semantics）。
import Foundation

struct DumpCase: Decodable {
    let name: String
    let md: String
    let files: [String]
}

struct DumpInput: Decodable {
    let cases: [DumpCase]
}

struct DumpOutCase: Encodable {
    let name: String
    let md: String
    let files: [String]
    let forLoad: String
    let forSave: String
    let refs: [String]
}

struct DumpOutput: Encodable {
    let cases: [DumpOutCase]
}

let raw = FileHandle.standardInput.readDataToEndOfFile()
let input = try JSONDecoder().decode(DumpInput.self, from: raw)

let base = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("semantics-dump-\(UUID().uuidString)")
    .resolvingSymlinksInPath()
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

func materialize(_ relPath: String) throws {
    let file = base.appendingPathComponent(relPath)
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
}

var out: [DumpOutCase] = []
for item in input.cases {
    for rel in item.files { try materialize(rel) }
    let md = item.md.replacingOccurrences(of: "$BASE", with: base.path)
    let forLoad = ImagePathRewriter.forLoad(md, baseURL: base)
    let forSave = ImagePathRewriter.forSave(md, baseURL: base)
    let refs = ImagePathRewriter.referencedLocalImagePaths(in: md, baseURL: base).sorted()
    let rebased = refs.map { $0.replacingOccurrences(of: base.path, with: "$BASE") }
    let rebaseText: (String) -> String = { $0.replacingOccurrences(of: base.path, with: "$BASE") }
    out.append(DumpOutCase(
        name: item.name, md: item.md, files: item.files,
        forLoad: rebaseText(forLoad), forSave: rebaseText(forSave), refs: rebased))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(DumpOutput(cases: out))
FileHandle.standardOutput.write(data)
