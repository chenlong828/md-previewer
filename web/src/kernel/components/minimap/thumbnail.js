// 缩略图页面几何：只做等比缩放，不读滚动、不碰指针。
// 短文档整页 fit；长文按 120px 宽固定、纵向裁切，宽度不再被压成窄条。

function positive(value, fallback = 1) {
    const n = Number(value)
    return Number.isFinite(n) && n > 0 ? n : fallback
}

/**
 * 等比缩放页面。
 * fit: 整页塞进轨道，顶左对齐；
 * crop: fit 后宽度不足轨道宽时，改为按轨道宽缩放，页面高度允许超出轨道。
 */
export function fitThumbnail({ pageWidth, pageHeight, railWidth, railHeight, minWidth = null }) {
    const pw = positive(pageWidth, 0)
    const ph = positive(pageHeight, 0)
    const rw = positive(railWidth, 0)
    const rh = positive(railHeight, 0)
    if (!pw || !ph || !rw || !rh) {
        return { mode: 'none', scale: 0, width: 0, height: 0, left: 0, top: 0 }
    }
    const fitScale = Math.min(rw / pw, rh / ph)
    const fitWidth = pw * fitScale
    const min = Number.isFinite(minWidth) && minWidth > 0 ? minWidth : rw
    if (fitWidth < min) {
        const scale = rw / pw
        return {
            mode: 'crop',
            scale,
            width: rw,
            height: ph * scale,
            left: 0,
            top: 0,
        }
    }
    return {
        mode: 'fit',
        scale: fitScale,
        width: fitWidth,
        height: ph * fitScale,
        left: 0,
        top: 0,
    }
}
