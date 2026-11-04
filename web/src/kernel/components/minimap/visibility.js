// 缩略图有效显示策略：唯一判据，纯函数，便于单测。
// 偏好是“用户想不想看”，有效显示还要叠加内容面、溢出与 32px 滞回。
export const OVERFLOW_HYSTERESIS = 32

export function shouldShow({ pref, hasSource, docHeight, viewportHeight, currentlyVisible, threshold = OVERFLOW_HYSTERESIS }) {
    if (!pref || !hasSource) return false
    if (!Number.isFinite(docHeight) || !Number.isFinite(viewportHeight)) return false
    if (docHeight <= 0 || viewportHeight <= 0) return false
    const overflow = docHeight - viewportHeight
    // 已显示时允许缩到 -32px 才隐藏；未显示时必须超过 +32px 才出现。
    return currentlyVisible ? overflow > -threshold : overflow > threshold
}
