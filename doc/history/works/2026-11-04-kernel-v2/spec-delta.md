---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 规格增量：editor-kernel v2（2026-10-21 存档规格的复核与增量）

> 本文件是工序 [brief.md](brief.md) 的 P1 规格件。**增量**指相对存档规格
> [2026-10-21-editor-kernel-spec.md](../../history/decisions/2026-10-21-editor-kernel-spec.md) 的差异；
> 存档规格仍是模块地图、不变量、决策 D1–D5 的基线，本文件不回抄其正文（一处一事）。
> 收口时本文件的有效结论并入 `design/`，本目录归档。

## 1. 复核结论（2026-11-04，对照现行代码）

存档规格写于 2026-10-21；此后 2026-11-04 落了代码文件只读视图（`CMP-code-view`，新增 6 个桥方法）。
逐条复核结论：

| 存档条款 | 结论 | 说明 |
|---|---|---|
| D1 各平台原生壳 + 共享 JS 内核 | **仍有效** | 本次按此执行；Windows 壳后续立项。 |
| D2 markdown 文本语义收进内核 | **仍有效，且是 R9 的收口点** | 现存双头实现已分叉：Swift `ImagePathRewriter`/`referencedLocalImagePaths` vs `web/src/image-view.js`，差在捕获正则、括号/标题拆分顺序、%XX 解码粒度、远程判定宽度、存在性校验。 |
| D3 统一 JSON 消息协议 v2 | **仍有效** | v1 现状：38 个 `window.mdbridge` 方法、30 处 `callJS` 字符串拼接、142 处求值、无版本号、未知 op 静默丢弃。 |
| D4 规格对壳技术中立 | **仍有效** | 本文件不出现 WebView2/GTK 专有假设。 |
| D5 不拆包/不拆仓 | **仍有效** | 内核源码仍在 `web/src/`，单包单仓。 |
| I1 往返一致 / I2 保存口径单一 / I3 磁盘唯一写入口是壳 | **仍有效** | 复核发现两处现存 I2 违例：`stats` 与 `setTheme` 读 `state.lastMarkdown`（旧镜像）而非当前内容，迁移时一并收口（§5 R7/R8）。 |
| §4.2/§4.3 op 表 | **需增量** | 缺代码视图 6 个 op；`getZoom`/`isSourceMode`/`isCodeMode` 合并为 `getState`；`onImageImported` 退化为 `importImage` 的响应；新增 `print`/`getContentSize`/`getSaveMarkdown`/`getResourceRefs`。 |
| §4.5 传输面与握手 | **仍有效** | 采纳；补「壳侧协议客户端」作为可复用件（Windows 参照实现）。 |
| §4.6 v1→v2 迁移 4 步 | **仍有效** | 采纳；第 2 步收敛为 39 个 op + 2 个请求 + 7 个通知。 |
| §8 验证计划 | **需增量** | 补 Node 套件分组与环境选型（§6.1）、selftest 改造口径（§6.2）、架构守门（§6.3）。 |
| §9 Q1/Q2/Q4 | **转出** | 属壳工序，转 `plan/open-questions.md`。 |

## 2. 组件切分（P1 结构决策）

### 2.1 候选与裁决

| 候选 | 内容 | 裁决理由 |
|---|---|---|
| **A（采纳）** | 内核 = 3 个技术边界组件（transport / contract / semantics）+ 1 个组合模块 core；`CMP-image` 退役、语义入 semantics、落盘与清理执行留壳 | 分层与禁边可用 lint/grep 守门；内核测试面可脱离 WebView（评审四条件之一）；core 内共享 `state` 单例，拆细会产生同层横调 |
| B | 内核单包不分层 | 否决：宿主符号会回流（现状已证明 `state.js` 是唯一 post 出口、`index.html` 三处裸调用），无守门点，R9 类风险无落点 |
| C | 内核拆 5+ 组件（find/tables/stats/code-view/editor 各自成组件） | 否决：这些能力共享同一 `state` 与同一 ProseMirror 实例，拆开即同层横调（禁边），契约宽度无收益 |

