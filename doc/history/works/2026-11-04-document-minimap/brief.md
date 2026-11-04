---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 工序 brief：右侧文档缩略图与定位（P1）

> **实现状态（2026-11-05，已收口并归档）**：已按 v2 七组件结构落地——新增第七个功能组件
> `CMP-kernel-minimap`；Markdown/代码只读快照分别作为 `CMP-kernel-editor` / `CMP-kernel-code`
> 的内部工厂，经 `assemble.js` 的 `minimapSources` 端口注入；偏好归 `CMP-app-shell`。
> 2026-11-05 根据原型用户确认改为 **DOM 克隆 + 顶对齐 + fit**，并按页面实际缩略矩形定位。
> Node 85 项 + `--selftest`（含缩略图诊断/开关/正文预留）全绿；文档已回填，用户确认
> Markdown/代码窗口效果并允许发布（见 §12）。

> 需求卡：[REQ-0011](../../../requirements/REQ-0011-document-minimap.md)；场景：[SCN-0017](../../../design/scenarios/navigation/in-document/minimap-navigation/scenario.md)；组件：[CMP-minimap](../../../design/components/CMP-minimap/spec.md)、[CMP-editor](../../../design/components/CMP-editor/spec.md)、[CMP-code-view](../../../design/components/CMP-code-view/spec.md)、[CMP-app-shell](../../../design/components/CMP-app-shell/spec.md)；视觉目标：[compare.png](compare.png)；对比页：[compare.html](compare.html)（含两张 120px 轨道原图）。

## 1. 需求

2026-11-04 用户提出：在右侧增加类似 Sublime 的文档内容整体预览 + 定位组件。经澄清确认：

- 覆盖 Markdown 渲染视图与代码只读视图；**不覆盖** Markdown 源码模式。
- 选择**真缩略图**：缩略图里能看出真实字形、图片/图表轮廓，接近缩小版页面；接受长文档采样/降级。
- 默认显示，可从「视图 → 显示文档缩略图」关闭；偏好跨窗口记忆，新窗口继承。
- 用户确认 P1 设计与组件边界后已进入编码；本工序同时交付实现、测试与回填文档。

## 2. 现状与问题

- WebView 整页滚动：Markdown 用 `#app`、代码用 `#code-view`，两者都依赖 `window` 滚动；当前没有右侧阅读辅助，长文只能拖系统滚动条。
- 代码视图已经有逻辑行结构（`.code-line`、`lineMeta`）、查找偏移和行号开关，适合提供逐行投影；Markdown 编辑器有 ProseMirror 顶层块与图片/Mermaid NodeView，适合提供块级投影。
- 正文宽度策略是 `#app`/`#code-view` 的 `min-width: 860px` + `--app-zoom`；任何固定栏都必须处理缩放、窄窗横向滚动、⌘F 查找栏和系统滚动条，不能覆盖正文。
- 源码模式是 `position: fixed` 的 textarea；代码文档只读、无脏标记、512 KB 上限；缩略图不能改变这些语义。
- 现有 `#find-bar` 固定在右上（`right: 18px`），缩略图出现后会与它重叠；打印/PDF 以内容面为基准，缩略图不应进入。

## 3. 范围

### 做

- 新增 `CMP-minimap` / `CMP-kernel-minimap`：右侧固定栏、只读 DOM 快照、顶左等比缩放、视口框、滚动同步、点击/拖动定位、有效显示、诊断信息。
- `CMP-kernel-editor` 增加只读 Markdown source 工厂（`createMarkdownMinimapSource`）：Markdown 顶层块几何/文字/图片；不暴露 ProseMirror 类型。
- `CMP-kernel-code` 增加只读代码 source 工厂（`createCodeMinimapSource`）：代码逻辑行文本/几何/颜色；不重绘 token、不写文件。
- `CMP-app-shell` 增加 `#minimap-menu`：视图菜单勾选项、`UserDefaults["minimapVisible"]`、跨窗口广播；源码模式置灰。
- v2 `contract/ops.js` 新增 `setMinimapVisible`、`minimapInfo` 与 `init.opts.minimapVisible`；不新增 JS→Swift op。
- 正文预留、查找栏避让、打印隐藏、主题/缩放/尺寸重绘、3+1 自动化与截图/人工验证。
- 文档同步：REQ、SCN、组件规格、architecture 落点、README、roadmap、selftest 断言表。

