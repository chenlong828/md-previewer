---
layer: works
module: navigation
status: active
updated: 2026-11-04
---

# 工序 brief：右侧文档缩略图与定位（P1）

> **暂停排队（2026-11-04）**：工序 [2026-11-04-kernel-v2](../2026-11-04-kernel-v2/brief.md)
> （桥协议 v2 / 内核重构）要重写 `web/src` 的装配与桥层，本工序停在其后；v2 落地后按新结构
> 重启本工序（设计已冻结，不重做澄清）。

> 需求卡：[REQ-0011](../../requirements/REQ-0011-document-minimap.md)；场景：[SCN-0017](../../design/scenarios/navigation/in-document/minimap-navigation/scenario.md)；组件：[CMP-minimap](../../design/components/CMP-minimap/spec.md)、[CMP-editor](../../design/components/CMP-editor/spec.md)、[CMP-code-view](../../design/components/CMP-code-view/spec.md)、[CMP-app-shell](../../design/components/CMP-app-shell/spec.md)；视觉目标：[compare.png](compare.png)；对比页：[compare.html](compare.html)（含两张 120px 轨道原图）。

## 1. 需求

2026-11-04 用户提出：在右侧增加类似 Sublime 的文档内容整体预览 + 定位组件。经澄清确认：

- 覆盖 Markdown 渲染视图与代码只读视图；**不覆盖** Markdown 源码模式。
- 选择**真缩略图**：缩略图里能看出真实字形、图片/图表轮廓，接近缩小版页面；接受长文档采样/降级。
- 默认显示，可从「视图 → 显示文档缩略图」关闭；偏好跨窗口记忆，新窗口继承。
- 本次交付物是**开发文档**，不直接实现；P1 设计与组件边界经用户确认后才进入编码。

## 2. 现状与问题

- WebView 整页滚动：Markdown 用 `#app`、代码用 `#code-view`，两者都依赖 `window` 滚动；当前没有右侧阅读辅助，长文只能拖系统滚动条。
- 代码视图已经有逻辑行结构（`.code-line`、`lineMeta`）、查找偏移和行号开关，适合提供逐行投影；Markdown 编辑器有 ProseMirror 顶层块与图片/Mermaid NodeView，适合提供块级投影。
- 正文宽度策略是 `#app`/`#code-view` 的 `min-width: 860px` + `--app-zoom`；任何固定栏都必须处理缩放、窄窗横向滚动、⌘F 查找栏和系统滚动条，不能覆盖正文。
- 源码模式是 `position: fixed` 的 textarea；代码文档只读、无脏标记、512 KB 上限；缩略图不能改变这些语义。
- 现有 `#find-bar` 固定在右上（`right: 18px`），缩略图出现后会与它重叠；打印/PDF 以内容面为基准，缩略图不应进入。

## 3. 范围

### 做

- 新增 `CMP-minimap`：右侧固定栏、Canvas 真缩略图、视口框、滚动同步、点击/拖动定位、有效显示、超量降级、诊断信息。
- `CMP-editor` 增加只读 `#minimap-source` 投影：Markdown 顶层块几何/文字/图片；不暴露 ProseMirror 类型。
- `CMP-code-view` 增加只读 `#minimap-source` 投影：代码逻辑行文本/几何/颜色；不重绘 token、不写文件。
- `CMP-app-shell` 增加 `#minimap-menu`：视图菜单勾选项、`UserDefaults["minimapVisible"]`、跨窗口广播；源码模式置灰。
- `bridge.js` 新增向后兼容的 `setMinimapVisible`、`minimapInfo` 与 `init` 选项；不新增 JS→Swift op。
- 正文预留、查找栏避让、打印隐藏、主题/缩放/尺寸重绘、3+1 自动化与截图/人工验证。
- 文档同步：REQ、SCN、组件规格、architecture 落点、README、roadmap、selftest 断言表。

### 不做

- 源码模式缩略图、目录/大纲/TOC、章节折叠、查找命中标记、hover 预览。
- 缩略图内编辑/选择/拖拽内容、缩略图宽度拖拽、逐文档宽度、独立窗口/停靠。
- 图片/Mermaid 内部文字可读、逐字像素还原、DOM 克隆。
- 代码折叠、编辑、LSP、多标签、Finder 关联等既有非目标。
- PDF/打印/HTML 导出包含缩略图。
- 不为缩略图引入新依赖、类型系统或桥协议 v2。

## 4. P1 定级与确认

**定级 P1**：新增组件 `CMP-minimap`；新增跨组件 source 投影契约；改 `CMP-editor` / `CMP-code-view` / `CMP-app-shell` 的公开契约；新增桥方法、菜单偏好与场景树节点（`navigation/in-document`）。触发“新增组件、核心契约、分层依赖、场景树结构”四项，按 P1 处理。

