// 代码面组件（CMP-kernel-code）：只读源码视图、高亮语言、行号、代码内查找。
export { showCode, hideCode, setCodeLanguage, setCodeLineNumbers, isCodeMode, codeInfo } from './code-view.js'
export { hasLanguage } from './languages.js'

import { findInCode, clearCodeFind, codeFindCount } from './code-view.js'

/** 供 find 组件消费的端口实现（searchSurface）：代码面自己的查找 */
export function createCodeSearch() {
    return { findInCode, clearCodeFind, codeFindCount }
}
