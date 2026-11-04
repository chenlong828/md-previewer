---
layer: design
module: kernel
component: CMP-kernel-semantics
status: active
updated: 2026-11-04
---

# CMP-kernel-semantics 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1a 技术边界；纯函数语义层
- 业务价值：让「图片路径怎么改写、怎么还原、怎么收集引用、新图片叫什么名字」只有一份实现。有它，macOS 与未来 Windows 壳共享同一套字节级结果；没有它，就是 R9 记录的双头分叉——Swift `ImagePathRewriter` 与 `image-view.js` 在括号拆分、`%XX` 解码粒度、存在性判定上各自演进。
- 负责：markdown 图片目的地的装载改写、保存还原、引用收集、落盘命名，以及路径编解码与 `posix`/`win32` 两种路径风格。
- 不负责：文件系统（存在性由壳作答后注入）、编辑器与 NodeView（`CMP-kernel-core`）、op 分发（`CMP-kernel-contract`）、GC 的删盘执行（`CMP-app-shell` 的 `ImageStore`）。
- 内部逻辑：`markdown.js` 用单行两段式解析——宽松捕获 `![alt](inner)`，再在 inner 内拆 `<>` 包裹目的地 / 尾部引号标题 / 裸路径；`mapLinesOutsideFences` 跳过围栏块；`paths.js` 做 `file://` 编解码与路径规范化。全部为纯函数。
- 拥有的数据：无。不持状态、不读写磁盘、不缓存壳的作答。
- 变化轴：路径风格（posix/win32）、`%XX` 编码口径、支持的路径写法边界（引用式图片/深层嵌套括号明确不支持）。
- 公开契约（含能力 ID）：
  - `CMP-kernel-semantics#for-load`：`applyForLoad(md, {resources})` —— 存在的相对/根相对路径改写为 `%20` 编码的 `file://`；缺失或解析失败静默保留原文；围栏内不动。
  - `CMP-kernel-semantics#for-save`：`restoreForSave(md, {baseDir, style})` —— `file://` 还原为文档目录内相对路径（空格/括号用 `<>` 包裹），目录外保留绝对路径。
  - `CMP-kernel-semantics#refs`：`collectImageRefs` 取字面引用；`collectResourceRefs(md, {resources})` 返回所有真实存在的候选绝对路径（字面 + 解码两口径取并集，GC 宁多保护）。
  - `CMP-kernel-semantics#candidates`：`refCandidates(ref, {baseDir, style})` 给出壳该去 `stat` 的绝对路径；两口径相同时只给一个。
  - `CMP-kernel-semantics#naming`：`nextResourceName({existing, kind, mime, preferredName})` —— blob 为 `img_NNN.<mime 扩展名>`（目录内最大序号 +1），file 保留原名、冲突加 `-2`/`-3`。
  - `CMP-kernel-semantics#path-policy`：`fileUrlFromPath` / `urlToPath` / `normalizePath(path, {style})` / `joinBase`，`posix` 与 `win32` 两风格同契约。
- 入口：
  - `CMP-kernel-semantics/web/src/kernel/semantics/markdown.js#applyForLoad`（另有 `restoreForSave`/`collectResourceRefs`/`collectImageRefs`/`refCandidates`/`nextResourceName`/`splitInner`）
  - `CMP-kernel-semantics/web/src/kernel/semantics/paths.js#fileUrlFromPath`（另有 `urlToPath`/`normalizePath`/`joinBase`/`percentDecodedPath`）
  - `CMP-kernel-semantics/Sources/MDPreview/DocumentWindowController.swift#resolveResources`（壳侧的「存在性作答」实现，不是语义实现）
- 依赖：零。不 import 其它层，不引第三方；`web/check-kernel.mjs` 把本层的 import 白名单限定在 `semantics/` 内。
- 冷热属性：装载/保存各一次全篇扫描，输入热路径外；`file://` 编解码为字符串操作，无 IO。
- 尺寸预算：目标 ≤120k token；当前 311 行（markdown 228 + paths 83）。
- 单独运行：`cd web && npm test`（`web/test/semantics.test.js` 50 项，纯 Node、零 DOM）；禁边守门 `node check-kernel.mjs`。
- 验证计划：与已删除的 Swift 实现逐字节对拍 45 项（黄金件 `web/test/fixtures/semantics-golden.json`）+ 5 项规则断言；core 组另有装载/保存/引用收集 3 项端到端。
- 删除测试：删掉后路径规则重新散落到编辑器、壳与导出各一份，跨平台字节差异无法守门 → 真边界。

