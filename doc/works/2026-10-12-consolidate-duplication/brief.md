---
layer: works
module: global
status: active
updated: 2026-10-12
---

# 工序：重复知识与重复实现收敛

原则：每类事实只保留一个权威位置（一处一事）。本序在 W2 删除结果之上合并，
不合并任何死物。

## 问题清单

### K1 Markdown 扩展名清单四处各写一份且互不一致（审计 #7）

- 位置：`DocumentWindowController.swift:31`（含 `txt`、`mdown` 重复两次）、
  `AppDelegate.swift:19`（不含 `txt`）、`EditorWebView.swift:92`（写成 `"text"`，
  疑为 `txt` 笔误，`mdown` 同样重复——复制粘贴传染证据）、
  `resources/Info.plist` `CFBundleTypeExtensions`。
- 收敛方案：`AppDelegate.markdownUTTypes` 作为 Swift 唯一来源（扩展名派生 UTType），
  `EditorWebView.decidePolicyFor` 改引该常量；Info.plist 保持手写但文件头注释指回
  Swift 常量，并加一条 selftest 断言比对 plist 与代码清单一致。
- 顺带决策：`txt` 是否属于可打开类型（现状各处分裂）——执行时定，结论进 result。

### K2 桥命令名双端散布（审计 #14）

- 位置：Swift `@objc` 动作里的 `"toggleStrongCommand"` 等
  （DocumentWindowController.swift:741-759）、`tableCommand("insertRowBelow")` 等 7 个
  （:405-415）；JS 注册表键名（main.js:43-51）。
- 收敛方案：Swift 侧建常量表（或让 EditorCommandSpec 直接携带 JS 命令名），
  JS 键名唯一出处仍是注册表；selftest 增加遍历校验：Swift 表中每个命令名
  在 JS 注册表中存在且 `typeof cmd.run === 'function'`。

### K3 web 资源定位逻辑两份（审计 #8、#17）

- 位置：`DocumentWindowController.indexPageURL`（:144-152）与
  `WebLocator.indexURL`（Selftest.swift:475-489）各用 `#filePath` 三级回退推仓库路径。
- 收敛方案：WebLocator 迁至 Util.swift（顺带解决"生产代码依赖测试文件"的归类错位），
  DocumentWindowController 只调用不复制。

### K4 `loadMarkdownContent` 与 `forceReload` 近乎复制（审计 #9）

- 位置：DocumentWindowController.swift:188-201 与 :623-636。
- 收敛方案：合并为 `injectMarkdown(_ text:, baseURL:)` 单入口；
  外部重载路径走同一函数，行为差异只保留一个参数。

### K5 `isReady` 双路径赋值（审计 #10）

- 位置：DocumentWindowController.swift:214（pushInitialContent 回调）与
  :305（handleBridgeMessage "ready"）。
- 收敛方案：保留桥消息路径为唯一赋值点，`pushInitialContent` 回调只负责
  pendingOpenURL 补载；或反之——执行时按实测时序定，删另一处。

### K6 缩放夹取与 860px 魔法数重复（审计 #11）

- 位置：夹取 0.5–3 双端（main.js:907 与 DocumentWindowController.swift:422）；
  860px 活在 typora.css:23,71、Selftest.swift:296（`contains("860")` 字符串断言）、README。
- 收敛方案：夹取保留在 JS（Swift 透传），Swift 注释指明归属；
  860px 断言改为读取 CSS 变量 `--editor-max-width` 比对，不再字符串匹配。

### K7 "光标是否在表格内"三种判定（审计 #12）

- 位置：selInfo 插件用 `isInTable`（main.js:472-487）、`focusAt` 祖先扫描
  （main.js:944-962）、`tableInfo` 又一套扫描+兜底（main.js:981-994）。
- 收敛方案：统一走 `isInTable`（prosemirror-tables 已依赖）；`tableInfo` 保留
  行列数读取但 inTable 判定同源，消除右键菜单项与右键定位判定分叉的可能。

### K8 任务列表 CSS 三段重叠（审计 #13）

- 位置：typora.css:129-136（`data-type` + `:has` 兜底）与 :393-425
  （`data-checked` 驱动的 `::before` 机制），原生 checkbox 定位 -1.6em 与伪元素 -1.55em 并存。
- 收敛方案：确认 milkdown 7.7 实际输出的 DOM 后保留一套视觉机制，
  删除另一套及其 `:has` 兜底；selftest 截图/断言核对无"双复选框"。

### K9 `#filePath` 推仓库路径的第三处变体

- 位置：若 K3 合并后仍存在其他 `#filePath` 依赖，一并在本序清点归一。
- 状态：执行时全仓 grep `#filePath` 核实。

## 验收标准

- [ ] 扩展名清单：Swift 侧唯一常量 + plist 一致性断言存在
- [ ] 桥命令名：双端一致性由 selftest 自动校验（人为改漏会红）
- [ ] WebLocator 位于 Util.swift，`DocumentWindowController` 无复制逻辑
- [ ] 注入/重载单入口；`isReady` 单赋值路径
- [ ] 表格判定单源；任务列表 CSS 单机制
- [ ] selftest 全部通过；`./build.sh` 通过

## 依赖与顺序

- 前置：[W2 remove-dead-code](../2026-10-12-remove-dead-code/brief.md) 收口。
- 后继：W4（结构拆分）与 W5（时序治理）以本序产出的单源位置为基准。