**人工门**：

1. **设计门（当前）**：用户确认组件切分、source 契约、真缩略图绘制方式、固定 120px、场景放在 `navigation/in-document`。未确认不编码。
2. **最终门**：实现 + selftest + 截图 + 人工点验后，用户最终确认才收口归档。

**待确认项**：

| # | 决策 | 建议 |
|---|---|---|
| D1 | 新组件 + source 投影，而不是把缩略图塞进 editor/code-view | 采纳；两个内容面各自提供只读投影，组合根注入 |
| D2 | 真缩略图用 Canvas 文字采样 + 图片缩略，不复制 DOM | 采纳；避开 DOM 克隆/临时编辑态/长文内存 |
| D3 | 固定 120px，正文预留 146px，系统滚动条保留 | 采纳；不做宽度拖拽 |
| D4 | 新场景 `SCN-0017` 放 `navigation/in-document` | 采纳；比塞进 SCN-0002/0016 更能承载跨内容面旅程 |

## 5. 组件级修改方案

### 5.1 组件地图与依赖方向

```
main.js（组合根）
  ├─ 创建 CMP-minimap
  ├─ 从 CMP-editor 取 Markdown MinimapSource
  ├─ 从 CMP-code-view 取代码 MinimapSource
  └─ 按当前内容面 setSource(source | null)

CMP-minimap（新，L1 导航）
  ├─ 只读 source 数据（普通对象，不 import 编辑器）
  ├─ Canvas 真缩略图 + 视口框 + 指针映射
  └─ 诊断 minimapInfo()

CMP-app-shell（Swift，L2）
  ├─ 视图菜单「显示文档缩略图」
  ├─ UserDefaults["minimapVisible"]（唯一写入口）
  └─ 广播 setMinimapVisible 给所有窗口

CMP-document-io / CMP-export：不改；缩略图不进入导出内容。
```

依赖规则：

- `CMP-minimap` 不 import `CMP-editor` / `CMP-code-view` 的实现；source 是结构化普通对象，由 `main.js` 注入。
- `CMP-editor` / `CMP-code-view` 不 import `CMP-minimap`；只返回投影，不知道谁消费。
- 偏好唯一写入口是 `CMP-app-shell`；组件不写 `UserDefaults`。
- 滚动位置唯一权威是浏览器；组件只发 `scrollTo` 命令，不维护第二份滚动状态。
- 同一内容面同一时刻只有一个 source；切换时释放旧观察器。

### 5.2 source 契约

`CMP-minimap#source` 读取：

```js
{
  root: Element,
  measure(): {
    contentWidth, docHeight, viewportHeight, scrollTop,
    blocks: [{
      kind, top, height, left, width,
      level?, text?, lineCount?, lines?[], image?, editing?
    }]
  },
  scrollTo(y)
}
```

- 坐标统一为**文档顶为 0 的视觉 CSS 像素**；source 处理 `zoom`/padding/滚动偏移，组件不碰编辑器内部结构。
- Markdown source：只取 `.ProseMirror` 顶层块；标题/段落/列表/引用/代码/表格/图片/公式/Mermaid/分隔线；`text` 供文字采样，`image` 供缩略；图片/Mermaid 正在源码编辑时 `editing=true` 用占位，不读临时 textarea。
- 代码 source：一个 `kind:'code'` 块 + `lines`（逻辑行 `text/top/height/left/width`）；复用 `lineMeta`，行号不进入文本；超过投影预算时按等距采样，保留首尾与当前视口附近行。
- `scrollTo` 必须夹取；`measure` 不得修改 DOM/选区/文档/脏基线，不发 `changed`。

### 5.3 真缩略图绘制

**决策**：Canvas 文字采样 + 图片缩略，不复制 ProseMirror DOM，不截图，不引入依赖。

- 画布：CSS 120 × railHeight，DPR 上限 2；先背景/类型底色，再标题/正文文字、代码行、图片缩略、表格网格、图表占位，最后视口框。
- 文字：字号按映射后的行高夹取 2–6px；标题加粗、正文降低透明度；文字被块宽度裁剪；`fillText` 的观感目标是“能看出真实文字纹理”，不保证逐字可读。
- 代码：逐逻辑行画等宽文字；行高 <1.5px 时退化为行条；不复制 token DOM。
- 图片：`drawImage` 缩略；未加载/失败画占位；**不调用** `getImageData` / `toDataURL`（file:// 图片可能污染 Canvas）。
- 表格/公式/Mermaid：类型底色 + 网格/简化符号；图表内部文字不作为验收。
- 超量降级：`blocks > 2000` 或累计 `lines > 4000` 或 `docHeight > 200000` → `compact` 模式只画块/行密度，仍可定位；`minimapInfo.mode` 暴露 `full/compact`。
- 重绘：内容变化防抖 250ms；主题/缩放/尺寸显式 `refresh`；滚动不重绘内容层。