`core` 按「模块」处理（带门面、顶层 1 层），不新增 CMP 编号：它无独立对外契约，只有内部模块契约。

### 2.2 归属变更

| 单元 | 归属 | 变更 |
|---|---|---|
| `CMP-kernel-transport`（新，L0） | 内核 | 唯一宿主感知点：`__mdHostChannel` 封装、`__mdKernel.receive` 暴露、jserror 三源钩子安装（迁自 `index.html` 内联脚本） |
| `CMP-kernel-contract`（新，L1 技术边界） | 内核 | 信封构造/校验、op 注册表与分发、id 关联、版本握手、错误码 |
| `CMP-kernel-semantics`（新，L1a） | 内核 | 纯函数：`rewriteForLoad` / `restoreForSave` / `collectResourceRefs` / `nextResourceName` / PathPolicy（posix/win32） |
| core（模块） | 内核 | 现有 `web/src` 除三层外全部迁入；含 `CMP-editor`、`CMP-code-view`、HTML 导出、图片 NodeView |
| `CMP-editor` | 内核 core | 入口由 `bridge.js#window.mdbridge` 改为 `kernel/core/editor.js#createEditor`；对外契约降为模块契约 |
| `CMP-code-view` | 内核 core | 入口 `kernel/core/code-view.js#showCode`；契约同上 |
| `CMP-image` | **退役（拆）** | 判定规则入 semantics；`import`/`cleanup` 执行入 `CMP-app-shell`（`ImageStore`）；`node-view` 入 core。能力 ID `#for-load`/`#for-save`/`#import`/`#cleanup`/`#node-view` 语义保留，归属改写 |
| `CMP-export` | 跨层 | HTML 生成入 core；PDF/打印编排留 `CMP-app-shell`（几何与打印改由 op 提供） |
| `CMP-app-shell` | 壳 | 新增「壳侧协议客户端」`KernelClient`：`send(op, payload, completion)`、响应表、超时、错误上报 |
| `CMP-document-io` / `CMP-drawer` / `CMP-diagnostics` | 壳 | 不变；`document-io` 的路径改写调用点删除（语义在内核） |

`CMP-minimap` 保持 `planned`，v2 落地后按新结构接入（brief §2 决定 3）。

## 3. 契约 diff（v1 → v2）

### 3.1 信封与错误码（采纳存档 §4.1）

```
请求：{"v":2,"op":"<name>","id":"<unique>","payload":{...}}
响应：{"v":2,"id":"<orig>","ok":true,"payload":{...}}
      {"v":2,"id":"<orig>","ok":false,"error":{"code":"<code>","message":"..."}}
通知：{"v":2,"op":"<name>","payload":{...}}            // 无 id、无响应
```

错误码：`unknown_op` / `bad_payload` / `not_ready` / `unsupported_version` / `internal`。
`not_ready` 取代 v1 的静默吞掉（v1 中 ready 前的 `setMarkdown`/`setCode`/命令被无声丢弃）。

### 3.2 host → kernel：39 个 op

与 v1 的 38 个 `window.mdbridge` 方法对照：删除 4（`isCodeMode`/`getZoom`/`isSourceMode`/
`onImageImported`，前三个并入 `getState`，`onImageImported` 变 `importImage` 的响应）、
新增 5（`getSaveMarkdown`/`getState`/`print`/`getContentSize`/`getResourceRefs`）、
其余 33 个语义不变只换形态。`_init` 为内部函数，不进契约。

