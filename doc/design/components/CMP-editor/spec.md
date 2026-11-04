---
layer: design
module: editing
component: CMP-editor
status: active
updated: 2026-11-04
---

# CMP-editor 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1 领域；业务能力（编辑面）
- 业务价值：让用户在渲染结果上直接编辑 Markdown，而不是在源码与预览之间来回切换；没有它，应用退化为带预览的文本编辑器。
- 负责：Milkdown/ProseMirror 编辑面、格式命令、源码模式、文档内查找、表格行列操作、数学/ Mermaid/代码高亮渲染、选择信息上报；向右侧缩略图提供 Markdown 顶层的**只读投影**（块几何/文字/图片）。
- 不负责：文件读写（`CMP-document-io`）、窗口/菜单（`CMP-app-shell`）、抽屉（`CMP-drawer`）、图片文件落盘（`CMP-image`）、代码文档的只读源码面（`CMP-code-view`）、缩略图绘制/视口/滚动定位（`CMP-minimap`）。
- 内部逻辑：web 实现已迁入内核 core（`web/src/kernel/core/`），对外只有 op 名，不再有 `window.mdbridge` 方法面；`editor.js` 装配 Milkdown 与插件；`ops.js` 把能力注册成 op；`commands.js`/`tables.js` 是命令表；`find*.js` 是查找；`mermaid-view.js`/`image-view.js` 是 NodeView；`state.js` 持文档与基线，`bus.js` 是通知端口。
- 拥有的数据：当前编辑器文档（内存）、源码模式状态、查找 UI 状态、选择/表格状态；不拥有磁盘文件。
- 变化轴：编辑器框架与插件版本、命令表、渲染扩展。
- 公开契约（含能力 ID）：
  - `CMP-editor#init`：`init` op（含 `opts.protocolVersion`）；`#set-markdown`/`#get-markdown`：`setMarkdown`/`getMarkdown`（渲染态口径）/`getSaveMarkdown`（写盘口径）。
  - `CMP-editor#format-command`：`formatCommand{name, payload?}`，按 `EditorCommands` 的动作名执行。
  - `CMP-editor#source-mode`：`toggleSource{force?}` → `{sourceMode}`；保存取一致内容。
  - `CMP-editor#find`：`openFindBar`/`closeFindBar`/`findNext`/`findPrev`/`findInfo`（Markdown 与源码模式；代码文档的查找归 `CMP-code-view#code-find`，复用同一查找栏 UI）。
  - `CMP-editor#table`：`tableCommand{name}` 与 `insertTable{row,col}`（插入/删除行列与整表）。
  - `CMP-editor#render`：KaTeX 数学、Mermaid 图表、Prism 代码高亮；可插入 `insertMarkdown`/`insertImage`。
  - `CMP-editor#theme-zoom`：`setTheme{theme}`/`setZoom{scale}` → `{zoom}`，正文宽度策略。
  - `CMP-editor#selection-info`：`selinfo{inTable}` 通知上报光标/表格状态；`requestStats` 触发 `stats{words,chars}`。
  - `CMP-editor#minimap-source`：向 `CMP-minimap` 提供只读投影 `{root, measure(), scrollTo()}`；`measure()` 返回 Markdown 顶层块与代码块行的几何/文字/图片；不写文档、不产生 `changed`、不暴露 ProseMirror 类型。
- 入口：
  - `CMP-editor/web/src/kernel/core/ops.js#createOps`（39 个 op 的唯一实现，本组件的入口在此）
  - `CMP-editor/web/src/kernel/core/editor.js#createEditor`
  - `CMP-editor/web/src/editor.js#createMarkdownMinimapSource`（planned，REQ-0011）
  - `CMP-editor/web/src/kernel/core/commands.js#commandRegistry`
  - `CMP-editor/web/src/kernel/core/find-bar.js#openFindBar`
  - `CMP-editor/web/src/kernel/core/tables.js#tableCommandImpls`
  - `CMP-editor/web/src/kernel/core/mermaid-view.js#getMermaidView`
  - `CMP-editor/web/src/kernel/core/state.js#setMode`（模式迁移唯一入口）
  - `CMP-editor/Sources/MDPreview/EditorWebView.swift#EditorWebView`
