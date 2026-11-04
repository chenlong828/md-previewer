// 输出：独立 HTML 导出、打印、内容几何（供壳校准 PDF 页面尺寸）。
import { exportStandaloneHTML } from './export.js'

export function createOutputOps(_table) {
    return {
            async exportStandaloneHTML() {
                return { html: await exportStandaloneHTML() }
            },

            print() {
                window.print()
                return { ok: true }
            },

            /** 供壳校准 PDF 页面几何：内容区尺寸（CSS 像素） */

            getContentSize() {
                const root = document.documentElement
                return { width: root.scrollWidth, height: root.scrollHeight }
            },

            // ---------- 资源 ----------

            /** GC 引用收集：宁多保护不误删（壳回答每个引用的全部存在路径） */
    }
}
