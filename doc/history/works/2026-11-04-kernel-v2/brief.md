---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 工序 brief：可移植内核与桥协议 v2 落地（kernel-v2，P1）

## 1. 背景：重启 2026-10-21 暂缓工序

2026-10-21 的可移植内核工序（[存档](../../history/works/2026-10-21-portable-kernel/brief.md)）
评审有条件通过、三决策已定、目标规格写成，但**零代码实施**、第二次门未走，整包冻结在
[2026-10-21-editor-kernel-spec.md](../../history/decisions/2026-10-21-editor-kernel-spec.md)。
风险 R9（跨壳路径语义漂移）因此处于「搁置未缓解」。

2026-11-04 用户决定重启：**先做好 v2，再做 Windows 壳移植，Windows 直接参照本实现。**
重启路径按存档 result 的要求执行：复核 D1–D5 与三不变量 → 规格增量与升格 → 第二次门
人工确认 → 实现。

## 2. 本轮已确认的三个决定（2026-11-04，用户选）

1. **交付口径：一次发布切换**——内核先落地、Node 契约套件全绿，再在同一工序内切 macOS 壳，
   不留 v1/v2 共存期（符合存档规格 §4.6.4；无灰度维护成本，代价是切换前测试要一次补齐）。
2. **Windows 参照物：含参照物、不含 Windows 代码**——交付升格后的现行契约文档、壳参考时序
   清单、可跑的 Node 契约套件、最小壳装配示例（FakeShell 即参照实现）；Windows 壳另行立项。
3. **在飞冲突：minimap 暂停排队**——[2026-11-04-document-minimap](../2026-11-04-document-minimap/brief.md)
   停在本工序之后（内核重构会重写 web/src 装配与桥层，旧结构上做等于返工）。

## 3. 目标与验收

目标：按存档规格 + 本次增量，把 `web/src` 落成**四层可移植内核**
（transport / contract / semantics / core），macOS Swift 壳从 v1（`window.mdbridge` 方法面 +
字符串拼 JS + 142 处求值）切到 v2（JSON 信封 + id 关联 + 版本握手 + 错误码）。

验收标准（全部满足才算收口）：

1. **Node 契约套件不依赖任何 WebView 全绿**（评审四条件之一）：`node --test` 覆盖 op 表全量、
   握手拒绝、not_ready、id 回显、错误码；semantics 黄金夹具对拍与 Swift 旧实现逐字节一致。
2. **macOS selftest 全绿**：现有 121 项断言（改造后）全部通过，另加 v2 新增断言。
3. **v1 面彻底下线**：`window.mdbridge`、`messageHandlers.mdbridge`、`JSArgs` 转义、
   `evaluateJavaScript` 返回值取数（产品路径）、Swift 侧 `ImagePathRewriter` 全部不存在；
   `grep` 守门进 CI/自检。
4. **R9 关闭**：路径语义单点在内核 semantics，壳只提供 `resolveResources` 的文件系统作答。
5. **Windows 可直接参照**：契约文档为现行真相、FakeShell 可跑、壳参考时序成文。
6. **现行文档与实现一致**：architecture.md 桥协议节、组件规格、roadmap、risks、README。

## 4. 非目标

- 不实现 Windows/Linux 壳代码（另立工序，依赖本工序产物）。
- 不改编辑器功能面（拆分是契约化，行为不变）；唯一允许的行为修正是迁移路径上的已知缺陷
  （`setTheme` 用陈旧 `lastMarkdown` 重建、`setTest` 类死字段、`stats` 读错源），逐条带断言。
- 不推翻 architecture.md 已定稿的安全与行为取舍（全盘读授权、mermaid loose、原生抽屉）。
- 不做 minimap（已排队）、不改 Milkdown 版本、不引入第二套编辑器。

## 5. 任务表

组件级 WIP=1；同一组件同一时刻只有一个在飞任务。装载清单为必读文件，单任务 ≤250k。

