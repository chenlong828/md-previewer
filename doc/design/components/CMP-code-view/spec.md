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
- 负责：文件种类判定与语言表（`FileSupport`）；代码文档的只读装载与状态（无脏、无保存）；`#code-view` 渲染、语言切换、纯文本降级、代码内查找、大文件阈值；逻辑行结构、行号、软换行、当前行高亮与行号显示偏好；状态栏语言/行数文案；向右侧缩略图提供**只读代码行投影**。
- 不负责：Markdown 解析/编辑/保存（`CMP-editor` / `CMP-document-io`）；窗口/菜单骨架（`CMP-app-shell`）；抽屉树与过滤调用（`CMP-drawer` 只调用 `#kind`）；PDF/打印的窗口级实现（`CMP-export` 以 `#code-view` 为内容面）；Markdown 围栏代码块的行号；缩略图绘制/视口/滚动定位（`CMP-minimap`）。
- 内部逻辑：`FileSupport.swift` 维护语言表与 `UTType` 构造；`DocumentWindowController` 的 kind 分支、偏好与菜单门禁；web 实现已迁入内核 core——`kernel/core/languages.js` 负责 refractor 语法注册（与编辑器代码块共用），`kernel/core/code-view.js` 负责行拆/渲染/当前行/查找映射/开关，`kernel/core/ops.js` 把能力暴露为 `setCode`/`setCodeLanguage`/`setCodeLineNumbers`/`codeInfo`/`hasLanguages`；样式复用 `typora.css` 的 token 调色板与行布局变量。
- 拥有的数据：代码文档的内存文本副本（只读投影，不写回）、当前高亮语言选择（会话级，不持久化）、大文件降级标志、逻辑行元数据（由文本派生）、当前行（会话级）、行号显示偏好（`UserDefaults`，全局）。
- 变化轴：受支持语言清单/扩展名映射、高亮引擎与调色板、大文件阈值、语言切换入口、行号开关入口。
- 公开契约（含能力 ID）：
  - `CMP-code-view#kind`：扩展名 → `DocumentKind`；可打开扩展名集合；语言表（id/显示名/扩展名）单一来源。
  - `CMP-code-view#set-code`：`setCode{text, opts}` → `{ok, ...codeInfo}` 进入只读代码视图并渲染；`opts.lineNumbers` 可携带行号偏好；不产生 `changed`；`setMarkdown` 必须退出代码视图（`mode` 状态机保证）。
  - `CMP-code-view#language-switch`：`setCodeLanguage{id}` → `{ok, language}`；`auto` / `plaintext` / 语言 id 三种选择，只重绘不写文件。
  - `CMP-code-view#line-numbers`：`setCodeLineNumbers{visible}` → `{ok, lineNumbers}` 只切换行号布局与偏好，不重绘 token、不写文件；非代码模式 no-op；行号是生成内容，不进入复制文本。
  - `CMP-code-view#line-layout`：每个逻辑行一个块；软换行、行号对齐逻辑行首、空行高度与复制保真；`currentLine` 由点击/⌘F/方向键驱动，仅会话级。
  - `CMP-code-view#code-find`：`findInfo{active,query,count}` 与 `findNext`/`findPrev` 驱动（复用 `CMP-editor#find` 的查找栏）；命中计数与上一处/下一处定位（文本选区），命中行成为当前行，无命中不抛错。
  - `CMP-code-view#large-guard`：超过 512 KB（UTF-8 字节）降级纯文本并在状态栏标注；行号/软换行仍按纯文本行结构工作；`codeInfo` 的 `tokenCount`/`lineCount` 反映当前面。
  - `CMP-code-view#minimap-source`：向 `CMP-minimap` 提供只读行投影 `{root, measure(), scrollTo()}`；一个 `kind:'code'` 块承载逻辑行 `text/top/height/left/width`；不重绘 token、不写文件、不发 `changed`、不 import `CMP-minimap`。
- 入口：
  - `CMP-code-view/Sources/MDPreview/FileSupport.swift#FileSupport`
  - `CMP-code-view/Sources/MDPreview/DocumentWindowController.swift#openDocument`
  - `CMP-code-view/Sources/MDPreview/DocumentWindowController.swift#toggleCodeLineNumbersAction`
  - `CMP-code-view/web/src/kernel/core/code-view.js#showCode`
  - `CMP-code-view/web/src/kernel/core/code-view.js#setCodeLineNumbers`
  - `CMP-code-view/web/src/kernel/core/code-view.js#codeInfo`（`hideCode`/`setCodeLanguage`/`findInCode`）
  - `CMP-code-view/web/src/kernel/core/code-view.js#createCodeMinimapSource`（planned，REQ-0011）
  - `CMP-code-view/web/src/kernel/core/languages.js#highlightInto`（`hasLanguage`/`ensureLanguages`）
  - `CMP-code-view/web/src/kernel/core/ops.js#createOps`（`setCode`/`setCodeLanguage`/`setCodeLineNumbers`/`codeInfo`/`hasLanguages` 五个 op）
