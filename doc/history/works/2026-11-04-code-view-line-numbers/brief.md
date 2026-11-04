---
layer: history
module: editing
status: frozen
updated: 2026-11-04
---

# 工序 brief：代码视图行号与按行阅读（P2）

> 需求卡：[REQ-0010](../../../requirements/REQ-0010-code-view-line-numbers.md)；影响场景：[SCN-0016](../../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md)；组件：[CMP-code-view](../../../design/components/CMP-code-view/spec.md)、[CMP-app-shell](../../../design/components/CMP-app-shell/spec.md)；收口：[result](result.md) / [P2 review](review.md)。

## 1. 需求（2026-11-04 用户提出）

代码视图增加行号；同时希望抽屉文件列表除 Markdown 外支持其他语言。第二条经用户确认是误读（「我看错了，没这个问题」），本工序**不触碰抽屉**。行号口径经用户四项全选：静态行号栏、当前行高亮、长行软换行、行号可开关；交付方式为「文档 + 直接实现并验证」。

## 2. 现状与问题

- `#code-view` 当前是 `<pre><code>` 一整块：`render()` 把高亮结果或纯文本直接 append 进 `<code>`，`white-space: pre` + `overflow-x: auto`；没有行结构，也没有行号。
- 代码文档只读，没有光标；「当前行」不能复用编辑器选区。⌘F 的命中偏移目前直接映射到整块 `code` 的文本节点。
- 复制/查找/PDF 都以「原始文本 + 整块 DOM」为前提；引入行结构后必须保持字符、换行、偏移与导出结果不变。
- 行号是阅读偏好，不是文档内容；不能写入文件、不能触发 `changed`、不能产生脏标记。

## 3. 范围

### 做

- 逻辑行 DOM：每条逻辑行一个 `.code-line`，内含行号槽与内容槽；高亮 token 跨行时按行克隆 span，字符不变。
- 静态行号：CSS `::before` 生成行号数字，不进入文本节点；行号宽度按总行数位数自适应。
- 软换行：行内容 `white-space: pre-wrap` + `overflow-wrap: anywhere`；行号对齐逻辑行首，长行不产生横向代码滚动。
- 当前行：点击行、⌘F 命中行、代码视图聚焦时 ↑/↓/Home/End 移动；高亮整行背景；不持久化。
- 行号开关：视图菜单「显示行号」勾选项，全局 UserDefaults 偏好，默认开；切换即时作用于所有已打开代码窗口，新窗口继承。
- 复制/查找保真：行号不进入选中文本；空行复制不丢行；⌘F 偏移仍按原文本计算；PDF/打印包含当前开关下的行号。
- 自动化与截图验证、文档同步。

### 不做

- 抽屉过滤改动（用户已撤回）。
- 代码编辑、折叠、minimap、LSP、行号点击跳转外部编辑器。
- Markdown 围栏代码块行号。
- 逐文件持久化行号开关、行号写入复制文本/HTML 导出。
- 桥协议 v2 迁移、主题/字体/布局重构。

## 4. P2 定级与确认

**定级 P2**：跨组件、兼容性契约增量（`CMP-code-view` 的 `#set-code` 选项/新 `#line-numbers` 契约 + `CMP-app-shell` 菜单入口），不改模块切分、不新增组件、不改数据所有权模型、不进编辑热路径。P2 的人工门是「合并前最终确认」；本次按用户「文档 + 直接实现并验证」执行，2026-11-04 用户确认任务完成，人工门通过，工序收口归档。

**已确认决策（用户 2026-11-04 四项全选）**：静态行号栏、当前行高亮、软换行、可开关。

## 5. 组件级修改方案

### 5.1 组件地图（本次相关）

```
CMP-code-view（代码阅读面）
  web: code-view.js  渲染/行结构/当前行/查找映射/开关
       languages.js  refractor 注册 + hast→DOM（不改语义）
       typora.css    行布局、行号、当前行、软换行、打印
       state.js      行号偏好 + 代码文本真源
       bridge.js     setCode 选项 + setCodeLineNumbers
  Swift: FileSupport（不改）
         DocumentWindowController  injectCode 选项、偏好、菜单动作
CMP-app-shell（菜单入口）
  AppDelegate：视图菜单「显示行号」+ 勾选同步 + 广播所有代码窗口
CMP-document-io / CMP-export：不改契约；PDF 内容面仍是 #code-view
```

### 5.2 DOM 与渲染

```
<pre id="code-view" tabindex="-1">
  <code class="code-lines language-python">
    <span class="code-line" data-line="1">
      <span class="code-line-number" data-line="1" aria-hidden="true"></span>
      <span class="code-line-content"><span class="token ...">…</span>…</span>
    </span>
    …
  </code>
</pre>
```

