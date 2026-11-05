// 缩略图轨道：只负责“挂快照 + 缩放 + 视口框 + 指针映射”。
// 内容投影来自 minimapSources 端口，正文/代码组件不在此 import；
// 用户偏好来自 setVisible / init，本组件不持久化任何宿主偏好。
import { state } from '../../shared/state.js'
import { use } from '../../shared/ports.js'
import { shouldShow } from './visibility.js'
import {
    clamp,
    cropPanTop,
    isInsideContent,
    isInsideViewport,
    maxScrollTop,
    scrollTopForDrag,
    scrollTopForPointer,
    scrollTopForThumbDrag,
    viewportMetrics,
} from './viewport.js'
import { fitThumbnail } from './thumbnail.js'

const RAIL_WIDTH = 120
const CONTENT_REDRAW_DELAY = 250
const SCROLLBAR_PROPERTY = '--minimap-scrollbar'

function now() {
    return typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now()
}

function sourceKind() {
    if (state.sourceMode) return 'none'
    return state.codeMode ? 'code' : 'markdown'
}

function safeMeasure(source) {
    try {
        return source?.measure?.() || null
    } catch (error) {
        console.warn('minimap measure failed', error)
        return null
    }
}

export function createMinimap() {
    let started = false
    let pref = true
    let visible = false
    let rail = null
    let stage = null
    let viewport = null
    let source = null
    let currentKind = 'none'
    let lastMeasure = null
    let lastLayout = null
    let lastPageRect = null
    let lastPan = 0
    let snapshotCount = 0
    let redrawCount = 0
    let snapshotWarned = false
    let refreshTimer = 0
    let scrollFrame = 0
    let drag = null
    let mutationObserver = null
    let resizeObserver = null
    let scrollbarValue = 0
    let lastInfo = null
    let startedAt = 0

    function resolveSource() {
        const kind = sourceKind()
        if (kind === 'none') {
            currentKind = 'none'
            source = null
            return null
        }
        if (kind !== currentKind || !source) {
            currentKind = kind
            const sources = use('minimapSources')
            source = kind === 'code' ? sources.code() : sources.markdown()
        }
        return source
    }

    function measure() {
        const active = resolveSource()
        return active ? safeMeasure(active) : null
    }

    function railRect() {
        return rail?.getBoundingClientRect?.() || null
    }

    function railHeight() {
        return Math.max(1, railRect()?.height || window.innerHeight || 1)
    }

    function railWidth() {
        return Math.max(1, railRect()?.width || RAIL_WIDTH)
    }

    function updateScrollbar() {
        const width = Math.max(0, (window.innerWidth || 0) - (document.documentElement.clientWidth || 0))
        scrollbarValue = width
        document.documentElement.style.setProperty(SCROLLBAR_PROPERTY, `${width}px`)
    }

    function safeSnapshot(active) {
        try {
            return active?.snapshot?.() || null
        } catch (error) {
            if (!snapshotWarned) {
                snapshotWarned = true
                console.warn('minimap snapshot failed', error)
            }
            return null
        }
    }

    function clearSnapshot() {
        stage?.replaceChildren()
        if (stage) stage.style.top = '0px'
        lastLayout = null
        lastPageRect = null
        lastPan = 0
        if (viewport) {
            viewport.style.display = 'none'
            viewport.style.width = '0px'
            viewport.style.height = '0px'
        }
    }

    function rebuildSnapshot() {
        if (!visible || !source || !stage) return false
        const page = safeSnapshot(source)
        if (!page) return false
        // 先按未缩放布局测量页面；stage 的 transform 不影响真实页面尺寸。
        stage.style.transform = 'none'
        stage.style.left = '0px'
        stage.style.top = '0px'
        stage.replaceChildren(page)
        const pageRect = page.getBoundingClientRect?.()
        if (!pageRect || pageRect.width <= 0 || pageRect.height <= 0) return false
        const layout = fitThumbnail({
            pageWidth: pageRect.width,
            pageHeight: pageRect.height,
            railWidth: railWidth(),
            railHeight: railHeight(),
        })
        if (!layout.scale) return false
        applyStage(layout, 0)
        lastLayout = layout
        lastPageRect = { width: pageRect.width, height: pageRect.height }
        lastPan = 0
        snapshotCount += 1
        redrawCount += 1
        return true
    }

    function applyStage(layout, panTop) {
        if (!stage) return
        stage.style.transform = `scale(${layout.scale})`
        stage.style.left = '0px'
        stage.style.top = `${-panTop}px`
    }

    function currentPanTop(measured) {
        if (!lastLayout || lastLayout.mode !== 'crop') return 0
        return cropPanTop({
            docHeight: measured?.docHeight || 0,
            viewportHeight: measured?.viewportHeight || 0,
            scrollTop: measured?.scrollTop || 0,
            railHeight: railHeight(),
            contentHeight: lastLayout.height,
        })
    }

    function updateViewport() {
        if (!viewport || !visible || !lastLayout || !lastMeasure) {
            if (viewport) viewport.style.display = 'none'
            return
        }
        const panTop = cropPanTop({
            docHeight: lastMeasure.docHeight,
            viewportHeight: lastMeasure.viewportHeight,
            scrollTop: window.scrollY || document.documentElement.scrollTop || 0,
            railHeight: railHeight(),
            contentHeight: lastLayout.mode === 'crop' ? lastLayout.height : 0,
        })
        lastPan = panTop
        applyStage(lastLayout, panTop)
        const metrics = viewportMetrics({
            docHeight: lastMeasure.docHeight,
            viewportHeight: lastMeasure.viewportHeight,
            scrollTop: window.scrollY || document.documentElement.scrollTop || 0,
            railHeight: railHeight(),
            railWidth: railWidth(),
            contentTop: lastLayout.top - panTop,
            contentHeight: lastLayout.height,
            contentLeft: lastLayout.left,
            contentWidth: lastLayout.width,
        })
        if (!metrics.boxHeight || !metrics.boxWidth) {
            viewport.style.display = 'none'
            return
        }
        viewport.style.display = 'block'
        viewport.style.left = `${metrics.railLeft}px`
        viewport.style.top = `${metrics.railTop}px`
        viewport.style.width = `${metrics.boxWidth}px`
        viewport.style.height = `${metrics.boxHeight}px`
    }

    function hideEffective() {
        visible = false
        document.body.classList.remove('minimap-shown')
        if (rail) {
            rail.classList.remove('is-visible')
            rail.setAttribute('aria-hidden', 'true')
        }
        clearSnapshot()
    }

    function apply() {
        if (!started) return null
        const active = resolveSource()
        const measured = active ? safeMeasure(active) : null
        const nextVisible = shouldShow({
            pref,
            hasSource: !!active,
            docHeight: measured?.docHeight,
            viewportHeight: measured?.viewportHeight,
            currentlyVisible: visible,
        })
        if (!nextVisible || !measured) {
            hideEffective()
            lastMeasure = null
            return { visible: false, measure: measured }
        }
        visible = true
        document.body.classList.add('minimap-shown')
        if (rail) {
            rail.classList.add('is-visible')
            rail.setAttribute('aria-hidden', 'false')
        }
        lastMeasure = measured
        if (!rebuildSnapshot()) {
            hideEffective()
            lastMeasure = null
            return { visible: false, measure: measured }
        }
        updateViewport()
        return { visible: true, measure: measured }
    }

    function scheduleRefresh(delay = CONTENT_REDRAW_DELAY) {
        if (!started) return
        if (refreshTimer) clearTimeout(refreshTimer)
        refreshTimer = window.setTimeout(() => {
            refreshTimer = 0
            apply()
        }, Math.max(0, delay))
    }

    function scheduleViewport() {
        if (!started || !visible || scrollFrame) return
        const raf = window.requestAnimationFrame || ((fn) => window.setTimeout(fn, 16))
        scrollFrame = raf(() => {
            scrollFrame = 0
            updateViewport()
        })
    }

    function scrollTo(top) {
        const active = resolveSource()
        if (!active) return
        const max = Math.max(0, (lastMeasure?.docHeight || 0) - (lastMeasure?.viewportHeight || window.innerHeight || 0))
        active.scrollTo?.(clamp(top, 0, max))
    }

    function pointerY(event) {
        const rect = railRect()
        return clamp(event.clientY - (rect?.top || 0), 0, rect?.height || railHeight())
    }

    function pointerX(event) {
        const rect = railRect()
        return clamp(event.clientX - (rect?.left || 0), 0, rect?.width || railWidth())
    }

    function currentMetrics(measured) {
        const panTop = currentPanTop(measured)
        lastPan = panTop
        return viewportMetrics({
            docHeight: measured.docHeight,
            viewportHeight: measured.viewportHeight,
            scrollTop: measured.scrollTop,
            railHeight: railHeight(),
            railWidth: railWidth(),
            contentTop: (lastLayout?.top || 0) - panTop,
            contentHeight: lastLayout?.height,
            contentLeft: lastLayout?.left || 0,
            contentWidth: lastLayout?.width,
        })
    }

    function onPointerDown(event) {
        if (!visible || !lastMeasure || !lastLayout || event.button !== 0) return
        const active = resolveSource()
        if (!active) return
        const measured = safeMeasure(active) || lastMeasure
        if (!measured) return
        const x = pointerX(event)
        const y = pointerY(event)
        const metrics = currentMetrics(measured)
        if (!isInsideContent({
            pointerX: x,
            pointerY: y,
            contentLeft: metrics.contentLeft,
            contentTop: metrics.contentTop,
            contentWidth: metrics.contentWidth,
            contentHeight: metrics.contentHeight,
        })) {
            // 轨道空白区不参与文档定位，避免整轨 100% 映射造成偏差。
            return
        }
        event.preventDefault()
        event.stopPropagation()
        if (isInsideViewport(y, metrics)) {
            drag = {
                startScrollTop: measured.scrollTop,
                startY: y,
                pointerId: event.pointerId,
                boxHeight: metrics.boxHeight,
            }
        } else {
            active.scrollTo?.(scrollTopForPointer({
                pointerY: y,
                railHeight: railHeight(),
                docHeight: measured.docHeight,
                viewportHeight: measured.viewportHeight,
                contentTop: metrics.contentTop,
                contentHeight: metrics.contentHeight,
            }))
            drag = null
        }
        lastMeasure = measured
        try {
            rail.setPointerCapture(event.pointerId)
        } catch {
            // 指针捕获是增强；没有它仍可点击，拖动会在离开轨道时结束。
        }
    }

    function onPointerMove(event) {
        if (!visible || !drag || event.pointerId !== drag.pointerId || !lastLayout) return
        event.preventDefault()
        const y = pointerY(event)
        const height = railHeight()
        const docHeight = lastMeasure?.docHeight || 0
        const viewportHeight = lastMeasure?.viewportHeight || window.innerHeight || 0
        let target
        if (lastLayout.mode === 'crop' && lastLayout.height > height) {
            // 长文裁切：视口框是整篇滚动条的滑块，指针与框 1:1 跟手。
            target = scrollTopForThumbDrag({
                startScrollTop: drag.startScrollTop,
                startPointerY: drag.startY,
                pointerY: y,
                railHeight: height,
                boxHeight: drag.boxHeight,
                docHeight,
                viewportHeight,
            })
        } else {
            target = scrollTopForDrag({
                startScrollTop: drag.startScrollTop,
                startPointerY: drag.startY,
                pointerY: y,
                railHeight: height,
                docHeight,
                viewportHeight,
                contentTop: lastLayout.top - lastPan,
                contentHeight: lastLayout.height,
            })
        }
        // 拖到轨道顶/底时严格对齐文档开头/结尾。
        if (y <= 1) target = 0
        else if (y >= height - 1) target = maxScrollTop(docHeight, viewportHeight)
        scrollTo(target)
    }

    function onPointerUp(event) {
        if (!drag || event.pointerId !== drag.pointerId) return
        drag = null
        try {
            rail.releasePointerCapture(event.pointerId)
        } catch {
            // 已释放或从未捕获
        }
    }

    function onWheel(event) {
        if (!visible) return
        event.preventDefault()
        const active = resolveSource()
        if (!active) return
        active.scrollTo?.(window.scrollY + event.deltaY)
    }

    function onScroll() {
        if (!visible) return
        scheduleViewport()
    }

    function onResize() {
        updateScrollbar()
        scheduleRefresh(0)
    }

    function observe() {
        if (typeof MutationObserver !== 'undefined') {
            mutationObserver = new MutationObserver((mutations) => {
                const insideRail = (node) => {
                    const element = node?.nodeType === 1 ? node : node?.parentElement
                    return !!element?.closest?.('#minimap')
                }
                if (mutations.every((mutation) => insideRail(mutation.target))) return
                scheduleRefresh()
            })
            mutationObserver.observe(document.documentElement, {
                attributes: true,
                attributeFilter: ['data-theme', 'style'],
            })
            mutationObserver.observe(document.body, {
                subtree: true,
                childList: true,
                characterData: true,
                attributes: true,
                attributeFilter: ['class', 'data-type', 'style'],
            })
        }
        if (typeof ResizeObserver !== 'undefined') {
            resizeObserver = new ResizeObserver(() => scheduleRefresh(0))
            resizeObserver.observe(document.documentElement)
            const root = document.getElementById('app') || document.getElementById('code-view')
            if (root) resizeObserver.observe(root)
        }
    }

    function start() {
        if (started) return true
        if (typeof document === 'undefined' || !document.body) return false
        rail = document.createElement('div')
        rail.id = 'minimap'
        rail.className = 'minimap'
        rail.setAttribute('role', 'navigation')
        rail.setAttribute('aria-label', '文档缩略图，可拖动定位')
        rail.setAttribute('aria-hidden', 'true')
        stage = document.createElement('div')
        stage.className = 'minimap-stage'
        stage.setAttribute('aria-hidden', 'true')
        viewport = document.createElement('div')
        viewport.className = 'minimap-viewport'
        viewport.setAttribute('aria-hidden', 'true')
        rail.append(stage, viewport)
        document.body.append(rail)
        started = true
        startedAt = now()
        updateScrollbar()
        observe()
        window.addEventListener('scroll', onScroll, { passive: true })
        window.addEventListener('resize', onResize, { passive: true })
        rail.addEventListener('pointerdown', onPointerDown, { passive: false })
        rail.addEventListener('pointermove', onPointerMove, { passive: false })
        rail.addEventListener('pointerup', onPointerUp)
        rail.addEventListener('pointercancel', onPointerUp)
        rail.addEventListener('wheel', onWheel, { passive: false })
        if (document.fonts?.ready) document.fonts.ready.then(() => scheduleRefresh(0)).catch(() => {})
        apply()
        return true
    }

    function stop() {
        if (!started) return
        started = false
        if (refreshTimer) clearTimeout(refreshTimer)
        refreshTimer = 0
        if (scrollFrame) {
            const cancel = window.cancelAnimationFrame || window.clearTimeout
            cancel(scrollFrame)
        }
        scrollFrame = 0
        drag = null
        mutationObserver?.disconnect()
        mutationObserver = null
        resizeObserver?.disconnect()
        resizeObserver = null
        window.removeEventListener('scroll', onScroll)
        window.removeEventListener('resize', onResize)
        if (rail) {
            rail.removeEventListener('pointerdown', onPointerDown)
            rail.removeEventListener('pointermove', onPointerMove)
            rail.removeEventListener('pointerup', onPointerUp)
            rail.removeEventListener('pointercancel', onPointerUp)
            rail.removeEventListener('wheel', onWheel)
            rail.remove()
        }
        document.body.classList.remove('minimap-shown')
        rail = null
        stage = null
        viewport = null
        source = null
        currentKind = 'none'
        visible = false
        lastMeasure = null
        lastLayout = null
        lastPageRect = null
        lastPan = 0
    }

    function setVisible(value) {
        pref = value !== false
        if (started) apply()
        return { visible: pref, effective: visible }
    }

    function info() {
        if (!started) {
            lastInfo = {
                started: false,
                pref,
                visible: false,
                surface: state.sourceMode ? 'source' : (state.codeMode ? 'code' : 'markdown'),
                hasSource: false,
                mode: 'none',
                docHeight: 0,
                viewportHeight: 0,
                scrollTop: 0,
                railHeight: 0,
                railWidth: 0,
                viewportTop: 0,
                viewportBoxHeight: 0,
                viewportLeft: 0,
                viewportBoxWidth: 0,
                pageWidth: 0,
                pageHeight: 0,
                contentLeft: 0,
                contentTop: 0,
                contentWidth: 0,
                contentHeight: 0,
                panTop: 0,
                panRange: 0,
                scale: 0,
                snapshotCount: 0,
                redrawCount: 0,
                startedAt: 0,
            }
            return lastInfo
        }
        const measured = measure()
        const layout = lastLayout
        const panTop = measured && layout ? currentPanTop(measured) : 0
        const metrics = measured && layout
            ? viewportMetrics({
                docHeight: measured.docHeight,
                viewportHeight: measured.viewportHeight,
                scrollTop: measured.scrollTop,
                railHeight: railHeight(),
                railWidth: railWidth(),
                contentTop: layout.top - panTop,
                contentHeight: layout.height,
                contentLeft: layout.left,
                contentWidth: layout.width,
            })
            : null
        lastInfo = {
            started: true,
            pref,
            visible,
            surface: state.sourceMode ? 'source' : (state.codeMode ? 'code' : 'markdown'),
            hasSource: !!measured,
            mode: layout?.mode || 'none',
            docHeight: Math.round(measured?.docHeight || 0),
            viewportHeight: Math.round(measured?.viewportHeight || 0),
            scrollTop: Math.round(measured?.scrollTop || 0),
            railHeight: Math.round(railHeight()),
            railWidth: Math.round(railWidth()),
            viewportTop: Math.round(metrics?.railTop || 0),
            viewportBoxHeight: Math.round(metrics?.boxHeight || 0),
            viewportLeft: Math.round(metrics?.railLeft || 0),
            viewportBoxWidth: Math.round(metrics?.boxWidth || 0),
            pageWidth: Math.round(lastPageRect?.width || 0),
            pageHeight: Math.round(lastPageRect?.height || 0),
            contentLeft: Math.round(metrics?.contentLeft || 0),
            contentTop: Math.round(metrics?.contentTop || 0),
            contentWidth: Math.round(metrics?.contentWidth || 0),
            contentHeight: Math.round(metrics?.contentHeight || 0),
            panTop: Math.round(panTop),
            panRange: Math.round(Math.max(0, (layout?.height || 0) - railHeight())),
            scale: layout ? Number(layout.scale.toFixed(4)) : 0,
            snapshotCount,
            redrawCount,
            startedAt: Math.round(startedAt),
        }
        return lastInfo
    }

    return {
        start,
        stop,
        setVisible,
        info,
        // 仅测试与内部调度使用：强制重新测量（真实页面由 MutationObserver/滚动驱动）。
        refresh: apply,
        get visible() { return visible },
        get pref() { return pref },
        get scrollbarWidth() { return scrollbarValue },
    }
}

export function createMinimapSurface(minimap) {
    return {
        start: () => minimap.start(),
        stop: () => minimap.stop(),
        setVisible: (value) => minimap.setVisible(value),
        info: () => minimap.info(),
    }
}
