import Foundation

/// 文件抽屉的树模型:lazy 按层装载——每次只读一层,展开目录时才触发下一层读取。
/// 纯函数式扫描,无持久状态——权威数据在磁盘,产出只是某一刻的投影;
/// 过滤规则(哪些文件能展示)单源复用 AppDelegate.markdownExtensions,
/// 与打开面板/Info.plist 同一处定义,不复制第二份扩展名清单。
///
/// lazy 的语义取舍:不读到子层就无法知道后代有没有 md,因此**不做**
/// 「无 md 后代目录剪枝」——所有非隐藏目录都显示(含暂无 md 的目录,
/// 展开为空),与 Finder/Typora 文件树一致;换来的是任意规模目录树的
/// 恒定开销(单层 readdir),从结构上消灭截断问题。
enum DirectoryTree {
    /// 大纲视图条目:文件夹与文件统一为节点,身份即对象身份(NSOutlineView 直用)。
    final class Node {
        /// 父节点(展开祖先链/选中定位用);根为 nil
        weak var parent: Node?
        let name: String
        let url: URL
        let isFolder: Bool
        /// 目录子层是否已装载(lazy:未装载的目录展开时触发下一层读取)
        var childrenLoaded: Bool
        var children: [Node] = []

        init(name: String, url: URL, isFolder: Bool, childrenLoaded: Bool = false) {
            self.name = name
            self.url = url
            self.isFolder = isFolder
            self.childrenLoaded = childrenLoaded
        }

        /// 按 url 定位**已装载**子树中的节点(lazy:未装载层不在此列)
        func descendant(at url: URL) -> Node? {
            if self.url.standardizedFileURL == url.standardizedFileURL { return self }
            for child in children {
                if let found = child.descendant(at: url) { return found }
            }
            return nil
        }
    }

    /// 整棵跳过的目录名(依赖目录约定,其内 README 等与文档树无关且体量巨大)
    private static let skippedDirectoryNames: Set<String> = ["node_modules"]

    /// 锚点下拉框的一条目录项(显示名 + 完整 URL)
    struct AnchorEntry {
        let name: String
        let url: URL
    }

    /// 锚点链:从文件系统根到指定目录的父级序列(末项 = 该目录自身)。
    /// 抽屉下拉框据此列出「父级目录」供重新锚定;纯路径逻辑,无 IO。
    static func ancestorChain(of url: URL) -> [AnchorEntry] {
        var chain: [AnchorEntry] = []
        var cursor = url.standardizedFileURL
        while true {
            let name = cursor.path == "/" ? "/" : cursor.lastPathComponent
            chain.append(AnchorEntry(name: name, url: cursor))
            guard cursor.path != "/" else { break }
            cursor = cursor.deletingLastPathComponent()
        }
        return chain.reversed()
    }

    /// 根目录不可读(不存在/无权限)时抛出;其余层级同样抛错,由调用方决定展示空态。
    enum ScanError: Error { case inaccessible }

    /// 装载一个目录的**单层**:立即子级 = 全部目录(未装载态)+ 可展示 md 文件。
    /// 单层 readdir,无递归——任意规模目录树开销恒定,无预算无深度限制。
    /// 跳过:隐藏条目;符号链接(防环);node_modules;包目录(.app/.bundle 等,
    /// Finder 同款不透明语义)。排序恒定:文件夹在前文件在后,各自本地化自然序。
    static func scanLevel(of url: URL) throws -> Node {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey,
                                              .isRegularFileKey, .isPackageKey],
                options: [])
        } catch {
            throw ScanError.inaccessible
        }
        let node = Node(name: url.lastPathComponent, url: url, isFolder: true, childrenLoaded: true)
        var folders: [Node] = []
        var files: [Node] = []
        for child in contents {
            if child.lastPathComponent.hasPrefix(".") { continue } // 隐藏条目(.DS_Store/.git 等)
            let values = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey])
            if values?.isSymbolicLink == true { continue } // 不跟随符号链接,杜绝环
            if values?.isDirectory == true {
                // 依赖目录与包整棵跳过(单层装载下是纯噪音过滤,不再是预算问题)
                if values?.isPackage == true { continue }
                if skippedDirectoryNames.contains(child.lastPathComponent) { continue }
                folders.append(Node(name: child.lastPathComponent, url: child, isFolder: true))
            } else if values?.isRegularFile == true, isDisplayableMarkdown(child) {
                // 文件是叶子,装载态无意义,恒标记已装载
                files.append(Node(name: child.lastPathComponent, url: child,
                                  isFolder: false, childrenLoaded: true))
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
