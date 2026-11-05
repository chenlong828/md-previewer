// 缩略图组件契约测试：纯 Node + jsdom，不启 WKWebView。
// 重点覆盖顶左对齐的等比缩放，以及“指针只映射到实际页面矩形”的定位口径。
import test from 'node:test'
import assert from 'node:assert/strict'
import { JSDOM } from 'jsdom'

import { createMinimap } from '../src/kernel/components/minimap/minimap.js'
import { provide, resetPorts } from '../src/kernel/shared/ports.js'
import { state } from '../src/kernel/shared/state.js'
import { shouldShow } from '../src/kernel/components/minimap/visibility.js'
import { fitThumbnail } from '../src/kernel/components/minimap/thumbnail.js'
import {
    cropPanTop,
    isInsideContent,
    scrollTopForDrag,
    scrollTopForPointer,
    scrollTopForThumbDrag,
    viewportMetrics,
} from '../src/kernel/components/minimap/viewport.js'
import { cloneReadonly } from '../src/kernel/shared/readonly-clone.js'

function defineDom() {
    const dom = new JSDOM(`<!doctype html><html><body>
        <div id="app"><div class="ProseMirror"></div></div>
        <pre id="code-view"><code></code></pre>
    </body></html>`, { pretendToBeVisual: true, url: 'file:///tmp/doc.md' })
    const win = dom.window
    const setGlobal = (name, value) => {
        Object.defineProperty(globalThis, name, { value, configurable: true, writable: true })
    }
    setGlobal('window', win)
    setGlobal('document', win.document)
    setGlobal('navigator', win.navigator)
    setGlobal('HTMLElement', win.HTMLElement)
    setGlobal('Element', win.Element)
    setGlobal('Node', win.Node)
    setGlobal('NodeFilter', win.NodeFilter)
    setGlobal('MutationObserver', win.MutationObserver)
    setGlobal('getComputedStyle', win.getComputedStyle.bind(win))
    setGlobal('requestAnimationFrame', win.requestAnimationFrame.bind(win))
    setGlobal('cancelAnimationFrame', win.cancelAnimationFrame.bind(win))
    setGlobal('Image', win.Image)
    return dom
}

function makePage(width, height) {
    const page = document.createElement('div')
    page.className = 'minimap-page'
    page.getBoundingClientRect = () => ({
        width, height, top: 0, left: 0, right: width, bottom: height,
    })
    return page
}

function fakeSources() {
    const markdown = {
        scrollTop: 100,
        snapshots: 0,
        measure() {
            return {
                contentWidth: 800,
                docHeight: 1000,
                viewportHeight: 400,
                scrollTop: this.scrollTop,
            }
        },
        snapshot() {
            this.snapshots += 1
            return makePage(800, 2000)
        },
        scrollTo(top) { this.scrollTop = top },
    }
    const code = {
        scrollTop: 0,
        snapshots: 0,
        measure() {
            return {
                contentWidth: 800,
                docHeight: 1200,
                viewportHeight: 400,
                scrollTop: this.scrollTop,
            }
        },
        snapshot() {
            this.snapshots += 1
            return makePage(800, 4000)
        },
        scrollTo(top) { this.scrollTop = top },
    }
    return { markdown, code }
}

test('页面缩放：等比、顶左对齐，不居中', () => {
    assert.deepEqual(
        fitThumbnail({ pageWidth: 800, pageHeight: 2000, railWidth: 120, railHeight: 768 }),
        { mode: 'fit', scale: 0.15, width: 120, height: 300, left: 0, top: 0 },
    )
    // 高度受限：页面比轨道更“宽”，宽度只占一部分，但仍从左上开始。
    const wide = fitThumbnail({ pageWidth: 1000, pageHeight: 100, railWidth: 120, railHeight: 300 })
    assert.equal(wide.scale, 0.12)
    assert.deepEqual(
        { width: wide.width, height: wide.height, left: wide.left, top: wide.top },
        { width: 120, height: 12, left: 0, top: 0 },
    )
    // 长文：fit 后宽度 61.44 < 120，改为固定 120 宽、页面高度超出轨道。
    const crop = fitThumbnail({ pageWidth: 800, pageHeight: 10000, railWidth: 120, railHeight: 768 })
    assert.equal(crop.mode, 'crop')
    assert.equal(crop.scale, 0.15)
    assert.equal(crop.width, 120)
    assert.equal(crop.height, 1500)
})