### 不做

- 源码模式缩略图、目录/大纲/TOC、章节折叠、查找命中标记、hover 预览。
- 缩略图内编辑/选择/拖拽内容、缩略图宽度拖拽、逐文档宽度、独立窗口/停靠。
- 图片/Mermaid 内部文字逐字可读、缩放后逐字像素还原。
- 代码折叠、编辑、LSP、多标签、Finder 关联等既有非目标。
- PDF/打印/HTML 导出包含缩略图。
- 不为缩略图引入新依赖、类型系统或桥协议 v2。

## 4. P1 定级与确认

**定级 P1**：新增组件 `CMP-minimap` / `CMP-kernel-minimap`；新增内部 source 端口与 2 个 host op；改 `CMP-kernel-editor` / `CMP-kernel-code` / `CMP-kernel-document` / `CMP-app-shell` 的实现契约；新增菜单偏好与场景树节点（`navigation/in-document`）。触发“新增组件、核心契约、分层依赖、场景树结构”四项，按 P1 处理。

**人工门**：

1. **设计门（已过）**：用户确认组件切分、source 注入方式、真缩略图绘制方式、固定 120px、场景放在 `navigation/in-document`；2026-11-04 转入实现。
2. **最终门**：实现 + selftest + 截图 + 人工点验后，用户最终确认才收口归档。

**待确认项**：

| # | 决策 | 建议 |
|---|---|---|
| D1 | 新组件 + source 投影，而不是把缩略图塞进 editor/code-view | 采纳；两个内容面各自提供只读投影，组合根注入 |
| D2 | 真缩略图用 DOM 克隆 + 顶左等比缩放（2026-11-05 修订） | 采纳；快照只读、脱敏、只挂一份；Canvas 采样方案已废弃 |
| D3 | 固定 120px，正文预留 146px，系统滚动条保留 | 采纳；不做宽度拖拽 |
| D4 | 新场景 `SCN-0017` 放 `navigation/in-document` | 采纳；比塞进 SCN-0002/0016 更能承载跨内容面旅程 |

## 5. 组件级修改方案

### 5.1 组件地图与依赖方向

```
web/src/page.js + kernel/assemble.js（组合根）
  ├─ 创建 CMP-kernel-minimap
  ├─ provide('minimapSources', {markdown: createMarkdownMinimapSource, code: createCodeMinimapSource})
  ├─ provide('minimapSurface', createMinimapSurface(minimap))
  └─ 按 state.sourceMode / state.codeMode 解析当前 source

CMP-kernel-minimap（新，第七个功能组件）
  ├─ 只读 source 数据（普通对象，不 import 编辑器/代码）
  ├─ 只读 DOM 快照 + 顶左等比缩放 + 视口框 + 指针映射
  └─ 诊断 minimapInfo()

CMP-app-shell（Swift，L2）
  ├─ 视图菜单「显示文档缩略图」
  ├─ UserDefaults["minimapVisible"]（唯一写入口）
  └─ 广播 setMinimapVisible 给所有窗口

CMP-document-io / CMP-export：不改；缩略图不进入导出内容。
```

依赖规则：

- `CMP-kernel-minimap` 不 import `CMP-kernel-editor` / `CMP-kernel-code` 的实现；source 是结构化普通对象，由 `assemble.js` 的端口注入。
- `CMP-kernel-editor` / `CMP-kernel-code` 不 import minimap；只返回投影工厂，不知道谁消费。source 不提升为领域公开契约。
- 偏好唯一写入口是 `CMP-app-shell`；组件不写 `UserDefaults`。
- 滚动位置唯一权威是浏览器；组件只发 `scrollTo` 命令，不维护第二份滚动状态。
- 同一内容面同一时刻只有一个 source；切换时释放旧观察器。

### 5.2 source 形状（内部工厂，不是公开契约）

实现修正：第一门草案把 source 写成 `CMP-editor#minimap-source` / `CMP-code-view#minimap-source` 的公开契约；落地时改为两个内核组件的内部工厂，经 `minimapSources` 端口消费，避免把缩略图语义提升成领域契约。以下形状仍是两端共同遵守的实现约束：

