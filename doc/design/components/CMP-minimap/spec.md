---
layer: design
module: navigation
component: CMP-minimap
status: planned
updated: 2026-11-04
---

# CMP-minimap 组件规格

## 组件卡

- 状态：planned
- 单元：组件
- 层 / 类型：L1 领域；业务能力（文档内定位）
- 业务价值：为 Markdown 渲染面与只读代码面提供右侧整篇缩略图、当前视口与点击/拖动定位；没有它，长文档只能靠系统滚动条盲找位置，代码阅读也缺少 Sublime 习惯的整体预览。
- 负责：右侧固定栏 DOM 与 Canvas、内容投影的缩放/采样/绘制、视口框几何与滚动同步、点击/拖动到滚动位置的映射、有效显示判定、重绘调度、缩略图诊断信息。
- 不负责：文档正文与 Markdown/代码渲染（`CMP-editor` / `CMP-code-view`）；滚动位置本身（浏览器滚动模型）；窗口/菜单/偏好存储（`CMP-app-shell`）；文件 IO、保存、导出（`CMP-document-io` / `CMP-export`）；主题定义（仍读 `CMP-editor#theme-zoom` 的 CSS 变量）。
- 内部逻辑：`minimap.js` 负责生命周期、布局、可见性、滚动/指针映射与重绘调度；`minimap-source.js` 定义内容投影形状（结构契约，不引入运行时依赖）；`minimap-render.js` 负责 Canvas 真缩略图绘制与超量降级；`minimap.css` 负责固定栏、正文预留、查找栏避让与打印隔离。
- 拥有的数据：缩略图内容缓存（由 source 投影派生）、当前有效显示状态、当前内容面（markdown/code/none）、视口框几何、最近一次绘制模式（full/compact）；不拥有文档内容、滚动位置或可见性偏好。
- 变化轴：缩略图绘制算法（文字采样/图片缩略/降级阈值）、采样预算、固定宽度、主题、交互映射。
- 公开契约（含能力 ID）：
  - `CMP-minimap#source`：接收/卸下只读内容投影 `MinimapSource`；无 source 时隐藏。
  - `CMP-minimap#visibility`：接收偏好并计算有效显示（偏好 ∧ 有 source ∧ 内容溢出）；不持久化偏好。
  - `CMP-minimap#refresh`：内容/主题/缩放/尺寸变化后重测并重绘；幂等、可重复调用。
  - `CMP-minimap#viewport`：滚动位置 ↔ 视口框的单一映射；滚动只更新框。
  - `CMP-minimap#pointer`：点击定位、拖动视口、边界夹取、指针捕获。
  - `CMP-minimap#info`：诊断快照（不暴露 DOM/像素），含 `visible/pref/surface/mode/docHeight/viewportHeight/scrollTop/railHeight/viewportTop/blockCount/lineCount/redrawCount`，供 `--selftest` 几何与重绘断言。
- 入口：
  - `CMP-minimap/web/src/minimap.js#createMinimap`
  - `CMP-minimap/web/src/minimap.js#setSource`
  - `CMP-minimap/web/src/minimap.js#setVisible`
  - `CMP-minimap/web/src/minimap.js#refresh`
  - `CMP-minimap/web/src/minimap.js#minimapInfo`
  - `CMP-minimap/web/src/minimap-render.js#drawMinimap`
  - `CMP-minimap/web/src/minimap.css`
- 依赖：`CMP-editor#minimap-source`（Markdown 投影）、`CMP-code-view#minimap-source`（代码行投影）；Canvas 2D / DOM 标准能力，无新增第三方依赖。source 由组合根（`main.js`）注入，本组件不 import 编辑器或代码视图实现；可见性偏好由 `CMP-app-shell` 经桥下发，本组件只接收，不反向依赖壳。
- 冷热属性：滚动是热路径，只更新视口框（rAF，≤1ms 目标）；内容投影与重绘是低频路径，防抖 250ms，不进入编辑输入主路径。
- 尺寸预算：目标 ≤120k token；预计 web ~600–850 行（核心/绘制/样式）+ Swift 菜单与测试另计，实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`（缩略图断言）；视觉用 `--screenshot out.png <长文.md>` 与代码文件。
- 验证计划：source 生命周期、有效显示、视口几何、点击/拖动、代码面、源码模式隐藏、短文档隐藏、超量降级、打印隔离、无脏变更；详见下表。
- 删除测试：删掉后 Markdown 与代码两面都要各自重建缩略栏、视口和指针映射，复杂度集中而非消失 → 真边界。

## 公开契约细节

### 1. `#source`：只读内容投影

`MinimapSource` 是 `CMP-editor` / `CMP-code-view` 提供给本组件的**普通数据对象**，不导入 `CMP-minimap` 的实现类型：

```js
{
  root: Element,                 // 用于 MutationObserver / ResizeObserver
  measure(): {
    contentWidth: number,        // 投影坐标系宽度（视觉 CSS px）
    docHeight: number,           // 文档总高（视觉 CSS px）
    viewportHeight: number,      // 当前可视高度
    scrollTop: number,           // 当前滚动位置
    blocks: MinimapBlock[]
  },
  scrollTo(y: number): void      // 按文档坐标滚动，内部必须夹取
}
```

