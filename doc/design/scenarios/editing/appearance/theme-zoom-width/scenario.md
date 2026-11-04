---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-003
scenario: SCN-0010
domain: 编辑
valueStream: 外观
title: 切换主题、缩放与正文宽度
entries:
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#setAppearanceMode
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#zoomIn
  - CMP-kernel-contract/web/src/kernel/contract/ops.js#HOST_OPS
docs:
  - path: README.md
    heading: 功能特性
  - path: doc/design/architecture.md
    heading: 2.6 代码高亮配色：token 调色板自有化（单一真源）
  - path: doc/requirements/REQ-0008-appearance.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-DISP-001
  - role: R2
    id: TC-DISP-002
  - role: R3
    id: TC-DISP-003
  - role: N1
    id: TC-DISP-004
---

# 切换主题、缩放与正文宽度

## 1. 场景与价值

用户跟随系统深浅色，或在「视图 → 外观」锁定；用 ⌘+ / ⌘− / ⌘0 调整缩放；窗口变窄时正文跟随，但收缩到 860px 下限后出现横向滚动，避免表格/代码挤爆。

结果：不同屏幕、不同环境光下都能读得清，缩放与外观在重启后保留。

## 2. 入口

- `CMP-app-shell#appearance`：`AppDelegate.setAppearanceMode`。
- `CMP-app-shell#zoom`：`DocumentWindowController.zoomIn/zoomOut/zoomReset`。
- `CMP-kernel-document#state`：op `setTheme` / `setZoom`。
- 宽度：`typora.css` 的 `#app` min-width 与视口策略。

## 3. 运行序

流程定义：`FLOW-EDIT-003`。

1. 应用启动读取外观模式与缩放比例。
2. 系统外观变化：未锁定时实时切换 CSS 变量/主题；锁定时忽略。
3. ⌘+/⌘−：更新比例，桥设 `setZoom`，正文 100% 跟随，视觉下限恒定；⌘0 复位。
4. 窗口变窄：正文跟随到 860px 下限，再窄出现横向滚动。
5. 退出/重启：比例与外观锁定持久化。

失败路径：

- 非法缩放值：夹取到允许范围，不进入 NaN/0。
- 宽度小于下限：横向滚动，不压缩表格/代码到不可读。
- 主题切换时编辑器未就绪：就绪后补应用，不永久错色。

## 4. 不可变引用

- 代码高亮 token 调色板浅/深双值，单一规则来源（architecture §2.6）。
- 正文宽度 100% + 860px 下限；缩放下视觉下限恒定。
- 外观/缩放是应用级设置，不是每文档设置。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-DISP-001 | R1 | 自动 | `--selftest` | `PASS 深色主题切换` | present |
| TC-DISP-002 | R2 | 自动 | `--selftest` | `PASS 缩放应用` | present |
| TC-DISP-003 | R3 | 自动 | `--selftest` | `PASS 宽度策略(100%+CSS变量下限)` | present |
| TC-DISP-004 | N1 | 自动/人工 | 缩放到边界、窗口 <860px、重启 | 夹取/横向滚动/持久化，不出现 NaN 或压爆 | missing |

3 正存在；边界/持久化反例未固化，暂 `designed`。

## 6. 验证债

- 缩放上下限、`⌘0` 复位、重启持久化。
- 窄窗 + 表格/代码的横向滚动断言。
- token 调色板已有 selftest，但深浅切换后的对比度未守门。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 缩放/外观/自适应宽度、selftest 主题/缩放/宽度、architecture §2.6。