- 高亮仍先由 refractor 生成完整 hast→DOM，再按 `\n` 拆成逻辑行；跨行 token 在每个行片段里克隆同一 `class`/属性，不按行重新解析（避免多行注释/字符串被截断后误判）。
- 行号用 `.code-line-number::before { content: attr(data-line) }` 生成，**不是文本节点**：`code.textContent` 与复制选择都不含行号。
- 空行（非最后一行）在内容槽放一个 `<br>`，保证浏览器复制序列化保留空行；最后一行若为空则不放，避免复制结果多一个换行。
- 空文件渲染 0 行；文件以 `\n` 结尾时按 `split('\n')` 保留末尾空行，与状态栏「N 行」口径一致。
- 行号宽度：`--code-gutter-digits = max(2, 总行数位数)`；CSS `calc(var(--code-gutter-digits) * 1ch + 18px)`。

### 5.3 软换行与当前行

- `#code-view` 从 `white-space: pre` + `overflow-x: auto` 改为块级行结构；`.code-line-content` 用 `pre-wrap`，长 token `overflow-wrap: anywhere`，无横向代码滚动。
- 行号格与内容格同一 grid 行、`align-items: start`；折行后行号只出现一次，位于该逻辑行第一视觉行。
- 行号列与内容列之间用 `column-gap` + 细边框分隔；空行用 `min-height: calc(1em * var(--code-line-height))` 保持高度（行号关闭时也不能丢空行）。
- 当前行语义：点击行（选区折叠时）、⌘F 命中行、代码视图聚焦时 ↑/↓/Home/End；只加 `.is-current` 样式，不移动文本、不写选区（⌘F 除外）。换文档重置；切换高亮语言/行号开关保留有效行号。

### 5.4 查找与复制

- `findInCode` 仍以 `state.codeText` 计算偏移；新增 `lineMeta`（每行 `start/end` + DOM 引用）把偏移映射到行内容文本节点。
- `focusMatch` 设选区后把命中行设为当前行；无命中不抛错、不丢当前行。
- 选择所有代码时浏览器按块级行插入 `\n`；行号是生成内容不参与选择；空行 `<br>` 保证空行保留。selftest 用 `Range.selectNodeContents` + `Selection.toString()` 断言“选择文本 = 原文”。

### 5.5 偏好与菜单

| 项 | 值 |
|---|---|
| 存储 | `UserDefaults.standard["codeLineNumbersVisible"]` |
| 缺省 | `true`（未写 key 时） |
| 所有权 | `CMP-code-view`（实现于 `DocumentWindowController` 静态入口；`CMP-app-shell` 只读/写入口） |
| 生效范围 | 所有代码窗口即时；新代码窗口经 `setCode` 选项继承 |
| 菜单 | 视图 →「显示行号」，仅代码文档可用，勾选反映偏好 |
| 持久化 | 全局，不写文件、不产生 `changed`、不进入脏基线 |

桥增量（向后兼容）：

| 方向 | 名称 | 入参 | 语义 |
|---|---|---|---|
| Swift→JS | `setCode(text, opts)` | opts 新增 `lineNumbers?: Bool` | 进入代码视图时按偏好渲染；不传则沿用 web 当前偏好 |
| Swift→JS | `setCodeLineNumbers(visible)` | `Bool` | 只切换行号布局，不重绘 token、不写文件；非代码模式返回 false |
| 诊断 | `codeInfo()` | — | 新增 `lineNumbers`、`currentLine` 字段 |

### 5.6 修改点与波及面

| 文件 | 改动 | 不改 |
|---|---|---|
| `web/src/code-view.js` | 行拆分、行号、当前行、查找映射、开关 | 高亮语法注册、命中计数算法 |
| `web/src/state.js` | `codeLineNumbers` 字段 | 其他全局状态 |
| `web/src/bridge.js` | `setCodeLineNumbers`、`setCode` 选项 | 既有 op 语义 |
| `web/src/typora.css` | 行布局/行号/当前行/软换行/打印/变量 | token 调色板 |
| `web/src/index.html` | 无需改（`#code-view > code` 保留） | 其他内容面 |
| `web/src/find-bar.js` | 不改（`findInCode` 签名不变） | — |
| `Sources/MDPreview/DocumentWindowController.swift` | 偏好、injectCode 选项、菜单动作/校验、广播 | 编辑/保存/抽屉/图片路径 |
| `Sources/MDPreview/AppDelegate.swift` | 菜单项、MenuID、刷新勾选、广播 | 打开路由/最近文件 |
| `Sources/MDPreview/Selftest.swift` | 行结构文本重建 + 4 组新断言 | 既有断言语义 |
| `README.md` / `doc/*` | 特性、边界、规格、场景、路线图 | 历史归档件 |

## 6. 走查

1. **正常流程**：打开 `.py` → 读文本 → 判定 512 KB → `setCode(text,{language,allowHighlight,lineNumbers})` → 按行拆高亮 → 行号/软换行/当前行可交互 → ⌘F 命中设当前行 → 复制全部保持原文 → 切换行号开关只改布局。
2. **失败流程**：未知语法 → 纯文本行结构；高亮失败/无 token → 整段纯文本按行拆；空文件 → 0 行不报错；超大文件 → 纯文本 + 行号仍可用；未就绪切换 → 菜单动作 guard，装载后按偏好渲染。
3. **未来扩展**：新增语言只改 `FileSupport` + `languages.js`，行拆分与行号不感知语言；新增只读文档种类若复用 `#code-view`，行号/当前行为自然继承，不需要改菜单。
4. **三条路径分离**：行号是纯展示（主路径），当前行是交互状态（可缺省），开关是偏好（偶发）；查找偏移与复制保真是验证断言，不散落在渲染分支。