`CMP-kernel-minimap` 读取：

```js
{
  root: Element,
  measure(): { contentWidth, docHeight, viewportHeight, scrollTop },
  scrollTo(y),
  snapshot(): Element | null
}
```

- 坐标统一为**文档顶为 0 的视觉 CSS 像素**；`measure` 只跑几何，不碰内容 DOM；组件不依赖 ProseMirror/Prism 内部类型。
- Markdown `snapshot()`：以 `#app` 的宽度/内边距/zoom/背景/颜色建页面容器，挂 `.ProseMirror` 的只读 DOM 副本；副本由 `shared/readonly-clone` 去脚本/控件/编辑态并重写 SVG id 引用。
- 代码 `snapshot()`：以 `#code-view` 的宽度/内边距/zoom/背景/颜色/字体/行高/行号宽度建页面容器，挂 `<code>` 的只读 DOM 副本；`no-line-numbers` 在页面容器上还原。
- `scrollTo` 必须夹取；`measure`/`snapshot` 不得修改正文/选区/文档/脏基线，不发 `changed`。快照失败返回 `null`，组件隐藏并警告一次。

### 5.3 缩略图呈现：只读 DOM 快照

**决策（2026-11-05）**：DOM 克隆 + 顶对齐 + fit，不截图、不引入依赖、不再绘制 Canvas 内容层。

- 页面挂载：轨道内 `.minimap-stage` 顶左；页面 `transform-origin: 0 0`；先测未缩放页面矩形，再 `scale = min(railWidth/pageWidth, railHeight/pageHeight)`。
- 顶左：页面 `left=0, top=0`；页面较窄/较短时右侧/下方留空，不居中。
- 视口框：宽 = 缩放后页面宽；高 = `viewportHeight/docHeight * contentHeight`，最小 12px；顶 = `scrollTop/docHeight * contentHeight`。
- 定位：只认页面缩放后的实际矩形；点击目标 `localY/contentHeight*docHeight - viewportHeight/2`；拖动位移 `/ (contentHeight/docHeight)`；轨道空白区不响应。
- 重绘：内容/主题/缩放/尺寸变化防抖 250ms 重建快照；滚动只更新视口框；快照只在有效显示时构建，隐藏释放。
- 安全：副本去 `script/button/input(除任务 checkbox)/textarea/select`、`contenteditable`/`tabindex`/`on*`/链接 `href`、编辑态 class；SVG 内部 id 加前缀并重写 `href`/`url(#id)`/style，SVG 外 id 移除；`javascript:`/`vbscript:`/`data:text/html` URL 剥离。
- 失败：快照异常隐藏 + `console.warn` 一次；图片/图表加载失败保留原占位或空框。

- 固定栏：`right: 10px`、宽 120px、`top: 0`、`height: 100vh`、`z-index: 60`；右侧留 8px 系统滚动条。
- 正文预留：`body.minimap-shown { padding-right: 146px; }`；`body` 不加 `zoom`，所以 `--app-zoom` 不会缩放预留宽度。`#app`/`#code-view` 的 860px 下限不变，因此窗口可视宽 < 约 1006px 时出现横向滚动；v1 不自动隐藏（固定栏的明确代价）。
- 查找栏：`body.minimap-shown #find-bar { right: calc(18px + 120px + 10px); }`，左移避让 120px 栏 + 间距。
- 源码模式：不挂 `minimap-shown`，`#source-editor` 保持全屏；菜单项置灰。
- 打印/PDF：`@media print` 隐藏固定栏并取消 `padding-right`；HTML 导出只取编辑器内容，天然不含缩略图。
- 有效显示：偏好 ∧ source ∧ 溢出；溢出用 32px 滞回（显示 `> +32`，隐藏 `<= -32`），避免“显示→正文变窄→高度增加→隐藏”的临界抖动。
- 偏好：`UserDefaults["minimapVisible"]` 默认 true；**key 不存在时必须按 true**（`object(forKey:) == nil` 或 `register(defaults:)`，不能用 `bool(forKey:)` 直接得到 false）；菜单勾选反映偏好；切换广播所有窗口；源码模式置灰但勾选保留。

### 5.5 滚动与指针

