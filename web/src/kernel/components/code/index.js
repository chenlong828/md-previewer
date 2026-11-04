// 代码面组件（CMP-kernel-code）：只读源码视图、高亮语言、行号、代码内查找。
export { showCode, hideCode, setCodeLanguage, setCodeLineNumbers, isCodeMode, codeInfo } from './code-view.js'
export { hasLanguage, ensureLanguages } from './languages.js'

import { findInCode, clearCodeFind, codeFindCount, hideCode, codeInfo } from './code-view.js'
import { hasLanguage, ensureLanguages } from './languages.js'

/** 供 editor/document 消费（codeSurface）：页面级代码视图切换与信息 */
export function createCodeSurface() {
    return { hideCode, codeInfo }
}

/** 供 editor 消费（codeLanguages）：语法按需加载与可用性查询 */
export function createCodeLanguages() {
    return { ensureLanguages, hasLanguage }
}

/** 供 find 组件消费的端口实现（searchSurface）：代码面自己的查找 */
export function createCodeSearch() {
    return { findInCode, clearCodeFind, codeFindCount }
}
