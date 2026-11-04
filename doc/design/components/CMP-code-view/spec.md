---
layer: design
module: editing
component: CMP-code-view
status: active
updated: 2026-11-04
---

# CMP-code-view 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1 领域；业务能力（代码阅读面）
- 业务价值：让用户在同一窗口里阅读常见代码文件的**只读高亮源码**；没有它，代码文件只能交给外部编辑器，Markdown 与代码之间要换应用。
- 负责：文件种类判定与语言表（`FileSupport`）；代码文档的只读装载与状态（无脏、无保存）；`#code-view` 渲染、语言切换、纯文本降级、代码内查找、大文件阈值；状态栏语言/行数文案。
- 不负责：Markdown 解析/编辑/保存（`CMP-editor` / `CMP-document-io`）；窗口/菜单骨架（`CMP-app-shell`）；抽屉树与过滤调用（`CMP-drawer` 只调用 `#kind`）；PDF/打印的窗口级实现（`CMP-export` 以 `#code-view` 为内容面）。
- 内部逻辑：`FileSupport.swift` 维护语言表与 `UTType` 构造；`DocumentWindowController` 的 kind 分支与菜单门禁；`languages.js` 负责 refractor 语法注册（与编辑器代码块共用）；`code-view.js` 负责渲染与查找；样式复用 `typora.css` 的 token 调色板。
- 拥有的数据：代码文档的内存文本副本（只读投影，不写回）、当前高亮语言选择（会话级，不持久化）、大文件降级标志。
- 变化轴：受支持语言清单/扩展名映射、高亮引擎与调色板、大文件阈值、语言切换入口。
- 公开契约（含能力 ID）：
  - `CMP-code-view#kind`：扩展名 → `DocumentKind`；可打开扩展名集合；语言表（id/显示名/扩展名）单一来源。
  - `CMP-code-view#set-code`：进入只读代码视图并渲染；不产生 `changed`；`setMarkdown` 必须退出代码视图。
  - `CMP-code-view#language-switch`：`auto` / `plaintext` / 语言 id 三种选择，只重绘不写文件。
  - `CMP-code-view#code-find`：命中计数与上一处/下一处定位（文本选区），无命中不抛错。
  - `CMP-code-view#large-guard`：超过 512 KB（UTF-8 字节）降级纯文本并在状态栏标注。
- 入口：
  - `CMP-code-view/Sources/MDPreview/FileSupport.swift#FileSupport`
  - `CMP-code-view/Sources/MDPreview/DocumentWindowController.swift#openDocument`
  - `CMP-code-view/web/src/code-view.js#showCode`
  - `CMP-code-view/web/src/languages.js#highlightInto`
  - `CMP-code-view/web/src/bridge.js#setCode`
- 依赖：`CMP-document-io`（读文本/编码探测）、`CMP-editor`（token 调色板、查找栏 UI、主题/缩放变量）、`CMP-app-shell`（菜单与打开路由）。
- 冷热属性：冷路径；打开文件与切换语言是低频同步动作，文本框选/滚动不经过桥。
- 尺寸预算：目标 ≤120k token；当前约 700 行（FileSupport ~200 + 控制器分支 ~180 + web ~320），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；视觉 `--screenshot out.png samples/code-sample.py`。
- 验证计划：`#kind` 表驱动与未知扩展名；`#set-code` 渲染/退出；`#language-switch` 切换与纯文本；`#code-find` 计数/跳转；`#large-guard` 降级；双端语言清单一致。
- 删除测试：删掉后代码文件没有阅读面，复杂度会散落到 `CMP-editor` 的每个渲染分支与壳的打开判定 → 真边界。

## 公开契约细节

- `#kind` 的不变量：扩展名小写比较，大小写不敏感；未知扩展名返回 `nil`（调用方拒绝装载，不按 Markdown 解析）；`md` 扩展名恒为 `markdown`；语言 id 与 web 语法表同一标识。
- `#set-code` 的不变量：进入后 `#app` 隐藏、`#code-view` 显示；不写脏基线、不发 `changed`；文本按 UTF-8 字符串原样渲染（Prism 只切 span，不改字符）。
- `#language-switch` 的不变量：文件内容与字节不变；选择只影响渲染；`plaintext` 恒无 token；未知 id 回落纯文本。
- `#code-find` 的错误模式：无命中计数 0、不抛错；切语言后重新搜索；关闭查找栏清除选区高亮。
- `#large-guard` 的不变量：阈值判定在 Swift 侧按 UTF-8 字节，web 不自行判断；切换语言不改变降级状态。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#kind` | `--selftest`：「代码视图 语言表覆盖扩展名」「代码视图 未知扩展名不装载」 |
| `#set-code` | `--selftest`：「代码视图 自动语言与高亮」「代码视图 退出代码模式」 |
| `#language-switch` | `--selftest`：「代码视图 切换语言与纯文本」「代码视图 未知语法回落纯文本」 |
| `#code-find` | `--selftest`：「代码视图 查找命中与只读退出」 |
| `#large-guard` | `--selftest`：「代码视图 大文件降级纯文本」 |
| 语言清单双端一致 | `--selftest`：「代码视图 双端语言清单一致」 |
| PDF/打印 | 人工：`--screenshot` + 几何核对 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 代码文件字节 | `CMP-document-io#open`（只读） | 本组件渲染 | 单文档；本组件不写回 |
| 语言表 / 扩展名映射 | `FileSupport` | 本组件、`CMP-drawer`、`CMP-app-shell` 打开面板 | 单一来源 |
| 高亮语言选择 / 大文件标志 | 本组件 | 本组件、状态栏 | 会话级，不持久化 |

## 验证债

- PDF/打印只做人工截图与 DOM 几何核对，未固化为自动断言。
- 真实 GUI 的菜单置灰、窗口标题与状态栏文案靠人工记录（R8）。

## 删除测试

删掉后代码阅读面没有替代归属，复杂度散落到编辑器与壳 → 真边界。
