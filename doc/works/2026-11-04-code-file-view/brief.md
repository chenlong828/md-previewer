---
layer: works
module: global
status: active
updated: 2026-11-04
---

# 工序 brief：代码文件只读查看与高亮语言切换

> 需求卡：[REQ-0009](../../requirements/REQ-0009-code-view.md)；场景：[SCN-0016](../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md)。

## 需求（2026-11-04 用户提出）

在现有 Markdown 所见即所得之外，直接打开常见代码文件：纯源码、只读、语法高亮；支持常见开发语言与 XML；可切换高亮语言。先评估修改量，再实施。

## 背景

- 现有单窗口模型：`DocumentWindowController` 管文件 IO/脏标记/菜单/桥；web 单页有 `#app`（Milkdown）与 `#source-editor`（源码模式）两个面。
- 语言能力已在包里：`@milkdown/plugin-prism` 引入 refractor 主包（62 种语言），`editor.js` 另注册 10 种；token 配色是 `typora.css` 单一真源。
- 扩展名清单当前单一来源 `AppDelegate.markdownExtensions`（打开面板/抽屉/链接拦截/Info.plist 断言）；本工序把它升级为「文件种类 + 语言表」单一来源。
- 2026-11-04 文档树升级五态；本工序是该树上的第一个 P1 功能工序（新增组件 `CMP-code-view`）。

## P1 确认

2026-11-04 用户确认评估结论（「按推荐来」）：

1. **只读查看**（不做编辑、保存、撤销）。
2. 语言切换入口 = **视图 → 高亮语言**子菜单（自动 / 纯文本 / 语言表），状态栏显示当前语言。
3. **不做 Finder「打开方式」关联**（不注册 `Info.plist` 文档类型）。
4. 首版范围 = 自动语言 + 手动切换 + 查找 + PDF/打印 + 大文件降级 + 6 个入口面；不含行号、编辑、HTML 导出、折叠/minimap。

结构决策（随上述确认）：新增组件 `CMP-code-view`，承载「文件种类/语言表 + 只读代码面」；否决「并入 `CMP-editor`」（其编辑面已 1.7k 行且代码面不走 ProseMirror，混入会让「内容面」契约含糊）。回退成本仅为组件卡与文档归属，代码不变。评审记录见 `review.md`。

## 范围

- 新增 `FileSupport`（`DocumentKind`、语言表、`UTType`、可打开判定）并替换 `AppDelegate.markdownExtensions` 的四处引用。
- `openDocument` 按 kind 分派；代码文档只读装载、状态栏、菜单置灰、右键菜单、PDF 内容面、外部变更重载、图片/资源清理守卫。
- web 新增 `#code-view` 面、`languages.js`（refractor 注册与 hast→DOM）、`code-view.js`（渲染/切换/查找/降级）、桥 op、CSS。
- 视图 → 高亮语言子菜单与勾选同步；`EditorCommands` 增「代码文档可用」字段。
- 抽屉过滤、文档内链接拦截、打开面板类型跟进。
- selftest 新增断言；README/architecture/组件规格/roadmap 同步。

## 非目标

- 不改 Milkdown/ProseMirror 版本与现有 Markdown 管线；不改桥既有 op 语义。
- 不做代码编辑、行号、折叠、LSP、HTML 导出、Finder 关联。
- 不做文件名（无扩展名）识别，如 `Dockerfile`/`Makefile`（记为边界）。
- 不改抽屉/多窗口/图片/导出组件的既有行为，除过滤与禁用项。

## 关键契约（桥 v1 增量，向后兼容）

| 方向 | 名称 | 入参 | 语义 |
|---|---|---|---|
| Swift→JS | `setCode(text, opts)` | `language`、`allowHighlight` | 进入代码视图并渲染；不产生 `changed` |
| Swift→JS | `setCodeLanguage(id)` | `auto` 由 Swift 解析后再传实际 id；`plaintext` 或语言 id | 只重绘，不写文件 |
| Swift→JS | `isCodeMode()` | — | 当前是否代码视图 |
| Swift→JS | `codeInfo()` | — | 自检/诊断：语言、行数、token 数、是否纯文本 |
| 不变式 | `setMarkdown` | — | 必须退出代码视图（切回 md/目录模式不残留） |
| 不变式 | 代码文档 | — | 不发 `changed`；保存/格式/源码模式/插入图片/HTML 导出不可用 |

## 验收标准

1. `--selftest` 新增断言全绿，既有断言零回归：`代码视图 语言表覆盖扩展名`、`未知扩展名不装载`、`自动语言与高亮`、`切换语言与纯文本`、`未知语法回落纯文本`、`大文件降级纯文本`、`查找命中与只读退出`、`退出代码模式`、`双端语言清单一致`。
2. `--screenshot out.png samples/code-sample.py` 得到代码视图截图：高亮、状态栏「只读 · Python」、无 `#app`。
3. 真实 GUI 人工核对：⌘O 打开 `.py`/`.xml`、视图菜单切换语言与纯文本、格式/保存/源码模式/HTML 导出置灰、⌘E PDF 内容完整、⌘F 查找可用、抽屉列出代码文件、拖放/最近文件/链接打开。
4. 文档：REQ/SCN/组件规格/architecture/README/roadmap 与实现一致；`review.md` 给出四档裁决。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-2026-11-04-01 | design | CMP-code-view | done | 本 brief、`arch-design-spec`、`doc-layout-spec`、`REQ-0009` |
| T-2026-11-04-02 | change | CMP-code-view（Swift） | done | `FileSupport.swift`、`DocumentWindowController.swift` 打开/菜单/导出、`Util.swift` |
| T-2026-11-04-03 | change | CMP-code-view（web） | done | `languages.js`、`code-view.js`、`bridge.js`、`find-bar.js`、`typora.css`、`index.html` |
| T-2026-11-04-04 | change | CMP-app-shell / document-io / editor / drawer / export | done | `AppDelegate.swift`、`EditorCommands.swift`、`EditorWebView.swift`、`DirectoryTree.swift`、`export.js` |
| T-2026-11-04-05 | verify | CMP-code-view | in_progress | `Selftest.swift`、`--screenshot`、`--drawer-test` |
| T-2026-11-04-06 | change | docs | done | `architecture.md`、组件规格、README、`roadmap.md` |

## 装载清单

- `.agents/skills/arch-design-spec/SKILL.md`
- `.agents/skills/design-before-coding/SKILL.md`
- `.agents/skills/req-scenario-spec/SKILL.md`
- `.agents/skills/dev-execution-spec/SKILL.md`
- `.agents/skills/doc-layout-spec/SKILL.md`
- `doc/design/architecture.md` §2、§3
- `doc/design/components/CMP-document-io/spec.md`、`CMP-editor/spec.md`、`CMP-app-shell/spec.md`
- `Sources/MDPreview/DocumentWindowController.swift`、`AppDelegate.swift`、`EditorCommands.swift`、`Selftest.swift`
- `web/src/editor.js`、`bridge.js`、`find-bar.js`、`typora.css`

## 开放问题与边界

- PDF/打印仅人工验证（与既有 `CMP-export` 同口径）。
- 无扩展名代码文件（`Dockerfile`/`Makefile`）不识别；如需支持，另开需求（文件名映射）。
- 512 KB 阈值是首版经验值；如实际使用频繁触发，再评估异步分块高亮。