## 7. 性能与预算

- 行结构 DOM 随逻辑行数线性增长；512 KB 上限内典型代码文件（约 1–2 万行）预计可接受。极端「单字符行」文件会放大 DOM，作为观察项：若实测卡顿，再评估分块/虚拟化或行数阈值降级，不在本次预付复杂度。
- 切换行号不重建行 DOM、不重新高亮；切换语言重建一次（既有行为）。
- CMP-code-view 预计增加 web ~220 行、Swift ~40 行、测试 ~120 行；仍在 ≤120k token 预算内。

## 8. 测试计划（3 正 1 反 + 配套）

| ID | 角色 | 执行 | 断言 |
|---|---|---|---|
| TC-CODE-005 | R1 | `--selftest` | 行数 = `split('\n')`；逐行拼接 = 原文；行号首项为 1；长行 `scrollWidth <= clientWidth`；`white-space: pre-wrap` |
| TC-CODE-006 | R2 | `--selftest` | 点击第 2 行 → `.is-current` 在第 2 行；⌘F 命中 → 当前行落在命中行 |
| TC-CODE-007 | R3 | `--selftest` | 关闭行号 → class/display/`codeInfo` 一致；选择文本 = 原文（含空行、无行号）；再开恢复 |
| TC-CODE-008 | N1 | `--selftest` | 空文件 → 0 个 `.code-line`、`codeInfo.lineCount=0`、行号开关不抛错 |
| 既有 | R1–N1 | `--selftest` | 自动语言/切换/查找/大文件/双端清单/退出代码模式零回归 |

截图：`--screenshot out.png samples/code-sample.py` 核对行号视觉；另用长行样本核对软换行。
人工（R8）：视图菜单开关/勾选、跨窗口记忆、深色主题、PDF/打印行号、真实鼠标点击当前行；2026-11-04 用户确认任务完成。

## 9. 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-2026-11-04-07 | design | CMP-code-view | done | 本 brief、REQ-0010、SCN-0016、CMP-code-view spec、arch-design-spec |
| T-2026-11-04-08 | change | CMP-code-view（web） | done | `code-view.js`、`state.js`、`bridge.js`、`typora.css`、`index.html` |
| T-2026-11-04-09 | change | CMP-code-view（Swift） | done | `DocumentWindowController.swift`、`AppDelegate.swift` |
| T-2026-11-04-10 | change | CMP-app-shell | done | `AppDelegate.swift`、`DocumentWindowController.swift` 菜单校验 |
| T-2026-11-04-11 | verify | CMP-code-view | done | `Selftest.swift`、`--screenshot`、`--drawer-test`、`--multiwindow-test`；人工项经用户 2026-11-04 确认 |
| T-2026-11-04-12 | change | docs | done | `README.md`、`architecture.md`、CMP 规格、SCN-0016、`doc/README.md`、`roadmap.md` |
| T-2026-11-04-13 | close | 工序 | done | [result.md](result.md)、[review.md](review.md)、场景/需求状态回填、归档 `history/works/` |

## 10. 装载清单（单任务 ≤250k）

- `.agents/skills/arch-design-spec/SKILL.md`、`design-before-coding/SKILL.md`、`req-scenario-spec/SKILL.md`、`doc-layout-spec/SKILL.md`、`dev-execution-spec/SKILL.md`
- `doc/requirements/REQ-0010-code-view-line-numbers.md`
- `doc/design/scenarios/editing/document-lifecycle/view-code-file/scenario.md`
- `doc/design/components/CMP-code-view/spec.md`、`CMP-app-shell/spec.md`
- `doc/design/architecture.md` §2.7、§3
- `web/src/code-view.js`、`state.js`、`bridge.js`、`languages.js`、`typora.css`、`index.html`
- `Sources/MDPreview/DocumentWindowController.swift`（代码视图/菜单段）、`AppDelegate.swift`（菜单段）、`Selftest.swift`（代码视图段）

## 11. 风险与开放问题

- **R-行号复制**：行号若进入文本节点会污染复制/查找；已用生成内容 + selftest 选择断言守门。
- **R-空行复制**：浏览器会丢无内容的块行；已用非末行 `<br>` + 选择断言守门。
- **R-当前行语义**：只读面没有光标；本次定为点击/⌘F/方向键，不跟随滚动，避免阅读时高亮乱跳。真实 GUI 观感经用户 2026-11-04 确认。
- **R-极端行数**：512 KB 单字符行文件 DOM 放大；本次记录观察项，不预置阈值降级。
- **开放**：行号是否也要出现在 Markdown 围栏代码块（非目标，暂不做）；行号开关是否需要快捷键（本次不加，避免占用系统组合）。
