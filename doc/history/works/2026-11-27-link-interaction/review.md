---
layer: history
module: editing
status: frozen
updated: 2026-11-28
---

# 工序评审：链接悬停操作与行内源码编辑（P2）

## 1. 结论

**通过**。用户 2026-11-28 真机点验通过；自动门全绿。
摘要：blocker 0 / decision 0 / hold 1（#anchor slug 边界，已记入 result）。

## 2. 四档裁决（P2：blocker / decision now / verified sound）

### Blocker

- 无。单击链接不导航、不改文档；提交失败/非法源码不破坏文档；`openLink` 只传 href，
  壳按白名单协议路由，未知协议与不存在的本地文件返回 `ok:false`。

### Decision now

- 无。`openLink` 为兼容扩展：`HOST_OPS` 的 41 个 host op 与 7 个通知不变，
  `KERNEL_REQUESTS` 从 2 个增至 3 个；既有 op 语义与响应形状不变，无迁移。

### Verified sound

| 检查 | 证据 | 结果 |
|---|---|---|
| 链接渲染仍可被自检/导出识别 | `--selftest`「链接渲染」；`toDOM` 仍输出 `<a href>` | 通过 |
| 悬停弹层出现/收起 | `--selftest` 2 项 + `web npm test` 悬停用例 | 通过 |
| 单击展开源码不改文档 | `--selftest`「单击展开源码(文档不变)」+ core 用例 | 通过 |
| Enter/失焦提交、Esc 取消、Command+单击 | `--selftest` 4 项 + 截图 | 通过 |
| 非法/空源码边界 | `--selftest` 2 项 | 通过 |
| 协议清单双端一致 | `web/test/contract.test.js`「3 个内核请求」 | 通过 |
| 分层禁边 | `node check-kernel.mjs`（45 文件） | 通过 |
| 回归 | `--multiwindow-test`、`--context-menu-test` | 通过 |
| 兼容性 | 既有 41 host op / 7 通知未动；`EditorWebView` 原生链接拦截保留 | 通过 |

## 3. Hold

- `#anchor` 只按标题文本 slug 匹配，不生成标题 id；跨文档锚点需要时再扩。不阻塞本次交付，
  已记入 [result.md](./result.md) §4 与 SCN-0022 §6。

## 4. 风险与人工门

- 真实鼠标轨迹、系统默认浏览器弹出、深/浅色源码视觉由用户 2026-11-28 点验通过；
  自动断言只覆盖 DOM 事件与 `openLink` 请求边界。
