---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-002
scenario: SCN-0006
domain: 编辑
valueStream: 富文本编辑
title: 在文档内查找
entries:
  - CMP-kernel-find/web/src/kernel/components/find/find-bar.js#openFindBar
  - CMP-kernel-find/web/src/kernel/components/find/find.js#searchDoc
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openFindBar
docs:
  - path: doc/design/architecture.md
    heading: 3. 桥协议
  - path: doc/requirements/REQ-0002-editing.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-FIND-001
  - role: R2
    id: TC-FIND-002
  - role: R3
    id: TC-FIND-003
  - role: N1
    id: TC-FIND-004
---

# 在文档内查找

## 1. 场景与价值

用户按 ⌘F 呼出查找栏，输入查询后看到 `当前/总数`，用 Enter/Shift+Enter 在命中项间跳转并高亮当前项；源码模式同样可用。

结果：长文档内定位不依赖肉眼滚动。

## 2. 入口

- `CMP-editor#find`：`openFindBar` / `searchDoc`。
- `CMP-app-shell#menu-commands`：⌘F 菜单动作。
- `CMP-editor#source-mode`：源码模式查找路径。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（查找分支）。

1. ⌘F 打开查找栏，焦点进入输入框。
2. 输入查询：渲染模式用 ProseMirror decorations 标记命中；源码模式扫描文本。
3. 更新 `当前/总数`；Enter/Shift+Enter 调 `stepFind`。
4. 当前命中滚动到可视区并高亮；无命中显示 0/0。
5. Esc/关闭按钮清除装饰并隐藏查找栏。

失败路径：

- 无命中：计数 0，不抛错，不改变文档。
- 源码/渲染切换：查找栏状态按实现重置或保持，不产生脏标记。

## 4. 不可变引用

- 查找不修改文档；不产生脏标记。
- 命中计数与跳转顺序对同一查询稳定。
- 源码模式与渲染模式使用同一查询语义（大小写选项一致）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-FIND-001 | R1 | 自动 | `--selftest` | `PASS 查找命中计数` | present |
| TC-FIND-002 | R2 | 自动 | `--selftest` | `PASS 查找下一处` | present |
| TC-FIND-003 | R3 | 自动 | `--selftest` | `PASS 查找高亮与定位` | present |
| TC-FIND-004 | N1 | 自动 | `--selftest`（待补） | 无命中时计数 0、文档不变、不抛错 | missing |

3 正存在；无命中反例未固化，暂 `designed`。

## 6. 验证债

- 无命中、空查询、大小写切换、源码模式无命中的反例。
- 查找栏关闭后装饰是否清理干净。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 查找、selftest 查找用例。
