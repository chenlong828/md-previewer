---
layer: design
module: kernel
component: CMP-kernel-document
status: active
updated: 2026-11-04
---

# CMP-kernel-document 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；会话与文档
- 业务价值：让「文档」这件事只有一处状态：装载/取回口径、基线、主题缩放、GC 引用。
- 负责：会话状态迁移（init/setMarkdown/getSaveMarkdown/markClean/setBaseDir/setTitle/setTheme/setZoom/getState/toggleSource）、装载前的资源问答编排、GC 引用收集；`init` 把 `opts.minimapVisible` 交给 `minimapSurface` 应用偏好。
- 不负责：编辑器装配（editor）、查找（find）、代码面渲染（code）、导出（output）、粘贴（media）、缩略图挂载/缩放（minimap）。
- 内部逻辑：`render.js` 渲染入口与基线；`ops.js` 12 个 op；装载改写经 semantics.applyForLoad，取回答复经 restoreForSave；`init` 末尾经 `minimapSurface.setVisible` 应用偏好（不直接 import minimap）。
- 拥有的数据：文档级状态（baseDir/theme/zoom/baselineMarkdown）唯一写入口；不拥有文件内容。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、会话与文档内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-document#session`：init/setMarkdown/getSaveMarkdown/markClean/setBaseDir：文档会话生命周期
  - `CMP-kernel-document#state`：getState/setTheme/setZoom/setTitle：可观测状态与显示偏好
  - `CMP-kernel-document#resource-refs`：getResourceRefs：GC 引用集合（宁多保护）
- 入口：
  - `components/document/ops.js#createSessionOps`
  - `components/document/render.js#renderMarkdown`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口
  （`editorSurface`/`renderSurface`/`codeSurface`/`minimapSurface`），由 `kernel/assemble.js` 注入
  （详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- Node `core.test.js` 的装载改写/保存口径/基线/统计/资源集合各组；「缩略图：init 应用偏好，
  setMinimapVisible/minimapInfo 经端口工作」；selftest「装载改写」「保存口径」「缩略图 默认显示」。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 85 项 + selftest 全绿，断言数只增不减。
