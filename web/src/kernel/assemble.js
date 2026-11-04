// 内核装配（组合根的唯一实现）：把组件端口接上，再汇总 op 表。
// 页面入口与测试组合根都走这里，避免装配逻辑出现第二份。
import { provide, resetPorts } from './shared/ports.js'
import { createFindService } from './components/find/index.js'
import { createCodeSearch } from './components/code/index.js'
import { createOps } from './core/ops/index.js'

/**
 * 装配内核能力表。
 * @param {{ fresh?: boolean }} opts fresh=true 时先清空端口（测试里多次装配用）
 */
export function createKernelOps({ fresh = false } = {}) {
    if (fresh) resetPorts()
    const findService = createFindService()
    provide('findService', findService)
    provide('searchSurface', createCodeSearch())
    return { ops: createOps(), findService }
}
