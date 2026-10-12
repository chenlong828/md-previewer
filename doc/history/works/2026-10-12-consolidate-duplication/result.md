---
layer: history
module: global
status: frozen
updated: 2026-10-14
---

# 工序收口：重复知识与重复实现收敛

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| 扩展名清单：Swift 侧唯一常量 + plist 一致性断言存在 | ✅ | `AppDelegate.markdownExtensions` 为唯一来源（UTTypes 由此派生）；selftest `Info.plist 扩展名一致(6 项)` |
| 桥命令名：双端一致性由 selftest 自动校验（人为改漏会红） | ✅ | selftest `桥命令名双端一致(21 条)` + 行为抽检 3 条；实现期实测红（抓到基线缺陷，见下） |
| WebLocator 位于 Util.swift，DocumentWindowController 无复制逻辑 | ✅ | 迁移完成；`indexPageURL` 复制逻辑删除，仅调用 `WebLocator.indexURL()` |
| 注入/重载单入口；isReady 单赋值路径 | ✅ | `injectMarkdown(_:baseURL:)` 唯一入口（forceReload 复用）；isReady 仅桥消息 "ready" 分支赋值，暂存补载同分支 |
| 表格判定单源；任务列表 CSS 单机制 | ✅ | `focusAt`/`tableInfo` 的 inTable 判定统一 `isInTable`；typora.css 删除旧 DOM 假设的三条兜底规则，仅保留 data-checked 驱动机制 |
| selftest 全部通过；构建通过 | ✅ | 59 项 PASS，SELFTEST PASSED |

## 实现期发现并修复的基线缺陷（超出收敛本身）

1. **标题菜单动作基线静默失败**：`wrapInHeadingCommand` 从未登记进 web 命令注册表（W2 删除的幻影命令之外它是"反向幻影"——Swift 转发了但 web 没注册），且 milkdown 命令为位置参数形态（`run(level)`），Swift 传的 `{"level": n}` 对象即使注册了也无法应用。双端一致性校验实现期即红，修复：注册表补登记 + `jsPayload` 改为数字位置参数 + `formatCommand` 支持 fragmentsAllowed 标量 payload + 行为抽检常驻守门。
2. **tableCommand 重构为名字表**：`tableCommandImpls`（名字 → view 实现）替代内联 switch，使表格命令名同样可被 selftest 校验。

## 决策记录

- **txt 取舍**：markdown 类型 = `md, markdown, mdown, mkdn, mdtext, mdwn`，**不含 txt**——`.txt` 链接由系统外部打开，与 Info.plist / 打开面板现状一致；删除了 EditorWebView 里 `"text"` 笔误（复制粘贴传染证据）。
- **注入/重载差异收敛方向**：历史差异（是否重启文件监视）按"重启"收敛——重载后以磁盘现状为新监视基线，消除旧路径不刷新监视属性的不一致。
- **isReady 合并方向**：桥消息为唯一赋值点；init 回调只留日志。谁先到达都安全（补载只在桥分支发生，openDocument 自带守卫）。
- **缩放夹取归属**：web 端 `mdbridge.setZoom` 单点负责（返回有效值）；Swift 透传并采用返回值显示状态栏。顺带完成 W5-T2 的缩放行（删除 1.2s 盲等，改直接 requestStats）。
- **860px 断言**：改为读取 CSS 变量 `--editor-max-width` 与 #app 实际 min-width 比对，Swift 侧不再出现具体数字。

## 结论落点表

| 活结论 | 落点 |
|---|---|
| K1 扩展名唯一来源 + txt 不属于可打开类型 | `Sources/MDPreview/AppDelegate.swift` `markdownExtensions`；`EditorWebView.decidePolicyFor`；`resources/Info.plist` 注释；selftest 断言 |
| K2 桥命令名双端规格（spec 携带 jsCommand/jsPayload；位置参数形态） | `Sources/MDPreview/EditorCommands.swift`；`DocumentWindowController.performEditorAction`；`web/src/main.js` `commandRegistry`/`tableCommandImpls`/`hasCommands`；selftest 双端+行为断言 |
| K3 资源定位单点（全仓唯一 #filePath） | `Sources/MDPreview/Util.swift` `WebLocator` |
| K4 注入单入口 | `DocumentWindowController.injectMarkdown` |
| K5 isReady 单赋值点 | `DocumentWindowController.handleBridgeMessage` "ready" 分支 |
| K6 夹取归属 JS + 宽度下限读 CSS 变量 | `web/src/main.js` `setZoom`；`Selftest.swift` 宽度策略断言 |
| K7 表格判定同源 isInTable | `web/src/main.js` `focusAt`/`tableInfo` |
| K8 任务列表视觉单机制 | `web/src/typora.css`（data-checked 段） |

## 遗留

- W4 拆分与 W5 时序治理以本序产出的单源位置为基准（`performEditorAction`、`injectMarkdown`、`tableCommandImpls`）。
