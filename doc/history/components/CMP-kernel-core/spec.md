---
layer: history
module: kernel
component: CMP-kernel-core
status: retired
updated: 2026-11-04
---

# CMP-kernel-core 组件规格（已退役）

> **退役说明（2026-11-04）**：本卡片对应的 `W-KERNEL-CORE` 单元在「内核按功能组件拆分」工序中解体，
> 拆成六个组件：`CMP-kernel-document` / `CMP-kernel-editor` / `CMP-kernel-code` /
> `CMP-kernel-find` / `CMP-kernel-output` / `CMP-kernel-media`，共享状态与端口归 `kernel/shared/`。
> 保留此卡片仅为追溯当时的接口与理由；现行规格见 `doc/design/components/` 下六张卡片。
> 工序：`doc/history/works/2026-11-04-kernel-core-split/`。

## 组件卡

- 状态：active
- 单元：组件（组合模块，不带独立对外契约——对外只有 op 通道）
- 层 / 类型：L2 领域；内核能力实现（编辑面、代码阅读面、查找、导出、图片导入编排）
- 业务价值：把 39 个 op 的实现收在一处，让壳只面对 op 名；没有它，编辑能力会重新长回壳侧（v1 的 30 处 `callJS` 字符串拼接就是这么来的）。
- 负责：39 个 host op 的唯一实现；`state` 单例（含 `mode` 状态机与干净基线）；编辑器装配与格式/表格命令；源码模式；代码阅读面；查找；统计与选择信息上报；独立 HTML 导出；图片粘贴的导入编排（选区快照 + `importImage` 请求 + 回插）；Markdown/Mermaid 图片 NodeView；列表缩进序列化。
- 不负责：宿主通道（`CMP-kernel-transport`）；帧与 op 校验（`CMP-kernel-contract`）；路径与 markdown 文本语义（`CMP-kernel-semantics`）；图片落盘与 GC 执行（`CMP-app-shell` 的 `ImageStore`）；窗口/菜单/PDF 编排（`CMP-app-shell`）。
- 内部逻辑：`ops.js` 是 op 名 → handler 的唯一映射，装配期注册进 registry；`bus.js` 是内核↔壳的两个端口（`notify` 只发通知、`hostCall` 发带 id 请求，组合根在 `page.js` 绑定一次），**core 内不出现任何宿主符号**；`state.js` 是全局事实单例，写入点显式（如 `setMode` 是模式迁移唯一入口）；其余 15 个模块按能力分工，互相只经 import 读写 `state`。
- 拥有的数据：当前编辑器文档与干净基线、模式（markdown/code）、源码模式与查找 UI 状态、代码视图文本与语言/行号、统计与选择信息；不拥有磁盘文件，不持久化任何东西。
- 变化轴：编辑器引擎与插件版本、命令表、查找实现、导出模板、语言注册表。
- 公开契约（含能力 ID）：
  - `CMP-kernel-core#ops`：39 个 op 的 handler（清单权威在 `CMP-kernel-contract#op-inventory`）；响应一律为 JSON 对象。
  - `CMP-kernel-core#bus`：`notify(op, payload)` / `hostCall(op, payload)`；未绑定时调用即报错，不静默丢弃。
  - `CMP-kernel-core#state`：`mode:'markdown'|'code'` 与 `sourceMode` 的互斥由 `setMode()` 保证；`baselineMarkdown` 由 `setMarkdown`/`markClean` 同步落定。
  - `CMP-kernel-core#editor`：`createEditor` 装配 Milkdown；`setMarkdown`/`getMarkdown`/`getSaveMarkdown`/`formatCommand`/`tableCommand`/`insertTable`/`insertMarkdown`。
  - `CMP-kernel-core#find`：`openFindBar`/`closeFindBar`/`findNext`/`findPrev`/`findInfo`；Markdown 与源码模式共用查找栏，代码文档的查找走 `CMP-code-view` 的文本选区实现。
  - `CMP-kernel-core#code-view`：`setCode`/`setCodeLanguage`/`setCodeLineNumbers`/`codeInfo`/`hasLanguages`；进入代码面即 `mode='code'` 且 `sourceMode=false`。
  - `CMP-kernel-core#export`：`exportStandaloneHTML` 在核内 `await` 完成，响应携带 `{html}`（不跨桥传 Promise）；`print`/`getContentSize` 供壳的打印与 PDF 几何。
  - `CMP-kernel-core#image-import`：`insertImage` 落节点；粘贴经 `setupImagePaste` → `hostCall('importImage')` → 回插到**请求时刻的选区快照**；文档未保存时由壳拒绝，核只清挂起态。
  - `CMP-kernel-core#notifications`：`ready`/`changed{dirty}`/`stats{words,chars}`/`sourceMode{value}`/`selinfo{inTable}`；`changed` 有 200ms 防抖与过期过滤。
