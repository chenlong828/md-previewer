import Foundation

/// 文件抽屉的树模型:一个根目录下「可展示的 .md 文件 + 承载它们的文件夹」。
/// 纯函数式扫描,无持久状态——权威数据在磁盘,产出只是某一刻的投影;
/// 过滤规则(哪些文件能展示)单源复用 AppDelegate.markdownExtensions,
/// 与打开面板/Info.plist 同一处定义,不复制第二份扩展名清单。
enum DirectoryTree {
    /// 大纲视图条目:文件夹与文件统一为节点,身份即对象身份(NSOutlineView 直用)。
    final class Node {
        /// 父节点(展开祖先链/选中定位用);根为 nil
        weak var parent: Node?
        let name: String
        let url: URL
        let isFolder: Bool
        var children: [Node] = []

        init(name: String, url: URL, isFolder: Bool) {
            self.name = name
            self.url = url
            self.isFolder = isFolder
        }

        /// 按 url 定位子孙节点(抽屉选中当前文档用)
        func descendant(at url: URL) -> Node? {
            if self.url.standardizedFileURL == url.standardizedFileURL { return self }
            for child in children {
                if let found = child.descendant(at: url) { return found }
            }
            return nil
        }
    }

    /// 扫描上限(防挂起的硬闸):枚举预算与递归深度。
    /// 预算按「实际枚举的条目数」计——node_modules/包目录在递归入口被整棵跳过,
    /// 其内部条目不进枚举(修复:17k 条目的 node_modules 曾把 8000 预算耗尽,
    /// readdir 顺序靠后的兄弟目录全部被截断)。20000 ≈ 大型文档库规模,
    /// 超过即截断(宁少勿卡);深度 10 覆盖一切合理文档树。
    enum Limits {
        static let maxEntries = 20000
        static let maxDepth = 10
    }

    /// 整棵跳过的目录名(依赖目录约定,其内 README 等与文档树无关且体量巨大)
    private static let skippedDirectoryNames: Set<String> = ["node_modules"]

    /// 根目录本身不可读(不存在/无权限)时抛出;子目录不可读只剪枝不报错。
    enum ScanError: Error { case inaccessible }

    /// 扫描根目录,产出只含「md 文件与其承载文件夹」的树。
    /// 剪枝规则:隐藏条目跳过;符号链接不跟随(防环);不含 md 后代的文件夹不出现;
    /// 排序恒定:文件夹在前文件在后,各自按本地化自然序。
    static func scan(root: URL) throws -> Node {
        var budget = Limits.maxEntries
        guard let node = try scanFolder(root, depth: 0, budget: &budget, isRoot: true) else {
            throw ScanError.inaccessible
        }
        return node
    }

    /// 目录递归扫描:isRoot 区分「根不可读=失败」与「子目录不可读=剪枝」。
    private static func scanFolder(
        _ url: URL, depth: Int, budget: inout Int, isRoot: Bool
    ) throws -> Node? {
        guard depth <= Limits.maxDepth, budget > 0 else { return nil }
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
                options: [])
        } catch {
            if isRoot { throw error }
            return nil
        }
        budget -= contents.count
        let node = Node(name: url.lastPathComponent, url: url, isFolder: true)
        var folders: [Node] = []
        var files: [Node] = []
        for child in contents {
            if child.lastPathComponent.hasPrefix(".") { continue } // 隐藏条目(.DS_Store/.git 等)
            let values = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey])
            if values?.isSymbolicLink == true { continue } // 不跟随符号链接,杜绝环
            if values?.isDirectory == true {
                // 依赖目录与包(.app/.bundle 等,Finder 同款不透明语义)整棵跳过:
                // 内部条目不进枚举,预算不会被体量巨大的无关子树吃掉
                if let packageValues = values, packageValues.isPackage == true { continue }
                if skippedDirectoryNames.contains(child.lastPathComponent) { continue }
                if let sub = try? scanFolder(child, depth: depth + 1, budget: &budget, isRoot: false),
                   !sub.children.isEmpty {
                    folders.append(sub)
                }
            } else if values?.isRegularFile == true, isDisplayableMarkdown(child) {
                files.append(Node(name: child.lastPathComponent, url: child, isFolder: false))
            }
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        node.children = folders + files
        for child in node.children { child.parent = node }
        return node
    }

    /// 展示过滤唯一判定点:能被本应用打开的 md 文件才进树
    private static func isDisplayableMarkdown(_ url: URL) -> Bool {
        AppDelegate.markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
