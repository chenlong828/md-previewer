// 缩略图组件的两个 host op：可见偏好与诊断信息。
// 快照/定位不暴露给宿主；本组件只经 minimapSurface 端口被 document 与 page 使用。
import { use } from '../../shared/ports.js'

export function createMinimapOps(_table) {
    return {
        setMinimapVisible(payload = {}) {
            return use('minimapSurface').setVisible(payload.visible !== false)
        },
        minimapInfo() {
            return use('minimapSurface').info()
        },
    }
}