test('视口几何：以内容矩形为基准，空白区不参与', () => {
    const metrics = viewportMetrics({
        docHeight: 1000, viewportHeight: 400, scrollTop: 300,
        railHeight: 500, railWidth: 120,
        contentTop: 0, contentHeight: 250, contentLeft: 0, contentWidth: 100,
    })
    assert.equal(metrics.scale, 0.25)
    assert.equal(metrics.railTop, 75)
    assert.equal(metrics.boxHeight, 100)
    assert.equal(metrics.boxWidth, 100)
    assert.equal(metrics.maxScroll, 600)

    assert.equal(scrollTopForPointer({
        pointerY: 145, railHeight: 500, docHeight: 1000, viewportHeight: 400,
        contentTop: 20, contentHeight: 250,
    }), 300)
    assert.equal(scrollTopForDrag({
        startScrollTop: 100, startPointerY: 100, pointerY: 150,
        railHeight: 500, docHeight: 1000, viewportHeight: 400,
        contentTop: 20, contentHeight: 250,
    }), 300)
    assert.equal(viewportMetrics({
        docHeight: 1000, viewportHeight: 20, scrollTop: 0,
        railHeight: 500, contentHeight: 250,
    }).boxHeight, 12)

    // crop：contentTop 为负的平移量，整页高度可大于轨道。
    const crop = viewportMetrics({
        docHeight: 10000, viewportHeight: 1000, scrollTop: 5000,
        railHeight: 500, railWidth: 120,
        contentTop: -1400, contentHeight: 3000,
    })
    assert.equal(crop.scale, 0.3)
    assert.equal(crop.railTop, 100)
    assert.equal(crop.boxHeight, 300)
    assert.equal(crop.contentTop, -1400)
    assert.equal(Math.round(cropPanTop({
        docHeight: 10000, viewportHeight: 1000, scrollTop: 5000,
        railHeight: 500, contentHeight: 3000,
    })), 1389)
    assert.equal(cropPanTop({
        docHeight: 10000, viewportHeight: 1000, scrollTop: 4500,
        railHeight: 500, contentHeight: 3000,
    }), 1250)
    assert.equal(cropPanTop({
        docHeight: 10000, viewportHeight: 1000, scrollTop: 9000,
        railHeight: 500, contentHeight: 3000,
    }), 2500)
    assert.equal(cropPanTop({
        docHeight: 10000, viewportHeight: 1000, scrollTop: 0,
        railHeight: 500, contentHeight: 3000,
    }), 0)
    assert.equal(scrollTopForPointer({
        pointerY: 100, railHeight: 500, docHeight: 10000, viewportHeight: 1000,
        contentTop: -1400, contentHeight: 3000,
    }), 4500)
    assert.equal(Math.round(scrollTopForDrag({
        startScrollTop: 100, startPointerY: 100, pointerY: 200,
        railHeight: 500, docHeight: 10000, viewportHeight: 1000,
        contentTop: -1400, contentHeight: 3000,
    })), 433)
    // crop 拖动：视口框是整篇滚动条滑块，指针移动 1px，框也移动 1px。
    assert.equal(scrollTopForThumbDrag({
        startScrollTop: 4500, startPointerY: 250, pointerY: 300,
        railHeight: 500, boxHeight: 100, docHeight: 10000, viewportHeight: 1000,
    }), 5625)
    assert.equal(scrollTopForThumbDrag({
        startScrollTop: 4500, startPointerY: 250, pointerY: 500,
        railHeight: 500, boxHeight: 100, docHeight: 10000, viewportHeight: 1000,
    }), 9000)
    assert.equal(scrollTopForThumbDrag({
        startScrollTop: 4500, startPointerY: 250, pointerY: 0,
        railHeight: 500, boxHeight: 100, docHeight: 10000, viewportHeight: 1000,
    }), 0)

    assert.equal(isInsideContent({
        pointerX: 50, pointerY: 50, contentLeft: 0, contentTop: 0, contentWidth: 100, contentHeight: 200,
    }), true)
    assert.equal(isInsideContent({
        pointerX: 50, pointerY: 250, contentLeft: 0, contentTop: 0, contentWidth: 100, contentHeight: 200,
    }), false)
    assert.equal(isInsideContent({
        pointerX: 150, pointerY: 50, contentLeft: 0, contentTop: 0, contentWidth: 100, contentHeight: 200,
    }), false)
})

test('显示策略：32px 滞回、无内容源/源码模式不显示', () => {
    const base = { pref: true, hasSource: true, viewportHeight: 900, currentlyVisible: false }
    assert.equal(shouldShow({ ...base, docHeight: 1000 }), true)
    assert.equal(shouldShow({ ...base, docHeight: 930 }), false)
    assert.equal(shouldShow({ ...base, currentlyVisible: true, docHeight: 880 }), true)
    assert.equal(shouldShow({ ...base, currentlyVisible: true, docHeight: 860 }), false)
    assert.equal(shouldShow({ ...base, pref: false, docHeight: 2000 }), false)
    assert.equal(shouldShow({ ...base, hasSource: false, docHeight: 2000 }), false)
})