- 依赖：Milkdown 7.7 / ProseMirror / KaTeX / Mermaid / Prism；`CMP-kernel-contract`（op 注册与信封）、`CMP-kernel-semantics`（装载/保存口径）、`CMP-image#node-view`（图片 NodeView 与导入回插）；`CMP-app-shell` 的 op 转发（菜单 → `formatCommand`/`tableCommand`）；`CMP-code-view` 的 `web/src/kernel/core/languages.js`（refractor 语法注册表）与 §2.6 token 调色板共享；`CMP-minimap` 只通过组合根消费本组件的 `#minimap-source`，不反向 import。
- 冷热属性：编辑输入是热路径；内部不得同步调用文件 IO/导出。`#minimap-source` 的 `measure()` 是低频只读投影，由缩略图防抖调用，不进入输入热路径。
- 尺寸预算：目标 ≤120k token；当前约 1.6k 行 web（`ops.js` 442 + `editor.js` 186 + `tables.js` 156 + `find-bar.js` 149 + `find.js` 92 + `mermaid-view.js` 117 + `image-view.js` 178 + 其余约 280）+ 165 行 Swift，实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；视觉用 `--screenshot`。
- 验证计划：命令/源码/查找/表格/主题/缩放/宽度用 selftest；数学/Mermaid/代码高亮用截图与人工。
- 删除测试：删掉后没有编辑面，复杂度集中到壳/文件层 → 真边界。

## 公开契约细节

- `#get-markdown` 的不变量：`getMarkdown` 返回渲染态序列化（诊断口径），`getSaveMarkdown` 返回写盘口径（图片路径已还原为相对路径）；两者都保持列表每级 4 空格、首行标记紧凑，都不含临时 UI 状态。
- `#source-mode` 的不变量：切换不改变文档语义；源码模式保存与渲染模式保存取一致内容。
- `#find` 的错误模式：无命中时计数为 0 且不抛错；源码模式同样可用。
- `#table` 的错误模式：光标不在表格内时命令 no-op，不插入孤立行列。
- `#render` 的不变量：代码围栏内的图片/链接不被路径改写；Mermaid 源码编辑失焦重绘。
- `#minimap-source` 的不变量：只读；`measure()` 的块按文档顶为 0 的视觉 CSS 像素返回，按 `top` 非降序；只取顶层块，不重复嵌套；图片/Mermaid 正在源码编辑时用 `editing` 占位，不读临时 textarea；`scrollTo` 夹取；不修改 DOM/选区/脏基线，不发 `changed`；不 import `CMP-minimap`。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#format-command` | `--selftest`：「桥命令行为」标题/正文 |
| `#source-mode` | `--selftest`：「源码模式显示原文」「源码模式编辑回写」「D1 源码模式保存取一致内容」 |
| `#find` | `--selftest`：「查找命中计数」「查找下一处」「查找高亮与定位」「查找栏关闭」 |
| `#table` | `--selftest`：「表格-插入/删除…」「表格-定位首表」；`--multiwindow-test` 表格内状态 |
| `#theme-zoom` | `--selftest`：「深色主题切换」「缩放应用」「宽度策略」 |
| `#render` | 截图/人工：KaTeX、Mermaid、Prism |
| `#minimap-source` | `--selftest`：「缩略图 Markdown 显示与投影」：source 可挂载/卸载、块数 >0、坐标有序、`measure()` 无 DOM 写入；截图/人工：真缩略图观感 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 编辑器文档 | `ops.js` 的 `setMarkdown`/命令 op/用户输入 | 保存、导出、统计 | 单内存实例 |
| 源码模式/查找/选择状态 | 本组件 | 本组件 | 不持久化 |
| 缩略图投影（块/文字/图片） | 本组件 `#minimap-source`（派生） | `CMP-minimap` | 只读派生；不落盘、不成为第二真源 |

## 验证债

数学/Mermaid 渲染没有稳定自动断言；格式/查找/源码/表格的“失败反例”未固化。相关场景最高 `designed`。`#minimap-source` 为 2026-11-04 新增的 planned 契约（REQ-0011），实现与断言待 P1 工序完成。

## 删除测试

删掉后编辑面没有替代归属，复杂度集中 → 真边界。
