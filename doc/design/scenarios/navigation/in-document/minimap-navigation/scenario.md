---
layer: design
module: navigation
status: verified
updated: 2026-11-05
flow: FLOW-NAV-003
scenario: SCN-0017
domain: 导航
valueStream: 文档内定位
title: 用右侧缩略图掌握全文并定位
entries:
  - CMP-kernel-minimap/web/src/kernel/components/minimap/minimap.js#createMinimap
  - CMP-kernel-minimap/web/src/kernel/components/minimap/minimap.js#createMinimapSurface
  - CMP-kernel-editor/web/src/kernel/components/editor/editor.js#createMarkdownMinimapSource
  - CMP-kernel-code/web/src/kernel/components/code/code-view.js#createCodeMinimapSource
  - CMP-kernel-minimap/web/src/kernel/components/minimap/thumbnail.js#fitThumbnail
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleMinimapAction
docs:
  - path: doc/requirements/REQ-0011-document-minimap.md
    heading: 5. 影响场景
  - path: doc/design/components/CMP-minimap/spec.md
    heading: 公开契约细节
  - path: doc/design/components/CMP-kernel-minimap/spec.md
    heading: 公开契约细节
tests:
  - role: R1
    id: TC-MINI-001
  - role: R2
    id: TC-MINI-002
  - role: R3
    id: TC-MINI-003
  - role: N1
    id: TC-MINI-004
---

# 用右侧缩略图掌握全文并定位

## 1. 场景与价值

用户打开一篇超过一屏的 Markdown 文档，或一个只读代码文件；右侧出现整页内容的真缩略图（长文按 120px 宽裁切），当前视口用一个半透明蓝框标出。用户滚动正文时框同步移动；点击缩略图的页面内容区跳到目标附近，或按住视口框上下拖动连续定位。用户可以从「视图 → 显示文档缩略图」关闭，偏好跨窗口保留；源码模式与一屏内的短文档不显示。

结果：长文档不必靠系统滚动条盲找位置；用户先掌握内容分布，再直达目标，同时正文、复制、查找、文件内容与导出语义完全不变。

本场景不覆盖文件打开/保存（SCN-0002）、代码装载与高亮（SCN-0016）、抽屉（SCN-0001）与导出内容（SCN-0014）；缩略图只属于阅读辅助层，不写文件。

## 2. 入口

- `CMP-kernel-minimap#surface`：组合根 `assemble.js` 提供 `minimapSurface`；页面入口 `page.js` 启动；源码模式无 source。
- `CMP-kernel-minimap#visibility`：原生偏好经 v2 `init.opts.minimapVisible` 与 `setMinimapVisible` 下发；有效显示在组件内计算。
- `CMP-kernel-minimap#viewport` / `#pointer`：滚动事件与缩略图栏指针事件。
- `CMP-kernel-editor#minimap-source`：Markdown 渲染 DOM 的只读快照（页面容器 + 脱敏副本；不写正文）。
- `CMP-kernel-code#minimap-source`：代码视图 DOM 的只读快照（只读副本；不重建高亮）。
- `CMP-app-shell#minimap-menu`：视图菜单项、勾选、偏好写入口、跨窗口广播。

## 3. 运行序

流程定义：`FLOW-NAV-003`。

1. 装载：文档打开后，组合根按当前内容面注入 `minimapSources`；`CMP-kernel-minimap` 读取 `measure()`，判断偏好、内容面与溢出（带 32px 滞回）。
2. 布局：有效显示时给 `body` 加 `minimap-shown`，正文预留 146px；⌘F 查找栏左移避让；右侧保留系统滚动条。
3. 快照：把 source 的只读 DOM 快照挂到轨道；先按 `min(轨道宽/页面宽, 轨道高/页面高)` 做整页 fit，fit 后宽度 <120px 时改为固定 120px 宽、纵向裁切；页面顶左对齐，并画视口框。
4. 滚动：正文滚动 → passive `scroll` 合并到 rAF → 只更新视口框与裁切平移 `panTop`；不重建快照、不测量整篇 DOM。
5. 定位：点击**页面实际缩略矩形** → 目标点居中 → source `scrollTo`；在视口框内按下拖动 → fit 按页面缩略高度、crop 按整篇滚动条进度 1:1 换算文档位移 → 指针捕获 → 连续滚动；拖到轨道顶/底分别对齐文档开头/结尾；松开/取消释放；轨道空白区不响应。
6. 开关：视图 →「显示文档缩略图」→ 写 `UserDefaults["minimapVisible"]` → 广播所有窗口 → 每个窗口隐藏/显示并重排正文；勾选同步。
7. 内容变化：Markdown 编辑、代码切换语言/行号、图片/Mermaid 编辑结束 → MutationObserver/显式 `refresh` 防抖 250ms → 重建只读快照并缩放，保持当前滚动位置。
8. 外观/尺寸：主题、缩放、窗口尺寸、代码行号开关 → 重建快照并重新缩放；视口框保持当前比例。
9. 切换内容面：`setMarkdown` → Markdown source；`setCode` → 代码 source；源码模式 → `null` 并隐藏；返回渲染面时重新挂载。
10. 打印/导出：打印/PDF 隐藏缩略图并取消正文预留；HTML 导出只取编辑器内容，不含缩略图。

失败路径：

