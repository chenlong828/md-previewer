---
layer: works
module: global
status: active
updated: 2026-10-12
---

# 工序：时序耦合与隐式契约治理

消灭"以固定时长代替就绪信号"与"泵主循环等回调"两类模式；它们是慢环境
偶现缺陷（风险 R2/R6）的共同根源。全部改动集中在 Sources/ 侧流程编排，
与 W4（web 拆分）文件不相交。

## 问题清单

### T1 confirmClose 内嵌 RunLoop 泵送等待异步保存（审计 #24，R2）

- 位置：DocumentWindowController.swift:650-682（泵送循环 :668-673）。
- 危害：泵送期间应用继续处理事件，用户可再触发 ⌘W/菜单/拖放，重入
  保存与打开路径；`isLoadingContent` 等守卫位在嵌套下语义失效。
- 方向：保存确认改为异步流程——`windowShouldClose` 返回 false 并自行发起
  sheet 式确认，确认结果回调里续做 `performClose`/`close()`；退出流程
  （applicationShouldTerminate）同理逐窗口异步确认后再 `replyToApplicationShouldTerminate`。

### T2 魔法延时三处（审计 #25，R6）

| 位置 | 现状 | 方向 |
|---|---|---|
| DocumentWindowController.swift:488-491 | PDF 导出临时关 AutoLayout 拉高 WebView 后固定等 0.35s | 以内容高度测量回调 + WebView 几何就绪信号驱动；确需一帧 settle 的用下一次 RunLoop tick 或 CATransaction 完成回调 |
| DocumentWindowController.swift:427-429 | 缩放后 1.2s 盲等再 requestStats 恢复状态栏 | 缩放设置后直接调 `requestStats()`（消息本身有 250ms 节流，main.js:117-124），删除盲等 |
| DocumentWindowController.swift:597 | 文件监听 0.4s 防抖 | 保留防抖但提取为命名常量并注明依据（防抖是合理模式，魔法裸数字不是） |

### T3 脏标记双重抑制机制并存（审计 #26）

- 位置：main.js:93-95（pendingBaseline 声明）、:311-318（listener 判定）、
  :869-878（setMarkdown 双置位 + queueMicrotask 清 suppressChange）。
- 危害：两套机制语义重叠、清零时机不同（一个等下一次 listener 回调、一个微任务窗），
  重构加载路径漏掉任一即"打开文件即报已修改"。
- 方向：收敛为单一机制——加载序号（generation counter）：setMarkdown 时
  `loadSeq++` 并记录当前 seq，listener 回调携带 seq 比对即可同时表达
  "基线待定"与"抑制上报"，删除另一套。

### T4 pendingOpenURL 双读文件（审计 #27）

- 位置：DocumentWindowController.swift:166-184（未就绪时读文本后丢弃只留 URL）、
  :218-221（就绪后重读）。
- 危害：两次读取之间文件可被外部修改（TOCTOU）；大文件双读。
- 方向：就绪前只记 URL 不读内容（现状已如此），但删去"先读后弃"的分支——
  `openDocument` 在 `!isReady` 时直接暂存返回，读文件动作只在补载时发生一次。

### T5 argvFileHandled 跨回调顺序耦合（审计 #28）

- 位置：AppDelegate.swift:15, 41-46, 105-119；依赖 `application(_:openFile:)`
  晚于 `applicationDidFinishLaunching` 的 AppKit 时序防 CLI 双开。
- 方向：不改变机制（AppKit 时序可靠），但把该不变量写成显式注释 + 防御断言
  （openFile 到达时若 CLI 已开过同一 URL 则去重），并补进 selftest 的启动矩阵说明。

### T6 状态栏 label 双职责 + 全局监视器无人管理（审计 #19、#20）

- 位置：statusLabel 平时词数、缩放时百分比（DocumentWindowController.swift:314, 425）；
  EditorWebView.swift:39-57 每实例两个全局事件监视器且 `rightMouseDown` 句柄丢弃，
  多窗口下事件穿越 N 个监视器；:30-31 注释与代码（关手势）不对应。
- 方向：状态栏拆分字段（词数区/缩放区各自短暂数值由同一渲染函数管理）；
  监视器句柄存数组、`deinit`/窗口关闭时移除；修正漂移注释。

## 验收标准

- [ ] 关闭/退出流程：确认弹窗期间再触发 ⌘W/⌘Q 无重复弹窗、无重入保存
      （selftest 或手动脚本留档）
- [ ] PDF 导出无固定 sleep；慢速模拟（大文档）下导出完整
- [ ] main.js 脏抑制单机制；"打开文件即脏"回归断言通过
- [ ] 全仓 `grep -n 'asyncAfter'` 只剩有命名常量且注明依据的用点
- [ ] selftest 全部通过；`./build.sh` 通过

## 依赖与顺序

- 前置：[W3 consolidate-duplication](../2026-10-12-consolidate-duplication/brief.md) 收口
  （同在 DocumentWindowController.swift 密集改动，顺序执行避免冲突）。
- 与 W4 可并行。
