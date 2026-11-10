---
layer: design
module: editing
status: verified
updated: 2026-11-10
flow: FLOW-EDIT-002
scenario: SCN-0008
domain: 编辑
valueStream: 富文本编辑
title: 编辑表格的行与列
entries:
  - CMP-kernel-editor/web/src/kernel/components/editor/tables.js#tableCommandImpls
  - CMP-kernel-editor/web/src/kernel/components/editor/commands.js#commandRegistry
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#tableCommand
  - CMP-app-shell/Sources/MDPreview/EditorWebView.swift#pagePoint
docs:
  - path: doc/design/architecture.md
    heading: 2.8 右键菜单定位：坐标口径
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
  - role: R1
    id: TC-TBL-005
  - role: R2
    id: TC-TBL-006
---

# 编辑表格的行与列

## 1. 场景与价值

光标在表格单元格内时，用户通过格式/右键菜单在上/下插入行、左/右插入列，删除当前行/列/整表；插入后光标落入新单元格。

结果：不手写 Markdown 表格语法也能改结构，且不会把表格改坏。

## 2. 入口

- `CMP-editor#table`：`tableCommandImpls`。
- `CMP-app-shell#menu-commands`：表格菜单/右键动作。
- `CMP-app-shell#context-menu-position`：右键先定位光标（`EditorWebView.pagePoint` → `focusAt`），再构建菜单。
- `CMP-editor#selection-info`：`inTable` 状态决定菜单可用性。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（表格分支）。

1. 光标进入单元格，`selinfo` 上报 `inTable=true`，右键菜单追加行列操作。
2. 右键：`EditorWebView` 把事件窗口坐标换算为页面视口坐标（flipped 视图不二次翻转），`focusAt` 把选区放到点击处并聚焦编辑器；菜单的 `inTable` 由该选区判定。
3. 命令经桥到 `tableCommandImpls`，按当前表格深度操作。
4. 插入行/列：新单元格为空，光标进入新行/列；删除行/列/整表：保持剩余表格结构合法；整表删除后回到普通段落。
5. `changed` 上报，脏标记更新。

失败路径：

- 光标不在表格内（含右键落在表格外）：命令 no-op，不插入孤立行列。
- 表格边界（首行/末列）：按方向夹取或 no-op，不越界。
- 源码模式：表格命令按实现不可用/降级，不破坏文档。

## 4. 不可变引用

- 表格命令名双端一致：`EditorCommands` 与 `tableCommandImpls`。
- 表格外 no-op。
- 插入后光标位置符合“新行/新列”语义：连续插入沿同一方向累积，删除作用于“当前行”。
- 右键定位：菜单行列命令必须作用于**点击的单元格所在行/列**；点击点换算后必须命中同一单元格（含单元格内边距），不受视口缩放/滚动影响。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-TBL-001 | R1 | 自动 | `--selftest` | `PASS 表格-插入行命令` | present |
| TC-TBL-002 | R2 | 自动 | `--selftest` | `PASS 表格-插入列命令` | present |
| TC-TBL-003 | R3 | 自动 | `--selftest` | `PASS 表格-删除行命令` / `删除列命令` | present |
| TC-TBL-004 | N1 | 自动 | `--selftest` | 表格外执行 no-op，文档不变 | present |
| TC-TBL-005 | R1 | 自动 | `--context-menu-test` | 合成右键第 1/2/3 行与内边距：光标在该行；删除/插入只作用于该行；列删除只移除该列 | present |
| TC-TBL-006 | R2 | 自动 | `--selftest` + `web npm test` | 插入后光标进入新行/新列（连续两次插入的 row/col 递增） | present |

## 6. 验证债

- 单元格边框（共享 1px 分隔线）恰好压线的点击归属未固化；现按 `posAtCoords` 就近取位置，内边距点击已验证。
- 右键菜单没有行高亮浮层；“当前行”靠 caret 呈现，视觉强调未做。
- 真机右键手感已由用户于 2026-11-10 验收通过（R8 关闭）。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 表格编辑、selftest 表格用例、multiwindow-test。
- 2026-11-10 修复右键定位：flipped WKWebView 的页面坐标不再二次翻转；`focusAt` 聚焦编辑器显示 caret；插入行列后光标进入新单元格。新增 TC-TBL-004～006，来源 `--context-menu-test` 与 selftest。
