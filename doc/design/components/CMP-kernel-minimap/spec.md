---
layer: design
module: kernel
component: CMP-kernel-minimap
status: active
updated: 2026-11-05
---

# CMP-kernel-minimap 组件规格

## 组件卡

- 状态：active
- 单元：内核功能组件（第七个）
- 层 / 类型：L1b 能力组件；阅读辅助
- 业务价值：把「右侧整页缩略图（长文固定宽度裁切）」收敛为一个只做阅读/定位的组件；Markdown 面与代码面共享同一套快照挂载、等比缩放、视口映射和指针交互，而不是各写一份。
- 负责：缩略图栏 DOM、只读快照的挂载与等比缩放、视口框几何、滚动同步、点击/拖动定位、有效显示判定（32px 滞回）、快照调度、`minimapInfo` 诊断。
- 不负责：文档内容与 Markdown/代码渲染（`CMP-kernel-editor` / `CMP-kernel-code`）；快照内容与脱敏（source 工厂）；滚动位置本身（浏览器滚动模型）；菜单/偏好持久化（`CMP-app-shell`）；文件 IO/导出；主题定义（只读 CSS 变量）。
- 内部逻辑：
  - `minimap.js`：生命周期、栏/舞台/视口 DOM、观察器、滚动/指针/滚轮、快照重建与缩放调度、诊断。
  - `thumbnail.js`：纯几何 `fitThumbnail`，返回 `fit`（整页）或 `crop`（固定 120px 宽、页面高于轨道）布局；顶左。
  - `viewport.js`：纯几何（内容矩形、视口框、裁切平移量 `cropPanTop`、整篇进度拖动 `scrollTopForThumbDrag`、点击居中、夹取、最小框高 12px）。
  - `visibility.js`：纯函数 `shouldShow`（偏好 ∧ 有 source ∧ 内容溢出；32px 滞回）。
  - `ops.js`：`setMinimapVisible` / `minimapInfo` 两个 host op。
  - `minimap.css`：120px 固定轨、146px 正文预留、查找栏避让、源码模式与打印隐藏、只读快照的指针/选择隔离。
- 拥有的数据：当前 source、有效显示状态、内容面（markdown/code/none）、快照 DOM 生命周期、视口框几何、快照重建次数；不拥有文档内容、滚动位置、偏好。
- 变化轴：快照内容、缩放口径、固定宽度、主题、指针映射。
- 公开契约（组件级）：
  - `CMP-kernel-minimap#surface`：`minimapSurface` 端口 `{start, stop, setVisible, info}`；由组合根提供，`document/init` 与 minimap ops 消费。
  - `CMP-kernel-minimap#ops`：`setMinimapVisible{visible:boolean}`、`minimapInfo` → `{visible,pref,started,surface,mode,...几何}`。
  - `CMP-kernel-minimap#sources`：消费 `minimapSources` 端口的 `{markdown, code}` 两个工厂；不 import editor/code。
- 入口：
  - `web/src/kernel/components/minimap/minimap.js#createMinimap`
  - `web/src/kernel/components/minimap/minimap.js#createMinimapSurface`
  - `web/src/kernel/components/minimap/visibility.js#shouldShow`
  - `web/src/kernel/components/minimap/thumbnail.js#fitThumbnail`
  - `web/src/kernel/components/minimap/viewport.js#viewportMetrics`
  - `web/src/kernel/assemble.js`（注入 `minimapSurface` / `minimapSources`）
  - `web/src/page.js`（产品入口 `minimap.start()`）
- 依赖：只 import 自身目录 + `shared` + `semantics`；跨组件只经 `shared/ports.js`。DOM / Pointer Events / CSS transform 标准能力，零新增第三方依赖。
- 冷热属性：滚动是热路径，只更新视口框（rAF）；快照只在内容/主题/缩放/尺寸变化时防抖重建 250ms；滚动不 `measure` 整篇、不 `cloneNode`。
- 尺寸预算：实现约 820 行（minimap 605 + thumbnail 44 + viewport 142 + visibility 12 + ops 14），CSS 119 行，测试 386 行；实测见 `wc -l`。
- 单独运行：`cd web && node --test test/minimap.test.js`；产品视觉 `./.build/debug/MDPreview --screenshot out.png <长文.md>`。
- 删除测试：删掉后 Markdown 与代码两面各自重建轨道、快照、视口和指针映射，复杂度复制而非消失 → 真边界。

## 公开契约细节

