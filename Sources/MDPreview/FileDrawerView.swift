import AppKit
import UniformTypeIdentifiers

/// 左侧文件抽屉:头部(目录名 + 刷新)+ 大纲视图树形目录。
/// 契约:load(root:) 装入扫描根;onOpenFile(URL) 双击 md 文件回调;
/// select(url:) 高亮定位当前文档;reload() 重扫磁盘。
/// 树数据是 DirectoryTree 的展示投影(权威在磁盘),刷新动作单点在 rescan。
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
    /// 展开态记忆(按目录路径;rescan 重建树后恢复)
    private var expandedPaths = Set<String>()
    /// 扫描代际:后台扫描完成回主线程时只应用最新一代,过期结果丢弃
    private var scanGeneration = 0

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

        // 空态提示(根目录没有可展示 md / 尚无目录时显示)
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

    /// 装入扫描根并立即扫描(抽屉展开/切换根目录的入口);
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

    /// 重扫磁盘(唯一刷新动作):后台扫描 + 代际校验,回主线程应用
    func rescan() {
        guard let rootURL else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let url = rootURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let node = try? DirectoryTree.scan(root: url)
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return } // 过期扫描丢弃
                self.apply(node: node, rootURL: url)
            }
        }
    }

    /// 应用扫描结果:重建模型、恢复展开态与选中、刷新头部与空态
    private func apply(node: DirectoryTree.Node?, rootURL: URL) {
        captureExpandedPaths()
        root = node
        outlineView.reloadData()
        // 根恒展开;其余恢复记忆中的展开目录(只恢复仍存在的)
        if let node {
            outlineView.expandItem(node)
            expandRememberedFolders(node)
        }
        headerLabel.stringValue = rootURL.lastPathComponent
        let isEmpty = node?.children.isEmpty ?? true
        emptyLabel.stringValue = node == nil ? "文件夹不可读" : (isEmpty ? "无 Markdown 文件" : "")
        if let selectedURL { select(url: selectedURL) }
    }

    private func expandRememberedFolders(_ node: DirectoryTree.Node) {
        guard node.isFolder else { return }
        if expandedPaths.contains(node.url.standardizedFileURL.path) {
            outlineView.expandItem(node)
        }
        for child in node.children where child.isFolder {
            expandRememberedFolders(child)
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

    // MARK: - 选中同步

    /// 高亮并滚动到指定文档行(打开文件后由控制器调用);找不到时静默
    func select(url: URL) {
        selectedURL = url
        guard let node = root?.descendant(at: url) else { return }
        expandAncestors(of: node)
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    private func expandAncestors(of node: DirectoryTree.Node) {
        var chain: [DirectoryTree.Node] = []
        var cursor: DirectoryTree.Node? = node.parent
        while let parent = cursor {
            chain.append(parent)
            cursor = parent.parent
        }
        for ancestor in chain.reversed() where ancestor.isFolder {
            outlineView.expandItem(ancestor)
        }
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
        (item as? DirectoryTree.Node)?.isFolder == true
    }

    // MARK: - NSOutlineViewDelegate

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

    /// 当前树中是否包含指定文件(自检断言目录内容正确性,如真实仓库的 doc/ 是否在树)
    func debugTreeContains(_ url: URL) -> Bool {
        root?.descendant(at: url) != nil
    }

    /// 模拟双击打开指定文件:走 doubleClicked 同一回调路径(onOpenFile → 控制器 openDocument)
    func debugOpenByDoubleClick(url: URL) {
        guard let node = root?.descendant(at: url) else { return }
        expandAncestors(of: node)
        onOpenFile?(node.url)
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
