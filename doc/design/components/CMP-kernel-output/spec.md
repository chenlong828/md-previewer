---
layer: design
module: kernel
component: CMP-kernel-output
status: active
updated: 2026-11-04
---

# CMP-kernel-output 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；输出
- 业务价值：把文档按「可交付形态」取出：独立 HTML、打印、内容几何（供壳出 PDF）。
- 负责：exportStandaloneHTML、print、getContentSize；导出前确保渲染模式（renderSurface）。
- 不负责：PDF 分页与写盘（壳）、打印对话框（系统）、代码文档导出（产品面禁用）。
- 内部逻辑：`export.js` 读渲染后 DOM 拼独立 HTML；`ops.js` 3 个 op。
- 拥有的数据：无持久数据；只读当前渲染结果。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、输出内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-output#export-html`：exportStandaloneHTML：响应携带 html
  - `CMP-kernel-output#print-and-geometry`：print/getContentSize：打印与 PDF 几何
- 入口：
  - `components/output/export.js#exportStandaloneHTML`
  - `components/output/ops.js#createOutputOps`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口，
  由 `kernel/assemble.js` 注入（详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- selftest PDF 导出（bytes/高度）、HTML 导出断言。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 78 项 + selftest 115 断言全绿，断言数只增不减。
