---
layer: design
module: editing
status: verified
updated: 2026-11-28
flow: FLOW-EDIT-002
scenario: SCN-0022
domain: 编辑
valueStream: 富文本编辑
title: 悬停链接与行内源码编辑
entries:
  - CMP-kernel-editor/web/src/kernel/components/editor/link-view.js#getLinkView
  - CMP-kernel-editor/web/src/kernel/components/editor/editor.js#createEditor
  - CMP-kernel-contract/web/src/kernel/contract/ops.js#KERNEL_REQUESTS
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#handleKernelRequest
docs:
  - path: doc/design/architecture.md
    heading: 3. 桥协议
  - path: doc/requirements/REQ-0016-link-interaction.md
    heading: 4. 行为约定
tests:
  - role: R1
    id: TC-LINK-001
  - role: R2
    id: TC-LINK-002
  - role: R3
    id: TC-LINK-003
  - role: N1
    id: TC-LINK-004
---

# 悬停链接与行内源码编辑

## 1. 场景与价值

用户在渲染视图里悬停链接，弹层给出「编辑 / 访问链接」；点「访问链接」按 URL 类型走系统浏览器或应用内打开；
点「编辑」或直接单击链接，链接在正文中原地展开为 Markdown 源码，可改文字与地址；Enter/失焦提交，Esc 取消。

结果：改链接与访问链接都不离开当前编辑视图，也不必切到全文源码模式。

## 2. 入口

- `CMP-kernel-editor#link-view`：链接 MarkView、悬停弹层、行内源码编辑。
- `CMP-kernel-contract#host-requests`：新增 `openLink` 内核→壳请求。
- `CMP-app-shell#open-link`：壳侧按 URL 类型路由（默认浏览器 / 应用内新窗口 / 系统默认应用）。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（链接分支）。

1. 链接以 `<a class="md-link" href=…>` 渲染；单击的默认导航被拦截。
2. 鼠标进入链接：120ms 后显示弹层「编辑 / 访问链接」；移出后 180ms 收起（移入弹层不收起）。
3. 「编辑」或单击链接：定位链接的文本区间，把该区间在视图中替换为源码编辑层
   `[文字](地址)`，其余正文保持渲染态；源码编辑层获得焦点。
4. 编辑源码：Enter 或失焦提交——用编辑器 parser 解析源码，成功则把原链接区间替换为解析结果；
   空源码删除链接；Esc 取消——不修改文档，恢复渲染态。
5. 「访问链接」或 Command+单击：经 `openLink{href}` 请求交给壳；壳按协议打开默认浏览器/应用内窗口/系统应用。
6. 纯 `#anchor` 不发请求，在内核内滚动到匹配标题。

失败路径：

- 源码解析失败、解析出多个块或非段落：不修改文档，恢复渲染态。
- 链接区间在提交时已失效（文档被外部修改）：不修改文档。
- 壳拒绝/无法打开（未知协议、未保存文档的相对链接）：静默保持原状，不进入编辑路径。

## 4. 不可变引用

- 单击链接不导航、不改文档；展开源码本身不产生脏标记。
- 提交只在源码与原文不同且可解析时写文档；提交是一次可撤销的编辑。
- 渲染态与源码态共用同一 Markdown 文档模型；不新增链接语法。
- 壳与内核的分界不变：web 只上报 `openLink` 意图，系统 API 与窗口路由只在壳内。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-LINK-001 | R1 | 自动 | `--selftest` + `web npm test` | 悬停链接出现「编辑 / 访问链接」两个动作；移出后收起；`openLink` 请求按 href 到达壳 | present（`--selftest`「链接 悬停…」2 项 + core「悬停弹层出现与收起」） |
| TC-LINK-002 | R2 | 自动 | `--selftest` + `web npm test` | 单击链接后 `.md-link-editing` 出现，编辑层文本等于 `[链接](https://example.com)`；提交前 `getMarkdown` 不变 | present（`--selftest`「单击展开源码」+ core「渲染与行内源码提交」） |
| TC-LINK-003 | R3 | 自动 | `--selftest` | 编辑源码 + Enter/失焦后 Markdown 出现新文字/新地址；Esc 取消后 Markdown 与展开前一致；Command+单击触发 `openLink` | present（Enter/失焦/Esc/Command+单击 4 项） |
| TC-LINK-004 | N1 | 自动 | `--selftest` | 非法源码（解析成块级标题）提交不破坏文档；空源码只删除该链接 | present（非法源码 + 空源码 2 项） |

## 6. 验证债

- 自动门已绿：`--selftest` 链接交互 10 项（另有初始渲染的「链接渲染」1 项）+ `web npm test` 链接组 3 项；用户 2026-11-28 真机点验通过（悬停弹层、行内源码编辑、访问链接）。
- 链接嵌套行内格式（如 `[**粗**](url)`）的源码往返由 parser/serializer 覆盖，自动断言暂只固定纯文本标签。

## 7. 变更记录

- 2026-11-28 新建：REQ-0016 的实现场景；自动断言落在 `--selftest` 的「链接」组。
- 2026-11-28 用户真机点验通过，状态转 `verified`。
