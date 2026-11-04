// 光标位置信息上报:供原生右键菜单按需启用表格操作
import { Plugin } from '@milkdown/prose/state'
import { $prose } from '@milkdown/utils'
import { isInTable } from '@milkdown/prose/tables'
import { notify } from '../../shared/bus.js'

export const selInfoProse = $prose(() => {
    let last
    return new Plugin({
        view() {
            return {
                update(view) {
                    let inTable = false
                    try { inTable = isInTable(view.state) } catch (e) { /* ignore */ }
                    if (last !== undefined && inTable === last) return
                    last = inTable
                    notify('selinfo', { inTable })
                },
            }
        },
    })
})