| 组 | op | payload → 响应 | 相对 v1 |
|---|---|---|---|
| 会话 | `init` | `{markdown, opts:{theme, zoom?, plugins?, title?, baseDir?, pathStyle, protocolVersion}} → {ok, kernelVersion, protocolVersion, ops[]}` | 加 `pathStyle`/`protocolVersion`/`ops[]` |
| | `setMarkdown` | `{md, opts:{baseDir?}, flush?} → {ok}` | `md` 为磁盘原文，改写移入内核 |
| | `getMarkdown` | `{} → {md}` | 渲染态序列化（诊断口径） |
| | `getSaveMarkdown` | `{} → {md}` | **新**：保存口径（含路径还原），迁自 Swift `forSave` |
| | `markClean` | `{} → {ok, baseline?}` | 响应化 |
| | `setBaseDir` / `setTitle` / `setTheme` | `{path}` / `{title}` / `{theme} → {ok}` | 返回 `{ok}` 而非 `true` |
| | `setZoom` | `{scale} → {zoom}` | 响应携带夹取后的有效值（0.5–3） |
| | `getState` | `{} → {sourceMode, codeMode, theme, zoom, title, baseDir, code:{language,lineNumbers,allowHighlight}?}` | **新**：吸收 `getZoom`/`isSourceMode`/`isCodeMode` |
| | `toggleSource` | `{force?} → {sourceMode}` | 响应携带落定值 |
| | `focus` | `{} → {ok}` | — |
| | `focusAt` | `{x, y} → {ok, inTable}` | 坐标仍为 WebView CSS 像素；壳侧转换归壳 |
| 代码 | `setCode` | `{text, opts:{language, allowHighlight, lineNumbers?}} → {ok, ...codeInfo 字段}` | 响应化（v1 返回 boolean） |
| | `setCodeLanguage` | `{id} → {ok, language}` | 同上 |
| | `setCodeLineNumbers` | `{visible} → {ok, lineNumbers}` | 同上 |
| | `codeInfo` | `{} → {mode, language, allowHighlight, textLength, lineCount, tokenCount, lineNumbers, currentLine}` | **字段契约化**（v1 已被自检当契约用） |
| | `hasLanguages` | `{ids[]} → {supported[]}` | 双端语言表一致性守门 |
| 命令 | `undo` / `redo` / `requestStats` | `{} → {ok}` | stats 仍走通知 |
| | `formatCommand` | `{name, payload?} → {ok, applied}` | milkdown 位置参数形态不变 |
| | `tableCommand` | `{name} → {ok, applied}` | — |
| | `insertTable` / `insertMarkdown` / `insertImage` | `{row,col}` / `{md}` / `{src,alt,title} → {ok}` | — |
| 查找 | `openFindBar` / `closeFindBar` / `findNext` / `findPrev` | `{} → {ok}` | — |
| | `findInfo` | `{} → {active, query, count}` | `count=-1` 表未就绪 |
| 输出 | `exportStandaloneHTML` | `{} → {html}` | **改响应携带**：内核内部 `await`，消灭 Promise 跨桥 |
| | `print` | `{} → {ok}` | **新**：内核调 `window.print()`，替掉壳侧 `evaluate("window.print()")` |
| | `getContentSize` | `{} → {width, height}` | **新**：PDF 几何改由 op 提供，替掉壳侧脚本量 `scrollHeight` 轮询 |
| 资源 | `getResourceRefs` | `{} → {refs[]}` | **新**：GC 引用收集迁自 Swift |
| 诊断 | `hasCommands` | `{names[]} → {results:[{name, ok}]}` | — |
| | `debugFocusTable` / `tableInfo` / `testImagePayload` | `{}` / `{}` / `{data}` | 保持诊断档，壳可选择不暴露入口 |

### 3.3 kernel → host：7 个通知 + 2 个请求

通知（无 id）：`boot`、`ready`、`changed{dirty}`、`stats{words,chars}`、`sourceMode{value}`、
`selinfo{inTable}`、`jserror{message, where?, stack?}`。

请求（带 id，壳必须应答）：

