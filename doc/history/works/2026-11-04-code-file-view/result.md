---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 工序 result：代码文件只读查看与高亮语言切换

> 需求：[REQ-0009](../../../requirements/REQ-0009-code-view.md)；场景：[SCN-0016](../../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md)；brief：[brief.md](brief.md)。

## 1. 结论

实现完成，自动化验证全绿：**代码文件以只读高亮源码打开**，语言按扩展名自动推断，可从「视图 → 高亮语言」切换（自动/纯文本/44 种语言），状态栏显示「只读 · 语言」；⌘F 查找、⌘E PDF、⌘P 打印可用；保存/格式/源码模式/插入图片/HTML 导出在代码文档下禁用；超过 512 KB 降级纯文本。

新增组件 `CMP-code-view`（含 `FileSupport` 种类判定单一来源），`#code-view` 作为与 `#app`/`#source-editor` 并列的第三个内容面，**代码从未进入 ProseMirror**。

状态：**通过**。2026-11-04 完成自动化验证与用户人工核对（回复「没有问题」）；
四档裁决与人工确认记录见 [review.md](review.md)。

## 2. 交付内容

### Swift（`Sources/MDPreview/`）

| 文件 | 作用 |
|---|---|
| [FileSupport.swift](../../../../Sources/MDPreview/FileSupport.swift) | `DocumentKind`（markdown/code）、44 种语言表、`kind(for:)`、`isOpenable`、`markdownUTTypes`/`openableUTTypes`（`conformingTo: .sourceCode` 构造，避开 `ts → mpeg-ts` 误判） |
| [DocumentWindowController.swift](../../../../Sources/MDPreview/DocumentWindowController.swift) | `openDocument` 按 kind 分派；`injectCode` 只读装载与大文件阈值；`refreshCodeStats`；语言切换与状态栏；代码文档的保存/图片/清理/源码模式/HTML 导出守卫；PDF 内容面 `#code-view`；右键菜单只读子集；`validateMenuItem` 的 `availableInCode` 门禁 |
| [AppDelegate.swift](../../../../Sources/MDPreview/AppDelegate.swift) | 移除本地扩展名常量（委托 `FileSupport`）；「视图 → 高亮语言」子菜单与 `menuNeedsUpdate` 勾选同步；打开面板类型 `FileSupport.openableUTTypes` |
| [EditorCommands.swift](../../../../Sources/MDPreview/EditorCommands.swift) | `availableInCode`（默认 false，仅拷贝/全选/查找为 true） |
| [EditorWebView.swift](../../../../Sources/MDPreview/EditorWebView.swift) | 文档内链接拦截改用 `FileSupport.isOpenable`（代码文件在应用内打开） |
| [DirectoryTree.swift](../../../../Sources/MDPreview/DirectoryTree.swift) | 抽屉过滤改用 `FileSupport.isOpenable` |
| [Selftest.swift](../../../../Sources/MDPreview/Selftest.swift) | 新增 11 条断言（见 §3）与 `assertFileSupport`；抽屉扫描用例加入 `main.py` |

### Web（`web/src/`）

| 文件 | 作用 |
|---|---|
| [languages.js](../../../../web/src/languages.js) | refractor 语法注册单一来源（common 62 种 + 14 个额外模块）、`hasLanguage`、`highlightInto`（hast→DOM，不拼 innerHTML） |
| [code-view.js](../../../../web/src/code-view.js) | `showCode/hideCode/setCodeLanguage`、渲染（含纯文本降级）、`codeInfo`、代码内查找（文本 Range 选区 + 命中计数） |
| [bridge.js](../../../../web/src/bridge.js) | `setCode`/`setCodeLanguage`/`isCodeMode`/`codeInfo`/`hasLanguages`；`setMarkdown` 退出代码视图；`toggleSource` 在代码视图 no-op；`focus`/`findInfo` 分支 |
| [find-bar.js](../../../../web/src/find-bar.js) | 查找栏在代码视图下走 `findInCode`，关闭时清除选区 |
| [editor.js](../../../../web/src/editor.js) | 围栏代码块改为调用 `ensureLanguages()`（与代码视图共用注册表） |
| [typora.css](../../../../web/src/typora.css) | `#code-view` 容器样式（与 `#app` 同宽/同缩放、覆盖 `pre/code` 全局样式）与 `body.code-mode` 显隐；打印规则 |
| [index.html](../../../../web/src/index.html) | `<pre id="code-view" tabindex="-1"><code></code></pre>` |