test('只读克隆：去交互、去编辑态、SVG id 改写', (t) => {
    const dom = defineDom()
    t.after(() => dom.window.close())
    const root = document.createElement('div')
    root.innerHTML = `
        <p contenteditable="true" class="ProseMirror-focused">正文</p>
        <script>alert(1)</script>
        <button>按钮</button>
        <a href="file:///tmp/x">链接</a>
        <img src="javascript:alert(1)">
        <input type="text" value="x">
        <input type="checkbox" checked>
        <div id="outside">外部 id</div>
        <svg aria-labelledby="g"><defs><linearGradient id="g"><stop offset="0"></stop></linearGradient></defs><use href="#g"></use><style>#g { fill: red }</style></svg>
    `
    const clone = cloneReadonly(root)
    assert.equal(clone.getAttribute('aria-hidden'), 'true')
    assert.equal(clone.querySelector('script'), null)
    assert.equal(clone.querySelector('button'), null)
    assert.equal(clone.querySelector('a').hasAttribute('href'), false)
    assert.equal(clone.querySelector('img').hasAttribute('src'), false)
    assert.equal(clone.querySelector('p').hasAttribute('contenteditable'), false)
    assert.equal(clone.querySelector('.ProseMirror-focused'), null)
    assert.equal(clone.querySelector('input[type="text"]'), null)
    const checkbox = clone.querySelector('input[type="checkbox"]')
    assert.equal(checkbox.disabled, true)
    assert.equal(checkbox.checked, true)
    assert.equal(clone.querySelector('#outside'), null)
    assert.match(clone.querySelector('linearGradient').id, /^mdp-thumb-\d+-g$/)
    assert.match(clone.querySelector('use').getAttribute('href'), /^#mdp-thumb-\d+-g$/)
    assert.match(clone.querySelector('svg').getAttribute('aria-labelledby'), /^mdp-thumb-\d+-g$/)
    assert.match(clone.querySelector('style').textContent, /#mdp-thumb-\d+-g/)
})

test('缩略图 surface：fit 顶左、空白区不跳转、拖动按内容高度折算', (t) => {
    resetPorts()
    const dom = defineDom()
    Object.defineProperty(dom.window, 'scrollY', { value: 100, configurable: true })
    state.codeMode = false
    state.sourceMode = false
    state.mode = 'markdown'
    const sources = fakeSources()
    provide('minimapSources', {
        markdown: () => sources.markdown,
        code: () => sources.code,
    })
    const minimap = createMinimap()
    t.after(() => {
        minimap.stop()
        resetPorts()
        dom.window.close()
    })

    assert.equal(minimap.start(), true)
    assert.equal(document.body.classList.contains('minimap-shown'), true)
    let info = minimap.info()
    assert.equal(info.visible, true)
    assert.equal(info.surface, 'markdown')
    assert.equal(info.mode, 'fit')
    assert.equal(info.snapshotCount, 1)
    assert.equal(info.pageWidth, 800)
    assert.equal(info.pageHeight, 2000)
    assert.equal(info.scale, 0.15)
    assert.equal(info.contentWidth, 120)
    assert.equal(info.contentHeight, 300)
    assert.equal(info.redrawCount, 1)

    const rail = document.getElementById('minimap')
    const box = rail.querySelector('.minimap-viewport')
    // content 300px 高，scrollTop=100/1000 → 顶部 30px，视口 400/1000 → 120px。
    assert.equal(box.style.top, '30px')
    assert.equal(box.style.height, '120px')
    assert.equal(box.style.width, '120px')

    // 视口框内向下拖 60px：60 / (300/1000) = 200 文档像素；不是按整条轨道折算。
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 60, button: 0, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointermove', { clientX: 10, clientY: 120, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointerup', { clientX: 10, clientY: 120, bubbles: true }))
    assert.ok(sources.markdown.scrollTop > 295 && sources.markdown.scrollTop < 305)

    // 点击页面下方空白（y=500，内容只到 300）：不跳转。
    sources.markdown.scrollTop = 100
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 500, button: 0, bubbles: true }))
    assert.equal(sources.markdown.scrollTop, 100)

    // 点击页面内容 y=250：目标 (250/300*1000)-200 = 633 → 夹到底 600。
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 250, button: 0, bubbles: true }))
    assert.equal(sources.markdown.scrollTop, 600)

    minimap.setVisible(false)
    assert.equal(document.body.classList.contains('minimap-shown'), false)
    assert.equal(minimap.info().pref, false)

    minimap.setVisible(true)
    state.codeMode = true
    minimap.refresh()
    info = minimap.info()
    assert.equal(info.surface, 'code')
    assert.equal(info.mode, 'fit')
    assert.equal(info.snapshotCount, 3)
    assert.equal(info.pageHeight, 4000)
    assert.equal(info.contentHeight, 600)

    state.sourceMode = true
    minimap.refresh()
    assert.equal(minimap.info().surface, 'source')
    assert.equal(document.body.classList.contains('minimap-shown'), false)
})