| op | payload → 响应 | 说明 |
|---|---|---|
| `resolveResources` | `{refs[], baseDir} → {resources:{ref:{url:string\|null, exists:bool, isImage:bool, paths:string[]}}}` | **新**。装载改写的文件感知点：内核解析候选引用后批量问壳，壳以文件系统为准作答。请求必须自包含（带 `baseDir`，壳不猜当前文档目录，否则未保存/另存场景会误判缺失）；`url`/`exists` 按字面写法（装载改写用），`paths` 给全部存在的候选绝对路径（字面 + 解码，GC 宁多保护用） |
| `importImage` | `{kind:'blob'\|'file', mime?, data?, path?} → {ok, src?, error?}` | 幂等键 = 消息 id；v1 的 `requestId` 即 id，语义不变；`onImageImported` 反向注入取消 |

### 3.4 传输面与握手（采纳存档 §4.5 + 壳侧客户端）

壳必须在内核 bundle 求值前注入：

- `window.__mdHostChannel.post(json)` —— 内核 → 壳；
- `window.__mdKernel.receive(json)` —— 壳 → 内核（v1 的 `window.mdbridge` 方法面退役）。

握手：壳发 `init{protocolVersion: 2}`；内核校验后响应 `{kernelVersion, protocolVersion, ops}`。
版本不匹配 → 内核回 `unsupported_version` 拒绝装载，壳必须**显式报错停用**（禁止错配继续跑）。
壳与内核 bundle 的版本配对由组装脚本校验（`build.sh` 内加一步）。

新增可复用件 **`KernelClient`（壳侧协议客户端，Swift）**：`send(op, payload, id?, completion)`、
响应表（id → completion）、超时、错误码→日志/告警。`DocumentWindowController` 与
`Selftest` 共用它；Windows 壳按同一语义实现（本次交付其伪代码与契约测试）。

### 3.5 页面与内核资产边界（新决策 D6）

`index.html` 随内核资产打包，由壳装进 WebView；壳只负责「注入 channel → 装载页面」，
不复制 DOM 骨架。理由：DOM 结构是内核渲染契约的一部分（`#app`/`#source-editor`/`#code-view`/
`#find-bar`），放进壳会让每个壳重复一份 DOM 并产生结构性漂移；Windows 壳因此只需
一个 WebView 容器 + 注入 channel。

页面入口拆分：`web/src/page.js`（`import './typora.css'; import './kernel/main.js'`）是唯一
带 CSS 的入口；`kernel/main.js` 及以下不 import 任何 CSS，可被 Node 直接 import（内核测试面
不依赖构建产物）。`index.html` 的三处内联错误钩子移入 transport。

## 4. 内核内部结构、装配与守门

### 4.1 目录与组合根

```
web/src/
  page.js                     # 页面入口：import './typora.css'; import './kernel/main.js'
  kernel/
    main.js                   # 组合根：装配 transport → 建 contract → 发 boot
    transport/channel.js      # 宿主感知唯一豁免点
    contract/envelope.js      # 信封构造/校验
    contract/registry.js      # op 注册表、分发、id 关联、握手、错误码
    contract/ops.js           # op 名与 payload 形状的单一清单（自检与壳侧对齐用）
    semantics/markdown.js     # applyForLoad / restoreForSave / collectResourceRefs / nextResourceName
    semantics/paths.js        # PathPolicy：fileUrlFromPath / urlToPath / normalizePath（posix|win32）
    core/*.js                 # 现有 15 个模块迁入（state/editor/code-view/find/...）
```

### 4.2 禁边与守门（脚本，不靠自律）

| 禁边 | 守门手段 |
|---|---|
| core / contract / semantics 出现宿主符号（`window.webkit`、`messageHandlers`、`__mdHostChannel`、`chrome.webview`） | `web/check-kernel.mjs`：仅 `kernel/transport/` 与 `page.js` 豁免，其余命中即红 |
| semantics import core/contract | 同脚本：`kernel/semantics/**` 的 import 白名单 |
| core 出现 `wcwidth` 类 DOM 全局以外的宿主对象 | 同脚本：`kernel/core/**` 禁 `window.webkit`/`document.title` 以外的宿主面（`document` 允许，属 DOM） |
| 契约 payload 出现第三方类型 | 契约测试断言：payload 结构仅 JSON 原语（递归检查） |
| 内核层引入第三方依赖 | 仅 `kernel/core/` 允许（Milkdown/refractor 等引擎本身）；transport/contract/semantics 必须零依赖 |
| 壳解析/改写 markdown | Swift 侧 grep 守门：`Sources/MDPreview` 禁 `imagePattern`/`forLoad`/`forSave` 类残留（`Util.swift` 对应符号删除后自然消失，脚本断言不存在） |