`MinimapBlock`：

```js
{
  kind: 'heading' | 'paragraph' | 'list' | 'quote' | 'code' |
        'table' | 'image' | 'math' | 'diagram' | 'rule',
  top: number, height: number, left: number, width: number,
  level?: 1..6,                  // heading
  text?: string,                 // 段落/标题/引用的可绘制文本
  lineCount?: number,            // 可选：由 source 估算的真实行数
  lines?: Array<{                // 代码/逐行文本；代码面必填
    text: string, top: number, height: number,
    left: number, width: number, color?: string
  }>,
  image?: { src: string, alt?: string } | null,  // image
  editing?: boolean              // 图片/Mermaid 正在源码编辑：用占位，不读临时输入框
}
```

不变量：

- `measure()` 返回的坐标一律是**文档顶为 0 的视觉 CSS 像素**；source 自己处理 `#app`/`#code-view` 的 `zoom`、padding 与滚动偏移，本组件不感知编辑器内部结构。
- `blocks` 按 `top` 非降序；只含顶层内容，不重复嵌套块；空块可省略。
- `scrollTop`、`docHeight`、`viewportHeight` 与浏览器滚动模型一致；`scrollTo` 必须夹取到 `[0, docHeight - viewportHeight]`。
- 只读：source 不得在 `measure()` 中修改 DOM、文档、选区、脏基线；不得发 `changed`。
- 编辑器/代码视图正在显示临时 UI（图片源码编辑块、Mermaid 源码编辑块）时，`editing=true` 用占位绘制，不把 textarea 文本当成正文。
- 代码面：一个 `kind: 'code'` 块承载全部行；`lines` 按逻辑行给出；超大文件由 source 采样，但至少保留首尾与当前视口附近的行。
- 切换内容面（Markdown ↔ 代码 ↔ 源码模式）由组合根调用 `setSource(newSource | null)`；旧 source 的观察器必须释放。

### 2. `#visibility`：偏好与有效显示

- 偏好由 `CMP-app-shell` 持有（`UserDefaults["minimapVisible"]`，默认 `true`）；本组件只接收 `setVisible(pref)`。
- 有效显示 = `pref && source != null && contentOverflow`，其中 `contentOverflow` 用**滞回**判定：显示阈值 `docHeight > viewportHeight + 32`，隐藏阈值 `docHeight <= viewportHeight - 32`。这样避免“显示缩略图 → 正文变窄 → 高度增加 → 保持显示；隐藏 → 正文变宽 → 变短 → 保持隐藏”的临界抖动。
- 显示/隐藏切换先改 `minimap-shown` class，再在 `requestAnimationFrame` 后测量新布局；不得用改 class 前的 `docHeight` 做最终判定。`setSource`/换文档时先移除 class、按隐藏布局重测，再决定是否显示，不复用上一文档的 `shown`。
- `pref=false`、无 source、源码模式、空文档、无溢出时：不画、不占正文宽度；菜单勾选仍反映偏好。
- `setSource(null)` 时移除 `minimap-shown`、清空 Canvas、停止滚动监听；重新挂载后重算滞回状态，不复用上一内容面的 `shown`。

### 3. `#viewport`：滚动同步

- 映射：`sy = railHeight / docHeight`；视口框 `top = clamp(scrollTop * sy, 0, railHeight - boxH)`，`boxH = max(12, viewportHeight * sy)`。
- 文档滚动：监听 `scroll`（passive），用 `requestAnimationFrame` 合并，只更新视口框的 `transform`/`height`，不重绘内容层、不读整篇 DOM。
- 内容重绘后重新计算 `sy`、`boxH`，保持当前 `scrollTop`。
- 滚动到文档末尾时框贴底；文档高度变化时框夹取，不出现负值/溢出。

### 4. `#pointer`：点击与拖动

- 在缩略图栏上 `pointerdown`：
  - 命中视口框内部：记录按下点相对框中心的偏移，进入拖动。
  - 命中框外：把目标点居中 → `scrollTo(target - viewportHeight / 2)`，然后进入拖动。
- `pointermove`：目标中心 = 指针 y 映射到文档坐标；`scrollTo(targetCenter - viewportHeight / 2)`；夹取由 source 负责。
- `pointerup` / `pointercancel`：释放指针捕获，清除拖动状态；不残留监听。
- `pointerdown` 时 `preventDefault`，避免选中正文；缩略图不抢焦点、不弹右键菜单；`touch-action: none`。
- 滚轮不拦截：缩略图区域的滚轮继续走浏览器默认页面滚动。

### 5. `#refresh`：重绘与采样