### 5.4 布局、可见性与开关

- 固定栏：`right: 10px`、宽 120px、`top: 0`、`height: 100vh`、`z-index: 60`；右侧留 8px 系统滚动条。
- 正文预留：`body.minimap-shown { padding-right: 146px; }`；`body` 不加 `zoom`，所以 `--app-zoom` 不会缩放预留宽度。`#app`/`#code-view` 的 860px 下限不变，因此窗口可视宽 < 约 1006px 时出现横向滚动；v1 不自动隐藏（固定栏的明确代价）。
- 查找栏：`body.minimap-shown #find-bar { right: calc(18px + 120px + 10px); }`，左移避让 120px 栏 + 间距。
- 源码模式：不挂 `minimap-shown`，`#source-editor` 保持全屏；菜单项置灰。
- 打印/PDF：`@media print` 隐藏固定栏并取消 `padding-right`；HTML 导出只取编辑器内容，天然不含缩略图。
- 有效显示：偏好 ∧ source ∧ 溢出；溢出用 32px 滞回（显示 `> +32`，隐藏 `<= -32`），避免“显示→正文变窄→高度增加→隐藏”的临界抖动。
- 偏好：`UserDefaults["minimapVisible"]` 默认 true；**key 不存在时必须按 true**（`object(forKey:) == nil` 或 `register(defaults:)`，不能用 `bool(forKey:)` 直接得到 false）；菜单勾选反映偏好；切换广播所有窗口；源码模式置灰但勾选保留。

### 5.5 滚动与指针

- 滚动：`scroll` passive → rAF 合并 → 只改视口框 `transform`/`height`；`sy = railH / docHeight`，`boxH = max(12, viewportH * sy)`；贴底夹取。
- 点击：目标文档 y = pointerY / railH × docHeight；把目标居中 → `scrollTo(y - viewportH/2)`；夹取由 source 负责。
- 拖动：命中视口框 → 记录偏移；`setPointerCapture`；移动时连续 `scrollTo`；`pointerup/cancel` 释放并清状态；`touch-action: none`，不抢焦点、不选中正文。
- 滚轮：不拦截，沿用浏览器页面滚动。

### 5.6 桥与原生菜单

| 方向 | 名称 | 语义 |
|---|---|---|
| Swift→JS | `init(markdown, opts)` 新增 `opts.minimapVisible?: Bool` | 首帧按偏好决定；不传沿用 web 当前值 |
| Swift→JS | `setMinimapVisible(Bool)` | 只改可见性偏好投影，不重建编辑器、不写文件；未 ready 时缓存待应用 |
| 诊断 | `minimapInfo()` | 返回 `{pref, visible, surface, mode, docHeight, viewportHeight, scrollTop, railHeight, viewportTop, viewportHeightPx, blockCount, lineCount, redrawCount, compact}` |
| JS→Swift | 无新增 op | 偏好写入口只在原生菜单；web 不回写 UserDefaults |

`CMP-app-shell#minimap-menu`：

- 菜单：视图 →「显示文档缩略图」，checkmark 反映偏好。
- 可用性：Markdown 渲染面与代码面可用；源码模式置灰；无文档/目录空文档可用但无效果。
- 动作：切换 `UserDefaults["minimapVisible"]` → 更新所有窗口菜单勾选 → 对每个窗口调用 `setMinimapVisible`。
- 初始化：窗口装载内容时把偏好放进 `init` opts；代码文档切换时沿用同一偏好。

### 5.7 修改点与波及面