| ID | 类型 | 组件 | 主题 | 出口（可判定） | 状态 |
|---|---|---|---|---|---|
| T1 | design | — | 规格增量与升格（复核 D1–D5/不变量、契约 diff、16 风险处置、验证计划） | 本目录 [spec-delta.md](spec-delta.md) 冻结 + 第二次门确认记录 | ✅ 已完成（2026-11-04 确认 G1/G2） |
| T2 | change | CMP-kernel-contract（含 transport） | 信封/分发/握手/错误码 + FakeShell + Node 套件骨架 + DOM 环境选型（Q3） | `node --test` 契约组全绿（零 DOM、零 WebView） | ✅ 已完成（2026-11-04；18 项契约测试 + 禁边脚本；Q3 移到 T4 冒烟） |
| T3 | change | CMP-kernel-semantics | 路径与 markdown 文本语义移植 + 黄金夹具 + 与 Swift 旧实现对拍 | 对拍逐字节一致；纯函数守门（无 fs/DOM/宿主符号） | ✅ 已完成（2026-11-04；15 用例×3 函数 45 项逐字节对拍 + 5 项规则断言） |
| T4 | change | core（组合模块） | `web/src` 迁入 core、39 个 op 处理器抽出、`bridge.js` 拆解、模式状态机、`lastMarkdown` 收口 | Node 套件 core 组绿；无宿主符号（lint 守门） | ✅ 已完成（2026-11-04；39 op 单点实现、jsdom core 组 10 项绿、selftest 121/121） |
| T5 | change | CMP-app-shell（含 document-io） | Swift：`send(op,payload,id)` + 响应表；30 处 callJS 收敛；PDF 几何/print op；导出改响应携带 | 编译通过 + 自检中产品路径无 `evaluateJavaScript` 取数 | ✅ 已完成（2026-11-04；callJS 全收敛、Swift 改写器删除、GC/保存走内核；selftest 115 PASS） |
| T6 | verify | — | Node 全绿 + selftest 全绿 + 人工点验（R8 交互清单） | result.md 记录命令与输出；blocker 清零 | ✅ 已完成（78 项 Node + 115 selftest + 粘贴链路 e2e 取证；打印/另存时序转人工清单） |
| T7 | doc | — | architecture/组件规格/roadmap/risks/README 收口；R9 关闭；规格升格 | 文档与实现一致；引用无归档件依据 | ✅ 已完成（architecture/组件规格/README/roadmap/risks 同步 v2；R9 关闭） |

依赖：T2 → T3 → T4 → T5 → T6 → T7；T4 与 T5 可并行（文件不相交）。
T6 依赖 T4+T5 合流。T7 在 T6 绿后执行。

装载清单（各任务共用基线）：本 brief、[spec-delta.md](spec-delta.md)、
[存档规格](../../history/decisions/2026-10-21-editor-kernel-spec.md)、
[architecture.md](../../design/architecture.md)、相关 CMP 规格；T5 另读
`Sources/MDPreview/DocumentWindowController.swift`（桥与装载段）与 `Selftest.swift`（断言面）。

## 6. 领取的开放问题

- 存档规格 Q3（Node 契约套件的 DOM 环境 jsdom vs happy-dom）→ T2 冒烟定，判据
  「ProseMirror 可运行 + 速度」，结论回填 spec-delta。
- 存档规格 Q1/Q2/Q4 属壳工序（Windows 技术栈、自定义 resource scheme、GC 大小写口径），
  本工序不领取，转 `plan/open-questions.md` 留存。

## 7. 定级与确认门

- 定级 **P1**（模块切分/新增组件、核心契约整体替换、数据所有权变更、扇入平台级）。
- 第一次门（2026-10-21）：已过，D1–D5 已拍板。
- 第二次门（本工序）：走查 spec-delta §7 的增量与 §8 的待确认项；用户确认后才编码。
