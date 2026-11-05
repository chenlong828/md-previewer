---
layer: design
module: navigation
component: CMP-minimap
status: active
updated: 2026-11-05
---

# CMP-minimap 组件规格

## 组件卡

- 状态：active
- 单元：组件（领域能力）
- 层 / 类型：L1 领域；业务能力（文档内定位）
- 业务价值：为 Markdown 渲染面与只读代码面提供右侧整页缩略图（长文按 120px 宽裁切）、当前视口与点击/拖动定位；没有它，长文档只能靠系统滚动条盲找位置，代码阅读也缺少 Sublime 习惯的整体预览。
- 负责：右侧固定栏的**用户可见行为**——整篇内容缩略、当前视口框、滚动同步、点击/拖动定位、显示/隐藏规则、与查找栏/源码模式/打印的关系。缩略图内容由 Markdown/代码组件提供的只读 DOM 快照呈现。
- 不负责：只读快照的构建与脱敏、缩放/视口几何与指针映射（实现归 `CMP-kernel-minimap`）；Markdown/代码内容与快照（`CMP-kernel-editor` / `CMP-kernel-code`）；窗口/菜单/偏好持久化（`CMP-app-shell`）；文件 IO、保存、导出；主题定义。
- 内部逻辑：领域行为由内核组件 `CMP-kernel-minimap` 实现；本卡只定义能力边界、用户可见不变量和跨组件关系，不复制实现契约。
- 拥有的数据：无持久化数据。有效显示与视口是会话态；显示偏好归 `CMP-app-shell`；内容归编辑器/代码面。
- 变化轴：快照呈现方式、固定宽度、显示阈值、交互映射、缩放口径。
- 公开契约（含能力 ID）：
  - `CMP-minimap#visibility`：用户可以从「视图 → 显示文档缩略图」打开/关闭；偏好跨窗口记忆；默认显示。
  - `CMP-minimap#locate`：点击缩略图的**页面实际内容区**跳到目标附近；按住视口框上下拖动连续定位；长文裁切模式让视口框与整篇滚动条进度 1:1 跟手，拖到轨道顶/底时对齐文档开头/结尾；轨道空白区不响应；越界夹取。
  - `CMP-minimap#viewport`：正文滚动时视口框同步；短文档整页 fit，长文按 120px 宽、纵向裁切并平移；页面顶左对齐；滚动不改变正文内容与选区。
  - `CMP-minimap#info`：只读诊断快照（不暴露 DOM/像素），供自检与排障。
- 入口：
  - `CMP-kernel-minimap/web/src/kernel/components/minimap/minimap.js#createMinimap`（实现入口）
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleMinimapAction`（菜单入口）
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applyMinimapVisibilityToAllDocuments`（跨窗口广播）
- 依赖：实现依赖 `CMP-kernel-minimap`；只读 DOM 快照由 `CMP-kernel-editor` / `CMP-kernel-code` 内部提供，经组合根端口注入；偏好由 `CMP-app-shell` 经 `setMinimapVisible` / `init.opts.minimapVisible` 下发。本组件不 import 任何实现。
- 冷热属性：滚动是热路径，只更新视口框；快照构建与缩放是低频路径；不进入编辑输入主路径。
- 尺寸预算：领域卡不设代码预算；实现预算见 `CMP-kernel-minimap`。
- 单独运行：`./.build/debug/MDPreview --selftest`（缩略图断言）；视觉用 `--screenshot out.png <长文.md>` 与代码文件。
- 验证计划：显示/隐藏、视口同步、点击/拖动、代码面、源码模式、短文档、快照预算、打印隔离、无脏变更。
- 删除测试：删掉后 Markdown 与代码两面都要各自重建缩略栏、视口和指针映射，复杂度集中而非消失 → 真边界。

## 公开契约细节

### 1. `#visibility`：显示规则

- 默认显示；偏好为 `true` 且当前内容面有可生成快照的内容、内容超出一屏时显示。
- 源码模式不显示；一屏内的短文档不显示。
- 显示/隐藏带 32px 滞回，避免窗口缩放时布局抖动。
- 偏好只由壳写入 `UserDefaults["minimapVisible"]`；内核只接收，不回写偏好。
- 关闭后正文右侧预留立即取消；重新打开按偏好恢复。

### 2. `#locate`：定位

- 点击缩略图：只认页面实际缩略矩形；把点击点映射到文档坐标，目标点尽量居中；结果夹取到 `[0, docHeight - viewportHeight]`。轨道空白区不响应。
- 拖动视口框：按住框内拖动，指针捕获。fit 模式按缩放后的页面高度 `contentHeight / docHeight` 换算；crop 模式把视口框当作整篇滚动条滑块，按 `railHeight - boxHeight` 的轨道进度 1:1 移动，指针与视口框同步；指针到轨道顶/底时分别夹到文档开头/结尾；松开或取消释放，不残留“粘住”的滚动。
- 滚轮在缩略图上滚动正文；不触发编辑/选择。

