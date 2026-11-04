// 查找组件（CMP-kernel-find）：查找栏、命中遍历、ProseMirror 插件与装饰。
// 代码面的查找不在此实现——经 searchSurface 端口向 code 组件索取。
export { findKey, findUI, findProsePlugin, searchDoc, selectMatch } from './find.js'
export { updateFindCount, runFind, stepFind, openFindBar, closeFindBar, setupFindBar } from './find-bar.js'

import { findKey, findUI, findProsePlugin, searchDoc, selectMatch } from './find.js'
import { runFind, updateFindCount, stepFind, openFindBar, closeFindBar, setupFindBar } from './find-bar.js'

/** 供 editor / code 组件消费的端口实现（findService） */
export function createFindService() {
    return {
        findKey, findUI, findProsePlugin, searchDoc, selectMatch,
        runFind, updateFindCount, stepFind, openFindBar, closeFindBar, setupFindBar,
    }
}