- 滚动：`scroll` passive → rAF 合并 → 只改视口框 `top`/`height`；`sy = contentHeight / docHeight`，`boxH = max(12, viewportH * sy)`；贴底夹取。
- 点击：只认页面实际缩略矩形；目标文档 y = `(pointerY - contentTop)/contentHeight × docHeight`；把目标居中 → `scrollTo(y - viewportH/2)`；夹取由 source 负责；轨道空白区不响应。
- 拖动：命中视口框 → 记录偏移；位移 `/ sy`；`setPointerCapture`；移动时连续 `scrollTo`；`pointerup/cancel` 释放并清状态；`touch-action: none`，不抢焦点、不选中正文。
- 滚轮：不拦截，沿用浏览器页面滚动。

### 5.6 桥与原生菜单

| 方向 | 名称 | 语义 |
|---|---|---|
| Swift→JS | `init(markdown, opts)` 新增 `opts.minimapVisible?: Bool` | 首帧按偏好决定；不传沿用默认 true |
| Swift→JS | `setMinimapVisible{visible: Bool}` | 只改可见性偏好投影，不重建编辑器、不写文件；握手前调用回 `not_ready`，不缓存 |
| 诊断 | `minimapInfo` | 返回 `{started,pref,visible,surface,hasSource,mode,docHeight,viewportHeight,scrollTop,railHeight,railWidth,viewportTop,viewportBoxHeight,viewportLeft,viewportBoxWidth,pageWidth,pageHeight,contentLeft,contentTop,contentWidth,contentHeight,scale,snapshotCount,redrawCount,startedAt}`；`mode` 为 `fit/none` |
| JS→Swift | 无新增 op | 偏好写入口只在原生菜单；web 不回写 UserDefaults |

`CMP-app-shell#minimap-menu`：

- 菜单：视图 →「显示文档缩略图」，checkmark 反映偏好。
- 可用性：Markdown 渲染面与代码面可用；源码模式置灰；无文档/目录空文档可用但无效果。
- 动作：切换 `UserDefaults["minimapVisible"]` → 更新所有窗口菜单勾选 → 对每个窗口调用 `setMinimapVisible`。
- 初始化：窗口装载内容时把偏好放进 `init` opts；代码文档切换时沿用同一偏好。

### 5.7 修改点与波及面

| 文件/层 | 改动 | 不改 |
|---|---|---|
| `web/src/kernel/components/minimap/*`（新） | 生命周期、快照挂载/顶左缩放、可见性、滚动/指针、快照调度、诊断、两个 op | 编辑器/代码内部 |
| `web/src/kernel/components/minimap/minimap.css`（新） | 固定栏、正文预留、查找栏避让、源码模式/打印隔离 | `#app` 原有排版 |
| `web/src/kernel/assemble.js` | 创建组件、提供 `minimapSurface` / `minimapSources` | 既有装配顺序语义 |
| `web/src/kernel/contract/ops.js` | `setMinimapVisible`、`minimapInfo`（39→41） | 既有 op 语义 |
| `web/src/kernel/components/document/ops.js` | `init` 应用 `opts.minimapVisible` | 文档/脏基线真源 |
| `web/src/kernel/components/editor/editor.js` | `createMarkdownMinimapSource`（内部工厂） | Markdown 编辑/序列化 |
| `web/src/kernel/components/code/code-view.js` | `createCodeMinimapSource`（内部工厂） | 高亮/行号/查找 |
| `web/src/page.js` | `minimap.start()` | 既有启动顺序语义 |
| `Sources/MDPreview/DocumentWindowController.swift` | 偏好、菜单动作/校验、广播、init 选项、源码模式联动 | 打开/保存/抽屉/图片 |
| `Sources/MDPreview/AppDelegate.swift` | 菜单项、MenuID、跨窗口广播 | 窗口路由/最近文件 |
| `Sources/MDPreview/Selftest.swift` | 缩略图诊断/默认显示/正文预留/开关断言 | 既有断言 |
| `README.md` / `doc/*` | 特性、边界、规格、场景、路线图、索引 | 历史归档件 |

## 6. 走查