- 触发：`setSource`、内容 MutationObserver（防抖 250ms）、`ResizeObserver`（150ms）、主题 `data-theme` 变化、`setZoom` 后由组合根显式调用、代码行号开关（布局变化）后。
- 绘制：Canvas CSS 尺寸 120 × railHeight；backing store 按 `devicePixelRatio`（上限 2）缩放；`ctx.scale(dpr, dpr)`。
- 内容层：
  1. 背景与类型底色；
  2. 标题：深色粗线/文字，一级更宽；
  3. 段落/列表/引用：真实文字采样，小字号（2–6px 夹取），按块宽度裁剪；有 `lines` 时逐行绘制；
  4. 代码：逐逻辑行绘制等宽文字；行高不足时退化为 1px 行条；
  5. 图片：`drawImage` 缩略；失败/未完成画占位块；
  6. 表格：底色 + 横线/列线；数学/图表：类型底色 + 简化符号，不追求图表内部文字可读；
  7. 分隔线：1px。
- 视口框最后绘制：半透明蓝填充 + 1.5px 边框 + 上下把手；主题切换改变背景/文字颜色，不改变视口语义。
- 采样上限：`blocks > 2000` 或累计 `lines > 4000` 或 `docHeight > 200000` 时进入 `compact`：只画类型色块/行密度条，不画文字，仍保留视口与定位；`info.mode` 返回 `'compact'`。降级不抛错、不提示、不阻塞正文。
- `drawImage` 不得调用 `getImageData`/`toDataURL`（file:// 图片可能污染 Canvas）；图片失败只影响该块。
- 空内容/测量异常：捕获异常，隐藏缩略图，`console.warn` 一次，不向原生抛 `jserror` 循环。

### 6. 布局与打印

- CSS 变量：`--minimap-width: 120px`、`--minimap-gutter: 10px`、`--minimap-reserve: 146px`（120 + 16 间隙 + 10 右侧留白）。
- `body.minimap-shown { padding-right: var(--minimap-reserve); }`；`#minimap { position: fixed; top: 0; right: var(--minimap-gutter); width: var(--minimap-width); height: 100vh; z-index: 60; }`。`body` 不加 zoom，正文的 `--app-zoom` 不会把预留宽度一起放大/缩小。
- 右侧留出 8px 系统滚动条；缩略图不覆盖滚动条。缩略图显示时 `#find-bar { right: calc(18px + var(--minimap-width) + var(--minimap-gutter)); }`（148px），与栏之间留 18px 间隙，避免遮挡。
- 正文预留后 `#app`/`#code-view` 的 860px 下限不变，因此窗口可视宽小于约 1006px 时会出现横向滚动；这是固定 120px 栏的明确代价，v1 不自动隐藏、不压缩正文下限。
- 源码模式：不挂 `minimap-shown`，`#source-editor` 仍全屏；Menu 项在源码模式置灰。
- 打印/PDF：`@media print { #minimap { display: none !important; } body { padding-right: 0 !important; } }`；HTML 导出只取编辑器内容，不包含缩略图。
- 文档/窗口尺寸变化：先重算布局再重绘；不改变 `#app`/`#code-view` 的 `min-width: 860px` 横向策略。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#source` | `--selftest`「缩略图 Markdown 显示与投影」「缩略图 代码行投影」：source 挂载/卸载、block 数量、坐标排序、无 DOM 写入 |
| `#visibility` | `--selftest`「缩略图 开关与短文档/源码模式」：偏好开/关、短文档隐藏、源码模式隐藏、滞回不抖动 |
| `#viewport` | `--selftest`「缩略图 滚动同步与视口几何」：滚动前后视口 top 比例、贴底夹取、只更新框 |
| `#pointer` | `--selftest`「缩略图 点击与拖动」：点击 50% 后滚动比例、拖动位移、越界夹取；人工真实拖拽手感（R8） |
| `#refresh` | `--selftest`「缩略图 超量降级」：compact 模式、无异常、仍可定位；`--screenshot` 视觉 |
| 打印隔离 | `--screenshot` PDF/打印截图；`@media print` 断言不显示、正文无预留 |
| 无脏变更 | `--selftest`：打开/滚动/点击缩略图后 `changed` 计数不增加 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 缩略图内容缓存 | 本组件 `refresh` | 本组件 Canvas | 由 source 派生；source 变化即失效 |
| 有效显示 / 当前内容面 | 本组件 | 本组件 | 会话级；偏好与菜单可用性不在此 |
| 视口框几何 | 本组件 | 本组件 | 与 `scrollTop` 同帧更新 |
| 可见性偏好 | `CMP-app-shell`（`UserDefaults`） | 本组件、菜单勾选 | 全局单一来源；本组件只读 |

预算：Canvas backing store ≤ 120 × 2 × viewportHeight × 2；内容层重绘目标 ≤50ms，滚动更新 ≤1ms；采样上限见 `#refresh`。

## 验证债

- 组件尚未实现；所有测试为 `missing`，实现后按 `--selftest` 与截图补齐。
- “真缩略图”的视觉验收是人工判断：标题/正文行/代码/图片轮廓可辨，不追求逐字可读；以 `compare.png` 为目标，允许为性能采样。
- 真实拖拽/触控板惯性、深色主题、窗口缩放属于 R8 人工项，必须在 verify 任务收口前点验。

## 删除测试

删掉本组件后，Markdown 与代码阅读面各自需要重建固定栏、内容投影、视口映射与指针交互；复杂度不会消失，只会复制到两个内容面 → 保留为真边界。
