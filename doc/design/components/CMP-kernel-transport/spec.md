---
layer: design
module: kernel
component: CMP-kernel-transport
status: active
updated: 2026-11-04
---

# CMP-kernel-transport 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L0 技术边界；内核防腐层（宿主通道）
- 业务价值：让内核其余三层完全不知道宿主是什么；Windows 壳因此只需「注入两个全局函数 + 装载页面」，而不是复刻一套宿主适配。没有它，`window.webkit`／`chrome.webview` 会沿调用链回流到编辑逻辑里。
- 负责：唯一宿主感知点——取用壳注入的 `window.__mdHostChannel.post`、暴露 `window.__mdKernel.receive`、安装/卸载 jserror 三源钩子（`window error`、`unhandledrejection`、`console.error` 转发），并把内核发出的帧序列化为 JSON 字符串。
- 不负责：信封构造/校验、op 分发、握手与错误码（`CMP-kernel-contract`）；任何编辑能力（`CMP-kernel-*` 六组件）；路径与 markdown 语义（`CMP-kernel-semantics`）；壳侧帧编解码、id 表与超时（`CMP-app-shell` 的 `KernelClient`）。
- 内部逻辑：`createTransport({win})` 构造即校验 channel（`post` 非函数则抛错，不静默降级）；`send()` 只接受普通对象，`JSON.stringify` 后一次交给 channel；`expose(handler)` 把 `__mdKernel` 冻结为单方法对象，后注册者覆盖前值；`installErrorHooks(report)` 注册三个监听并返回卸载函数，`console.error` 补丁在 `finally` 里转调原函数。
- 拥有的数据：`receive` 单引用与错误钩子的 cleanup 列表；不持有文档、会话或 UI 状态，不持久化任何东西。
- 变化轴：宿主通道名与形态（WKWebView / WebView2 / GTK）、错误钩子来源集合。
- 公开契约（含能力 ID）：
  - `CMP-kernel-transport#host-channel`：内核→壳唯一出口；一帧一个 JSON 字符串，不做批量与合并。
  - `CMP-kernel-transport#kernel-entry`：壳→内核唯一入口；`receive(json)` 永不抛出，畸形输入进协议错误通道而非崩页面。
  - `CMP-kernel-transport#boot-strict`：channel 缺失时构造抛错，`boot` 可见失败——壳装错顺序立刻暴露。
  - `CMP-kernel-transport#error-hooks`：三源错误转成 `jserror` 载荷 `{message, where?, stack?}`；返回卸载函数供组件停止时回收。
- 入口：
  - `CMP-kernel-transport/web/src/kernel/transport/channel.js#createTransport`
  - `CMP-kernel-transport/web/src/kernel/main.js#bootKernel`（装配顺序：建 transport → 建 registry → `expose` → 装钩子 → 注册 op → 发 `boot`）
  - `CMP-kernel-transport/Sources/MDPreview/KernelClient.swift#installScript`（壳侧对应物：注入 channel 与内核版本）
- 依赖：无。零第三方依赖、零层间 import（`web/check-kernel.mjs` 把宿主符号限定在本层）。
- 冷热属性：每帧一次 `JSON.stringify`，在输入热路径之外（`changed` 有 200ms 防抖）；错误钩子只在异常时触发。
- 尺寸预算：目标 ≤120k token；当前 73 行（`channel.js`），全内核 2942 行。
- 单独运行：`cd web && npm test`（`web/test/contract.test.js` 经 `FakeShell` 走真实类实例）；宿主符号守门 `node check-kernel.mjs`。
- 验证计划：宿主符号只出现在本层（脚本守门）；通道单出口/单入口由契约套件经 `FakeShell` 全量驱动；缺 channel 的负例与钩子卸载无自动断言。
- 删除测试：删掉后每个宿主符号都要散落到 contract/core，Windows 移植时逐文件改源码 → 真边界。

## 公开契约细节

- `#host-channel` 的不变量：`post` 只接收字符串；内核不读 channel 的其它字段，也不缓存其实现（每次经 channel 对象调用）。
- `#kernel-entry` 的不变量：`__mdKernel` 是冻结对象，只暴露 `receive`；`receive` 返回 Promise 且永不 reject——协议错误走 `onProtocolError` 或 `jserror` 通知。
- `#boot-strict` 的错误模式：抛 `kernel transport: window.__mdHostChannel.post is required before kernel evaluation`；壳据此判定「注入脚本没跑或跑了但被 CSP 拦」，不做二次降级。
- `#error-hooks` 的不变量：三源共用同一 `report` 回调；卸载函数可重复调用（空 cleanup 亦安全）；钩子自身抛错不得打断页面原始行为。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#host-channel` / `#kernel-entry` | `web/test/contract.test.js`：握手往返、id 回显、通知无响应、畸形输入、无主响应（全部经 `web/test/support/fake-shell.js` 的真实 transport） |
| `#boot-strict` | 无自动断言（见验证债）；人工：删掉注入脚本启动，确认 boot 报错而非白屏 |
| `#error-hooks` | 无自动断言（见验证债）；selftest 的 `jserror` 上报路径间接触达 |
| 禁边 | `web/check-kernel.mjs`：`window.webkit`/`messageHandlers`/`__mdHostChannel`/`chrome.webview` 只在本层命中合法 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 出站帧（JSON 字符串） | 本组件 `send` | 壳 messageHandler | 一帧一次，不缓存 |
| `__mdKernel.receive` | 本组件 `expose` | 壳 `KernelClient.deliver` | 单实例，冻结 |
| 错误钩子 cleanup | 本组件 | 停止时的调用方 | 进程级，无持久化 |

## 验证债

缺 channel 的抛错路径与 `installErrorHooks` 的卸载没有自动化负例（只在真实 WebView 里靠装配顺序验证）。补法低成本：往 `contract.test.js` 加两条——`createTransport({win:{}})` 抛错、卸载后 `error` 事件不再上报。本次未加，属文档已记录的缺口。

## 删除测试

删掉本组件后宿主符号将出现在 contract/core 的多个文件里，Windows 移植退化成逐文件改源码，R9 类分叉风险复发 → 保留为真边界。
