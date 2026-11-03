---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-002
scenario: SCN-0005
domain: 编辑
valueStream: 富文本编辑
title: 用格式命令编辑文档结构
entries:
  - CMP-editor/web/src/commands.js#commandRegistry
  - CMP-app-shell/Sources/MDPreview/EditorCommands.swift#EditorCommands
  - CMP-editor/web/src/bridge.js#window.mdbridge
docs:
  - path: doc/design/architecture.md
    heading: 3. 桥协议
  - path: doc/requirements/REQ-0002-editing.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-FMT-001
  - role: R2
    id: TC-FMT-002
  - role: R3
    id: TC-FMT-003
  - role: N1
    id: TC-FMT-004
---

# 用格式命令编辑文档结构

## 1. 场景与价值

用户在渲染视图里选中文本或放置光标，通过菜单/右键/快捷键执行标题、正文、引用、列表、代码块、分割线等格式命令；菜单与右键共用同一命令表。

结果：不切源码也能完成结构编辑，新增命令只改一处。

## 2. 入口

- `CMP-editor#format-command`：`commandRegistry` 的格式命令。
- `CMP-app-shell#menu-commands`：`EditorCommands` 菜单/右键规格。
- `CMP-editor#init`：命令经桥到达编辑器。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（格式分支）。

1. 菜单/右键/快捷键命中 `EditorCommands` 动作。
2. Swift 经桥调用 `window.mdbridge.formatCommand(name, payload)`。
3. web 在 `commandRegistry` 查表执行；光标/选区更新。
4. `changed` 上报，脏标记与状态栏更新。

失败路径：

- 未知命令：no-op，不改变文档。
- 光标位置不允许：命令返回 false/no-op，不抛错。
- 源码模式：结构命令按编辑器当前能力执行或明确不可用。

## 4. 不可变引用

- 命令名双端一致：Swift `EditorCommands` 与 web `commandRegistry`。
- 格式命令不改变未选中的内容。
- 源码模式与渲染模式共享同一文档模型。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-FMT-001 | R1 | 自动 | `--selftest` | `PASS 桥命令行为:标题1动作可运行` | present |
| TC-FMT-002 | R2 | 自动 | `--selftest` | `PASS 桥命令行为:标题2动作可运行` | present |
| TC-FMT-003 | R3 | 自动 | `--selftest` | `PASS 桥命令行为:正文动作可运行` | present |
| TC-FMT-004 | N1 | 自动 | `--selftest`（待补） | 未知/不可用命令 no-op，文档不变 | missing |

3 正存在；反例未固化，暂 `designed`。

## 6. 验证债

- 未知命令、源码模式下不可用命令的 no-op 反例。
- 命令注册表完整性已有断言，但“新增命令只改一处”仍需契约测试。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 格式菜单、`EditorCommands`、selftest 桥命令。