- 内容未就绪/空文档/无溢出：不显示，不占正文宽度，不报错。
- 源码模式：`setSource(null)`，隐藏并把菜单项置灰；返回渲染面后恢复。
- 图片/图表加载失败：保留原占位或空框，不影响其他块、不抛 `jserror`。
- 快照创建/测量异常：隐藏缩略图并 `console.warn` 一次；正文滚动与编辑不受影响。
- 超长内容：仍生成只读快照；先实测，若超过快照预算再按实测结果处理，不改变定位语义。
- 点击轨道空白区：不响应；点击页面内容越界时夹取到 `[0, docHeight - viewportHeight]`；不出现负滚动或底部空白。
- 拖动中指针取消/离开：释放捕获并清状态，不残留“粘住”的滚动。
- 缩略图显示/隐藏临界：32px 滞回防止布局抖动。
- 原生调用早于 web ready：`setMinimapVisible` 在握手前回调 `not_ready`；`init` 后以 `init.opts` 为准。

## 4. 不可变引用

- `architecture.md` §2.4 的正文宽度/抽屉联动与 §2.7 的代码只读、512 KB 上限、行结构。
- `CMP-editor#get-markdown` / `#source-mode`：缩略图不改变文档内容与源码模式语义。
- `CMP-code-view#set-code` / `#line-layout` / `#large-guard`：代码文档只读、无脏、行结构是投影来源，不因缩略图重建或改写。
- `CMP-app-shell#open-document` / `#menu-commands`：菜单命令表与窗口路由不变；只新增一个勾选项。
- `CMP-document-io` 的保存/编码口径、`CMP-export` 的 PDF/打印/HTML 内容面不变。
- 桥协议既有 op 语义不变；新增 `setMinimapVisible` / `minimapInfo` 为 v2 加法扩展，握手 op 数 41。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-MINI-001 | R1 | 自动 | `--selftest` | `PASS 缩略图 默认显示`（快照数、mode=fit|crop、内容矩形有效、顶左）与「正文预留生效」；`core.test` 偏好往返 | `--selftest` / `web/test/core.test.js` |
| TC-MINI-002 | R2 | 自动 | `web/test/minimap.test.js` | fit 顶左；长文 120px 裁切、`panTop` 按整篇进度平移、视口框 1:1 跟手；fit 拖动按内容高度折算；轨道空白区不响应；滚动只更新视口框 | `minimap.test.js` |
| TC-MINI-003 | R3 | 自动 | `minimap.test.js` + `--screenshot` | surface 切换 Markdown/代码；开关隐藏/恢复；长代码文件保留真实 token 与行结构 | `minimap.test.js` / `.build/minimap-dom-code.png` |
| TC-MINI-004 | N1 | 自动 | `minimap.test.js` | 空/无 source/源码模式隐藏；只读克隆去掉脚本/交互/编辑态；缩略图操作不产生 `changed`（只读） | `minimap.test.js` |
| TC-MINI-005 | R1 | 人工 | `--screenshot` + 真机 | 深色主题、120px 视觉宽、顶左对齐、正文/查找栏无遮挡；视觉接近缩小版页面 | `.build/minimap-dom-fit.png` + 2026-11-05 用户确认 |
| TC-MINI-006 | R2 | 人工 | 真机拖拽 | 视口拖动跟手、触控板惯性不抖、指针移出边界不粘住 | 2026-11-05 用户确认 |
| TC-MINI-007 | N1 | 人工 | PDF/打印 | 缩略图不出现、正文无预留空白 | `@media print` 规则 + 用户确认收口 |
| TC-MINI-008 | R2 | 人工 | 真机长文 | 长文宽度保持 120px；视口框与鼠标 1:1 跟手；到轨道顶/底与文档开头/结尾对齐 | `.build/minimap-20-rail-right.png` / `-bottom-right.png`（顶底几何）；2026-11-05 用户确认手感 |

配套断言：既有 Markdown 编辑/保存/查找、代码视图行号/查找/大文件、主题缩放、抽屉、双窗口全部零回归；`minimapInfo()` 只暴露几何/模式，不暴露 DOM。

## 6. 验证债

- TC-MINI-001～004 已有自动证据；TC-MINI-005/006 由用户 2026-11-05 确认；TC-MINI-007 由 `@media print` 规则保障并随本次收口。
- 真缩略图的视觉判断依赖人工（TC-MINI-005），不承诺逐字可读；以 `compare.png` 为目标。
- 快照耗时与滚动视口更新（目标 ≤50ms / ≤1ms）尚未仪表化；未达标先查克隆/脱敏，不改变交互语义。
- 长文裁切为 2026-11-05 追加行为，TC-MINI-008 已由用户真机确认。
- 2026-11-05 用户确认 Markdown 与代码窗口效果后转 `verified`；自动门与人工门均已收口。

## 7. 变更记录

- 2026-11-04 新建（REQ-0011，P1 设计工序 `2026-11-04-document-minimap`）；场景放在 `navigation/in-document`，覆盖 Markdown 渲染面与代码只读面；源码模式不覆盖。
- 2026-11-04 实现落地：第七个功能组件 `CMP-kernel-minimap`，41 个 host op；入口/测试/证据回填；当时人工拖拽与 PDF/打印待验收，后于 2026-11-05 收口。
- 2026-11-05 用户选定 DOM 克隆 + 顶对齐 + fit；定位改为页面实际缩略矩形，轨道空白区不响应；Canvas 采样/compact 路线废弃。
- 2026-11-05 用户验收 Markdown 与代码窗口效果，同意提交推送；场景转 `verified`。
- 2026-11-05 长文窄条修正：fit 宽度 <120px 转固定 120px 宽纵向裁切；增加 `panTop` 与顶底夹取。
- 2026-11-05 长文拖拽手感修正：视口框改为整篇滚动条滑块，按 `railHeight - boxHeight` 1:1 跟手；`panTop` 与整篇进度线性同步；用户确认后收口。