- 入口：
  - `CMP-kernel-document/web/src/kernel/ops.js#createOps`（另有 `renderMarkdown` 同步辅助）
  - `CMP-kernel-document/web/src/kernel/shared/bus.js#bindBus`（另有 `notify`/`hostCall`/`isBound`）
  - `CMP-kernel-document/web/src/kernel/shared/state.js#setMode`（`state` 单例、`isCodeMode`、`currentMarkdown`）
  - `CMP-kernel-editor/web/src/kernel/components/editor/editor.js#createEditor`（`toggleSource`）
  - `CMP-kernel-code/web/src/kernel/components/code/code-view.js#showCode`（`hideCode`/`setCodeLanguage`/`setCodeLineNumbers`/`codeInfo`）
  - `CMP-kernel-find/web/src/kernel/components/find/find-bar.js#openFindBar`（`runFind`/`stepFind`/`setupFindBar`）
  - `CMP-kernel-output/web/src/kernel/components/output/export.js#exportStandaloneHTML`
  - `CMP-kernel-media/web/src/kernel/components/media/image-paste.js#setupImagePaste`（`extractImagePayload`/`handleImported`）
  - `CMP-kernel-editor/web/src/kernel/components/editor/commands.js#commandRegistry`、`tables.js#tableCommandImpls`、`languages.js#highlightInto`、`image-view.js#getImageView`、`mermaid-view.js#getMermaidView`、`stats.js#scheduleStats`、`selinfo.js#selInfoProse`、`list-indent.js#fourSpaceListItem`
- 依赖：Milkdown/ProseMirror/KaTeX/Mermaid/refractor（内核内唯一允许第三方依赖的层）；`contract/`（`PROTOCOL_VERSION` 等常量）；`semantics/`（装载/保存/命名）。不得 import `transport/`。
- 冷热属性：编辑输入是热路径，`changed` 只走防抖通知；`hostCall` 只在装载、粘贴导入、GC 引用收集三类低频动作上出现。
- 尺寸预算：目标 ≤120k token；当前 2182 行（17 个模块），组合根 `web/src/page.js` 47 行 + `kernel/main.js` 26 行。
- 单独运行：`cd web && npm test`（`web/test/core.test.js`，jsdom + `bootCore`，无 WebView）；真壳 `./.build/debug/MDPreview --selftest`。
- 验证计划：core 组 10 项（装载/保存/模式/脏/统计/引用/诊断/代码信息/命令表）+ selftest 115 项覆盖产品路径。
- 删除测试：删掉后 39 个 op 的实现与 `state` 单例没有归属，会退回壳侧脚本或散落各壳 → 真边界。

## 公开契约细节

