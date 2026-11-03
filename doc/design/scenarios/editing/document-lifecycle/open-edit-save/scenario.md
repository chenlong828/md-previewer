---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-001
scenario: SCN-0002
domain: 编辑
valueStream: 文档生命周期
title: 打开、编辑并保存文档
entries:
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDocument
  - CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#saveDocument
  - CMP-editor/web/src/bridge.js#window.mdbridge
docs:
  - path: doc/design/architecture.md
    heading: 2.2 保存无条件补尾换行
  - path: doc/requirements/REQ-0004-persistence.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-DOC-001
  - role: R2
    id: TC-DOC-002
  - role: R3
    id: TC-DOC-003
  - role: N1
    id: TC-DOC-004
---

# 打开、编辑并保存文档

## 1. 场景与价值

用户打开一个 Markdown，在渲染视图里修改，看到脏标记后保存；纯查看不弹保存询问，撤销回原文恢复干净，关闭时只对真正脏的文档确认。

结果：编辑—保存—关闭闭环不丢内容，也不被误报打扰。

本场景不覆盖编码/规范化细节（SCN-0003）和外部变更（SCN-0004）。

## 2. 入口

- `CMP-app-shell#open-document`：`DocumentWindowController.openDocument`。
- `CMP-document-io#save`：`DocumentWindowController.saveDocument`。
- `CMP-editor#get-markdown`：`window.mdbridge.getMarkdown`。

## 3. 运行序

流程定义：`FLOW-EDIT-001`。

1. 打开：读文件、注入编辑器、建立干净基线；标题/代理图标更新。
2. 编辑：输入触发脏标记；`changed` 消息更新状态栏。
3. 保存：取 Markdown → 图片路径 `forSave` → 规范化 → UTF-8 写盘 → 重建干净基线。
4. 关闭：脏文档弹保存确认；取消则不关闭；保存失败保留窗口。
5. 纯查看：不产生脏标记；撤销回原文后脏标记消失。

失败路径：

- 文件不可读/编码识别失败：明确报错，不注入半内容。
- 保存写盘失败：保留原文件与窗口，提示失败，不标干净。
- 关闭时选择取消：窗口保留。

## 4. 不可变引用

- `architecture.md` §2.2/§2.3 的保存口径（尾换行、UTF-8）。
- 脏基线语义：加载/保存/源码切换后干净；撤销回原文恢复干净。
- 图片路径由 `CMP-image#for-save` 改写；本场景不重复其规则。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-DOC-001 | R1 | 自动 | `--selftest` | `PASS T3 打开文件即脏回归(注入后零误报)` | present |
| TC-DOC-002 | R2 | 自动 | `--selftest` | `PASS D1 markClean 基线等于所见` | present |
| TC-DOC-003 | R3 | 自动 | `--selftest` | `PASS D1 源码模式保存取一致内容` | present |
| TC-DOC-004 | N1 | 人工 | 保存到只读路径/关闭选取消 | 保存失败保留窗口与原文件；取消不关闭 | missing |

3 正存在，反例未固化；暂 `designed`。反例补成可执行脚本后才可 `verified`。

## 6. 验证债

- 保存失败、关闭取消没有自动化；需构造只读目录/注入写失败。
- 真实打开/关闭的窗口生命周期目前靠人工。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README、selftest T3/D1、DocumentWindowController open/save。
