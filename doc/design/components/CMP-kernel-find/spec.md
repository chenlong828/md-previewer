---
layer: design
module: kernel
component: CMP-kernel-find
status: active
updated: 2026-11-04
---

# CMP-kernel-find 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；查找
- 业务价值：一处查找体验：⌘F 栏、命中计数、循环定位，Markdown 与代码面同口径。
- 负责：查找栏开合与输入、命中遍历与装饰、源码模式与代码面分派。
- 不负责：编辑器文档结构（editor）、代码面高亮与滚动（code，经 searchSurface）。
- 内部逻辑：`find.js` ProseMirror 插件与命中算法；`find-bar.js` UI 与遍历；`ops.js` 5 个 op + findService 端口。
- 拥有的数据：查找会话状态（query/caseSensitive/srcMatches），不写文档。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、查找内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-find#open-close`：openFindBar/closeFindBar：查找栏生命周期
  - `CMP-kernel-find#step`：findNext/findPrev/findInfo：命中遍历与计数
- 入口：
  - `components/find/index.js#createFindService`
  - `components/find/ops.js#createFindOps`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口，
  由 `kernel/assemble.js` 注入（详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- selftest 查找组（命中计数、循环、源码模式）；代码面查找经 searchSurface 的分派。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 78 项 + selftest 115 断言全绿，断言数只增不减。