- `#ops` 的不变量：handler 返回值必须是 JSON 原语对象（契约层递归校验）；空返回补 `{}`；抛错由契约层转成 `internal`，核内不得自行吞异常返回成功。
- `#bus` 的错误模式：未绑定时 `notify` 抛 `kernel bus: notifier not bound`、`hostCall` 返回 rejected Promise（不抛），让装配顺序错误立刻可见而不静默丢帧；`hostCall` 的失败一律以 reject 传回，调用方决定降级。
- `#state` 的不变量：`setMode` 是 `mode`/`codeMode` 的唯一写入口（非法值抛错）；`sourceMode` 在 `mode='code'` 时恒 false；`baselineMarkdown` 只在装载与 `markClean` 落定，`changed{dirty}` 由「当前序列化 ≠ 基线」派生，不由防抖回调猜测。
- `#editor` 的不变量：`getSaveMarkdown` 返回写盘口径（经 `restoreForSave`），`getMarkdown` 返回渲染态序列化（诊断口径）——两者不可互换。
- `#code-view` 的不变量：`setCode` 先 `hideCode` 再进代码面（`setMarkdown` 同样先退出代码视图）；代码文档不发 `changed`、不写脏；行号开关只改布局类，不重绘 token。
- `#export` 的不变量：导出在一次 handler 内完成，响应只带字符串；核内不保留导出态（v1 的 `window.__exportedHTML` 技巧已废除）。
- `#image-import` 的错误模式：一次粘贴只取第一张图；壳拒绝（未保存/非图片/目录不可写）时核只清挂起态，不插节点、不改脏。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#ops` | `web/test/core.test.js`：「诊断 op：命令表、表格信息、图片载荷识别」；`web/test/contract.test.js`：「契约清单…」（op 集合与注册表全等） |
| `#editor` | `web/test/core.test.js`：「装载改写…」「保存口径…」；selftest：「装载改写(内核改写+壳作答)」「保存口径(内核还原相对路径)」 |
| `#state` | `web/test/core.test.js`：「模式状态机：代码视图与源码模式互斥，装载 markdown 退出代码视图」「脏口径：装载后基线对齐，插入内容后 changed(dirty=true)」 |
| `#find` | `web/test/core.test.js` 查找口径；selftest：「查找命中计数」「查找下一处」「查找高亮与定位」 |
| `#code-view` | `web/test/core.test.js`：「代码视图信息与语言表」；selftest：「代码视图 自动语言与高亮」「代码视图 行号开关与复制文本」 |
| `#export` | selftest：导出 HTML 响应携带（v2 断言） |
| `#notifications` | `web/test/core.test.js`：「统计口径…」；`web/test/support/dom.js#notificationsOf` 断言通知序列 |
| `#bus` | `web/test/support/dom.js#bootCore`：假壳实现 `notify`/`callHost` 两端（`resolveResources`/`importImage` 应答） |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 编辑器文档 / 干净基线 | `setMarkdown` / `markClean` / 用户输入 | 保存（`getSaveMarkdown`）、统计、导出 | 单内存实例；基线是脏判据唯一来源 |
| 模式（markdown/code） | `setMode()` | 全部渲染分支、壳的 `getState` | 单写入口，互斥由迁移函数保证 |
| 源码模式 / 查找 UI / 选择信息 | 本组件 | 本组件、壳（经通知镜像） | 会话级，不持久化 |
| 代码视图文本 / 语言 / 行号 | `setCode` 等 op | 本组件、PDF/打印（经 `getContentSize`） | 只读投影，不写回文件 |
| 统计（词/字） | `computeStats`（当前内容） | 壳状态栏（`stats` 通知） | 派生值，不缓存为第二真源 |

## 验证债

`#image-import` 的全链路（⌘V → `importImage` → 落盘 → 回插）只在 selftest 里覆盖到载荷识别与假壳应答，真实粘贴依赖 `MDP_IMPORT_IMAGE` 截图钩子人工核对；`#export` 的 HTML 内容正确性无逐字节断言（只断言响应携带字符串）。两者已记入工序 result 的验证口径。

## 删除测试

删掉后 39 个 op 与统一 `state` 没有归属，各壳会各自实现编辑编排，双端行为必然分叉 → 保留为真边界。
