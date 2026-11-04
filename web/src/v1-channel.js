// 迁移期（T5 前）的 v1 宿主通道：全仓唯一保留 window.webkit 的页面级文件。
// v2 切换后本文件与 bridge.js 一并删除（内核经 transport 与壳通信）。
export const post = (msg) => {
    try {
        window.webkit?.messageHandlers?.mdbridge?.postMessage(msg)
    } catch (e) {
        console.warn('postMessage failed', e)
    }
}
