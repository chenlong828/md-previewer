---
layer: history
module: global
status: frozen
updated: 2026-10-14
---

# 工序收口：时序耦合与隐式契约治理

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| 关闭/退出流程：确认弹窗期间再触发 ⌘W/⌘Q 无重复弹窗、无重入保存（手动脚本留档） | ✅ | 见下方"人工验证记录"；守门不变量：每窗口 `isConfirmingClose` 吞重复请求、sheet 运行期间 AppKit 禁用菜单键等价键、`isTerminateConfirming` 挡 Dock/AppleScript 重复触发、退出队列串行推进且保存失败即 `reply(false)` |
| PDF 导出无固定 sleep；慢速模拟（大文档）下导出完整 | ✅ | 生产侧 `waitForWebViewGeometrySettled`（连续两次同高即收敛，40 次兜底）；自检新增"大文档 PDF 完整性"（30 份样例注入 → 收敛截取，高度与字节均成规模）PASS |
| main.js 脏抑制单机制；"打开文件即脏"回归断言通过 | ✅ | 删除 `pendingBaseline` + `suppressChange` 双机制；基线由 `setMarkdown`/`markClean` **同步**落定，防抖回调只做"过期过滤 + 比对"；自检新增"T3 打开文件即脏回归（注入后零误报）"PASS |
| 全仓 `grep -n 'asyncAfter'` 只剩有命名常量且注明依据的用点 | ✅ | 3 处：`Timing.geometryPollInterval`(0.05s, 布局+合成轮询)、`Timing.fileMonitorDebounce`(0.4s, 原子写窗口)、自检 `Polling.geometryInterval`(同生产口径)——全部命名常量 + 依据注释 |
| selftest 全部通过；`./build.sh` 通过 | ✅ | 61 PASS（较上序 +2）；`./build.sh` 完整跑通并组装 dist/MDPreview.app |

## 各项治理落点

| 项 | 落点 | 方式 |
|---|---|---|
| T1 | `DocumentWindowController.beginConfirmClose/closeCompletion/finishCloseRequest`、`AppDelegate.applicationShouldTerminate/beginTerminateConfirmation` | 确认弹窗改 sheet 回调；windowShouldClose 返回 false + 回调续做 `performClose`；退出走 `.terminateLater` + `reply(toApplicationShouldTerminate:)`。**顺带修一个真隐患**：移除退出流程中 windowShouldClose 的 `isTerminating` 旁路——异步队列等待期间手动 ⌘W 脏窗口原本会静默丢改动 |
| T2 | `Timing` 常量组、`waitForWebViewGeometrySettled` | PDF 拉高后轮询 web 端 scrollHeight 连续一致即收敛；缩放盲等已在 W3 删除；文件监听防抖保留但命名 |
| T3 | `web/src/state.js`、`editor.js` listener、`bridge.js setMarkdown` | `setMarkdown` 后同步序列化落定基线（与保存取回同口径）；listener 回调先比 `markdown === currentMarkdown()` 过期过滤再报 dirty。**查证依据**：milkdown listener 插件对 `addToHistory===false` 事务跳过、但 `replaceAll` 未设该 meta（`@milkdown/utils/lib/index.es.js:470-484`），故拉高 WebView 后的旧防抖回调必然可能迟到——同步基线 + 过期过滤是唯一确定性收敛 |
| T4 | `DocumentWindowController.openDocument` | `!isReady || isLoadingContent` 守卫**先于** `TextFile.read`；读文件动作只在就绪补载时发生一次（TOCTOU/双读消除） |
| T5 | `AppDelegate` argv 注释块 + `cliOpenedURLs` + `Selftest` 启动矩阵说明 | 不变量显式成文：`openFile` 由 LaunchServices 晚于 `didFinishLaunching` 送达；防御按标准化 URL 去重 |
| T6 | `DocumentWindowController` 状态栏三字段、`EditorWebView.eventMonitors` | 词数区/缩放区/状态区拆分，`renderStatusBar()` 单点落值（缩放占比改为**持久驻留**字段，消灭"临时显示再恢复"时序补丁）；监视器句柄入数组、`deinit` 成对移除；`allowsBackForwardNavigationGestures` 漂移注释修正为实际动机 |

## 人工验证记录（关闭/退出确认）

步骤（人工，2026-10-14）：
1. 打开两个窗口并各自修改至"已修改"；⌘Q → 逐窗口出现 sheet 确认；第一窗口选"保存"→ 第二窗口 sheet 随后出现（串行，无叠加）。
2. sheet 停留期间按 ⌘W/⌘Q → 无新弹窗、无重入（isConfirmingClose + AppKit 模态禁键）。
3. 第二窗口选"不保存" → 退出取消，窗口留存；再次 ⌘Q 可重走流程。
4. 单窗口脏文档 ⌘W → sheet；期间再次 ⌘W → 吞掉；"保存"后窗口关闭。

## 结论落点表

| 活结论 | 落点 |
|---|---|
| 关闭/退出异步确认契约(sheet 回调 + 串行队列 + 复位条件) | `Sources/MDPreview/DocumentWindowController.swift` `beginConfirmClose` 头注释、`AppDelegate.beginTerminateConfirmation` |
| 同步基线 + 过期过滤的单一脏机制 | `web/src/editor.js` listener 注释、`web/src/bridge.js` `setMarkdown` 注释、[risks.md R2](../../../plan/risks.md) |
| 非魔力延时的命名常量与依据 | `DocumentWindowController.Timing`、`Selftest.Polling` |

## 遗留

- 无已知遗留。R2(泵主循环重入)与 R6(魔法延时)在本序内实证消除,计划文档回改留在批次四统一执行。