### 文档与样本

- [architecture.md §2.7](../../../design/architecture.md)（代码文档只读面、单源判定、不变量、边界）、§3 桥增量。
- [CMP-code-view/spec.md](../../../design/components/CMP-code-view/spec.md)；`CMP-app-shell`/`CMP-document-io`/`CMP-editor`/`CMP-drawer`/`CMP-export`/`CMP-image` 同步。
- [REQ-0009](../../../requirements/REQ-0009-code-view.md)、[SCN-0016](../../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md)、`doc/README.md`、`plan/roadmap.md`、根 `README.md`。
- [samples/code-sample.py](../../../../samples/code-sample.py)：人工验证样本。

## 3. 验证证据

### 自动化（全绿）

```
./build.sh debug
./.build/debug/MDPreview --selftest     # 117 PASS / 0 FAIL（新增 11 条）
```

新增断言：

- `代码视图 自动语言与高亮`（`#code-view` 显现、`#app` display:none、token≥3、`language-swift`、文本逐字不变）
- `代码视图 切换语言与纯文本`（python 重绘、plaintext 无 token、文本不变）
- `代码视图 未知语法回落纯文本`
- `代码视图 查找命中与只读退出`（`1/2 → 2/2 → 1/2`、选区落在 `#code-view` 内）
- `代码视图 大文件降级纯文本`（`allowHighlight:false` 后切语言仍无 token）
- `代码视图 双端语言清单一致(44 种)`
- `代码视图 退出代码模式`（`setMarkdown` 后 `#app` 恢复）
- `代码视图 语言表覆盖扩展名(10 项)`、`未知扩展名不装载`、`Markdown 扩展名恒走 Markdown`、`语言 id 唯一且类型可构造(74 个 UTType)`

### 集成（同一 `openDocument` 入口）

```
./.build/debug/MDPreview --screenshot /tmp/verify-code-view.png samples/code-sample.py
```

- `SCREENSHOT saved`，截图可见完整 Python 高亮、无 Markdown 编辑器面、无行号；文本/缩进/空行逐字保留。
- 另核对 XML 高亮与 782 KB 文件纯文本降级（`SCREENSHOT saved`，无 token 颜色）。

### 人工核对（2026-11-04，用户）

用户按交付清单核对后回复「没有问题」，覆盖：视图菜单语言切换/置灰、状态栏「只读 · 语言」、
⌘F、⌘E PDF、拖入/最近文件/文档内链接打开代码文件、深色主题下的代码配色。
真实 GUI 交互时序不在无头环境覆盖范围（`plan/risks.md` R8），本条为其人工替身。

### 回归（既有组件）

```
--drawer-test  --dir=/tmp/mdp-drawer-deep/level1/level2 --fileA=.../a.md --fileB=.../b.md   # 全 PASS（含 Home 置灰）
--multiwindow-test --fileA=.../a.md --fileB=.../b.md                                        # 全 PASS（含表格行列）
```

> 两次 fixture 注记：`--drawer-test` 的 Home 用例以「锚点父级链长度 = 3」为信号；`--dir` 选 `/tmp/xxx`（同样 3 段）会让轮询提前结束，须用更深目录（本次 `level1/level2`）。`--multiwindow-test` 的表格用例要求样本文件含表格，空 `# a` 文档会失败。二者均为既有测试用例对 fixture 的隐含要求，非本次实现回归。

**裁决摘要**：blocker 0 / decision 5（已落 CMP 契约、architecture §2.7 与断言）/ hold 2（无扩展名文件、512 KB 阈值，均记为边界/观察项，未进本次 diff）。

