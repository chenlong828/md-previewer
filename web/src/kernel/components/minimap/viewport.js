// 视口几何：只做滚动位置 ↔ 缩略图内容矩形的换算与夹取，不碰 DOM。
// 所有指针坐标都相对于页面实际缩略矩形，而不是整条轨道；轨道空白区不参与定位。

export function clamp(value, min, max) {
    if (!Number.isFinite(value)) return min
    return Math.min(max, Math.max(min, value))
}

export function maxScrollTop(docHeight, viewportHeight) {
    return Math.max(0, (Number.isFinite(docHeight) ? docHeight : 0) - (Number.isFinite(viewportHeight) ? viewportHeight : 0))
}

/**
 * 缩略图内实际内容矩形 + 视口框。
 * contentTop/contentHeight/contentLeft/contentWidth 来自 fit 后的页面矩形；
 * 缺省时退化为整条轨道，仅用于没有页面快照的测试。
 */
export function viewportMetrics({
    docHeight,
    viewportHeight,
    scrollTop,
    railHeight,
    railWidth = 0,
    contentTop = 0,
    contentHeight = null,
    contentLeft = 0,
    contentWidth = null,
}) {
    const height = Math.max(1, Number(railHeight) || 1)
    const doc = Math.max(0, Number(docHeight) || 0)
    const viewport = Math.max(0, Number(viewportHeight) || 0)
    const top = clamp(Number(contentTop) || 0, 0, height)
    const available = Math.max(0, height - top)
    const contentH = Math.max(0, Math.min(available, Number.isFinite(contentHeight) ? Number(contentHeight) : available))
    const contentW = Math.max(0, Math.min(
        Math.max(0, Number(railWidth) || 0) || Number.MAX_SAFE_INTEGER,
        Number.isFinite(contentWidth) ? Number(contentWidth) : (Number(railWidth) || 0),
    ))
    const left = clamp(Number(contentLeft) || 0, 0, Math.max(0, (Number(railWidth) || 0) - contentW))
    const maxScroll = maxScrollTop(doc, viewport)
    const scroll = clamp(Number(scrollTop) || 0, 0, maxScroll)
    const scale = doc > 0 && contentH > 0 ? contentH / doc : 0
    const railTop = top + scroll * scale
    const rawBox = viewport * scale
    const boxHeight = contentH > 0 ? Math.max(0, Math.min(contentH, Math.max(12, rawBox))) : 0
    return {
        scale,
        maxScroll,
        scrollTop: scroll,
        viewportHeight: viewport,
        contentTop: top,
        contentHeight: contentH,
        contentLeft: left,
        contentWidth: contentW,
        railTop,
        boxHeight,
        railLeft: left,
        boxWidth: contentW,
    }
}

export function isInsideContent({ pointerX = 0, pointerY, contentLeft = 0, contentTop = 0, contentWidth = 0, contentHeight = 0 } = {}) {
    if (contentWidth <= 0 || contentHeight <= 0) return false
    return pointerX >= contentLeft
        && pointerX <= contentLeft + contentWidth
        && pointerY >= contentTop
        && pointerY <= contentTop + contentHeight
}

/** 点击页面内容：把目标点居中到视口，返回夹取后的 scrollTop。 */
export function scrollTopForPointer({
    pointerY,
    railHeight,
    docHeight,
    viewportHeight,
    contentTop = 0,
    contentHeight = null,
}) {
    const height = Math.max(1, Number(railHeight) || 1)
    const doc = Math.max(0, Number(docHeight) || 0)
    const viewport = Math.max(0, Number(viewportHeight) || 0)
    const top = clamp(Number(contentTop) || 0, 0, height)
    const contentH = Math.max(0, Math.min(
        Math.max(0, height - top),
        Number.isFinite(contentHeight) ? Number(contentHeight) : Math.max(0, height - top),
    ))
    if (doc <= 0 || contentH <= 0) return 0
    const local = clamp(Number(pointerY) - top, 0, contentH)
    const target = (local / contentH) * doc - viewport / 2
    return clamp(target, 0, maxScrollTop(doc, viewport))
}

/** 拖动视口框：按页面内容矩形的位移换算文档位移。 */
export function scrollTopForDrag({
    startScrollTop,
    startPointerY,
    pointerY,
    railHeight,
    docHeight,
    viewportHeight,
    contentTop = 0,
    contentHeight = null,
}) {
    const height = Math.max(1, Number(railHeight) || 1)
    const doc = Math.max(0, Number(docHeight) || 0)
    const top = clamp(Number(contentTop) || 0, 0, height)
    const contentH = Math.max(0, Math.min(
        Math.max(0, height - top),
        Number.isFinite(contentHeight) ? Number(contentHeight) : Math.max(0, height - top),
    ))
    if (doc <= 0 || contentH <= 0) return clamp(Number(startScrollTop) || 0, 0, maxScrollTop(doc, Number(viewportHeight) || 0))
    const scale = contentH / doc
    const delta = (Number(pointerY) - Number(startPointerY)) / (scale || 1)
    return clamp((Number(startScrollTop) || 0) + delta, 0, maxScrollTop(doc, viewportHeight))
}

export function isInsideViewport(pointerY, metrics) {
    return pointerY >= metrics.railTop && pointerY <= metrics.railTop + metrics.boxHeight
}
