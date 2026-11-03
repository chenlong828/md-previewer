---
layer: design
module: shell
status: designed
updated: 2026-11-04
flow: FLOW-NAV-002
scenario: SCN-0013
domain: 导航
valueStream: 窗口
title: 多窗口与外部打开
entries:
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#openInNewWindow
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDocument
  - CMP-app-shell/Sources/MDPreview/main.swift#args
docs:
  - path: README.md
    heading: 功能特性
  - path: doc/requirements/REQ-0006-windows.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-WIN-001
  - role: R2
    id: TC-WIN-002
  - role: R3
    id: TC-WIN-003
  - role: N1
    id: TC-WIN-004
---

# 多窗口与外部打开

## 1. 场景与价值

用户用 ⌘N、拖放、Finder、命令行或目录模式打开多个文档：外部打开默认新窗口，⌘O/最近文件在当前窗口替换；应用单进程单 Dock，每个文档一个独立窗口。

结果：可并排对照多个文档，又不会出现重复窗口/多个 Dock 图标。

## 2. 入口

- `CMP-app-shell#new-window`：`AppDelegate` 新建窗口。
- `CMP-app-shell#open-document`：`DocumentWindowController.openDocument` / `openInNewWindow`。
- `CMP-app-shell#multi-window`：`main.swift` 的启动参数路由。

## 3. 运行序

流程定义：`FLOW-NAV-002`。

1. 启动：无参数开空白窗口；文件参数开该文件；目录参数进目录模式。
2. 外部打开（CLI/拖放/Finder/文档链接）：默认新窗口，标题=文件名。
3. ⌘N：新建空白窗口。
4. ⌘O/最近文件：当前窗口替换打开，不新增窗口。
5. 同一文档：不重复开两个窗口。
6. 退出：所有脏窗口逐个确认。

失败路径：

- 同一文件被外部重复打开：聚焦已有窗口，不创建副本。
- 目录模式窗口再开文件：退出目录模式并覆盖当前窗口。
- 窗口数超过屏幕：正常多窗口管理，不强制合并。

## 4. 不可变引用

- 单进程单 Dock；每文档独立窗口。
- 外部打开=新窗口；⌘O/最近=当前窗口替换。
- 目录模式只占一个窗口，双击文件退出目录模式。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-WIN-001 | R1 | 自动 | `--multiwindow-test --fileA=a.md --fileB=b.md` | `[MULTIWINDOW] PASS 窗口数量为 2` | present |
| TC-WIN-002 | R2 | 自动 | 同上 | `[MULTIWINDOW] PASS 窗口标题不重复` | present |
| TC-WIN-003 | R3 | 人工 | Finder/拖放/CLI 打开第三个文件 | 新窗口出现，单 Dock | missing |
| TC-WIN-004 | N1 | 自动/人工 | 同一文件再次外部打开；⌘O 打开 | 不重复窗口；⌘O 替换当前 | missing |

2 正有自动入口；R3/N1 未固化，暂 `designed`。

## 6. 验证债

- 单 Dock 与“同一文件不重复窗口”没有自动断言。
- ⌘O/最近文件替换路径需要脚本化。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 多窗口、`AppDelegate` 打开路由、multiwindow-test。
