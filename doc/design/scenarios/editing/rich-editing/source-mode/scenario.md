---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-002
scenario: SCN-0007
domain: 编辑
valueStream: 富文本编辑
title: 在渲染视图与源码模式之间切换
entries:
  - CMP-kernel-contract/web/src/kernel/contract/ops.js#HOST_OPS
  - CMP-kernel-editor/web/src/kernel/components/editor/editor.js#toggleSource
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleSourceMode
docs:
  - path: doc/design/architecture.md
    heading: 3. 桥协议
  - path: doc/requirements/REQ-0002-editing.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-SRC-001
  - role: R2
    id: TC-SRC-002
  - role: R3
    id: TC-SRC-003
  - role: N1
    id: TC-SRC-004
---

# 在渲染视图与源码模式之间切换

## 1. 场景与价值

用户按 ⌘/ 在排版视图与 Markdown 源码之间切换：源码模式显示原文、可直接编辑，切回渲染后修改生效；保存时两种模式取到一致内容。

结果：需要精确改语法时不用离开应用，也不担心切换丢内容。

## 2. 入口

- `CMP-editor#source-mode`：`toggleSource`。
- `CMP-app-shell#menu-commands`：⌘/ 动作。
- `CMP-editor#get-markdown`：保存取一致内容。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（源码分支）。

1. ⌘/ 切到源码：显示当前 Markdown 原文。
2. 编辑：文本域/源码视图修改；切回渲染前把源码写回文档。
3. 切回渲染：重新渲染并上报 `changed`（若有变化）。
4. 保存：无论当前模式，取同一份 Markdown。
5. 源码模式下查找可用（SCN-0006）。

失败路径：

- 源码内容非法：不崩溃；按编辑器能力尽量保留/提示。
- 切回时解析失败：保留源码，不丢用户输入。
- 未修改切换：不产生脏标记。

## 4. 不可变引用

- 源码模式与渲染模式共享同一文档内容。
- 保存内容与所见一致（D1）。
- 切换不改变图片路径/资源。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-SRC-001 | R1 | 自动 | `--selftest` | `PASS 源码模式显示原文` | present |
| TC-SRC-002 | R2 | 自动 | `--selftest` | `PASS 源码模式编辑回写` | present |
| TC-SRC-003 | R3 | 自动 | `--selftest` | `PASS D1 源码模式保存取一致内容` | present |
| TC-SRC-004 | N1 | 自动 | `--selftest`（待补） | 未修改切换不脏；非法源码不丢内容 | missing |

3 正存在；反例未固化，暂 `designed`。

## 6. 验证债

- 未修改切换的脏标记断言。
- 非法源码/解析失败的保留策略。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 源码模式、selftest 源码/D1 用例。
