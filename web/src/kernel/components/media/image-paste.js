// 图片粘贴/导入编排
// 职责：识别剪贴板中的图片载荷（截图位图或本地图片路径），经 hostCall 请求壳落盘，
// 拿到响应后恢复粘贴时的选区插入 image 节点。
// 内核只做识别与编排，落盘与提示（先保存/失败弹窗）由壳负责；
// 非图片粘贴不拦截，milkdown clipboard 的文本链路不受影响。
import { state } from '../../shared/state.js'
import { hostCall } from '../../shared/bus.js'
import { use } from '../../shared/ports.js'

// 本地图片路径文本识别：file:// URL、绝对路径、~/ 相对 + 图片扩展名。
// 仅作预筛（提示壳去验证），壳侧以 UTType 为权威。
const pathPattern = /^(?:file:\/\/\/\S.*|\/\S.*|~\/\S.*)$/i
const extPattern = /\.(png|jpe?g|gif|webp|bmp|svg|tiff?|heic|heif|avif)$/i

export function setupImagePaste(view) {
    // document 捕获阶段先于 ProseMirror 的 paste 处理（粘贴目标常是
    // contenteditable 根元素本身，同元素监听按注册顺序无法保证抢先）：
    // 图片载荷在此终结，preventDefault + stopPropagation 后文本链路完全不感知
    document.addEventListener('paste', (event) => {
        if (!state.ready || state.sourceMode || state.mode === 'code') return
        if (!view.dom.contains(event.target)) return // 只接管编辑器内的粘贴
        const payload = extractImagePayload(event.clipboardData)
        if (!payload) return
        event.preventDefault()
        event.stopPropagation()
        // 选区快照：落盘期间用户可能继续移动光标，回填时恢复到粘贴位置
        const selection = view.state.selection.toJSON()
        const request = payload.kind === 'blob'
            ? blobToBase64(payload.file).then((data) => ({ kind: 'blob', mime: payload.file.type || '', data }))
            : Promise.resolve({ kind: 'file', path: payload.path })
        request
            .then((body) => hostCall('importImage', body))
            .then((result) => handleImported(selection, result))
            .catch((e) => console.warn('image import failed', e))
    }, true)
}

/** 一次只取第一张（截图粘贴天然单张；多图粘贴为已知边界，后续可扩展） */
export function extractImagePayload(data) {
    const files = Array.from((data && data.files) || [])
    const image = files.find((f) => f && f.type && f.type.startsWith('image/'))
    if (image) return { kind: 'blob', file: image }
    const text = ((data && data.getData && data.getData('text/plain')) || '').trim()
    if (pathPattern.test(text) && extPattern.test(text)) return { kind: 'file', path: text }
    return null
}

/** 壳落盘响应：把插入动作交给编辑面（本组件不碰 ProseMirror 事务） */
export function handleImported(selection, payload) {
    if (!payload || payload.ok === false) return false // 壳已弹窗提示
    return use('imageInsertion').insert(selection, payload)
}

function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.onload = () => {
            const bytes = new Uint8Array(reader.result)
            // 分块拼接再 btoa：大图一次 String.fromCharCode 展开会栈溢出
            let bin = ''
            const chunkSize = 0x8000
            for (let i = 0; i < bytes.length; i += chunkSize) {
                bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize))
            }
            resolve(btoa(bin))
        }
        reader.onerror = () => reject(reader.error)
        reader.readAsArrayBuffer(blob)
    })
}