`web/check-kernel.mjs` 进 `build.sh` 与 `npm run lint` 链路，失败即中断构建。

### 4.3 模式状态机（治理 R16）

core `state` 增加显式 `mode: 'markdown' | 'code'`，`sourceMode` 仅在 `mode==='markdown'` 时有效：

- 进入代码文档：`mode='code'`、`sourceMode=false`（`setCode` 单点）；
- 返回 Markdown：`mode='markdown'`（`setMarkdown` 单点）；
- 两者互斥由状态迁移函数保证，不再依赖「调用顺序」；对 v1 语义是等价重写（行为断言守门）。

## 5. 迁移风险处置（16 条盘点结论 → v2 落点）

| # | 现状耦合 | 处置 | 落点 |
|---|---|---|---|
| R1 | `evaluateJavaScript` 返回值被当同步用（取正文/状态/几何） | **消灭**：取值改 op 响应；壳侧 `KernelClient` 用 completion 表 + RunLoop 等待 | T5 |
| R2 | Promise 跨桥（`init`/`exportStandaloneHTML`） | **消灭**：`exportStandaloneHTML` 改响应携带 `{html}`；`init` 握手响应化；自检的 `window.__exportedHTML` 技巧废除 | T4/T5 |
| R3 | 对象返回值形状不稳（`JSON.stringify` 再解析） | **消灭**：统一响应 payload 为 JSON 对象，`KernelClient` 直接取字典 | T5 |
| R4 | JSArgs 只转义 U+2028/2029，其余靠插值 | **消灭**：payload 走 `JSONSerialization` 后作为信封字符串传入，不拼 JS 源码 | T5 |
| R5 | ready 前调用被静默吞掉 | **消灭**：`not_ready` 错误码 + 壳侧显式处理 | T2/T5 |
| R6 | 装载期 `pendingOpen` 单槽（新打开覆盖旧请求） | **保留**（行为不变，跨平台时序一致性优先）；记入 `plan/open-questions.md` 作后续改进 | 文档 |
| R7 | `sourceModeCached`/`inTableCached` 双真相 | **降级**：壳侧只镜像通知值，不再用返回值自算；`getState` 为唯一查询口 | T5 |
| R8 | `setTheme` 用陈旧 `state.lastMarkdown` 重建 | **修正**：改为当前内容（`currentMarkdown()`）；新增断言「切主题后正文/脏标记不变」 | T4 |
| R9 | `stats` 读 `lastMarkdown` 而非当前内容（I2 违例） | **修正**：统一走 `currentMarkdown()`；源码模式与代码模式口径加断言 | T4 |
| R10 | `state.pendingBaseline` 未声明死字段 | **删除** | T4 |
| R11 | `window.print()` 不在协议内 | **op 化**：`print` | T4/T5 |
| R12 | `index.html` 三处裸 `postMessage` | **消灭**：jserror 三源钩子移入 transport | T2 |
| R13 | 无协议版本、未知 op 静默丢弃 | **消灭**：握手 + `unknown_op` 显式错误 | T2 |
| R14 | `jserror` 只 `print` 不进 os_log | **统一**：壳侧错误上报走同一日志通道（`os_log`） | T5 |
| R15 | selftest 依赖产品桥面与内部字段 | **收口**：动作走 `send(op)`；断言读 DOM 或 `codeInfo` 契约字段；`window.__listIndentTab` 改为诊断 op 或 `codeInfo` 扩展字段（T4 定，偏向后者的最小面：新增 `listIndent` 诊断字段） | T4/T6 |
| R16 | 代码视图/Markdown 互斥靠隐式调用顺序 | **消灭**：`mode` 状态机（§4.3） | T4 |

