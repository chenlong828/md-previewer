import AppKit
import UniformTypeIdentifiers

/// 左侧文件抽屉:头部(目录名 + 刷新)+ 大纲视图树形目录。
/// 契约:load(root:) 装入扫描根;onOpenFile(URL) 双击 md 文件回调;
/// select(url:) 高亮定位当前文档;reload() 重扫。
/// 树数据是 DirectoryTree 的展示投影(权威在磁盘),lazy 按层装载:
/// 展开未装载目录时拦截展开 → 后台 readdir 下一层 → 回填并续展;
/// 选中定位走同步装载链(低频动作,本地 readdir 每层毫秒级)。
final class FileDrawerView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// 抽屉固定宽度(窗口伸出/收敛计算与布局共用同一出处)
    static let width: CGFloat = 240

    /// 双击 md 文件回调(唯一对外动作;文件夹双击只切换展开)
    var onOpenFile: ((URL) -> Void)?

    /// 当前扫描根(目录模式 = 打开的目录;文件模式 = 文档所在目录)
    private(set) var rootURL: URL?
    private var root: DirectoryTree.Node?
    /// 当前高亮的文档 url(rescan 后保持选中)
    private var selectedURL: URL?
    /// 展开态记忆(按目录路径;重扫重建树后恢复,惰性续读到磁盘现状)
    private var expandedPaths = Set<String>()
    /// 根层扫描代际:后台扫描完成回主线程时只应用最新一代,过期结果丢弃
    private var scanGeneration = 0
    /// 展开被拦截、等待后台装载后续展的目录路径
    private var pendingExpandPaths = Set<String>()

    private let headerBackground = NSVisualEffectView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let refreshButton: NSButton
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")!,
                                 target: nil, action: nil)
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        wantsLayer = true
        setAccessibilityIdentifier("fileDrawer")

        // 侧栏底色与底部状态栏同材质(withinWindow 不挖穿窗口)
        headerBackground.material = .titlebar
        headerBackground.blendingMode = .withinWindow
        headerBackground.state = .active
        headerBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBackground)

        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.cell?.truncatesLastVisibleLine = true
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBackground.addSubview(headerLabel)

        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        refreshButton.isBordered = false
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.toolTip = "重新扫描文件夹"
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        headerBackground.addSubview(refreshButton)

        // 大纲视图:sourceList 圆角选中样式,系统图标自动适配深浅色
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = 14
        outlineView.rowSizeStyle = .default
        outlineView.autoresizesOutlineColumn = true
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.setAccessibilityIdentifier("fileDrawerOutline")

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // 空态提示(根目录没有可展示内容时显示)
        emptyLabel.stringValue = ""
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerBackground.topAnchor.constraint(equalTo: topAnchor),
            headerBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBackground.heightAnchor.constraint(equalToConstant: 28),

            headerLabel.leadingAnchor.constraint(equalTo: headerBackground.leadingAnchor, constant: 10),
            headerLabel.centerYAnchor.constraint(equalTo: headerBackground.centerYAnchor),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8),

            refreshButton.trailingAnchor.constraint(equalTo: headerBackground.trailingAnchor, constant: -6),
            refreshButton.centerYAnchor.constraint(equalTo: headerBackground.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerBackground.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 40),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    // MARK: - 装载与刷新

    /// 装入扫描根并立即装载根层(抽屉展开/切换根目录的入口);
    /// 同根重复调用等价 rescan;换根时展开态与选中记忆重置(旧根的状态不再有意义)
    func load(root newRoot: URL) {
        let target = newRoot.standardizedFileURL
        if target == rootURL {
            rescan()
            return
        }
        rootURL = target
        expandedPaths.removeAll()
        selectedURL = nil
        rescan()
    }

    /// 重扫(唯一刷新动作):重读根层;已展开目录的子层在恢复展开时按需重读
    /// (lazy 语义下刷新即"回到磁盘现状",不做全量深扫)。后台扫描 + 代际校验。
    func rescan() {
        guard let rootURL else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let url = rootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let node = try? DirectoryTree.scanLevel(of: url)
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return } // 过期扫描丢弃
                self.apply(node: node, rootURL: url)
            }
        }
    }

    /// 应用根层扫描结果:重建模型、恢复展开(惰性续读)、刷新头部与空态、恢复选中
    private func apply(node: DirectoryTree.Node?, rootURL: URL) {
        captureExpandedPaths()
        root = node
        outlineView.reloadData()
        if let node {
            outlineView.expandItem(node) // 根恒展开(根层已装载)
            expandRememberedChildren(of: node)
        }
        headerLabel.stringValue = rootURL.lastPathComponent
        let isEmpty = node?.children.isEmpty ?? true
        emptyLabel.stringValue = node == nil ? "文件夹不可读" : (isEmpty ? "无 Markdown 文件" : "")
        if let selectedURL { select(url: selectedURL) }
    }

    /// 恢复记忆中的展开目录:仅一层触发展开,子层装载完成后由 attach 续展
    private func expandRememberedChildren(of node: DirectoryTree.Node) {
        for child in node.children where child.isFolder {
            if expandedPaths.contains(child.url.standardizedFileURL.path) {
                outlineView.expandItem(child) // 未装载 → shouldExpand 拦截 → 后台装载续展
            }
        }
    }

    /// 从当前大纲视图收集展开中的目录路径(rescan 前调用,重建后恢复)
    private func captureExpandedPaths() {
        expandedPaths.removeAll()
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? DirectoryTree.Node,
                  item.isFolder, outlineView.isItemExpanded(item) else { continue }
            expandedPaths.insert(item.url.standardizedFileURL.path)
        }
    }

    // MARK: - 按层装载(lazy 核心)

    /// 异步装载目录子层:完成回主线程回填;重复装载/已装载静默幂等
    private func loadLevelAsync(_ node: DirectoryTree.Node) {
        guard !node.childrenLoaded else { return }
        let url = node.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let level = try? DirectoryTree.scanLevel(of: url)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.attachChildren(from: level, to: node)
                // 若装载期间该节点被同步装载(select 链),此处幂等跳过
            }
        }
    }

    /// 同步装载目录子层(选中定位用):本地 readdir 每层毫秒级,低频动作可接受
    private func loadLevelSync(_ node: DirectoryTree.Node) {
        guard !node.childrenLoaded, let level = try? DirectoryTree.scanLevel(of: node.url) else { return }
        attachChildren(from: level, to: node)
    }

    /// 回填子层:替换 children、标记已装载、刷新该节点并续展挂起的展开/记忆展开
    private func attachChildren(from level: DirectoryTree.Node?, to node: DirectoryTree.Node) {
        guard !node.childrenLoaded else { return }
        node.children = level?.children ?? []
        for child in node.children { child.parent = node }
        node.childrenLoaded = true
        outlineView.reloadItem(node, reloadChildren: true)
        // 续展:用户点击触发的挂起展开 + 记忆中的展开态(逐层惰性续读)
        let path = node.url.standardizedFileURL.path
        let shouldReveal = pendingExpandPaths.remove(path) != nil
        if shouldReveal {
            outlineView.expandItem(node)
        }
        for child in node.children where child.isFolder {
            if expandedPaths.contains(child.url.standardizedFileURL.path) {
                outlineView.expandItem(child)
            }
        }
    }

    // MARK: - 选中同步

    /// 高亮并滚动到指定文档行(打开文件后由控制器调用)。
    /// lazy 下先沿路径同步装载祖先链(缺层即读),再展开选中;找不到时静默。
    func select(url: URL) {
        selectedURL = url
        guard let root else { return }
        let target = url.standardizedFileURL
        let rootPath = root.url.standardizedFileURL.path
        guard target.path.hasPrefix(rootPath + "/") || target.path == rootPath else { return }
        // 根 → 文件所在目录 的节点链(按路径段逐层同步装载)
        var chain: [DirectoryTree.Node] = []
        var cursor = root
        let segments = target.path.dropFirst(rootPath.count)
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for name in segments.dropLast() { // 最后一段是文件本身
            loadLevelSync(cursor)
            guard let next = cursor.children.first(where: { $0.isFolder && $0.name == name }) else { return }
            chain.append(next)
            cursor = next
        }
        loadLevelSync(cursor) // 文件所在目录层
        for node in chain { outlineView.expandItem(node) }
        guard let fileNode = cursor.children.first(where: { !$0.isFolder && $0.url.standardizedFileURL == target }) else {
            return
        }
        let row = outlineView.row(forItem: fileNode)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? DirectoryTree.Node ?? root else { return 0 }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? DirectoryTree.Node ?? root!
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // lazy:目录恒可展开(是否为空要展开读了才知道),文件不可展开
        (item as? DirectoryTree.Node)?.isFolder == true
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, shouldExpand item: Any) -> Bool {
        guard let node = item as? DirectoryTree.Node, node.isFolder else { return true }
        guard !node.childrenLoaded else { return true }
        // 拦截展开:后台装载完成后续展(点击路径不阻塞主线程)
        pendingExpandPaths.insert(node.url.standardizedFileURL.path)
        loadLevelAsync(node)
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? DirectoryTree.Node else { return nil }
        let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("drawerCell"), owner: nil)
            as? NSTableCellView ?? {
                let cell = NSTableCellView()
                cell.identifier = NSUserInterfaceItemIdentifier("drawerCell")
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                let text = NSTextField(labelWithString: "")
                text.font = .systemFont(ofSize: 12)
                text.lineBreakMode = .byTruncatingTail
                text.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyDown
                cell.imageView = icon
                cell.textField = text
                cell.addSubview(icon)
                cell.addSubview(text)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }()
        cell.textField?.stringValue = node.name
        // 系统图标:文件夹用 UTType.folder 通用图标,md 文件按真实文件取(深浅色自动适配)
        cell.imageView?.image = node.isFolder
            ? NSWorkspace.shared.icon(for: UTType.folder)
            : NSWorkspace.shared.icon(forFile: node.url.path)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        22
    }

    // MARK: - 诊断/自检入口(与 webViewIfNeeded/evaluateForDiagnostics 同口径的受控暴露)

    /// 当前大纲行数(自检等待树装载完成)
    var rowCountForDiagnostics: Int { outlineView.numberOfRows }

    /// 当前**已装载**子树中是否包含指定文件(lazy:未装载层不在判定范围)
    func debugTreeContains(_ url: URL) -> Bool {
        root?.descendant(at: url) != nil
    }

    /// 模拟双击打开指定文件:走 doubleClicked 同一回调路径(onOpenFile → 控制器 openDocument)
    func debugOpenByDoubleClick(url: URL) {
        guard let node = root?.descendant(at: url) else { return }
        for ancestor in Self.ancestorChain(of: node) where ancestor.isFolder {
            outlineView.expandItem(ancestor)
        }
        onOpenFile?(node.url)
    }

    private static func ancestorChain(of node: DirectoryTree.Node) -> [DirectoryTree.Node] {
        var chain: [DirectoryTree.Node] = []
        var cursor = node.parent
        while let parent = cursor {
            chain.append(parent)
            cursor = parent.parent
        }
        return chain.reversed()
    }

    // MARK: - 动作

    @objc private func refreshAction() {
        rescan()
    }

    /// 双击行:md 文件 → 回调打开(同窗口覆盖);文件夹 → 切换展开
    @objc private func doubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? DirectoryTree.Node else { return }
        if node.isFolder {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            onOpenFile?(node.url)
        }
    }
}