### 3. `#viewport`：视口

- 正文滚动只移动缩略图覆盖层，不重建快照。
- 短文档整页等比 fit；fit 后宽度低于轨道宽（120px）时改为固定 120px 宽、纵向裁切，页面可高于轨道。
- 页面顶左对齐；裁切模式只纵向平移，不横向移动；视口框宽度等于内容宽度。
- 平移量 `panTop = progress * (pageHeight - railHeight)`，`progress = scrollTop / (docHeight - viewportHeight)`；视口框顶 = `progress * (railHeight - boxHeight)`，与整篇滚动条进度同步；顶部/底部与文档开头/结尾对齐。
- 视口框最小高度 12px；短文档不显示。
- 视口比例与 `scrollTop` 同帧更新。

### 4. `#info`：诊断

- 返回 `{started,pref,visible,surface,hasSource,mode,docHeight,viewportHeight,scrollTop,railHeight,railWidth,viewportTop,viewportBoxHeight,viewportLeft,viewportBoxWidth,pageWidth,pageHeight,contentLeft,contentTop,contentWidth,contentHeight,scale,snapshotCount,redrawCount,startedAt}`。
- `surface` 为 `markdown` / `code` / `source`；`mode` 为 `fit` / `crop` / `none`。
- 不暴露 DOM 节点、像素数据或 ProseMirror 类型。

## 跨组件关系

| 关系 | 说明 |
|---|---|
| 内容面 → 缩略图 | `CMP-kernel-editor` / `CMP-kernel-code` 提供只读 DOM 快照工厂；组合根注入 `minimapSources` 端口 |
| 缩略图 → 壳 | 壳只通过 `setMinimapVisible` / `init.opts.minimapVisible` 控制；缩略图不反向调用菜单 |
| 缩略图 → 文档 | 只读；不修改正文、选区、脏基线，不发 `changed` |
| 缩略图 → 导出/打印 | 不进入 PDF/打印/HTML；打印时隐藏并取消正文预留 |

## 验证计划

| 契约 | 测试 |
|---|---|
| `#visibility` | `--selftest`「缩略图 默认显示」「缩略图 正文预留生效」「缩略图 开关隐藏/恢复」；`web/test/minimap.test.js` 显示策略 |
| `#locate` / `#viewport` | `minimap.test.js` 内容矩形几何、空白区不响应、fit 按内容高度拖动、长文整篇进度 1:1 跟手与顶底夹取；`--selftest` 顶左/轨道内内容矩形 |
| `#info` | `web/test/core.test.js`、`contract.test.js`、`--selftest`「缩略图诊断」 |
| 代码面 | `minimap.test.js` surface 模式切换；`--screenshot .build/minimap-dom-code.png` |
| 源码模式/短文档/打印 | CSS 规则与 `--selftest` 源码模式用例；人工 PDF/打印 |
| 视觉 | 人工 `--screenshot`，对照 `.build/minimap-dom-fit.png` / `compare.png`；长文裁切另看真机长文（整篇进度视口） |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 可见性偏好 | `CMP-app-shell`（`UserDefaults["minimapVisible"]`） | 菜单、各窗口、缩略图 | 全局单一来源 |
| 有效显示 / 视口 | `CMP-kernel-minimap` | 缩略图、诊断 | 会话级，可重建 |
| 文档内容 | `CMP-kernel-editor` / `CMP-kernel-code` | 缩略图只读投影 | 不复制为第二真源 |

预算：实现侧快照与滚动预算见 `CMP-kernel-minimap`；领域层不新增依赖、不新增持久化。

## 验证债

- 真缩略图的视觉验收是人工判断：标题/正文行/代码/图片轮廓可辨，不追求逐字可读；以 `.build/minimap-dom-fit.png` 与 `compare.png` 为目标。长文裁切模式需额外确认：宽度保持 120px、视口框按整篇进度跟手、顶底对齐。
- 真实拖拽/触控板惯性、深色主题、窗口缩放属于 R8 人工项，必须在 verify 任务收口前点验。
- 性能阈值以 `CMP-kernel-minimap` 实测为准；未达标先查快照构建/脱敏，不改变交互语义。

## 删除测试

删掉本组件后，Markdown 与代码阅读面各自需要重建固定栏、内容投影、视口映射与指针交互；复杂度不会消失，只会复制到两个内容面 → 保留为真边界。
