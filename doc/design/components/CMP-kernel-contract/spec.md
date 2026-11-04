---
layer: design
module: kernel
component: CMP-kernel-contract
status: active
updated: 2026-11-04
---

# CMP-kernel-contract 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1 技术边界；协议与注册表
- 业务价值：把「Swift 壳 / 未来 Windows 壳 / kernel core」钉在同一份可校验的契约上。有它，Windows 壳可以照 `HOST_OPS` 与错误码实现客户端，不用读内核源码；没有它，v1 的「未知 op 静默丢弃、ready 前调用无声吞掉」会原样复发。
- 负责：信封构造与校验（`v` 恒 2）、op 清单与 payload 形状校验、op 注册与分发、id 关联（并发请求各得各的响应）、版本握手、五种错误码、内核→壳请求的 id 表。
- 不负责：宿主通道（`CMP-kernel-transport`）；op 的业务实现（`CMP-kernel-*` 七组件）；语义规则（`CMP-kernel-semantics`）；壳侧超时与重试（`CMP-app-shell` 的 `KernelClient`，协议层不设超时）。
- 内部逻辑：`envelope.js` 构造四类帧并 `decode`/`classify`；`ops.js` 是 op 名与「必填字段 + 类型」的单一清单；`registry.js` 持 `handlers`/`pending` 两张表与 `ready`/`disabled` 两个开关；`errors.js` 定义码值与 `KernelError`。
- 拥有的数据：注册表（op → handler、`readyGated`）、挂起请求表（id → resolve/reject）、序号计数器、握手状态；不持文档内容。
- 变化轴：协议版本（v3 起重开握手语义）、op 清单增删、错误码集合、payload 校验宽度。
- 公开契约（含能力 ID）：
  - `CMP-kernel-contract#envelope`：请求 `{v,op,id,payload}`／成功响应 `{v,id,ok:true,payload}`／失败响应 `{v,id,ok:false,error}`／通知 `{v,op,payload}`（无 id）。
  - `CMP-kernel-contract#op-inventory`：41 个 host op、7 个通知、2 个内核请求；`HOST_OPS` 同时是握手响应 `ops[]` 的来源，壳与测试都读这一处。
  - `CMP-kernel-contract#dispatch`：`unknown_op`/`bad_payload`/`not_ready` 三种拒绝都显式应答（带原 id），不静默丢弃。
  - `CMP-kernel-contract#handshake`：`init.payload.opts.protocolVersion` 必须为 2；缺失 → `bad_payload`，不等 → `unsupported_version`，两种失败都置 `disabled`，此后一切请求回 `unsupported_version`。
  - `CMP-kernel-contract#error-codes`：`unknown_op` / `bad_payload` / `not_ready` / `unsupported_version` / `internal`。
  - `CMP-kernel-contract#host-requests`：内核→壳请求走 `callHost(op,payload)`，按 `h<n>` id 关联；未知 id 的响应进协议错误通道，不污染其它 pending。
  - `CMP-kernel-contract#json-guard`：payload 递归校验为 JSON 原语；handler 返回函数/Map/undefined/类实例 → `internal`。
- 入口：
  - `CMP-kernel-contract/web/src/kernel/contract/ops.js#HOST_OPS`（权威清单，另有 `NOTIFICATIONS`/`KERNEL_REQUESTS`/`validatePayload`）
  - `CMP-kernel-contract/web/src/kernel/contract/envelope.js#buildRequest`（另有 `buildOk`/`buildError`/`buildNotification`/`decode`/`classify`/`isJsonValue`）
  - `CMP-kernel-contract/web/src/kernel/contract/registry.js#createRegistry`
  - `CMP-kernel-contract/web/src/kernel/contract/errors.js#CODES`
  - `CMP-kernel-contract/web/test/support/fake-shell.js#FakeShell`（壳侧参照实现：注入 channel、应答内核请求、按 id 回填）
