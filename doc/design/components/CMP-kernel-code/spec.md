---
layer: design
module: kernel
component: CMP-kernel-code
status: active
updated: 2026-11-04
---

# CMP-kernel-code 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；代码面
- 业务价值：代码文件只读可读：高亮、行号、语言切换、代码内查找，不与 Markdown 面互相污染。
- 负责：showCode/hideCode、语言注册与按需加载、行号、代码内查找、codeInfo。
- 不负责：文档种类判定（壳的 FileSupport）、编辑（代码恒只读）、查找栏 UI（find）。
- 内部逻辑：`code-view.js` DOM 与高亮；`languages.js` 语法注册表；`ops.js` 5 个 op + 端口实现（codeSurface/codeLanguages/searchSurface）。
- 拥有的数据：代码面 DOM 与语言表；不改文档内容、不发 changed。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、代码面内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-code#set-code`：setCode/setCodeLanguage/setCodeLineNumbers/codeInfo/hasLanguages：只读代码视图
  - `CMP-kernel-code#search`：findInCode/clearCodeFind/codeFindCount：代码面查找实现
- 入口：
  - `components/code/index.js#createCodeSurface`
  - `components/code/index.js#createCodeSearch`
  - `components/code/ops.js#createCodeOps`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口，
  由 `kernel/assemble.js` 注入（详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- selftest 代码视图组（语言切换、行号、查找命中）；Node core 组「代码视图信息与语言表」。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 78 项 + selftest 115 断言全绿，断言数只增不减。
