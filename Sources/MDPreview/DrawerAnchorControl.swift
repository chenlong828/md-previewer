import AppKit

/// 抽屉头部的锚点控件:显示当前锚点目录(Finder 同款文件夹图标 + 名称 + 展开箭头),
/// 点击弹出父级链菜单——根 → 当前的顺序、每条带同一套文件夹图标、当前锚点勾选,
/// 并按层级逐级右移(与下方大纲树同一套「越深越右」的视觉语言)。
/// 职责单一:只负责「当前锚点」的展示与菜单交互;菜单条目来自 `DirectoryTree.ancestorChain`,
/// 选中后经 `onSelect` 交给 FileDrawerView 转发重锚,控件本身不装载目录、不改抽屉根。
/// 宽度由头部布局决定(抽屉宽减去右侧 Home/刷新两个按钮),不做固有宽度。
final class DrawerAnchorControl: NSView {
    /// 菜单条目选中回调(携带该条目目录 URL)
    var onSelect: ((URL) -> Void)?

    private enum Metrics {
        /// 药丸底与控件边界的呼吸间距(头部高 32 → 药丸高 22)
        static let pillSideInset: CGFloat = 6
        static let pillTopInset: CGFloat = 5
        static let pillCornerRadius: CGFloat = 7
        /// 药丸内左内边距:图标起点 = 头部 6pt 边距 + 本值 = 26pt,
        /// 与源列表树内文件夹图标列对齐(头部图标与树图标同一竖列)
        static let contentLeading: CGFloat = 20
        static let iconSize: CGFloat = 15
        static let titleSpacing: CGFloat = 5
        static let chevronSize: CGFloat = 10
        /// 箭头距控件右缘(pill 边距 6 + 8):箭头永远贴药丸右缘,不随名称长度移动
        static let chevronTrailingInset: CGFloat = 14
        static let chevronSpacing: CGFloat = 4
        static let menuIconSize: CGFloat = 16
        /// 菜单顶缘落在控件下沿再下移的距离(视觉上贴住药丸底部)
        static let menuOffsetBelow: CGFloat = 4
    }

    /// 药丸底三态:常态淡、悬停稍强、菜单展开最强(深浅色都靠 labelColor 透明度自适应)
    private enum PillFill {
        static let idle = 0.06
        static let hover = 0.10
        static let open = 0.14
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    /// 锚点链菜单(根 → 当前);每次 update 重建条目,控件持有唯一实例
    private let anchorMenu = NSMenu()
    private var trackingArea: NSTrackingArea?

    private var isHovering = false { didSet { needsDisplay = true } }
    private var isMenuOpen = false { didSet { needsDisplay = true } }

    /// 自绘药丸底需要翻转坐标:菜单要落在控件下沿(翻转后 y 向下增大)
    override var isFlipped: Bool { true }
    /// 自绘视图非不透明;默认会退化成「拖动窗口」,点击必须落在本控件的菜单打开逻辑上
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle // 长目录名两端保留,中间省略
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        chevronView.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.chevronSize, weight: .semibold))
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevronView)

        anchorMenu.autoenablesItems = false
        toolTip = "锚定抽屉根目录(选择父级目录)"

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Metrics.pillSideInset + Metrics.contentLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.titleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor, constant: -Metrics.chevronSpacing),

            // 箭头钉在药丸右缘:名称再长也只截断文字,不吃掉箭头
            chevronView.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.chevronTrailingInset),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: Metrics.chevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: Metrics.chevronSize),
        ])
    }

    // MARK: - 装载

    /// 装载锚点链:标签/图标取链末(当前锚点),菜单按根 → 当前顺序重建并逐级缩进
    /// (`indentationLevel` = 链上序号,图标与标题一起右移,呈现与树同构的层次递进)。
    /// 空链(尚无锚点)时整个控件隐藏,头部只剩两个按钮。
    func update(chain: [DirectoryTree.AnchorEntry]) {
        let current = chain.last
        titleLabel.stringValue = current?.name ?? ""
        iconView.image = current.map { FinderIcon.folder(at: $0.url, size: Metrics.iconSize) }
        setAccessibilityLabel(current.map { "抽屉根目录:\($0.name)" } ?? "抽屉根目录")

        anchorMenu.removeAllItems()
        for (index, entry) in chain.enumerated() {
            let item = NSMenuItem(title: entry.name, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            item.image = FinderIcon.folder(at: entry.url, size: Metrics.menuIconSize)
            item.indentationLevel = index // 根在顶层,子级逐层右移(与下方树形同构)
            item.toolTip = entry.url.path
            // 当前锚点是链末:与 Finder 路径菜单一致地打勾
            item.state = index == chain.count - 1 ? .on : .off
            anchorMenu.addItem(item)
        }
        isHidden = chain.isEmpty
        needsLayout = true
    }

    /// 锚点菜单条目数(自检断言父级链长度)
    var menuItemCount: Int { anchorMenu.items.count }

    /// 菜单条目图标齐备(自检断言「每条都带 Finder 文件夹图标」)
    var allMenuItemsHaveIcons: Bool {
        !anchorMenu.items.isEmpty && anchorMenu.items.allSatisfy { $0.image != nil }
    }

    /// 菜单条目的缩进层级(自检断言「根 → 当前逐级递进」,与树同构)
    var menuIndentationLevels: [Int] { anchorMenu.items.map(\.indentationLevel) }

    // MARK: - 菜单交互

    override func mouseDown(with event: NSEvent) {
        openMenu()
    }

    /// VoiceOver/辅助功能的主操作与鼠标点击同一入口
    override func accessibilityPerformPress() -> Bool {
        guard !anchorMenu.items.isEmpty else { return false }
        openMenu()
        return true
    }

    /// 弹出锚点菜单:贴在药丸下沿;popUp 阻塞到菜单收起,
    /// 期间与收起后各刷一次底态(菜单展开时药丸加深)
    private func openMenu() {
        guard !anchorMenu.items.isEmpty else { return }
        isMenuOpen = true
        anchorMenu.popUp(positioning: nil,
                         at: NSPoint(x: Metrics.pillSideInset, y: bounds.height + Metrics.menuOffsetBelow),
                         in: self)
        isMenuOpen = false
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onSelect?(url)
    }

    // MARK: - 悬停与绘制

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: Metrics.pillSideInset, dy: Metrics.pillTopInset)
        guard !pill.isEmpty else { return }
        let alpha = isMenuOpen ? PillFill.open : (isHovering ? PillFill.hover : PillFill.idle)
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: pill,
                     xRadius: Metrics.pillCornerRadius,
                     yRadius: Metrics.pillCornerRadius).fill()
    }
}
