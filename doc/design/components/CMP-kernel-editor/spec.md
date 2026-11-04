---
layer: design
module: kernel
component: CMP-kernel-editor
status: active
updated: 2026-11-04
---

# CMP-kernel-editor 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；编辑面
- 业务价值：把 Markdown 编辑器本身（Milkdown 装配、命令、表格、NodeView）收在一处，其它组件经 op 与端口使用。
- 负责：Milkdown 装配与插件、源码模式、命令与表格实现、统计与选区上报、图片/mermaid NodeView、焦点与撤销重做、诊断 4 op。
- 不负责：文档装载与基线（document）、查找 UI（find）、代码只读面（code）、导出（output）、粘贴监听（media）。
- 内部逻辑：`editor.js` 装配与端口实现（editorSurface/renderSurface/imageInsertion/focusEditorView）；`commands.js`/`tables.js` 命令表；`stats.js`/`selinfo.js` 上报；`ops.js`＋`diagnostics-ops.js` 14 个 op。
- 拥有的数据：编辑器实例与 ProseMirror 文档（经 state.editor）；命令表与表格实现；序列化钩子 state.serialize。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、编辑面内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-editor#commands`：formatCommand/tableCommand/insertTable/insertMarkdown/insertImage：编辑命令与插入
  - `CMP-kernel-editor#source-mode`：toggleSource：源码/渲染切换（代码文档 no-op）
  - `CMP-kernel-editor#node-views`：image/mermaid NodeView 注册与主题重绘
  - `CMP-kernel-editor#diagnostics`：debugFocusTable/tableInfo/hasCommands/testImagePayload：诊断档
- 入口：
  - `components/editor/editor.js#createEditor`
  - `components/editor/editor.js#createEditorSurface`
  - `components/editor/ops.js#createEditorOps`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口，
  由 `kernel/assemble.js` 注入（详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- selftest 编辑/表格/源码模式/统计各组；Node core 组 `requestStats`、`debugFocusTable` 断言。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 78 项 + selftest 115 断言全绿，断言数只增不减。