- 依赖：`CMP-document-io`（读文本/编码探测）、`CMP-kernel-contract`（op 注册）、`CMP-editor`（token 调色板、查找栏 UI、主题/缩放变量）、`CMP-app-shell`（菜单与打开路由、`setCode` op 调用）；`CMP-minimap` 只通过组合根消费本组件的 `#minimap-source`，不反向 import。
- 冷热属性：冷路径；打开文件与切换语言是低频同步动作，文本框选/滚动不经过桥；行号开关只改布局类，不重绘 token。`#minimap-source` 的 `measure()` 是低频只读投影，由缩略图防抖调用，不进入滚动热路径。
- 尺寸预算：目标 ≤120k token；当前约 900 行（FileSupport ~200 + 控制器与菜单 ~220 + `kernel/core/code-view.js` 406 + `languages.js` 79），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；视觉 `--screenshot out.png samples/code-sample.py`。
- 验证计划：`#kind` 表驱动与未知扩展名；`#set-code` 渲染/退出；`#language-switch` 切换与纯文本；`#line-numbers` 行数/行号/软换行/当前行/开关/复制保真；`#code-find` 计数/跳转/命中行；`#large-guard` 降级；双端语言清单一致。
- 删除测试：删掉后代码文件没有阅读面，复杂度会散落到 `CMP-editor` 的每个渲染分支与壳的打开判定 → 真边界。

## 公开契约细节

- `#kind` 的不变量：扩展名小写比较，大小写不敏感；未知扩展名返回 `nil`（调用方拒绝装载，不按 Markdown 解析）；`md` 扩展名恒为 `markdown`；语言 id 与 web 语法表同一标识。
- `#set-code` 的不变量：进入后 `mode='code'`、`#app`/`#source-editor` 隐藏、`#code-view` 显示；不写脏基线、不发 `changed`；文本按 UTF-8 字符串原样渲染（Prism 只切 span，不改字符）；行结构下逐行文本以 `\n` 拼接后必须等于原文。
- `#language-switch` 的不变量：文件内容与字节不变；选择只影响渲染；`plaintext` 恒无 token；未知 id 回落纯文本；切换后行号/当前行布局不丢。
- `#line-numbers` 的不变量：行号数字用 CSS 生成内容（不进入文本节点）；行数 = `state.codeText ? split('\n').length : 0`；末行空行保留；非末行空行用 `<br>` 保复制；开关默认 true，存 `UserDefaults["codeLineNumbersVisible"]`；开关只改布局类，不重绘 token、不发 `changed`；非代码模式 no-op。
- `#line-layout` 的不变量：每逻辑行一个 `.code-line`；软换行后行号只在逻辑行首出现一次；长 token 断行且不产生横向代码滚动；当前行不持久化，换文档重置，切语言保留有效行号；点击/⌘F/方向键是唯一改变当前行的入口。
- `#code-find` 的错误模式：无命中计数 0、不抛错；偏移始终按原文计算并映射到行块；切语言后重新搜索；关闭查找栏清除选区高亮，但保留当前行。
- `#large-guard` 的不变量：阈值判定在 Swift 侧按 UTF-8 字节，web 不自行判断；切换语言不改变降级状态；降级纯文本仍按行渲染。
- `#minimap-source` 的不变量：只读；`lines` 按逻辑行给出，文本不含行号数字，`top/height` 为文档顶为 0 的视觉 CSS 像素；大文件按投影预算等距采样并保留首尾/视口附近；`scrollTo` 夹取；不修改 DOM/选区/脏基线，不发 `changed`；不 import `CMP-minimap`。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#kind` | `--selftest`：「代码视图 语言表覆盖扩展名」「代码视图 未知扩展名不装载」 |
| `#set-code` | `--selftest`：「代码视图 自动语言与高亮」「代码视图 退出代码模式」 |
| `#language-switch` | `--selftest`：「代码视图 切换语言与纯文本」「代码视图 未知语法回落纯文本」 |
| `#line-numbers` | `--selftest`：「代码视图 行号与软换行」「代码视图 行号开关与复制文本」「代码视图 空文件行号边界」 |
| `#line-layout` | `--selftest`：「代码视图 当前行点击与查找定位」 |
| `#code-find` | `--selftest`：「代码视图 查找命中与只读退出」（含命中行） |
| `#large-guard` | `--selftest`：「代码视图 大文件降级纯文本」 |
| `#minimap-source` | `--selftest`：「缩略图 代码面与开关」：行数/投影有序/无文件写入；源码模式不挂载；截图/人工：真缩略图观感 |
| 语言清单双端一致 | `--selftest`：「代码视图 双端语言清单一致」 |
| PDF/打印 | 人工：`--screenshot` + 几何核对；行号视觉随开关（2026-11-04 用户选择可开关，PDF/打印视觉经用户确认） |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 代码文件字节 | `CMP-document-io#open`（只读） | 本组件渲染 | 单文档；本组件不写回 |
| 语言表 / 扩展名映射 | `FileSupport` | 本组件、`CMP-drawer`、`CMP-app-shell` 打开面板 | 单一来源 |
| 高亮语言选择 / 大文件标志 | 本组件 | 本组件、状态栏 | 会话级，不持久化 |
| 行号显示偏好 | `DocumentWindowController` 静态入口写 `UserDefaults` | 本组件渲染、`CMP-app-shell` 菜单勾选 | 全局，默认 true |
| 当前行 / 行元数据 | 本组件 | 本组件 | 会话级，由文本派生 |
| 缩略图行投影 | 本组件 `#minimap-source`（派生） | `CMP-minimap` | 只读派生；不落盘、不成为第二真源 |

## 验证债

无既有未决验证债；新增 `#minimap-source` 为 2026-11-04 planned 契约（REQ-0011），实现与断言待 P1 工序完成。PDF/打印视觉与真实 GUI 的菜单置灰/「显示行号」勾选、窗口标题/状态栏文案经 2026-11-04 用户确认；极端单字符行文件的 DOM 放大保留为观察项，512 KB 上限作为兜底，卡顿再评估分块/阈值降级。

## 删除测试

删掉后代码阅读面没有替代归属，复杂度散落到编辑器与壳 → 真边界。
