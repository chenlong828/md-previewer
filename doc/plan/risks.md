---
layer: plan
module: global
status: current
updated: 2026-10-20
---

# 风险清单与缓解

只登记跨工序的活风险；单工序内的实现细节风险写在各工序 brief。
每条风险标注：严重度、存续条件、承接工序、缓解手段。修复完成后在对应工序
result.md 记录实证，并回改本文件状态——已消除条目**保留在本文件**（回改状态标注，
作回归监控与防复发台账），过程证据只存 history/works/，不在此复制。

## R1 源码模式下保存会写盘陈旧内容（严重度：高，数据丢失级）

- **现象**：文档内容存在两个真相源（编辑器 doc 与源码模式 textarea）。
  `web/src/main.js:887` 的 `getMarkdown()` 只读编辑器 doc；而 `web/src/main.js:1097`
  的 `requestStats()` 却知道在源码模式下读 textarea——同一座桥两种口径。
  用户在源码模式编辑后 ⌘S，Swift 侧 `fetchMarkdown`（DocumentWindowController.swift:271）
  拿到编辑前的旧内容写盘，并 `markClean()` 把旧内容设为干净基线；用户以为已保存。
- **存续条件**：源码模式可编辑 + 保存路径不读 textarea，两者同时成立即持续存在。
- **承接**：[W1 fix-latent-defects](../history/works/2026-10-12-fix-latent-defects/brief.md)。
- **缓解**：先写红→绿 selftest 断言；统一"当前文档内容"单一真相源（方案在 W1 定）。
- **状态（2026-10-14）：已消除**。`currentMarkdown()` 单一真相源（渲染读 doc、源码读 textarea），
  D1a 自检"源码模式保存取一致内容"守门；实证见 W1 result.md。

## R2 confirmClose 内嵌 RunLoop 泵送等待异步保存（严重度：高，状态损坏级）

- **现象**：`DocumentWindowController.swift:668-673` 用 `while isDirty { RunLoop.run }`
  最多转 5 秒等保存回调；泵送期间应用继续处理事件，用户可再触发 ⌘W/菜单/拖放，
  重入保存与打开路径，`isLoadingContent` 等守卫位在嵌套下语义失效。
- **存续条件**：关闭确认依赖"泵主循环等回调"这一模式。
- **承接**：[W5 timing-contracts](../history/works/2026-10-12-timing-contracts/brief.md)。
- **缓解**：关闭流程改为挂起-回调（beginSheetModal / 异步 windowShouldClose 路径），
  弹窗期间阻塞的只有确认流程本身，不再泵送主循环。
- **状态（2026-10-14）：已消除**。confirmClose 改 sheet 回调（beginConfirmClose），
  退出走 .terminateLater + reply；RunLoop 泵送等待已删除（全仓 grep 实证）；
  人工验证记录见 W5 result.md；契约沉淀于 design/architecture.md。

## R3 双 ProseMirror 来源（严重度：中，静默行为漂移）

- **现象**：`web/package.json` 同时依赖 `@milkdown/prose` 与独立的
  prosemirror-view / history / tables；undo/redo 用独立包（main.js:63），
  history 插件走 @milkdown/prose 内部版本。当前靠 node_modules 扁平化侥幸同版；
  一旦版本错开即出现两套 PM 状态模块，撤销栈静默分裂。
- **存续条件**：两种来源并存且无 dedupe 校验。
- **承接**：[W6 deps-and-build](../history/works/2026-10-12-deps-and-build/brief.md)。
- **缓解**：统一从 `@milkdown/prose` 取用；加安装后 dedupe 校验。
- **状态（2026-10-14）：已消除**。独立 prosemirror-* 三依赖已移除；`web/check-deps.mjs`
  挂 postinstall 双规则校验（禁独立 prosemirror-* + 嵌套拷贝白名单制）。

## R4 milkdown 混版升级回退（严重度：中）

- **现象**：`@milkdown/plugin-math` 锁 7.5.9，其余 7.7.0（package.json:16），
  无注释说明；代码注释记载 7.7 的 addRow*Command 存在 no-op 缺陷故自写表格命令。
  无人知情时"顺手统一版本"即触发回退。
- **存续条件**：混版无注释 + 表格命令行为无独立断言守门。
- **承接**：[W6 deps-and-build](../history/works/2026-10-12-deps-and-build/brief.md)。
- **缓解**：package.json 写明混版原因；selftest 已有表格几何断言，保持为守门断言。
- **状态（2026-10-14）：已缓解（长期项）**。`//milkdown-versions` 注释字段写明策略、
  兼容依据与统一版本前的重验条件；表格行为断言持续守门。混版组合本身仍在，
  消失条件=带断言重验通过后统一版本。

