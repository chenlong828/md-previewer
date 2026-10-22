import AppKit

/// 抽屉与编辑器之间的拖拽分隔条:透明热区横跨两侧边界,中间 1pt 竖线标示分界
/// (悬停/拖动时线条加强),光标为左右拖拽箭头。
/// 职责单一:只把「相对拖动起点的水平位移」上报出来;宽度状态、夹取区间与窗口联动
/// 归控制器(DocumentWindowController),分隔条不了解抽屉宽度语义。
final class DrawerResizeDivider: NSView {
    /// 拖动开始(控制器记录起始宽度)
    var onDragBegan: (() -> Void)?
    /// 拖动中(参数:相对拖动起点的水平位移,向右为正)
    var onDragMoved: ((CGFloat) -> Void)?
    /// 拖动结束(控制器持久化当前宽度)
    var onDragEnded: (() -> Void)?

    /// 热区半宽:边界两侧各占一半(布局以抽屉右缘为热区中心)
    static let hotZoneHalfWidth: CGFloat = 4

    private var dragStartX: CGFloat?
    private var trackingArea: NSTrackingArea?
    private var isDragging: Bool { dragStartX != nil }
    private var isHovering = false { didSet { needsDisplay = true } }

    /// 透明热区:默认会退化成「拖动窗口」,按在分界线上必须进入调宽逻辑
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - 拖拽

    override func mouseDown(with event: NSEvent) {
        dragStartX = event.locationInWindow.x
        NSCursor.resizeLeftRight.push() // 拖动全程保持箭头(松开前光标矩形不刷新)
        needsDisplay = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        onDragMoved?(event.locationInWindow.x - dragStartX)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        dragStartX = nil
        NSCursor.pop()
        needsDisplay = true
        onDragEnded?()
    }

    // MARK: - 光标与悬停

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

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

    // MARK: - 绘制

    /// 只画边界线,不铺底色:热区左右两半分别透出抽屉材质与编辑器内容
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = (isHovering || isDragging) ? .secondaryLabelColor : .separatorColor
        color.setFill()
        NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }
}
