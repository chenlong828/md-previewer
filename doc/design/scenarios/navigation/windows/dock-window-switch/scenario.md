---
layer: design
module: shell
status: verified
updated: 2026-11-20
flow: FLOW-NAV-003
scenario: SCN-0021
domain: 导航
valueStream: 窗口
title: 从 Dock 菜单切换窗口
entries:
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applicationDockMenu
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#rebuildDockMenu
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#focusDocumentWindow
docs:
  - path: README.md
    heading: 功能特性
  - path: doc/requirements/REQ-0015-dock-menu-window-switch.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-WIN-005
  - role: R2
    id: TC-WIN-006
  - role: R3
    id: TC-WIN-007
  - role: N1
    id: TC-WIN-008
---

# 从 Dock 菜单切换窗口

## 1. 场景与价值

用户同时开着多个文档窗口，在 Dock 图标上右键：菜单顶部列出所有已打开窗口，当前窗口带勾；
点一项即切到该窗口，最小化窗口同时恢复。

结果：多窗口时按名字直接定位目标文档，不必反复 ⌘` 轮换或进「显示所有窗口」网格翻找。
不做的后果见 [REQ-0015](../../../../../requirements/REQ-0015-dock-menu-window-switch.md) §2。

## 2. 入口

- `CMP-app-shell#dock-menu`：`AppDelegate.applicationDockMenu`（系统在展开 Dock 菜单时调用，
  返回自定义条目菜单）。
- `CMP-app-shell#dock-menu-rebuild`：`AppDelegate.rebuildDockMenu`（按当前文档集合与当前窗口
  ——key/main，应用未激活时取最前置窗口——重建条目与勾选）。
- `CMP-app-shell#dock-menu-focus`：`AppDelegate.focusDocumentWindow`（条目动作：激活、恢复最小化、置前）。

## 3. 运行序

流程定义：`FLOW-NAV-003`。

1. 用户按住/右键 Dock 图标 → AppKit 调用 `applicationDockMenu`。
2. `rebuildDockMenu` 按 `documents` 创建顺序生成条目：标题取窗口标题，`representedObject`
   指向窗口控制器，当前窗口（key/main；应用未激活时取最前置窗口）置勾选。
3. 自定义条目显示在标准项（选项 / 显示所有窗口 / 隐藏 / 退出）之前。
4. 用户点条目 → `focusDocumentWindow`：`NSApp.activate`、`deminiaturize`（若最小化）、
   `makeKeyAndOrderFront`。
5. 菜单关闭；下一次展开重新读取窗口集合与当前窗口。

失败路径：

- 无文档窗口（应用即将退出）：菜单不出现自定义条目，只保留标准项。
- 条目对应的窗口在菜单展开期间被关闭：动作对 nil 窗口 no-op，不崩溃、不误激活其它窗口。
- 窗口处于最小化：点击后恢复并置前。
- 应用在后台：点击后激活并前置目标窗口。

## 4. 不可变引用

- 窗口模型不变：单进程单 Dock、每文档独立窗口、外部打开新窗口、⌘O/最近文件替换当前窗口
  （[SCN-0013](../open-and-window/scenario.md)）。
- Dock 标准项由 macOS 附加，本场景不自建「显示所有窗口 / 隐藏 / 退出」。
- 菜单不写文件、不改变文档状态（不产生 `changed`、不触发保存）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-WIN-005 | R1 | 自动 | `--dockmenu-test`（自备临时文档） | 条目数 = 窗口数、条目按创建序指向各窗口（`representedObject` 身份）、标题与窗口标题逐一相等 | present |
| TC-WIN-006 | R2 | 自动 | 同上 | 当前窗口单条 `state == .on`，其余 `.off`；把另一窗口置前后重建，勾选跟随 | present |
| TC-WIN-007 | R3 | 自动 | 同上 | 执行条目动作后该窗口为应用最前窗口且不再最小化（激活环境下 `NSApp.keyWindow` 即它） | present |
| TC-WIN-008 | N1 | 自动 | 同上 | 关闭一个窗口后重建，条目数减一且不含已关闭窗口；同名「未命名」窗口各自成条并定位到自己的窗口 | present |

## 6. 验证债

- Dock 菜单的真实展开/点击手感（右键、菜单项位置、勾选视觉）无法自动断言，需人工点验一次。
- 自检进程未必被系统激活（`NSApp.isActive == false`），自动断言以应用内最前窗口（`orderedWindows`）
  等价“当前窗口”；激活状态下的 key window 语义由真实点击覆盖。

## 7. 变更记录

- 2026-11-20 新建：承接 REQ-0015（用户三选一确认：只列已打开窗口、文件名 + 勾选、不加管理动作）。