test('缩略图 surface：长文固定 120 宽裁切，拖视口框顶底对齐', (t) => {
    resetPorts()
    const dom = defineDom()
    let pageScroll = 0
    Object.defineProperty(dom.window, 'scrollY', { get: () => pageScroll, configurable: true })
    state.codeMode = false
    state.sourceMode = false
    state.mode = 'markdown'
    const long = {
        scrollTop: 0,
        snapshots: 0,
        measure() {
            return {
                contentWidth: 800,
                docHeight: 10000,
                viewportHeight: 800,
                scrollTop: pageScroll,
            }
        },
        snapshot() {
            this.snapshots += 1
            return makePage(800, 10000)
        },
        scrollTo(top) {
            pageScroll = Math.max(0, Math.min(9200, Number(top) || 0))
            this.scrollTop = pageScroll
        },
    }
    provide('minimapSources', {
        markdown: () => long,
        code: () => long,
    })
    const minimap = createMinimap()
    t.after(() => {
        minimap.stop()
        resetPorts()
        dom.window.close()
    })

    assert.equal(minimap.start(), true)
    let info = minimap.info()
    assert.equal(info.visible, true)
    assert.equal(info.mode, 'crop')
    assert.equal(info.snapshotCount, 1)
    assert.equal(info.pageWidth, 800)
    assert.equal(info.pageHeight, 10000)
    assert.equal(info.scale, 0.15)
    assert.equal(info.contentWidth, 120)
    assert.equal(info.contentHeight, 1500)
    assert.equal(info.contentTop, 0)
    assert.equal(info.panTop, 0)
    assert.equal(info.panRange, 732)

    const rail = document.getElementById('minimap')
    const stage = rail.querySelector('.minimap-stage')
    const box = rail.querySelector('.minimap-viewport')
    assert.equal(stage.style.top, '0px')
    assert.equal(box.style.width, '120px')
    assert.equal(box.style.height, '120px')
    assert.equal(box.style.top, '0px')

    // 正文滚到中段：页面按整篇进度平移，视口框也按整篇进度落在轨道中段。
    pageScroll = 5000
    minimap.refresh()
    info = minimap.info()
    assert.equal(info.contentTop, -398)
    assert.equal(info.panTop, 398)
    assert.equal(info.viewportTop, 352)
    assert.equal(Math.round(parseFloat(stage.style.top)), -398)

    // 拖动视口框 100px：框跟着指针移动 100px，内容进度同步。
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 360, button: 0, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointermove', { clientX: 10, clientY: 460, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointerup', { clientX: 10, clientY: 460, bubbles: true }))
    assert.ok(Math.abs(pageScroll - (5000 + (100 / 648) * 9200)) < 1)
    minimap.refresh()
    info = minimap.info()
    assert.equal(info.viewportTop, 452)

    // 回到同一中段，再从视口框向下拖到轨道底：页面底边贴住轨道底。
    pageScroll = 5000
    minimap.refresh()
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 360, button: 0, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointermove', { clientX: 10, clientY: 767, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointerup', { clientX: 10, clientY: 767, bubbles: true }))
    assert.equal(pageScroll, 9200)
    minimap.refresh()
    info = minimap.info()
    assert.equal(info.panTop, 732)
    assert.equal(info.contentTop, -732)
    assert.equal(info.viewportTop, 648)
    assert.equal(stage.style.top, '-732px')

    // 从底部往上拖到轨道顶：回到文档开头，页面顶边贴住轨道顶。
    rail.dispatchEvent(new dom.window.MouseEvent('pointerdown', { clientX: 10, clientY: 650, button: 0, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointermove', { clientX: 10, clientY: 0, bubbles: true }))
    rail.dispatchEvent(new dom.window.MouseEvent('pointerup', { clientX: 10, clientY: 0, bubbles: true }))
    assert.equal(pageScroll, 0)
    minimap.refresh()
    assert.equal(minimap.info().panTop, 0)
    assert.equal(stage.style.top, '0px')
})
