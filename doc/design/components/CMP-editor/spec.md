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
- 负责：Milkdown/ProseMirror 编辑面、格式命令、源码模式、文档内查找、表格行列操作、数学/ Mermaid/代码高亮渲染、选择信息上报。
- 不负责：文件读写（`CMP-document-io`）、窗口/菜单（`CMP-app-shell`）、抽屉（`CMP-drawer`）、图片文件落盘（`CMP-image`）、代码文档的只读源码面（`CMP-code-view`）。
- 内部逻辑：`bridge.js` 暴露 `window.mdbridge`；`editor.js` 装配 Milkdown 与插件；`commands.js`/`tables.js` 是命令表；`find*.js` 是查找；`mermaid-view.js`/`image-view.js` 是 NodeView。
- 拥有的数据：当前编辑器文档（内存）、源码模式状态、查找 UI 状态、选择/表格状态；不拥有磁盘文件。
- 变化轴：编辑器框架与插件版本、命令表、渲染扩展。
- 公开契约（含能力 ID）：
  - `CMP-editor#init` / `#set-markdown` / `#get-markdown`：初始化、整篇替换、取回 Markdown。
  - `CMP-editor#format-command`：按 `EditorCommands` 的动作名执行格式命令。
  - `CMP-editor#source-mode`：渲染视图 ↔ 源码视图；保存取一致内容。
  - `CMP-editor#find`：打开查找、下一处/上一处、命中计数与高亮（Markdown 与源码模式；代码文档的查找归 `CMP-code-view#code-find`，复用同一查找栏 UI）。
  - `CMP-editor#table`：插入/删除行列与整表。
  - `CMP-editor#render`：KaTeX 数学、Mermaid 图表、Prism 代码高亮。
  - `CMP-editor#theme-zoom`：应用主题/缩放，正文宽度策略。
  - `CMP-editor#selection-info`：上报光标是否在表格内等状态。
- 入口：
  - `CMP-editor/web/src/bridge.js#window.mdbridge`
  - `CMP-editor/web/src/editor.js#createEditor`
  - `CMP-editor/web/src/commands.js#commandRegistry`
  - `CMP-editor/web/src/find-bar.js#openFindBar`
  - `CMP-editor/web/src/tables.js#tableCommandImpls`
  - `CMP-editor/web/src/mermaid-view.js#getMermaidView`
  - `CMP-editor/Sources/MDPreview/EditorWebView.swift#EditorWebView`
- 依赖：Milkdown 7.7 / ProseMirror / KaTeX / Mermaid / Prism；`CMP-image` 的图片 NodeView 与导入回灌；`CMP-app-shell` 的命令转发；`CMP-code-view` 的 `web/src/languages.js`（refractor 语法注册表）与 §2.6 token 调色板共享。
- 冷热属性：编辑输入是热路径；内部不得同步调用文件 IO/导出。
- 尺寸预算：目标 ≤120k token；当前约 1.7k 行 web + 165 行 Swift，实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；视觉用 `--screenshot`。
- 验证计划：命令/源码/查找/表格/主题/缩放/宽度用 selftest；数学/Mermaid/代码高亮用截图与人工。
- 删除测试：删掉后没有编辑面，复杂度集中到壳/文件层 → 真边界。

## 公开契约细节

- `#get-markdown` 的不变量：返回当前文档的 Markdown 序列化；列表每级 4 空格、首行标记紧凑；不包含临时 UI 状态。
- `#source-mode` 的不变量：切换不改变文档语义；源码模式保存与渲染模式保存取一致内容。
- `#find` 的错误模式：无命中时计数为 0 且不抛错；源码模式同样可用。
- `#table` 的错误模式：光标不在表格内时命令 no-op，不插入孤立行列。
- `#render` 的不变量：代码围栏内的图片/链接不被路径改写；Mermaid 源码编辑失焦重绘。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#format-command` | `--selftest`：「桥命令行为」标题/正文 |
| `#source-mode` | `--selftest`：「源码模式显示原文」「源码模式编辑回写」「D1 源码模式保存取一致内容」 |
| `#find` | `--selftest`：「查找命中计数」「查找下一处」「查找高亮与定位」「查找栏关闭」 |
| `#table` | `--selftest`：「表格-插入/删除…」「表格-定位首表」；`--multiwindow-test` 表格内状态 |
| `#theme-zoom` | `--selftest`：「深色主题切换」「缩放应用」「宽度策略」 |
| `#render` | 截图/人工：KaTeX、Mermaid、Prism |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 编辑器文档 | `bridge.js` 的 set/命令 | 保存、导出、统计 | 单内存实例 |
| 源码模式/查找/选择状态 | 本组件 | 本组件 | 不持久化 |

## 验证债

数学/Mermaid 渲染没有稳定自动断言；格式/查找/源码/表格的“失败反例”未固化。相关场景最高 `designed`。

## 删除测试

删掉后编辑面没有替代归属，复杂度集中 → 真边界。