## 6. 验证计划

### 6.1 Node 契约套件（内核可移植性的验收定义：不依赖任何 WebView 全绿）

| 组 | 环境 | 覆盖 | 通过判据 |
|---|---|---|---|
| A contract | 纯 Node，零 DOM | 39 op 全量：成功 / 坏 payload / `unknown_op` / `not_ready` / 握手拒绝 / id 回显 / 通知无响应 / 五个错误码 | `node --test` 全绿 |
| B semantics | 纯 Node，零 DOM | `applyForLoad`/`restoreForSave`/`collectResourceRefs`/`nextResourceName`/PathPolicy 双风格；黄金夹具（15 用例：空格/括号/尖括号/标题/围栏/引用式/`%XX` 双口径/中文/一行多图）+ 纯函数守门 | 与 Swift 旧实现**逐字节对拍**一致（2026-11-04 已达成：45 项对拍 + 5 项规则断言全绿；黄金件 `web/test/fixtures/semantics-golden.json`，生成器 `tools/semantics-dump/`，收口时随 Swift 实现一起删除） |
| C core | 需 DOM（Milkdown/ProseMirror） | 命令注册表 ↔ op 表全等；源码模式保存口径（I2）；查找/统计口径；模式状态机；`changed` 防抖过期过滤 | 全绿；环境选型按存档 Q3 冒烟定（jsdom vs happy-dom，判据 ProseMirror 可运行 + 速度），结论回填 §6.1 |
| D 守门 | 纯 Node | §4.2 禁边脚本 `check-kernel.mjs` + payload JSON 原语递归断言 | 命中即红 |

运行：`cd web && npm test`（`node --test test/`）。CI 门禁：`node --test` + `check-kernel.mjs` +
`eslint src` + macOS selftest（壳冒烟基准）。

**FakeShell**（`web/test/support/fake-shell.js`）是套件的宿主替身，同时就是 Windows 壳的
参照实现：注入 `__mdHostChannel`、调 `__mdKernel.receive`、应答 `resolveResources`/`importImage`、
按 id 回填响应。其接口文档进 `design/components/CMP-kernel-contract/spec.md`（收口时）。

### 6.2 macOS selftest 改造

- 驱动方式不变：真实 WKWebView + 真实壳（`EditorWebView` + `KernelClient`），不引入模拟层。
- 动作断言改 `send(op, payload)`；取值断言改读 DOM/几何，或读 `codeInfo` 契约字段。
- `evaluate()` 保留给 DOM 断言与诊断探针（见 §7 G1）；产品路径不再用它取数。
- 断言基线：现有 121 项目标不减；新增 v2 断言（握手拒绝、`not_ready`、模式互斥、主题/统计口径、
  `exportStandaloneHTML` 响应携带、`getContentSize`）。

### 6.3 架构守门与人工点验（R8 风险）

- 脚本守门：§4.2 全部项进构建；`grep` 断言 `window.mdbridge`、`messageHandlers.mdbridge`、
  `JSArgs`、`ImagePathRewriter` 在源码中不存在。
- 人工点验清单（交互类无法自动化，R8）：真实 ⌘V 粘贴截图、拖放图片、右键表格菜单、
  抽屉打开/切目录、代码文档打印与 PDF、主题切换、Tab 列表缩进。
- 收口记录：`result.md` 写入命令、输出摘要与人工核对结论；`review.md` 四档裁决。

## 7. 待用户确认项（第二次门）

