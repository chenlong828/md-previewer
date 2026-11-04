---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# result.md — 可移植内核 v2 与桥协议切换（2026-11-04）

## 交付了什么

1. **四层内核**（`web/src/kernel/`）：`transport`（唯一宿主感知点）/ `contract`（信封·op 清单·注册表·握手·错误码）/
   `semantics`（路径与 markdown 语义，纯函数）/ `core`（39 个 op 的唯一实现）。组合根 `web/src/page.js`。
2. **桥协议 v2**：单通道 JSON 帧（`{v:2, op, id, payload}` / 响应回显 id / 通知无 id），39 op、7 通知、
   2 个内核请求（`resolveResources`、`importImage`）、5 个错误码、握手拒绝即禁用。
3. **macOS 壳切换**：`KernelClient`（帧编解码/id 关联/超时/请求应答）+ 26 处 `callJS` 全部收敛到 op；
   保存走 `getSaveMarkdown`、GC 引用走 `getResourceRefs`、装载改写走 `setMarkdown` op。
4. **语义单点**：Swift `ImagePathRewriter`（220 行）删除，`R9` 关闭。
5. **Windows 参照物**：可运行的 Node 契约/语义/core 套件 + `FakeShell`/`dom.js` 假壳 + 本工序 spec-delta。

## 验收证据（本机实测）

| 项 | 命令 | 结果 |
|---|---|---|
| 层禁边 | `node check-kernel.mjs` | OK（25 个内核文件） |
| Node 套件 | `npm run verify`（含 lint） | 78 项全绿：契约 18 + 语义 50 + core 10 |
| 语义等价 | `web/test/fixtures/semantics-golden.json`（Swift 旧实现生成） | 15 用例 × 3 函数 = 45 项逐字节一致 |
| 壳自检 | `./build.sh debug && ./.build/debug/MDPreview --selftest` | **115 PASS / 0 FAIL** |
| 图片粘贴全链路 | `MDP_PASTE_IMAGE=… --screenshot …` | 落盘 `resource/doc/img_001.png`，核内插入 `file:///tmp/…/img_001.png` |

### 断言数对账（121 → 115 不是退化）

- 基线 121（v1 时期）。
- 删：`testPathRewriter` 的 11 项——Swift 改写器已删除，其语义覆盖搬到 Node 黄金对拍（45 项）。
- 增：5 项 v2 断言（握手、`getState` 往返、装载改写端到端、保存口径端到端、v2 握手响应）。

## 关键设计决定与代价

- **一次发布切换**（用户决策）：不留 v1/v2 并行开关；迁移期 `window.mdbridge` 只作测试门面（`__MDP_TEST__`），
  产品 bundle 不暴露。
- **请求自包含**：`resolveResources` 必带 `baseDir`。真实壳里验证时发现的缺陷——让壳猜「当前文档目录」
  会在未保存/另存场景把引用误判为缺失。
- **存在性归壳、语义归核**：内核不碰文件系统，`semantics` 是纯函数；这也是 Windows 壳只需实现
  两个请求即可复用的原因。
- **代价**：`changed` 仍走 200ms 防抖 + 过期过滤（未改）；`evaluateJavaScript` 保留两处
  （帧投递、诊断取数），是刻意的边界而非遗漏。

## 未覆盖 / 转到后续

- 打印（`print` op）与「另存为后 baseDir 时序」未做自动化，列入人工点验清单（进入 `CMP-app-shell` 规格的验证计划）。
- 自检脚本仍大量经测试门面调 `window.mdbridge.*`（87 处 `evaluate`）。门面是测试专用，
  但把自检迁到 v2 请求是后续清理项（不在本工序验收内）。
- minimap 工序按用户决策延后，`2026-11-04-document-minimap` 暂停排队。

## 结论落点表

| 结论 | 落点 |
|---|---|
| 桥协议 v2（帧/握手/错误码/op 清单/内核请求） | `doc/design/architecture.md` §3 |
| 内核四层与禁边 | `doc/design/architecture.md` §4 |
| 桥面收敛为单通道、无注入脚本 | `doc/design/architecture.md` §1.3 |
| 路径改写规则不变、实现迁入内核 | `doc/design/architecture.md` §2.1 首段 |
| 四层组件契约 | `doc/design/components/CMP-kernel-{transport,contract,semantics,core}/spec.md` |
| 图片组件职责收缩（解析移交内核） | `doc/design/components/CMP-image/spec.md` |
| 壳侧协议实现与诊断边界 | `doc/design/components/CMP-app-shell/spec.md` |
| 风险 R9 关闭 | `doc/plan/risks.md` |
| 工序状态 | `doc/plan/roadmap.md` |
| 规格与实现的一致性证据 | 本文件「验收证据」+ `review.md` |