| 文件/层 | 改动 | 不改 |
|---|---|---|
| `web/src/minimap.js`（新） | 生命周期、source 挂载、可见性、滚动/指针、重绘调度、诊断 | 编辑器/代码内部 |
| `web/src/minimap-source.js`（新） | source 形状与校验辅助（无运行时依赖） | — |
| `web/src/minimap-render.js`（新） | Canvas 真缩略图/compact 绘制 | 主题变量定义 |
| `web/src/minimap.css`（新） | 固定栏、正文预留、查找栏避让、打印隔离 | `#app` 原有排版 |
| `web/src/main.js` | 创建组件、注册两面 source、切换内容面、refresh 钩子 | 既有启动顺序语义 |
| `web/src/bridge.js` | `setMinimapVisible`、`minimapInfo`、init opts | 既有 op 语义 |
| `web/src/state.js` | `minimapVisible` 投影字段 | 文档/脏基线真源 |
| `web/src/editor.js` | `createMarkdownMinimapSource`（只读投影） | Markdown 编辑/序列化 |
| `web/src/code-view.js` | `createCodeMinimapSource`（行投影） | 高亮/行号/查找 |
| `Sources/MDPreview/DocumentWindowController.swift` | 偏好、菜单动作/校验、广播、init 选项、源码模式联动 | 打开/保存/抽屉/图片 |
| `Sources/MDPreview/AppDelegate.swift` | 菜单项、MenuID、跨窗口广播 | 窗口路由/最近文件 |
| `Sources/MDPreview/Selftest.swift` | 缩略图几何/滚动/点击/开关/降级断言 | 既有断言 |
| `README.md` / `doc/*` | 特性、边界、规格、场景、路线图、索引 | 历史归档件 |

## 6. 走查

1. **正常流程**：打开长 Markdown → source 投影 → 有效显示 → 绘制 → 滚动同步 → 点击/拖动定位 → 菜单关闭 → 正文恢复全宽。
2. **失败流程**：空/短文档不显示；源码模式隐藏并置灰；图片失败占位；测量异常隐藏；超量 compact；点击越界夹取；拖动取消释放；原生调用早于 ready 不报错。
3. **扩展场景**：新增内容块类型只改 source 投影 + renderer 的 kind 分支，不改视口/指针；新增内容面（如未来的只读 PDF）只需提供 source；不复制缩略图核心。
4. **路径分离**：滚动热路径只更新框；内容重绘是防抖低频路径；菜单/偏好是冷路径；测量与绘制失败独立降级，不拖垮编辑主路径。
5. **布局临界**：显示/隐藏导致正文宽度变化，用 32px 滞回避免抖动；缩放不放大预留；查找栏避让；打印取消预留。
6. **数据边界**：缩略图不写文档/不写脏基线/不发 changed；偏好只由原生写；source 只读；滚动只由浏览器和 `scrollTo` 改。

## 7. 性能与预算

- 滚动：passive `scroll` + rAF；只改视口框；目标 ≤1ms/帧，不做整篇测量。
- 内容层：防抖 250ms；典型长文重绘 ≤50ms；超 4,000 行/2,000 块/200,000px 高度进入 compact。
- 测量：一次 `getBoundingClientRect` 批量读取，不在滚动/输入里读；图片只 `drawImage`，不读像素。
- 内存：不复制 DOM；Canvas 上限 120 × 2 × viewportH × 2；source 投影按需生成，缓存一次。
- 组件预算：预计 web 新增 600–850 行、Swift 菜单/偏好 ~80 行、测试 ~200 行；仍远低于 120k token/组件上限。
- 实测：verify 任务记录“长 Markdown（≥5,000px）/ 10,000 行代码”的首绘、滚动、compact 切换数据；超预算先调采样阈值，不改交互。

## 8. 测试计划

| ID | 角色 | 执行 | 断言 |
|---|---|---|---|
| TC-MINI-001 | R1 | `--selftest` | 长 Markdown 显示 rail；`minimapInfo.visible=true`、`mode='full'`、block 数 >0、坐标有序；正文 146px 预留；查找栏左移 |
| TC-MINI-002 | R2 | `--selftest` | 滚动后视口 top 比例一致；点击 50% 后滚动比例居中；越界夹取；滚动不增加 `redrawCount` |
| TC-MINI-003 | R3 | `--selftest` + `--multiwindow-test` | 代码视图 `surface='code'`、行投影数量正确；菜单开关隐藏/显示并跨窗口生效；源码模式/短文档隐藏 |
| TC-MINI-004 | N1 | `--selftest` | 超量 `compact` 不抛错、仍可定位；图片失败占位；空文档/未就绪不显示；缩略图操作不增加 `changed` |
| TC-MINI-005 | R1 | `--screenshot` + 真机 | 深色主题、120px、正文/查找栏无遮挡；视觉接近 `compare.png` |
| TC-MINI-006 | R2 | 真机 | 拖动跟手、触控板惯性、指针越界不粘住 |
| TC-MINI-007 | N1 | 真机 | PDF/打印不出现缩略图，正文无预留空白 |

配套：既有 Markdown 编辑/保存/查找、代码行号/查找/大文件、主题/缩放、抽屉、双窗口断言零回归；`--selftest` 输出计数不写死在文档里。

## 9. 任务表

