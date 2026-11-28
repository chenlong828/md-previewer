---
layer: history
module: editing
status: frozen
updated: 2026-11-28
---

# 工序结果：链接悬停操作与行内源码编辑（P2）

## 1. 交付内容

- 链接仍以 `<a class="md-link" href>` 渲染，单击的默认导航被拦截；普通单击在正文中原地展开
  Markdown 源码 `[文字](地址)`，Command+单击直接访问。
- 悬停 120ms 弹出「编辑 / 访问链接」，移出 180ms 收起；移入弹层不收起。
- 源码层复用编辑器自身的 parser/serializer：Enter/失焦提交（一次可撤销事务），Esc 取消；
  空源码只删除该链接；非法/多块源码不破坏文档。
- 访问意图经新增内核→壳请求 `openLink` 交给壳：`http/https/mailto/tel` 走系统默认应用
  （网页即默认浏览器）；本地 Markdown/代码在应用内新窗口打开，其他本地文件交系统默认应用；
  `#anchor` 在文档内按标题文本 slug 滚动。
- 需求/场景：[REQ-0016](../../../requirements/REQ-0016-link-interaction.md) /
  [SCN-0022](../../../design/scenarios/editing/rich-editing/link-interaction/scenario.md)。

## 2. 验收结果

| 门 | 命令 | 结果 |
|---|---|---|
| 场景 3 正 1 反（自动） | `./.build/debug/MDPreview --selftest` | `SELFTEST PASSED`；链接交互 10 项 PASS（另有「链接渲染」1 项） |
| 打包产物自检 | `dist/MDPreview.app/Contents/MacOS/MDPreview --selftest` | `SELFTEST PASSED` |
| 单元/契约 | `cd web && npm test` | 92 项 PASS（链接 MarkView 3 项） |
| 内核分层 | `node check-kernel.mjs` | OK（45 个文件） |
| 回归 | `--multiwindow-test` / `--context-menu-test` | 全 PASS |
| 构建 | `./build.sh debug` / `./build.sh` | 均通过；release `.app` 已签名 |
| 真机点验 | 用户 2026-11-28 | 悬停弹层、行内源码编辑、Enter/Esc、访问链接均通过 |
| 视觉 | `MDP_HOVER_LINK=1` / `MDP_EDIT_LINK=1 --screenshot` | 弹层与源码展开截图核对通过 |

`--selftest` 链接交互断言：

```text
PASS  链接 悬停弹层出现(编辑/访问链接)
PASS  链接 悬停弹层收起
PASS  链接 单击展开源码(文档不变)
PASS  链接 Esc 取消还原
PASS  链接 Enter 提交生效
PASS  链接 Command+单击访问请求
PASS  链接 访问不进入编辑
PASS  链接 失焦提交生效
PASS  链接 非法源码不破坏文档
PASS  链接 空源码只删除该链接
```

## 3. 结论落点

| 结论 | 落点 |
|---|---|
| 链接悬停/源码编辑的行为与不变量 | [CMP-editor §#link](../../../design/components/CMP-editor/spec.md)、[CMP-kernel-editor #link-view](../../../design/components/CMP-kernel-editor/spec.md) |
| `openLink` 请求与 URL 打开策略 | [architecture §2.9 / §3](../../../design/architecture.md)、[CMP-app-shell §#protocol-client](../../../design/components/CMP-app-shell/spec.md) |
| 协议清单 2→3 个内核请求 | [CMP-kernel-contract §#op-inventory](../../../design/components/CMP-kernel-contract/spec.md)、`web/test/contract.test.js` |
| 截图诊断钩子 | [CMP-diagnostics §环境钩子](../../../design/components/CMP-diagnostics/spec.md) |
| 用户验收记录 | SCN-0022 §6/§7、REQ-0016 §7 |
| 实现与回归断言 | `web/src/kernel/components/editor/link-view.js`、`Selftest.swift`、`web/test/core.test.js` |

## 4. 遗留与边界

- `#anchor` 只按标题文本 slug 匹配，不生成标题 id；跨文档锚点不在本次范围。
- 链接嵌套行内格式（如 `[**粗**](url)`）的源码往返由 parser/serializer 覆盖，自动断言固定的是
  纯文本标签。
- 未保存文档中的相对本地链接无法解析（无目录基准），壳返回 `ok:false`，不弹错误。
- 无 blocker；无冻结期需拍板的 decision；上述边界记入本 result 与场景 §6，不阻塞收口。
