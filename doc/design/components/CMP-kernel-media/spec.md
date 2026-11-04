---
layer: design
module: kernel
component: CMP-kernel-media
status: active
updated: 2026-11-04
---

# CMP-kernel-media 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1b 能力组件；图片媒体
- 业务价值：粘贴/拖入图片时把「落盘」与「编辑器插入」分开：本组件只识别载荷并请求壳。
- 负责：粘贴监听安装、图片载荷识别（blob/file）、importImage 请求编排（选区快照）、经 imageInsertion 插入。
- 不负责：图片节点渲染与源码编辑块（editor 的 NodeView）、落盘本身（壳的 ImageStore）、GC 引用解析（document + semantics）。
- 内部逻辑：`image-paste.js`：extractImagePayload/setupImagePaste/handleImported；不持有 ProseMirror 事务。
- 拥有的数据：无持久数据；不写文件（落盘在壳）。
- 变化轴：op 集合增删（须同步 `contract/ops.js`）、图片媒体内的交互细节、引擎版本升级。
- 公开契约（含能力 ID）：
  - `CMP-kernel-media#payload`：extractImagePayload：剪贴板图片载荷识别
  - `CMP-kernel-media#import`：setupImagePaste：识别→请求→插入编排
- 入口：
  - `components/media/image-paste.js#createMediaPaste`
- 依赖：自身目录 + `shared`（state/bus/ports）+ `semantics`；跨组件能力经 `shared/ports.js` 端口，
  由 `kernel/assemble.js` 注入（详见 architecture §4.2）。第三方依赖允许（引擎绑定层）。
- 单独运行：`cd web && npm test`（Node 契约/语义/core 三组，零 WebView）。
- 删除测试：删掉本组件则对应 op 全部失效、端口无人提供（装配即抛 `port not provided`），
  故障面清晰可见 → 真组件。

## 验证计划

- Screenshot e2e `MDP_PASTE_IMAGE`（paste→v2 请求→落盘→插入）；Node core 组「图片载荷识别」。
- 禁边：`node check-kernel.mjs` 校验「组件只 import 自身 + shared + semantics」。
- 回归门：Node 78 项 + selftest 115 断言全绿，断言数只增不减。
