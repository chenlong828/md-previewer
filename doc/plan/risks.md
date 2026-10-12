---
layer: plan
module: global
status: current
updated: 2026-10-12
---

# 风险清单与缓解

只登记跨工序的活风险；单工序内的实现细节风险写在各工序 brief。
每条风险标注：严重度、存续条件、承接工序、缓解手段。修复完成后在对应工序
result.md 记录实证，并回改本文件状态。

## R1 源码模式下保存会写盘陈旧内容（严重度：高，数据丢失级）

- **现象**：文档内容存在两个真相源（编辑器 doc 与源码模式 textarea）。
  `web/src/main.js:887` 的 `getMarkdown()` 只读编辑器 doc；而 `web/src/main.js:1097`
  的 `requestStats()` 却知道在源码模式下读 textarea——同一座桥两种口径。
  用户在源码模式编辑后 ⌘S，Swift 侧 `fetchMarkdown`（DocumentWindowController.swift:271）
  拿到编辑前的旧内容写盘，并 `markClean()` 把旧内容设为干净基线；用户以为已保存。
- **存续条件**：源码模式可编辑 + 保存路径不读 textarea，两者同时成立即持续存在。
- **承接**：[W1 fix-latent-defects](../works/2026-10-12-fix-latent-defects/brief.md)。
- **缓解**：先写红→绿 selftest 断言；统一"当前文档内容"单一真相源（方案在 W1 定）。

## R2 confirmClose 内嵌 RunLoop 泵送等待异步保存（严重度：高，状态损坏级）

- **现象**：`DocumentWindowController.swift:668-673` 用 `while isDirty { RunLoop.run }`
  最多转 5 秒等保存回调；泵送期间应用继续处理事件，用户可再触发 ⌘W/菜单/拖放，
  重入保存与打开路径，`isLoadingContent` 等守卫位在嵌套下语义失效。
- **存续条件**：关闭确认依赖"泵主循环等回调"这一模式。
- **承接**：[W5 timing-contracts](../works/2026-10-12-timing-contracts/brief.md)。
- **缓解**：关闭流程改为挂起-回调（beginSheetModal / 异步 windowShouldClose 路径），
  弹窗期间阻塞的只有确认流程本身，不再泵送主循环。

## R3 双 ProseMirror 来源（严重度：中，静默行为漂移）

- **现象**：`web/package.json` 同时依赖 `@milkdown/prose` 与独立的
  prosemirror-view / history / tables；undo/redo 用独立包（main.js:63），
  history 插件走 @milkdown/prose 内部版本。当前靠 node_modules 扁平化侥幸同版；
  一旦版本错开即出现两套 PM 状态模块，撤销栈静默分裂。
- **存续条件**：两种来源并存且无 dedupe 校验。
- **承接**：[W6 deps-and-build](../works/2026-10-12-deps-and-build/brief.md)。
- **缓解**：统一从 `@milkdown/prose` 取用；加安装后 dedupe 校验。

## R4 milkdown 混版升级回退（严重度：中）

- **现象**：`@milkdown/plugin-math` 锁 7.5.9，其余 7.7.0（package.json:16），
  无注释说明；代码注释记载 7.7 的 addRow*Command 存在 no-op 缺陷故自写表格命令。
  无人知情时"顺手统一版本"即触发回退。
- **存续条件**：混版无注释 + 表格命令行为无独立断言守门。
- **承接**：[W6 deps-and-build](../works/2026-10-12-deps-and-build/brief.md)。
- **缓解**：package.json 写明混版原因；selftest 已有表格几何断言，保持为守门断言。

## R5 打开不可信文档的暴露面（严重度：中，安全取舍未显式化）

- **现象**：WebView 被授予全盘读权限（DocumentWindowController.swift:138、
  Selftest.swift:96 `allowingReadAccessTo: "/"`），mermaid `securityLevel: 'loose'`
  （main.js:133）。打开恶意 .md 时其内嵌内容在可读整个用户目录的上下文里执行。
- **存续条件**：宽授权为默认且未在现行文档中记录为显式取舍。
- **承接**：[W7 tests-and-security-doc](../works/2026-10-12-tests-and-security-doc/brief.md)。
- **缓解**：取舍写入 design/ 现行文档；评估把读权限收窄到"文档目录 + 其图片目录"。

## R6 魔法延时在慢环境失效（严重度：中，偶现缺陷源）

- **现象**：PDF 导出固定等 0.35s（DocumentWindowController.swift:491）、
  状态栏 1.2s 后补一次 requestStats（:427）、文件监听 0.4s 防抖（:597）。
  机器慢或文档大时时限不够 → 导出 PDF 缺内容、状态栏文案滞留；开发机难复现。
- **存续条件**：以固定时长代替就绪信号。
- **承接**：[W5 timing-contracts](../works/2026-10-12-timing-contracts/brief.md)。
- **缓解**：逐个替换为回调/信号驱动；确需防抖的参数化并注明依据。

## R7 测试断言与文档三处硬编码互相漂移（严重度：低）

- **现象**：selftest 断言数（Selftest.swift:270 `>= 30`）、README 的"30 项断言"、
  宽度下限 860px（typora.css / Selftest 字符串断言 / README）各自硬编码；
  增删命令或改样式即集体失真，且 [waitForCollect 超时不记失败](../works/2026-10-12-tests-and-security-doc/brief.md)，
  失败可能被静默吞掉。
- **存续条件**：断言数量与魔法值作为断言本体存在。
- **承接**：[W7 tests-and-security-doc](../works/2026-10-12-tests-and-security-doc/brief.md)。
- **缓解**：断言改为结构性校验（遍历注册表/读取 CSS 变量），文档不再复述计数。
