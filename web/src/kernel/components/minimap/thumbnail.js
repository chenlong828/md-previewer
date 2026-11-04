// 缩略图页面几何：只做等比缩放，不读滚动、不碰指针。
// 顶左对齐是产品口径：页面不居中，缩放后右侧/下方允许留空。

function positive(value, fallback = 1) {
    const n = Number(value)
    return Number.isFinite(n) && n > 0 ? n : fallback
}

/** 等比缩放到轨道内，返回零偏移的内容矩形（top-left）。 */
export function fitThumbnail({ pageWidth, pageHeight, railWidth, railHeight }) {
    const pw = positive(pageWidth, 0)
    const ph = positive(pageHeight, 0)
    const rw = positive(railWidth, 0)
    const rh = positive(railHeight, 0)
    if (!pw || !ph || !rw || !rh) {
        return { scale: 0, width: 0, height: 0, left: 0, top: 0 }
    }
    const scale = Math.min(rw / pw, rh / ph)
    return {
        scale,
        width: pw * scale,
        height: ph * scale,
        left: 0,
        top: 0,
    }
}
