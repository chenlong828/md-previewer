// 内核装配（组合根的唯一实现）：把组件端口接上，再汇总 op 表。
// 页面入口与测试组合根都走这里；组件之间互不 import，全部经本文件接线。
import { provide, resetPorts } from './shared/ports.js'
import { createFindService } from './components/find/index.js'
import { createCodeSearch, createCodeSurface, createCodeLanguages } from './components/code/index.js'
import { createEditorSurface, createRenderSurface, createImageInsertion } from './components/editor/editor.js'
import { createMediaPaste } from './components/media/image-paste.js'
import { createOps } from './ops.js'

/**
 * 装配内核能力表。
 * @param {{ fresh?: boolean }} opts fresh=true 时先清空端口（测试里多次装配用）
 */
export function createKernelOps({ fresh = false } = {}) {
    if (fresh) resetPorts()
    const findService = createFindService()
    provide('findService', findService)
    provide('searchSurface', createCodeSearch())
    provide('codeSurface', createCodeSurface())
    provide('codeLanguages', createCodeLanguages())
    provide('editorSurface', createEditorSurface())
    provide('renderSurface', createRenderSurface())
    provide('imageInsertion', createImageInsertion())
    provide('mediaPaste', createMediaPaste())
    return { ops: createOps(), findService }
}
