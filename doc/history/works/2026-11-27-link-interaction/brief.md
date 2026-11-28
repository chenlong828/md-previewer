---
layer: history
module: editing
status: frozen
updated: 2026-11-28
---

# 工序 brief：链接悬停操作与行内源码编辑（功能 / P2）

> 需求卡：[REQ-0016](../../../requirements/REQ-0016-link-interaction.md)；
> 场景：[SCN-0022](../../../design/scenarios/editing/rich-editing/link-interaction/scenario.md)。
> 本页是执行记录；why / 非目标 / 验收以卡为准。

## 1. 需求

文档中的链接支持在系统默认浏览器打开：悬停链接弹出「编辑 / 访问链接」；
单击链接进入 Markdown 源码编辑，源码在所见即所得正文中原地展开（参考 Obsidian）；
Enter/失焦提交，Esc 取消；Command+单击直接访问。

## 2. 组件设计（修改方案）

改动落在内核编辑面与壳的桥请求分发：新增一个链接 MarkView，链接渲染/悬停弹层/行内源码编辑都在
`CMP-kernel-editor` 内完成；「访问链接」只经 `openLink` 请求上报意图，系统 API 与窗口路由留在 `CMP-app-shell`。

```
ProseMirror link mark
  └─ link-view.js MarkView
       ├─ 渲染态 <a class="md-link">（单击默认导航被拦截）
       ├─ mouseenter → .md-link-popup「编辑 / 访问链接」
       ├─ 单击/编辑 → 行内源码层 [文字](地址)
       │     ├─ Enter/失焦 → parserCtx 解析 → replaceWith(可撤销)
       │     └─ Esc        → 还原，文档不变
       └─ 访问 → hostCall('openLink', {href})
                       │
                       ▼
            KernelClient → DocumentWindowController.handleKernelRequest
                       ├─ http/https/mailto/tel → NSWorkspace（默认浏览器/邮件）
                       ├─ 相对路径或 file:// → FileSupport 判定
                       │     ├─ md/代码 → AppDelegate.openInNewWindow
                       │     └─ 其他文件 → NSWorkspace
                       └─ #anchor → 由内核本地滚动
```

### 改动级别

**P2**：兼容性契约扩展（`KERNEL_REQUESTS` 增加 `openLink`，既有 op 语义不变），
跨 `CMP-kernel-contract` / `CMP-kernel-editor` / `CMP-app-shell` 三个组件；不新增组件、不改数据结构、
不改文档 schema、不加依赖。

### 外部契约调整

- `CMP-kernel-contract#host-requests`：内核→壳请求由 2 个增加到 3 个，新增
  `openLink {href: string, baseDir?: string}` → `{ok: boolean}`。纯增量，无迁移。
- `CMP-kernel-editor#link-view`：新增内部 MarkView（不是 host op）；链接渲染契约不变（仍是 `<a href>`）。
- `CMP-app-shell#open-link`：新增请求处理与打开策略；既有 `EditorWebView` 的 `.linkActivated` 拦截保留，
  兼容正文中未经过 MarkView 的原生链接（如未来嵌入的 HTML）。

### 组件间关系

- `link-view.js` 只依赖 `@milkdown/core`（parser/serializer）、`@milkdown/prose`（选区）、`shared`（state/bus）；
  不 import 其他组件。
- `openLink` 走既有 `callHost` 端口；壳不感知链接 DOM，只接收 href。
- 链接源码解析复用编辑器自身的 `parserCtx`，不引入第二套 Markdown 解析器；数据所有权不变
  （文档仍由 `CMP-kernel-document`/ProseMirror 持有）。

### 修改点与波及面

- 改：`web/src/kernel/components/editor/link-view.js`（新增）、`editor.js`（注册 MarkView）、
  `typora.css`（链接源码/弹层样式）、`contract/ops.js`（请求清单）、
  `Sources/MDPreview/DocumentWindowController.swift`（`openLink` 分发）、
  `Selftest.swift`（链接组断言与假壳应答）、`web/test/contract.test.js`（清单）。
- 不受影响：Markdown 解析/序列化规则、图片/Mermaid NodeView、文件读写、抽屉、导出、缩略图、查找。

## 3. 验收标准

- SCN-0022 的 3 正 1 反在 `--selftest` 全绿（悬停弹层、单击展开、提交/取消、非法源码反例、Cmd+单击请求）。
- `cd web && npm test` 契约清单更新后全绿；`node check-kernel.mjs` 通过。
- `./build.sh debug` 通过；`--selftest` / `--multiwindow-test` / `--context-menu-test` 不回归。
- 人工点验：真实悬停、系统浏览器打开、深/浅色下的源码编辑视觉。

## 4. 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-2026-11-27-01 | design | CMP-kernel-editor / CMP-app-shell | done | 本 brief、REQ-0016、SCN-0022、CMP-editor spec、architecture §3 |
| T-2026-11-27-02 | change | CMP-kernel-editor | done | `link-view.js`、`editor.js`、`typora.css`、`image-view.js`（同类实现） |
| T-2026-11-27-03 | change | CMP-kernel-contract / CMP-app-shell | done | `ops.js`、`KernelClient.swift`、`DocumentWindowController.swift`、`Selftest.swift` |
| T-2026-11-27-04 | verify | 全部 | done（自动门全绿 + release 构建 + 用户 2026-11-28 真机点验） | SCN-0022 测试表、`--selftest`、`npm test`、`build.sh` |

## 5. 验证记录（2026-11-28）

| 门 | 命令 | 结果 |
|---|---|---|
| 链接自动断言 | `./.build/debug/MDPreview --selftest`；打包产物同命令 | 两者均 `SELFTEST PASSED`；链接交互 10 项 PASS（另有「链接渲染」） |
| 单元/契约 | `cd web && npm test` | 92 项 PASS（含链接 MarkView 3 项） |
| 内核分层 | `node check-kernel.mjs` | OK（45 个文件） |
| 全量构建 | `./build.sh debug` / `./build.sh` | 均通过；`dist/MDPreview.app` 为 release 产物并已签名 |
| 回归 | `--multiwindow-test` / `--context-menu-test` | 全 PASS |
| 视觉 | `MDP_HOVER_LINK=1` / `MDP_EDIT_LINK=1 --screenshot` | 弹层与行内源码展开截图人工核对通过 |

真机鼠标悬停轨迹与「访问链接」实际拉起默认浏览器已由用户 2026-11-28 点验通过（自动断言只到 `openLink` 请求边界）。

## 5. 未决问题

- 真实鼠标轨迹下弹层的出现/收起手感、以及「访问链接」实际拉起默认浏览器已由用户 2026-11-28 点验；自动断言只覆盖 DOM 事件与请求边界。
- 锚点链接（`#标题`）的滚动只按标题文本 slug 匹配，不生成标题 id；若后续需要跨文档锚点再扩。