## 公开契约细节

- `#for-load` 的不变量：只改写图片目的地；行内代码、围栏代码块、远程 URL、`data:`/`#` 目的地不动；改写结果 `file://` 内空格必须编码为 `%20`，且 `!$&'()*+,;=@` 保持字面（`%21` 等被回解），与路径风格无关。
- `#for-load` 的错误模式：缺文件 → 保留原文（图片不显示，不破坏内容）；拆不出目的地 → 保留原文。静默是安全退化，不是失败吞掉。
- `#for-save` 的不变量：`restoreForSave(applyForLoad(md))` 在文件齐全时回到原写法（往返一致）；同一篇文档多次保存结果稳定（幂等）。
- `#refs` 的不变量：集合只增不减——同一引用在字面与解码两种写法下都存在的文件，两条路径都进集合；围栏内的引用不算引用。
- `#candidates` 的不变量：返回顺序固定为 `[字面, 解码]`；两者相等时只返回一个，壳不必去重。
- `#naming` 的错误模式：`existing` 为空时从 `img_001` 起；`preferredName` 无扩展名时按原名 + 后缀处理，不做猜测。
- `#path-policy` 的边界：引用式图片 `![alt][ref]`、两层以上嵌套括号、路径内转义字符、跨行目的地**明确不改写**（见 `doc/design/architecture.md` §2.1 覆盖边界）。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#for-load` / `#for-save` / `#refs` | `web/test/semantics.test.js`：15 个黄金用例 × 3 函数 = 45 项逐字节对拍（`对拍·装载改写：<名>`、`对拍·保存还原：<名>`、`对拍·引用收集：<名>`） |
| `#for-load` 端到端 | `web/test/core.test.js`：「装载改写：经壳作答把相对引用改写为可加载 URL」；selftest「装载改写(内核改写+壳作答)」 |
| `#for-save` 端到端 | `web/test/core.test.js`：「保存口径：目录内引用还原为相对路径」；selftest「保存口径(内核还原相对路径)」 |
| `#refs` 端到端 | `web/test/core.test.js`：「资源引用收集：宁多保护（两口径同时存在都进集合）」 |
| `#candidates` / `#path-policy` | `web/test/semantics.test.js`：「PathPolicy：file URL 编解码与 Swift 同口径（空格/括号/中文）」「normalizePath：posix 与 win32 两风格」「splitInner：尖括号优先、尾部标题、整体路径三态」 |
| `#naming` | `web/test/semantics.test.js`：「nextResourceName：blob 顺序命名与 file 冲突后缀」 |
| 纯函数守门 | 同套件：语义层无 import 副作用；`web/check-kernel.mjs` 限其 import 白名单 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 图片路径写法（磁盘原文） | 壳（`CMP-document-io`） | 本组件只读 | 本组件不改磁盘 |
| 装载改写结果 | 本组件（纯函数返回） | `CMP-kernel-core` 渲染 | 每次装载重算，无缓存 |
| 壳的作答（存在性/URL/候选） | 壳 `resolveResources` | 本组件入参 | 单次调用内有效，不落状态 |
| 黄金夹具 | `web/test/fixtures/semantics-golden.json`（测试资产） | 本组件套件 | 只读；生成器 `tools/semantics-dump/` 收口时删除 |

## 验证债

黄金件的生成器（`tools/semantics-dump/`，Swift）在 T6 收口时删除，此后夹具成为唯一基准、无法再生成——规则若改，只能手工改夹具并同步「与旧实现逐字节一致」的结论表述。已记录：v2 落地后不再有 Swift 对照物，"对拍"退化为"回归"。

## 删除测试

删掉后语义重回多头（编辑器一份、壳一份、导出可能第三份），跨平台一致性只能靠人工比对 → 保留为真边界。
