// 视口几何：只做滚动位置 ↔ 缩略图内容矩形的换算与夹取，不碰 DOM。
// fit 模式整页在轨道内；crop 模式页面高于轨道，contentTop 为负的平移量。

export function clamp(value, min, max) {
    if (!Number.isFinite(value)) return min
    return Math.min(max, Math.max(min, value))
}

export function maxScrollTop(docHeight, viewportHeight) {
    return Math.max(0, (Number.isFinite(docHeight) ? docHeight : 0) - (Number.isFinite(viewportHeight) ? viewportHeight : 0))
}

/**
 * crop 模式下，页面相对轨道的纵向平移量：直接按整篇滚动进度线性平移。
 * 这样视口框在轨道里的 Y 位置也与滚动条进度一致，拖到底即页面底。
 */
export function cropPanTop({
    docHeight,
    viewportHeight,
    scrollTop,
    railHeight,
    contentHeight,
}) {
    const rail = Math.max(1, Number(railHeight) || 1)
    const doc = Math.max(0, Number(docHeight) || 0)
    const content = Math.max(0, Number(contentHeight) || 0)
    const maxPan = Math.max(0, content - rail)
    const max = maxScrollTop(doc, viewportHeight)
    if (!maxPan || !max) return 0
    const progress = clamp((Number(scrollTop) || 0) / max, 0, 1)
    return maxPan * progress
}

/**
 * 缩略图内实际内容矩形 + 视口框。
 * contentTop 可以为负（crop 平移）；contentHeight 是缩放后的整页高度，
 * 允许大于轨道高度。缺省 contentHeight 时退化为轨道可用高度。
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
    const top = Number(contentTop) || 0
    const contentH = Number.isFinite(contentHeight)
        ? Math.max(0, Number(contentHeight))
        : Math.max(0, height - top)
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
/**
 * crop 模式拖动：视口框就是滚动条滑块，指针位移 1:1 映射整段轨道进度。
 * 不按页面缩略内容折算，避免长文里指针动了、视口框却停在中部。
 */
export function scrollTopForThumbDrag({
    startScrollTop,
    startPointerY,
    pointerY,
    railHeight,
    boxHeight,
    docHeight,
    viewportHeight,
}) {
    const rail = Math.max(1, Number(railHeight) || 1)
    const max = maxScrollTop(docHeight, viewportHeight)
    if (max <= 0) return 0
    const box = clamp(Number(boxHeight) || 0, 0, rail)
    const track = Math.max(1, rail - box)
    const start = clamp(Number(startScrollTop) || 0, 0, max)
    const delta = (Number(pointerY) || 0) - (Number(startPointerY) || 0)
    return clamp((start / max + delta / track) * max, 0, max)
}

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
    const top = Number(contentTop) || 0
    const contentH = Number.isFinite(contentHeight)
        ? Math.max(0, Number(contentHeight))
        : Math.max(0, height - top)
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
    const top = Number(contentTop) || 0
    const contentH = Number.isFinite(contentHeight)
        ? Math.max(0, Number(contentHeight))
        : Math.max(0, height - top)
    if (doc <= 0 || contentH <= 0) return clamp(Number(startScrollTop) || 0, 0, maxScrollTop(doc, Number(viewportHeight) || 0))
    const scale = contentH / doc
    const delta = (Number(pointerY) - Number(startPointerY)) / (scale || 1)
    return clamp((Number(startScrollTop) || 0) + delta, 0, maxScrollTop(doc, viewportHeight))
}

export function isInsideViewport(pointerY, metrics) {
    return pointerY >= metrics.railTop && pointerY <= metrics.railTop + metrics.boxHeight
}