- 依赖：只 import 本层文件；第三方依赖为零。`web/check-kernel.mjs` 禁其 import `core/`/`semantics/`。
- 冷热属性：每帧一次校验与一次 payload 形状检查，成本为字段级；`changed` 有 200ms 防抖，不在输入热路径。
- 尺寸预算：目标 ≤120k token；当前 350 行（envelope 62 + errors 25 + ops 78 + registry 185）。
- 单独运行：`cd web && npm test`（`web/test/contract.test.js` 19 项，纯 Node、零 DOM、零 WebView）。
- 验证计划：见下表；19 项覆盖清单、握手成功/两种拒绝、版本错配、并发 id、三类拒绝码、缩略图 op 的 payload 校验、通知无响应、handler 异常与非 JSON 返回、内核请求成功/失败、畸形输入、无主响应、原语守门。
- 删除测试：删掉后每个壳各自实现一份帧格式与错误语义，Windows 与 macOS 必然分叉 → 真边界。

## 公开契约细节

- `#envelope` 的不变量：响应必回显请求 id；通知不产生响应；`v` 不为 2 的请求回 `unsupported_version`（带 id），无 id 的只进协议错误通道。
- `#dispatch` 的不变量：`init` 是唯一豁免 ready 门槛的 op（`READY_EXEMPT`）；通知处理失败只上报、不应答；请求处理失败必须应答同一个 id。
- `#handshake` 的不变量：握手成功的那次响应携带 `kernelVersion`/`protocolVersion`/`ops`（`ops` 与注册表全等，顺序即注册顺序）；失败后 `disabled` 不再复位，只有重载页面才能恢复。
- `#host-requests` 的错误模式：内核请求的 `error.code` 原样保留在 reject 出的 `KernelError` 上；`shutdown()` 把挂起请求全部以 `internal` 拒绝，不悬挂 Promise。
- `#json-guard` 的边界：只做「必填字段 + 类型」校验，不做完整 JSON Schema（宽度按调用方裁剪）；空响应补成 `{}`，壳侧统一按字典取。

## 验证计划

| 契约 | 测试（`web/test/contract.test.js`） |
|---|---|
| `#op-inventory` | 「契约清单：41 个 host op、7 个通知、2 个内核请求，且不重复」 |
| `#handshake` | 「握手：init{protocolVersion:2} → 回显…」「握手拒绝：protocolVersion 1 → unsupported_version，之后内核停用」「握手缺字段…」 |
| `#envelope` | 「信封版本错配：v1 消息 → unsupported_version 响应（带原 id）」「id 回显：两个并发请求各得各的响应」 |
| `#dispatch` | 「unknown_op…」「bad_payload…」「缩略图 op：setMinimapVisible 必须带 boolean…」「not_ready：握手前的 gated op 显式报错；init 后可调用」「handler 抛普通异常 → internal…」 |
| `#host-requests` | 「内核 → 壳请求：callHost 按 id 关联，响应回填到调用方」「…请求失败：错误响应 → callHost reject」「无主响应：未知 id…不污染 pending」 |
| `#json-guard` | 「handler 返回非 JSON 值 → internal」「JSON 原语守门：函数 / Map / undefined / 类实例一律拒绝」 |
| 通知 | 「通知无响应：changed 只进通知通道」「通知 payload 非法：内核侧直接抛错」 |
| 健壮性 | 「畸形输入：非法 JSON 与非对象信封进协议错误通道，内核不崩」 |
| 壳侧参照 | `FakeShell` 被上述全部用例使用；真壳自检另有「v2 握手(protocolVersion=2, ops=41)」 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| op 清单与 payload 形状 | `ops.js`（人工维护，加法扩展） | 注册表、握手响应、壳侧对齐、测试 | 单一来源 |
| handler 表 | `register()` | 分发 | 单实例；重复注册覆盖 |
| pending（内核请求） | `callHost` / `settlePending` | 内核调用方 | 按 id 单次结算 |
| 握手状态 | `assertHandshake` | 全部分发路径 | 进程级，失败即锁死 |

## 验证债

无未决验证债。已知边界：`ops[]` 顺序取决于注册顺序，壳不该据此做等价判断（按集合比）；协议层无超时，超时语义只在壳侧（`KernelClient` 默认 10s，GC 路径显式传 2s）——两处口径不一致时以壳侧为准。

## 删除测试

删掉后帧格式与错误语义由每个壳各写一份，macOS 与 Windows 的分叉只在联调时暴露 → 保留为真边界。
