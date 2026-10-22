import AppKit

/// 左侧文件抽屉:头部(锚点控件 + 刷新)+ 大纲视图树形目录。
/// 契约:load(root:) 装入扫描根;onOpenFile(URL) 双击 md 文件回调;
/// onAnchorSelected(URL) 锚点控件重锚回调;select(url:) 高亮定位当前文档;reload() 重扫。
/// 树数据是 DirectoryTree 的展示投影(权威在磁盘),lazy 按层装载:
/// **数据源内同步装载**——NSOutlineView 展开取数(numberOfChildrenOfItem)那一刻
/// 同步 readdir 该层,展开即出子行,无拦截/无异步/无续展(AppKit 缓存时序无关);
/// 选中定位同口径(同步装载祖先链)。两者都是低频交互,本地单层 readdir 毫秒级;
/// node_modules/包已在单层跳过,无大目录单层阻塞风险。
final class FileDrawerView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// 抽屉默认宽度(首次展开的宽度;用户拖拽后以记忆宽度为准)
    static let width: CGFloat = 240
    /// 拖拽可调宽度的下界:再窄目录名与层级缩进就没有展示空间
    static let minWidth: CGFloat = 160
    /// 拖拽可调宽度的上界:抽屉过宽会挤掉正文,配合「正文最小宽」二次夹取
    static let maxWidth: CGFloat = 480
    /// 宽度记忆键(全局,与 fileDrawerVisible 同口径;非法值由读取侧回落默认)
    static let widthDefaultsKey = "fileDrawerWidth"

    /// 记忆宽度:缺失/越界一律回落默认宽度(抽屉开合动画与窗口宽度收敛以它为准)
    static var rememberedWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: widthDefaultsKey)
        return (minWidth...maxWidth).contains(stored) ? stored : width
    }

    /// 双击 md 文件回调(唯一对外动作;文件夹双击只切换展开)
    var onOpenFile: ((URL) -> Void)?
    /// 锚点控件选择回调:用户把某父级目录选为新抽屉根
    var onAnchorSelected: ((URL) -> Void)?

    /// 当前锚定目录(抽屉扫描根)
    private(set) var rootURL: URL?
    private var root: DirectoryTree.Node?
    /// 当前高亮的文档 url(rescan 后保持选中)
    private var selectedURL: URL?
    /// 展开态记忆(按目录路径;重扫重建树后恢复,子层同步装载逐级展开)
    private var expandedPaths = Set<String>()
    /// 根层扫描代际:后台扫描完成回主线程时只应用最新一代,过期结果丢弃
    private var scanGeneration = 0

    /// 头部尺寸:锚点控件与两个按钮共用同一组量,避免两处数字各自演化。
    /// 自检(drawer-test)按同一常量断言「控件宽度 = 抽屉宽 - 两个按钮 - 间距」,不复制数字
    enum HeaderMetrics {
        static let height: CGFloat = 32
        /// 刷新按钮与抽屉右缘的间距
        static let trailingInset: CGFloat = 6
        /// 锚点控件与按钮之间、按钮彼此之间的间距
        /// (控件宽度 = 抽屉宽 - Home 按钮 - 刷新按钮 - 两处间距);
        /// 两个图标按钮间留 4pt:Home 换根是有观感代价的动作,不和刷新挤到一起
        static let spacing: CGFloat = 4
        /// 图标按钮热区宽度:符号本身 16pt,补到 22pt 才好点(不小于系统侧栏按钮)
        static let buttonWidth: CGFloat = 22
    }

    private let headerBackground = NSVisualEffectView()
    /// 锚点控件:显示当前锚点(文件夹图标 + 目录名 + 展开箭头),点击弹出父级链菜单
    /// 供重新锚定;宽度铺满头部扣除 Home/刷新按钮后的剩余空间,选中项恒为当前锚点
    private let anchorControl = DrawerAnchorControl()
    private let homeButton: NSButton
    private let refreshButton: NSButton
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        homeButton = NSButton(image: NSImage(systemSymbolName: "house", accessibilityDescription: "Home 目录")!,
                              target: nil, action: nil)
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

        anchorControl.onSelect = { [weak self] url in self?.onAnchorSelected?(url) }
        anchorControl.translatesAutoresizingMaskIntoConstraints = false
        anchorControl.setAccessibilityIdentifier("drawerAnchorPopup")
        headerBackground.addSubview(anchorControl)

        homeButton.target = self
        homeButton.action = #selector(homeAction)
        homeButton.isBordered = false
        homeButton.contentTintColor = .secondaryLabelColor
        homeButton.toolTip = "回到当前用户 Home 目录"
        homeButton.translatesAutoresizingMaskIntoConstraints = false
        headerBackground.addSubview(homeButton)

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
            headerBackground.heightAnchor.constraint(equalToConstant: HeaderMetrics.height),

            // 锚点控件铺满头部扣除 Home/刷新按钮后的剩余宽度(不做固有宽度,不吃成「文字那么长」)
            anchorControl.leadingAnchor.constraint(equalTo: headerBackground.leadingAnchor),
            anchorControl.trailingAnchor.constraint(
                equalTo: homeButton.leadingAnchor, constant: -HeaderMetrics.spacing),
            anchorControl.topAnchor.constraint(equalTo: headerBackground.topAnchor),
            anchorControl.bottomAnchor.constraint(equalTo: headerBackground.bottomAnchor),

            homeButton.trailingAnchor.constraint(
                equalTo: refreshButton.leadingAnchor, constant: -HeaderMetrics.spacing),
            homeButton.centerYAnchor.constraint(equalTo: headerBackground.centerYAnchor),
            homeButton.widthAnchor.constraint(equalToConstant: HeaderMetrics.buttonWidth),

            refreshButton.trailingAnchor.constraint(
                equalTo: headerBackground.trailingAnchor, constant: -HeaderMetrics.trailingInset),
            refreshButton.centerYAnchor.constraint(equalTo: headerBackground.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: HeaderMetrics.buttonWidth),

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

    /// 应用根层扫描结果:重建模型、恢复展开(逐级同步装载)、刷新空态、恢复选中
    private func apply(node: DirectoryTree.Node?, rootURL: URL) {
        captureExpandedPaths()
        root = node
        outlineView.reloadData()
        if let node {
            outlineView.expandItem(node) // 根恒展开(根层已装载)
            expandRememberedDescendants(of: node)
        }
        rebuildAnchorMenu()
        let isEmpty = node?.children.isEmpty ?? true
        emptyLabel.stringValue = node == nil ? "文件夹不可读" : (isEmpty ? "无 Markdown 文件" : "")
        if let selectedURL { select(url: selectedURL) }
    }

    /// 恢复记忆中的展开目录:逐级展开(展开取数时同步装载该层,可继续深入)
    private func expandRememberedDescendants(of node: DirectoryTree.Node) {
        for child in node.children where child.isFolder {
            if expandedPaths.contains(child.url.standardizedFileURL.path) {
                outlineView.expandItem(child)
                expandRememberedDescendants(of: child)
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

    // MARK: - 按层装载(lazy 核心:数据源内同步)

    /// 装载目录子层(幂等):未装载即同步 readdir 该层。装载失败(无权限等)
    /// 也置为已装载且子层为空——与 Finder 空目录语义一致,避免无限重试。
    private func ensureLoaded(_ node: DirectoryTree.Node) {
        guard node.isFolder, !node.childrenLoaded else { return }
        guard let level = try? DirectoryTree.scanLevel(of: node.url) else {
            node.childrenLoaded = true
            return
        }
        node.children = level.children
        for child in node.children { child.parent = node }
        node.childrenLoaded = true
    }

    /// 定位文件节点:沿路径同步装载祖先链(缺层即读),返回(祖先链, 文件节点)
    private func locateFile(at url: URL) -> (chain: [DirectoryTree.Node], file: DirectoryTree.Node)? {
        guard let root else { return nil }
        let target = url.standardizedFileURL
        let rootPath = root.url.standardizedFileURL.path
        guard target.path.hasPrefix(rootPath + "/") || target.path == rootPath else { return nil }
        var chain: [DirectoryTree.Node] = []
        var cursor = root
        let segments = target.path.dropFirst(rootPath.count)
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for name in segments.dropLast() { // 最后一段是文件本身
            ensureLoaded(cursor)
            guard let next = cursor.children.first(where: { $0.isFolder && $0.name == name }) else { return nil }
            chain.append(next)
            cursor = next
        }
        ensureLoaded(cursor) // 文件所在目录层
        guard let file = cursor.children.first(where: { !$0.isFolder && $0.url.standardizedFileURL == target }) else {
            return nil
        }
        return (chain, file)
    }

    // MARK: - 选中同步

    /// 高亮并滚动到指定文档行(打开文件后由控制器调用);找不到时静默。
    func select(url: URL) {
        selectedURL = url
        guard let located = locateFile(at: url) else { return }
        for node in located.chain { outlineView.expandItem(node) } // 展开取数时子层已在
        let row = outlineView.row(forItem: located.file)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? DirectoryTree.Node ?? root else { return 0 }
        ensureLoaded(node) // lazy 核心:展开取数时同步装载该层
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
        // 图标与 Finder 同口径(FinderIcon 单点):文件夹按真实路径取系统图标
        // (特殊目录图标与 Finder 一致),md 文件取真实文件图标(深浅色自动适配)
        cell.imageView?.image = node.isFolder
            ? FinderIcon.folder(at: node.url, size: 16)
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

    /// 锚点菜单当前条目数(自检断言父级链长度)
    var anchorItemCountForDiagnostics: Int { anchorControl.menuItemCount }

    /// 锚点菜单每条是否都带 Finder 文件夹图标(用户可见的核心承诺,自检守门)
    var anchorMenuItemsHaveIconsForDiagnostics: Bool { anchorControl.allMenuItemsHaveIcons }

    /// 锚点菜单的缩进层级(自检断言「根 → 当前逐级递进」)
    var anchorMenuIndentationLevelsForDiagnostics: [Int] { anchorControl.menuIndentationLevels }

    /// 头部三块的对齐矩形(约束求解所用的几何;按钮 frame 含 alignmentRectInsets,
    /// 按 frame 断言会差半像素,按对齐矩形才是约束算出来的真几何)
    var headerFramesForDiagnostics: (control: NSRect, home: NSRect, refresh: NSRect) {
        (anchorControl.alignmentRect(forFrame: anchorControl.frame),
         homeButton.alignmentRect(forFrame: homeButton.frame),
         refreshButton.alignmentRect(forFrame: refreshButton.frame))
    }

    /// 模拟在锚点菜单中选择某父级目录(走 onAnchorSelected 同一回调路径)
    func debugAnchor(to url: URL) {
        onAnchorSelected?(url)
    }

    /// Home 按钮的目标目录(自检断言重锚落点)
    var homeTargetForDiagnostics: URL { homeURL }

    /// Home 按钮当前是否可用(已在 Home 时置灰;自检断言状态判断)
    var homeButtonEnabledForDiagnostics: Bool { homeButton.isEnabled }

    /// 模拟点击 Home 按钮(走 homeAction 同一路径)
    func debugHomePress() {
        homeAction()
    }

    /// 模拟用户点击三角展开指定目录(锁定 点击→取数同步装载→子行出现 全链路);
    /// 返回展开后可见的子行数(定位失败返回 -1)
    @discardableResult
    func debugExpandByClick(url: URL) -> Int {
        guard let root, let node = root.descendant(at: url), node.isFolder else { return -1 }
        outlineView.expandItem(node) // numberOfChildrenOfItem 内同步装载
        return node.children.filter { outlineView.row(forItem: $0) >= 0 }.count
    }

    /// 模拟双击打开指定文件:沿路径装载祖先链并展开,走 onOpenFile 同一回调路径
    func debugOpenByDoubleClick(url: URL) {
        guard let located = locateFile(at: url) else { return }
        for node in located.chain { outlineView.expandItem(node) }
        onOpenFile?(located.file.url)
    }

    // MARK: - 锚点控件

    /// 按当前锚点重建锚点链:标签/图标取当前锚点,菜单为根 → 当前的父级链
    /// (当前项勾选),选中即经 onAnchorSelected 重锚
    private func rebuildAnchorMenu() {
        let chain = rootURL.map { DirectoryTree.ancestorChain(of: $0) } ?? []
        anchorControl.update(chain: chain)
        homeButton.isEnabled = rootURL?.standardizedFileURL != homeURL // 已在 Home 时置灰
    }

    /// 当前用户 Home 目录(Home 按钮的回退目标)
    private var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    // MARK: - 动作

    /// Home 按钮:抽屉根切回当前用户 Home 目录(与锚点菜单选择同一重锚路径)
    @objc private func homeAction() {
        onAnchorSelected?(homeURL)
    }

    @objc private func refreshAction() {
        rescan()
    }

    /// 双击行:md 文件 → 回调打开(同窗口覆盖);文件夹 → 切换展开
    /// (展开取数时由 numberOfChildrenOfItem 同步装载,无需特判)
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