- `#surface` 的不变量：`start()` 幂等，首次调用才建轨道 DOM；`stop()` 移除观察器、指针监听与 `body.minimap-shown`；`setVisible(false)` 只关有效显示，不改偏好；`info()` 是纯读快照，不触发重排。
- `#ops` 的不变量：`setMinimapVisible` 只改本组件偏好，返回 `{visible,effective}`；`minimapInfo` 永远返回对象（未 start 时 `started:false`，不抛错）；两者都不写文件、不发 `changed`。
- `#sources` 的不变量：工厂返回 `{root, measure(), scrollTo(), snapshot()}`；`measure()` 的坐标是文档顶为 0 的视觉 CSS px；`snapshot()` 返回一个已脱敏、顶左排好的页面 `Element`，本组件只挂载/缩放，不感知 ProseMirror / Prism 类型。
- 缩放不变量：先算整页 fit `scale = min(railWidth / pageWidth, railHeight / pageHeight)`；若 fit 后宽度 `< railWidth`（长文），改按 `scale = railWidth / pageWidth`，页面宽固定 120px、高度可大于轨道。页面 `left=0`，不横向居中；fit 模式顶部/右侧可留空，crop 模式纵向裁切。
- 定位不变量：点击/拖动只认 `snapshot` 页面缩放后的实际矩形 `{left,top,width,height}`；fit 模式 `contentTop=0`，crop 模式 `contentTop=-panTop`；轨道空白区不响应。点击目标按 `localY/contentHeight*docHeight - viewportHeight/2` 计算；拖动的 fit 模式按 `contentHeight/docHeight` 反算，crop 模式把视口框当作整篇滚动条滑块、按 `railHeight - boxHeight` 1:1 拖动；两者夹取到 `[0, docHeight - viewportHeight]`。
- 裁切不变量：`panTop = progress * (pageHeight - railHeight)`，`progress = scrollTop / (docHeight - viewportHeight)`；视口框顶 = `progress * (railHeight - boxHeight)`，即与整篇滚动条进度同步。轨道顶/底分别对齐文档开头/结尾；拖动时指针与视口框 1:1 跟手。
- 视口不变量：视口框宽等于内容宽度，高度至少 12px；滚动只改 `top` 与高度，不重建快照；`redrawCount` 只在快照重建时增加。
- 显示不变量：`pref=false`、无 source、源码模式、`docHeight - viewportHeight <= 32` 时不显示；显示后跌破 32px 才隐藏，避免布局抖动。
- 失败模式：`snapshot()` 为空/异常/尺寸为 0 → 隐藏轨道、`console.warn` 一次、不抛；measure 异常 → 隐藏；只读克隆脱敏失败不得把脚本/按钮/可编辑节点挂进轨道；`javascript:`/`vbscript:`/`data:text/html` 等 URL 直接剥离。
- 性能不变量：滚动零 DOM 测量、零 `cloneNode`、零 `getComputedStyle`；快照重建才读取页面尺寸与主题。

## `minimapInfo` 字段

`{started,pref,visible,surface,hasSource,mode,docHeight,viewportHeight,scrollTop,railHeight,railWidth,viewportTop,viewportBoxHeight,viewportLeft,viewportBoxWidth,pageWidth,pageHeight,contentLeft,contentTop,contentWidth,contentHeight,panTop,panRange,scale,snapshotCount,redrawCount,startedAt}`

- `mode`：`fit`（短文档整页）/ `crop`（长文固定宽裁切）/ `none`。
- `panTop`：crop 模式页面相对轨道的向上平移量；`panRange`：最大平移量（0 表示 fit/不需要平移）。
- `snapshotCount`：本会话成功挂载快照次数；`redrawCount`：快照重建次数。
- 不暴露 DOM 节点、像素数据或 ProseMirror/Prism 类型。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#surface` | `web/test/minimap.test.js`「缩略图 surface：fit 顶左、空白区不跳转、拖动按内容高度折算」+「长文固定 120 宽裁切，拖视口框顶底对齐」；`--selftest`「缩略图 默认显示」「缩略图 正文预留生效」「缩略图 开关隐藏/恢复」 |
| `#ops` | `web/test/core.test.js`「缩略图：init 应用偏好，setMinimapVisible/minimapInfo 经端口工作」；`contract.test.js` payload 校验 |
| 显示/滞回 | `minimap.test.js`「显示策略：32px 滞回、无内容源/源码模式不显示」 |
| 缩放/视口/指针 | `minimap.test.js`「页面缩放：等比、顶左对齐」+「视口几何：以内容矩形为基准，空白区不参与」+ 两个 surface 用例（含长文 1:1 跟手） |
| 只读脱敏 | `minimap.test.js`「只读克隆：去交互、去编辑态、SVG id 改写」 |
| 视觉/打印/主题 | 人工 `--screenshot`；`@media print` 与源码模式规则由 CSS 断言/人工核对 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 有效显示 / 当前内容面 | 本组件 | 本组件 | 会话级；偏好不在此 |
| 视口框几何 | 本组件 | 本组件 | 与滚动同帧 |
| 快照 DOM | 本组件 `snapshot()` 消费方 | 本组件 | 由 source 派生；隐藏/重建即释放 |
| 可见性偏好 | `CMP-app-shell`（`UserDefaults["minimapVisible"]`） | 本组件 | 全局单一来源；本组件只读 |

预算：快照目标 ≤50ms（典型长文），滚动更新 ≤1ms；快照重建次数有诊断计数；滚动热路径零 DOM 测量、零样式读取。

## 验证债

- 真实拖拽/触控板惯性、深色主题、窗口缩放仍属人工点验（R8）；长文裁切的 120px 宽、整篇进度视口、顶底对齐需真机长文复核。
- 快照耗时以当前实现实测为准；若长文超 50ms，先查克隆/脱敏与页面尺寸，不改变交互语义。
- 快照脱敏对复杂 Mermaid/KaTeX 的 SVG 引用覆盖以样例与单元测试为准，真实复杂图仍需人工看样。

## 删除测试

删掉本组件后两个内容面各自重建缩略栏、快照、视口和指针映射，复杂度不会消失 → 保留为真边界。
