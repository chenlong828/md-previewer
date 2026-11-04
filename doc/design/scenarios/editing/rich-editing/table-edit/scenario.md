---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-002
scenario: SCN-0008
domain: 编辑
valueStream: 富文本编辑
title: 编辑表格的行与列
entries:
  - CMP-kernel-editor/web/src/kernel/components/editor/tables.js#tableCommandImpls
  - CMP-kernel-editor/web/src/kernel/components/editor/commands.js#commandRegistry
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#tableCommand
docs:
  - path: doc/design/architecture.md
    heading: 3. 桥协议
  - path: doc/requirements/REQ-0002-editing.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-TBL-001
  - role: R2
    id: TC-TBL-002
  - role: R3
    id: TC-TBL-003
  - role: N1
    id: TC-TBL-004
---

# 编辑表格的行与列

## 1. 场景与价值

光标在表格单元格内时，用户通过格式/右键菜单在上/下插入行、左/右插入列，删除当前行/列/整表；插入后光标落入新单元格。

结果：不手写 Markdown 表格语法也能改结构，且不会把表格改坏。

## 2. 入口

- `CMP-editor#table`：`tableCommandImpls`。
- `CMP-app-shell#menu-commands`：表格菜单/右键动作。
- `CMP-editor#selection-info`：`inTable` 状态决定菜单可用性。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（表格分支）。

1. 光标进入单元格，`selinfo` 上报 `inTable=true`，右键菜单追加行列操作。
2. 命令经桥到 `tableCommandImpls`，按当前表格深度操作。
3. 插入行/列：新单元格为空，光标落入新位置。
4. 删除行/列/整表：保持剩余表格结构合法；整表删除后回到普通段落。
5. `changed` 上报，脏标记更新。

失败路径：

- 光标不在表格内：命令 no-op，不插入孤立行列。
- 表格边界（首行/末列）：按方向夹取或 no-op，不越界。
- 源码模式：表格命令按实现不可用/降级，不破坏文档。

## 4. 不可变引用

- 表格命令名双端一致：`EditorCommands` 与 `tableCommandImpls`。
- 表格外 no-op。
- 插入后光标位置符合“新行/新列”语义。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-TBL-001 | R1 | 自动 | `--selftest` | `PASS 表格-插入行命令` | present |
| TC-TBL-002 | R2 | 自动 | `--selftest` | `PASS 表格-插入列命令` | present |
| TC-TBL-003 | R3 | 自动 | `--selftest` | `PASS 表格-删除行命令` / `删除列命令` | present |
| TC-TBL-004 | N1 | 自动 | `--selftest`（待补） | 表格外执行 no-op，文档不变 | missing |

3 正存在；表格外反例未固化，暂 `designed`。

## 6. 验证债

- 表格外 no-op、表格边界、源码模式下的行为。
- 右键菜单在 `inTable` 切换时的可用性已有 multiwindow 部分覆盖，但缺独立断言。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 表格编辑、selftest 表格用例、multiwindow-test。