1. **正常流程**：打开长 Markdown → source 快照 → 有效显示 → 顶左缩放 → 滚动同步 → 点击/拖动定位 → 菜单关闭 → 正文恢复全宽。
2. **失败流程**：空/短文档不显示；源码模式隐藏并置灰；图片失败保留占位；快照/测量异常隐藏；轨道空白区不响应；点击越界夹取；拖动取消释放；原生调用早于 ready 不报错。
3. **扩展场景**：新增内容块类型只需 source 快照自然带上；新增内容面（如未来的只读 PDF）只需实现同一 `{measure,snapshot,scrollTo}` 契约；不复制缩略图核心。
4. **路径分离**：滚动热路径只更新框；快照重建是防抖低频路径；菜单/偏好是冷路径；快照与测量失败独立降级，不拖垮编辑主路径。
5. **布局临界**：显示/隐藏导致正文宽度变化，用 32px 滞回避免抖动；缩放不放大预留；查找栏避让；打印取消预留。
6. **数据边界**：缩略图不写文档/不写脏基线/不发 changed；偏好只由原生写；source 只读；滚动只由浏览器和 `scrollTo` 改。

## 7. 性能与预算

- 滚动：passive `scroll` + rAF；只改视口框；目标 ≤1ms/帧，不做整篇测量。
- 快照：防抖 250ms；典型长文重建 ≤50ms；超预算先查克隆/脱敏，不改变定位语义。
- 测量：一次 `getBoundingClientRect` 批量读取，不在滚动/输入里读；快照只在显式重建时读样式。
- 内存：只保留一份可见快照，隐藏即释放；不保留 Canvas 位图；source 投影按需生成。
- 组件预算：web 实际约 730 行（不含 CSS/测试），Swift 菜单/偏好 ~44 行，测试 ~250 行；仍远低于 120k token/组件上限。
- 实测：verify 任务记录长 Markdown / 10,000 行代码的快照重建与滚动视口更新时间；超预算先查克隆/脱敏，不改交互。

## 8. 测试计划

| ID | 角色 | 执行 | 断言 |
|---|---|---|---|
| TC-MINI-001 | R1 | `--selftest` | 长 Markdown 显示 rail；`minimapInfo.visible=true`、`mode='fit'`、`snapshotCount>0`、顶左、内容矩形在轨道内；正文 146px 预留；查找栏左移 |
| TC-MINI-002 | R2 | `--selftest`/Node | 视口按内容矩形映射；点击 50% 后居中；空白区不响应；拖动按内容高度折算；滚动不增加 `redrawCount` |
| TC-MINI-003 | R3 | `--selftest` + `--multiwindow-test` | 代码视图 `surface='code'`、快照可见；菜单开关隐藏/显示并跨窗口生效；源码模式/短文档隐藏 |
| TC-MINI-004 | N1 | `--selftest` | 只读克隆去交互/编辑态；快照异常不抛；空文档/未就绪不显示；缩略图操作不增加 `changed` |
| TC-MINI-005 | R1 | `--screenshot` + 真机 | 深色主题、120px、正文/查找栏无遮挡；视觉接近 `compare.png` |
| TC-MINI-006 | R2 | 真机 | 拖动跟手、触控板惯性、指针越界不粘住 |
| TC-MINI-007 | N1 | 真机 | PDF/打印不出现缩略图，正文无预留空白 |

配套：既有 Markdown 编辑/保存/查找、代码行号/查找/大文件、主题/缩放、抽屉、双窗口断言零回归；`--selftest` 输出计数不写死在文档里。

## 9. 任务表

| ID | 类型 | 组件 | 状态 | 依赖 | 装载清单 |
|---|---|---|---|---|---|
| T-2026-11-04-14 | design | CMP-minimap | completed | 无 | 本 brief、REQ-0011、SCN-0017、CMP-minimap/editor/code-view/app-shell spec、architecture |
| T-2026-11-04-15 | change | CMP-kernel-minimap | completed | T14 | `components/minimap/{minimap,renderer,viewport,visibility,ops,index}.js`、`minimap.css`、`assemble.js`、`ops.js`、contract 41 op |
| T-2026-11-04-16 | change | CMP-kernel-editor | completed | T15 契约 | `components/editor/editor.js#createMarkdownMinimapSource`、CMP-kernel-editor spec |
| T-2026-11-04-17 | change | CMP-kernel-code | completed | T15 契约 | `components/code/code-view.js#createCodeMinimapSource`、CMP-kernel-code spec |
| T-2026-11-04-18 | change | CMP-app-shell | completed | T15 | `DocumentWindowController.swift`、`AppDelegate.swift`、菜单/偏好/跨窗口广播 |
| T-2026-11-04-19 | verify | CMP-kernel-minimap | completed（自动）/ 人工待办 | T15–T18 | `Selftest.swift`（诊断/默认显示/正文预留/开关）、`web/test/minimap.test.js`、`--screenshot` |
| T-2026-11-04-20 | change | docs/close | in_progress | T19 | README、architecture、组件规格/场景/需求、roadmap、result/review、归档 |