| ID | 类型 | 组件 | 状态 | 依赖 | 装载清单 |
|---|---|---|---|---|---|
| T-2026-11-04-14 | design | CMP-minimap | in_progress（待 P1 确认） | 无 | 本 brief、REQ-0011、SCN-0017、CMP-minimap/editor/code-view/app-shell spec、architecture |
| T-2026-11-04-15 | change | CMP-minimap | pending | T14 | `minimap.js`/`minimap-source.js`/`minimap-render.js`/`minimap.css`、`main.js`、`bridge.js`、`state.js`、组件规格 |
| T-2026-11-04-16 | change | CMP-editor | pending | T15 契约 | `editor.js`、`state.js`、CMP-editor spec、SCN-0017 |
| T-2026-11-04-17 | change | CMP-code-view | pending | T15 契约 | `code-view.js`、`state.js`、CMP-code-view spec、SCN-0017 |
| T-2026-11-04-18 | change | CMP-app-shell | pending | T15 | `DocumentWindowController.swift`、`AppDelegate.swift`、`bridge.js`、app-shell spec |
| T-2026-11-04-19 | verify | CMP-minimap | pending | T15–T18 | `Selftest.swift`、`Screenshot.swift`、`--drawer-test`、`--multiwindow-test`、REQ/SCN |
| T-2026-11-04-20 | change | docs/close | pending | T19 | README、architecture、组件规格/场景/需求、roadmap、result/review、归档 |

组件级 WIP=1：T15 先落 source 契约与 minimap 骨架；T16/T17 串行接各自投影；T18 只改 Swift 菜单/偏好；T19 统一验证；不并发改同一组件。

## 10. 装载清单（单任务 ≤250k）

- 技能：`arch-design-spec`、`design-before-coding`、`req-scenario-spec`、`doc-layout-spec`、`dev-execution-spec`。
- 文档：REQ-0011、SCN-0017、CMP-minimap/editor/code-view/app-shell spec、architecture §2.4/§2.7/§3、本 brief。
- 代码：`web/src/main.js`、`bridge.js`、`state.js`、`editor.js`、`code-view.js`、`typora.css`、`index.html`；`Sources/MDPreview/DocumentWindowController.swift`、`AppDelegate.swift`、`EditorCommands.swift`、`Selftest.swift`。
- 视觉：`compare.png`、`doc/history/works/2026-11-04-code-view-line-numbers/result.md`（测试/截图口径参考）。

单任务装载应控制在 250k token 内；T15 若同时装载 editor+code-view 超限，按 T16/T17 拆分，不合并任务。

## 11. 风险与开放问题

- **R-真缩略图保真**：Canvas 文字采样不等于截图逐像素；验收口径是“标题/正文行/代码/图片轮廓可辨”，以 `compare.png` 为目标，允许采样。若用户要求逐字可读，需重新评估 DOM 克隆方案（成本更高，不建议在 v1 做）。
- **R-布局抖动**：显示缩略图使正文变窄、文档变高，临界点可能反复；用 32px 滞回覆盖，selftest 加显示/隐藏切换断言。
- **R-Canvas 污染**：file:// 图片可能污染 Canvas；只 `drawImage`，不 `getImageData`/`toDataURL`；测试用 `minimapInfo` + 截图，不做像素断言。
- **R-临时编辑态**：图片/Mermaid 源码编辑时 DOM 是临时控件；source 用 `editing` 占位，不把 textarea 当正文。
- **R-源码模式**：隐藏与菜单置灰必须同时成立；返回渲染面重新挂载 source，不复用旧观察器。
- **R-性能**：超量降级阈值需实测；滚动绝不能触发整篇测量。
- **R-打印/导出**：打印隐藏、取消预留；HTML 导出只取编辑器内容；selftest 用打印截图/结构断言。
- **开放**：v1 固定 120px，宽度拖拽与“缩略图内高亮查找命中”不做；如后续需要，另立需求卡。
- **开放**：精确采样阈值（4,000 行/2,000 块/200,000px）在 verify 实测后可能有小幅调整，调整不改变契约语义。

## 12. 交付定义

1. 用户确认 §4 的 D1–D4（P1 设计门）。
2. T15–T18 完成，source/交互/菜单/桥全部接通。
3. `--selftest` 新增 3+1 断言全绿，既有断言零回归；`--screenshot` 视觉与 `compare.png` 同口径。
4. PDF/打印/HTML 导出不含缩略图；源码模式、短文档、超量降级可复现。
5. 人工点验（R8）通过：真实拖拽、深色主题、窗口缩放、长文视觉。
6. 文档回填并收口；若实现与本文冲突，先改本文再改代码，不允许代码悄悄偏离。