| ID | 决策 | 推荐 | 备选与代价 |
|---|---|---|---|
| **G1** | 诊断/截图/自检用的**任意 JS 求值**通道如何处置 | 产品路径全部 op 化（`print`/`getContentSize`/`exportStandaloneHTML`），壳侧保留 `evaluateForDiagnostics` **仅**用于自检断言与截图钩子，不进契约、Windows 不实现，脚本限定只出现在诊断文件中 | ①全部 op 化（新增 `debug.*` op）：壳零自由求值，但 macOS 专用截图钩子污染契约；②彻底禁止：截图钩子（`MDP_EDIT_IMAGE`）无法实现，自检改造量最大 |
| **G2** | 内核组件切分（§2.1） | 方案 A：transport / contract / semantics 三个新组件 + core 组合模块；`CMP-image` 退役拆分 | 方案 B 单包（无守门点，宿主符号回流）；方案 C 细拆（共享 ProseMirror 与 state，必然同层横调） |

确认后编码（P1 门）。未确认前只动文档。

**确认记录（2026-11-04，第二次门）**：

- G1 → **产品路径全 op 化 + 诊断求值限定**：`print`/`getContentSize`/`exportStandaloneHTML` 进契约；
  截图钩子与自检断言保留壳侧 `evaluateForDiagnostics`，不进契约、Windows 不实现；守门脚本限定其
  只出现在诊断类文件（`Selftest.swift`、`Screenshot.swift`、`main.swift` 的 e2e 分支）。
- G2 → **方案 A**：transport / contract / semantics 三个新组件 + core 组合模块；`CMP-image`
  退役拆分；禁边脚本 `web/check-kernel.mjs` 进构建。
- 编码（T2）自 2026-11-04 起解禁。

## 8. 顺序与工作量

| 任务 | 组件 | 工作量 | 前置 |
|---|---|---|---|
| T2 contract + transport + FakeShell + 套件骨架 | CMP-kernel-contract / transport | M | T1 确认 |
| T3 semantics 移植 + 对拍 | CMP-kernel-semantics | M–L（对拍占大头） | T2 |
| T4 core 迁移 + bridge 拆解 + 模式机 | core | L | T3 |
| T5 Swift 壳（KernelClient、30 处收敛、PDF/print/导出） | CMP-app-shell | L（可与 T4 并行） | T2 |
| T6 Node + selftest + 人工点验 | — | M | T4 + T5 |
| T7 文档收口与规格升格 | — | S–M | T6 |

## 9. 变更记录

- 2026-11-04：建档。增量相对 2026-10-21 存档规格：op 表 +5/−4、`getState` 合并、`print`/`getContentSize`
  入契约（替壳侧脚本）、`exportStandaloneHTML` 改响应携带、`CMP-image` 退役拆分、页面资产边界（D6）、
  模式状态机、16 条风险逐条处置、Node 套件分组与守门脚本。





**Q3 结论（2026-11-04）**：选 `jsdom`（30.1.3）。实测 Milkdown/ProseMirror 在 jsdom 内可完整建编辑器，装载/序列化/插图/通知全跑通（core 组 10 项），无需 happy-dom 对照。

## 9. 落地偏差记录（2026-11-04 收口时回填）

实现过程中有三处与本文件先前裁决不同，以「实际交付」为准：

1. **§2.1「core 按模块处理、不新增 CMP 编号」** → 实际登记为 `CMP-kernel-core`，
   但在规格里明确标注「组合模块、无独立对外契约」：它不进契约清单、不被壳直接依赖，
   只借组件卡描述 39 op 的归属与数据所有权。理由：四层若只登记三层，op 清单的
   「实现在哪」在组件树里会失联。
2. **§2.2「CMP-image 退役（拆）」** → 实际保留 active、职责收缩：解析类能力
   （`#for-load`/`#for-save`/引用收集）移交 `CMP-kernel-semantics`，落盘/布局/GC 执行/
   NodeView 仍在组件内。理由：GC 的删盘与导入的原子写仍是业务能力，拆进 app-shell
   会让「图片资源」失去唯一主人；退役口径留待 Windows 壳落地后再评估。
3. **§3.3 `resolveResources` 请求形状** → 由 `{refs[]}` 改为 `{refs[], baseDir}`：
   真实壳自检发现「让壳猜当前文档目录」会在未保存/另存场景把引用误判为缺失。