组件级 WIP=1：T15 先落 minimap 骨架与两个端口；T16/T17 各自在组件内提供 source 工厂（不新增 host op、不暴露给领域卡）；T18 只改 Swift 菜单/偏好；T19 统一验证。实际实现中没有 `minimap-source.js`：source 工厂留在 editor/code 内，避免缩略图反向依赖内容面。

## 10. 装载清单（单任务 ≤250k）

- 技能：`arch-design-spec`、`design-before-coding`、`req-scenario-spec`、`doc-layout-spec`、`dev-execution-spec`。
- 文档：REQ-0011、SCN-0017、CMP-minimap/editor/code-view/app-shell spec、architecture §2.4/§2.7/§3、本 brief。
- 代码：`web/src/kernel/components/minimap/*`、`editor.js`、`code-view.js`、`assemble.js`、`ops.js`、`contract/ops.js`、`page.js`、`minimap.css`；`Sources/MDPreview/DocumentWindowController.swift`、`AppDelegate.swift`、`Selftest.swift`。
- 视觉：`compare.png`、`doc/history/works/2026-11-04-code-view-line-numbers/result.md`（测试/截图口径参考）。

单任务装载应控制在 250k token 内；T15 若同时装载 editor+code-view 超限，按 T16/T17 拆分，不合并任务。

## 11. 风险与开放问题

- **R-真缩略图保真**：DOM 克隆保留真实排版/token/图片，但缩放后不保证逐字可读；验收口径是“标题/正文行/代码/图片轮廓可辨”，以 `.build/minimap-dom-fit.png` 与 `compare.png` 为目标。
- **R-布局抖动**：显示缩略图使正文变窄、文档变高，临界点可能反复；用 32px 滞回覆盖，selftest 加显示/隐藏切换断言。
- **R-快照安全/内存**：只挂一份脱敏副本；去脚本/控件/编辑态，SVG 引用重写；隐藏即释放；测试用 `minimapInfo` + 截图，不做像素断言。
- **R-临时编辑态**：图片/Mermaid 源码编辑时 DOM 是临时控件；脱敏会移除 textarea/按钮，只留静态占位。
- **R-源码模式**：隐藏与菜单置灰必须同时成立；返回渲染面重新挂载 source，不复用旧观察器。
- **R-性能**：超量降级阈值需实测；滚动绝不能触发整篇测量。
- **R-打印/导出**：打印隐藏、取消预留；HTML 导出只取编辑器内容；selftest 用打印截图/结构断言。
- **开放**：v1 固定 120px，宽度拖拽与“缩略图内高亮查找命中”不做；如后续需要，另立需求卡。
- **开放**：快照耗时/长文内存以 verify 实测为准；不回到 Canvas 采样。

## 12. 交付定义

1. ~~用户确认 §4 的 D1–D4（P1 设计门）~~：2026-11-04 已确认并转入实现。
2. T15–T18 完成，source/交互/菜单/桥全部接通。
3. `npm test` 85 项全绿；`--selftest` 含缩略图诊断/默认显示/正文预留/开关断言，既有断言零回归；`--screenshot` 已出 Markdown 与长代码视觉。
4. PDF/打印/HTML 导出不含缩略图；源码模式、短文档、快照异常分支可复现（CSS/Node/用户验收已覆盖）。
5. 人工点验（R8）：用户 2026-11-05 确认 Markdown/代码窗口效果；PDF/打印按 CSS 规则收口。
6. 文档回填并收口；工序已归档，本文件冻结为历史记录。