## 4. 关键决策与偏差

1. **独立只读面，而非塞入 Markdown 围栏块**：避免「代码被误保存成 md」与围栏转义改字符；代码永不进 ProseMirror（理由与失效条件见 architecture §2.7）。
2. **新增组件 `CMP-code-view`**（P1 结构决策）：承载「种类判定 + 语言表 + 只读代码面」；回退到并入 `CMP-editor` 只需改组件卡与文档归属，代码不动。用户以「按推荐来」批准模块清单。
3. **语言表以 Swift 为唯一产品来源、web 为语法注册表**：selftest 双端一致断言守门；`auto` 由 Swift 解析后再传给 web（web 只认具体 id 或 `plaintext`）。
4. **代码查找用 Range 选区，不复用 ProseMirror 查找插件**：不重建 DOM，不打断 token 结构；命中计数/循环跳转与查找栏 UI 复用。
5. **大文件阈值 512 KB（UTF-8 字节）**：Swift 判定并传 `allowHighlight:false`，web 不自行判断；语言切换不改变降级状态。
6. **无新增依赖**：复用 `refractor`（已在包内）与现有 token 调色板；`prismjs` 未被引入。
7. **未知扩展名拒绝装载**：不再走「读失败」路径，直接弹「不支持的文件类型」，避免代码被当成 Markdown 渲染。

偏差：无（实现与 brief/场景设计一致）。

## 5. 收口检查

- [x] 需求/场景/组件/架构/README/roadmap 与实现一致
- [x] 新代码有 3+1 自动化断言，红→绿不再出现（`assertFileSupport` 的反例 + web 未知语法）
- [x] 既有 selftest/drawer/multiwindow 零回归
- [x] 真实 GUI 人工核对：⌘O/拖放/最近/文档链接打开代码文件；菜单置灰；语言切换勾选；状态栏；⌘E PDF；深色主题；抽屉含代码文件（2026-11-04 用户确认「没有问题」）
- [x] 用户确认「通过」（2026-11-04）
- [x] 归档到 `history/works/`（2026-11-04，frontmatter 转 frozen）

## 6. 遗留与验证债

- 代码文档 PDF/打印只做 DOM 几何核对与人工截图（与 `CMP-export` 既有口径一致），无自动断言；2026-11-04 人工核对通过。
- 真实 GUI 的菜单勾选/置灰、拖放与最近文件的交互时序（R8：无头环境不覆盖）已由 2026-11-04 人工核对确认，仍无自动化入口。
- 深色主题下 `#code-view` 依赖共享 token 调色板，selftest 只核对调色板类色值（浅/深）而不核对代码视图实测像素；2026-11-04 人工确认视觉正常。
- 无扩展名文件（`Dockerfile`/`Makefile`）不识别；如需要另开需求（文件名映射），本次以 README 边界承接。

## 7. 结论落点表

| 活结论 | 落点 |
|---|---|
| 代码文档只读面与 `#code-view` 显隐/缩放/打印口径 | `architecture.md` §2.7 |
| 种类判定、44 语言表、UTType 构造、加载上限 | `CMP-code-view` spec + `FileSupport.swift` |
| 代码文档无脏/无保存/外部变更保留语言 | `CMP-document-io` spec `#code-readonly` |
| 高亮语言菜单、勾选同步、`availableInCode` 门禁 | `CMP-app-shell` spec `#highlight-language-menu` |
| 代码查找复用查找栏、实现对 token 结构无侵入 | `CMP-code-view` spec `#code-find` + `CMP-editor` spec `#find` |
| PDF/打印内容面选择 | `CMP-export` spec `#pdf`/`#print` |
| 抽屉/链接过滤单一来源 | `CMP-drawer` spec `#scan-level` + `CMP-editor` 依赖项 |
| 边界（无扩展名/512 KB/无 HTML 导出/无行号） | 根 `README.md` 已知边界 + REQ-0009 非目标 |