## R5 打开不可信文档的暴露面（严重度：中，安全取舍未显式化）

- **现象**：WebView 被授予全盘读权限（DocumentWindowController.swift:138、
  Selftest.swift:96 `allowingReadAccessTo: "/"`），mermaid `securityLevel: 'loose'`
  （main.js:133）。打开恶意 .md 时其内嵌内容在可读整个用户目录的上下文里执行。
- **存续条件**：宽授权为默认且未在现行文档中记录为显式取舍。
- **承接**：[W7 tests-and-security-doc](../history/works/2026-10-12-tests-and-security-doc/brief.md)。
- **缓解**：取舍写入 design/ 现行文档；评估把读权限收窄到"文档目录 + 其图片目录"。
- **状态（2026-10-14）：已显式化（接受项）**。决策/理由/失效条件沉淀于
  design/architecture.md §1（收窄评估结论：暂不收窄）；存续条件未变——
  产品定位变为"打开不可信第三方文档"时失效条件触发，须重新评估。

## R6 魔法延时在慢环境失效（严重度：中，偶现缺陷源）

- **现象**：PDF 导出固定等 0.35s（DocumentWindowController.swift:491）、
  状态栏 1.2s 后补一次 requestStats（:427）、文件监听 0.4s 防抖（:597）。
  机器慢或文档大时时限不够 → 导出 PDF 缺内容、状态栏文案滞留；开发机难复现。
- **存续条件**：以固定时长代替就绪信号。
- **承接**：[W5 timing-contracts](../history/works/2026-10-12-timing-contracts/brief.md)。
- **缓解**：逐个替换为回调/信号驱动；确需防抖的参数化并注明依据。
- **状态（2026-10-14）：已消除**。PDF 0.35s 改几何收敛信号、缩放 1.2s 盲等已删（W3）、
  防抖参数化为 `Timing.fileMonitorDebounce`；全仓 grep asyncAfter 仅剩 3 处
  命名常量用点；自检新增"大文档 PDF 完整性"守门。

## R7 测试断言与文档三处硬编码互相漂移（严重度：低）

- **现象**：selftest 断言数（Selftest.swift:270 `>= 30`）、README 的"30 项断言"、
  宽度下限 860px（typora.css / Selftest 字符串断言 / README）各自硬编码；
  增删命令或改样式即集体失真，且 [waitForCollect 超时不记失败](../history/works/2026-10-12-tests-and-security-doc/brief.md)，
  失败可能被静默吞掉。
- **存续条件**：断言数量与魔法值作为断言本体存在。
- **承接**：[W7 tests-and-security-doc](../history/works/2026-10-12-tests-and-security-doc/brief.md)。
- **缓解**：断言改为结构性校验（遍历注册表/读取 CSS 变量），文档不再复述计数。
- **状态（2026-10-14）：已消除**。`>= 30` 改为 EditorAction CaseIterable 集全等断言；
  860 断言读 CSS 变量；README 不再复述计数；waitForCollect 超时必 FAIL 复核锁定。

## R8 真实 GUI 交互时序在无头 harness 不可复现（严重度：中，测试覆盖缺口）

- **现象**：文件抽屉「点击目录展开无反应」在 selftest/drawer-test 全绿后仍被
  真实使用暴露（2026-10-20 实证）。harness 的点击展开断言只能按调用链模拟
  （`debugExpandByClick`），复现不了真实点击下 AppKit 的时序——当时的三段式
  异步装载（shouldExpand 拦截 + 后台装载 + reloadItem 续展）与 NSOutlineView
  对未展开条目的子层缓存时序不合，自动化全程拦截不到。
- **存续条件**：仍在。凡纯用户交互驱动的链路（点击/拖拽/键盘焦点/动画），
  无头自动化只能覆盖调用级模拟，真实时序缺陷结构性无法被守门。
- **承接**：[2026-10-20-file-drawer](../works/2026-10-20-file-drawer/brief.md)
  （本例缺陷已修复——装载改数据源内同步，与 AppKit 缓存时序彻底无关）。
- **缓解**：①交互类工序收口必附「待人工实证」清单（真人点验是验收的一部分）；
  ②修复取确定性机制而非时序补丁，使自动化断言重新有效；③同类交互功能立项时
  把真人点验写入 brief 验收标准。
