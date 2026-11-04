---
layer: works
module: global
status: active
updated: 2026-11-04
---

# 评审：代码文件只读查看（P1）

> 工序：[2026-11-04-code-file-view](brief.md)；需求 [REQ-0009](../../requirements/REQ-0009-code-view.md)；场景 [SCN-0016](../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md)。

- **定级**：P1（新增业务组件 + 文档种类契约扩展 + 6 个入口面）。
- **评审时点**：设计冻结前（2026-11-04，随 brief 确认）；实现后补完整规格走查。
- **结论**：**有条件通过**。条件见 §3 Hold 档（真实 GUI 人工核对与代码文档 PDF 视觉），属非阻塞验证项；用户人工确认后转「通过」。
- **人参与记录**：2026-11-04 用户确认评估结论「按推荐来」，含四项决策（只读 / 视图菜单切换语言 / 不做 Finder 关联 / 首版范围）与模块切分；第二次人工确认（GUI 走查）待完成。

## 1. 四档裁决

### Decision now（已定，冻结后不可逆）

| 决策 | 选择 | 备选与否决理由 | 落点 |
|---|---|---|---|
| 代码如何呈现 | 独立只读面 `#code-view`，代码不进 ProseMirror | 塞入 Markdown 围栏块省 40% 工作量，但只读文件进入可编辑数据模型（⌘S 可写成 md）、大文件解析成本高、围栏转义改字符 | `architecture.md` §2.7 |
| 种类判定归属 | 新组件 `CMP-code-view` 持 `FileSupport`；不并入 `CMP-editor` | 并入后编辑面契约含糊（代码面不走 ProseMirror），且 `CMP-editor` 已 1.7k 行 | `CMP-code-view` spec |
| 代码文档可写性 | 恒只读：无脏基线、无保存、关闭不确认 | 若允许「另存为」需引入新数据模型与二次确认；首版不做 | `CMP-document-io#code-readonly` |
| 语言表真源 | Swift `FileSupport` 为产品清单，web `languages.js` 为语法注册表；`auto` 由 Swift 解析 | web 持产品清单会让打开面板/抽屉/菜单无法判定；双源必漂移 | `CMP-code-view#kind` + selftest 双端一致 |
| Finder 关联 | 不注册 `Info.plist` 文档类型 | 关联后未安装/版本回退时系统会记住旧应用；入口面已够（6 个） | REQ-0009 非目标 |

### Blocker（零）

无。评审中未发现数据丢失、默认行为错误或不可逆路径；代码文档没有任何写盘入口（保存/另存为/HTML 导出在菜单与代码路径双重禁用），图片导入与资源清理在代码文档 no-op。

### Verified sound（查过且确认）

| 区域 | 怎么查 | 结果 |
|---|---|---|
| 打开分派 | 读 `openDocument`；`--screenshot samples/code-sample.py` 端到端 | 代码走 `injectCode`，`#app` 隐藏、`#code-view` 高亮；Markdown 路径未变 |
| 只读守卫 | 读 `save`/`importImage`/`cleanOrphanResources`/`toggleSourceMode`/`validateMenuItem`；`--selftest` 退出代码模式 | 菜单置灰 + 代码路径 guard 双层；代码文档不发 `changed` |
| 大文件降级 | `--selftest`「大文件降级纯文本」；语言切换后 token 仍为 0 | 阈值只在 Swift 判定，切换语言不解除降级 |
| 双端语言表 | `--selftest`「双端语言清单一致(44 种)」 | 44/44 可高亮，无缺口 |
| 抽屉/链接过滤 | 读 `DirectoryTree`/`EditorWebView`；`--selftest` 目录扫描（含 `main.py`） | 代码文件进树、`b.txt` 仍排除；链接指向代码文件走应用内打开 |
| PDF 内容面 | 读 `measureAndCapturePDF`；`--selftest` 既有 PDF 用例 | 代码文档选 `#code-view`，裁切高度取内容高度（`<pre>` 在文档流内） |
| 主题/缩放/打印 | 读 CSS；`--selftest` token 调色板（浅/深）；`--screenshot` | `#code-view` 用同一组 CSS 变量与 `--app-zoom`；`@media print` 复位 padding/zoom |
| 既有回归 | `--selftest` 117 项、`--drawer-test`、`--multiwindow-test` | 全 PASS（fixture 要求见 result §3 注记） |

### Hold（不阻塞本次，转入验证/后续）

| 事项 | 为什么不阻塞 | 去向 |
|---|---|---|
| 真实 GUI 菜单勾选/置灰、拖放/最近/链接打开、深色代码视图观感 | 无头环境不覆盖真实交互时序（R8）；DOM/状态已由 selftest 断言 | 本次人工核对；失败则回退 SCN-0016 状态 |
| 代码文档 PDF/打印视觉 | 几何口径与 Markdown 一致，仅内容面选择不同；无法在无头下确认分页观感 | 人工一次；`CMP-export` 既有验证债同口径 |
| 无扩展名文件（Dockerfile/Makefile） | 不做不影响既有文件；需要文件名映射，超出首版范围 | `plan/open-questions.md` 候选/下一需求 |
| 超 512 KB 的异步分块高亮 | 降级纯文本已保证可用；分块需 worker/增量渲染 | 观察实际触发频率再评估 |

## 2. Breaking change 审查

只问一句：**哪些问题发布后再修就变成 breaking change？**

- `#code-view` 作为第三个内容面的 DOM 契约（`body.code-mode`、`#code-view > code`）一旦发布，外部样式/脚本若依赖会难改 → 已冻结在 `CMP-code-view` spec；首版无外部消费者。
- 桥增量 `setCode/setCodeLanguage/isCodeMode/codeInfo/hasLanguages` 若改变参数形态，属 breaking → 已定「`language` 为解析后的最终 id、`allowHighlight` 默认 true」，并写进 spec 与 selftest。
- 语言 id 与扩展名映射发布后会成为用户预期（最近文件/菜单），增删需按新需求走 → 表已单源化，新增只加一处。

结论：无「发布后再修即 breaking」的未决项；Hold 项均为验证或后续增强。

## 3. 开放问题

- 代码文档是否需要在窗口标题/状态栏标注「只读」以外的更多信息（如文件大小）？首版不加，观察使用。
- 512 KB 是否合适？首版经验值，按实际触发再调（改一个常量 + 一条断言）。
- 是否把代码文件加入「最近文件」的清理策略（与 Markdown 共用列表）？当前共用，无额外策略。

## 4. 反对意见与 owner

- 反对意见（自评）：把代码视图独立成组件会让组件数从 7 增到 8；若后续出现大量「只读文档种类」（如 CSV/日志），应评估「只读查看面」抽象是否合并，而不是继续加组件。
- owner：本次工序执行者；用户为最终确认人。
