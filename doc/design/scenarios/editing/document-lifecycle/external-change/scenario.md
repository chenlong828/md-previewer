---
layer: design
module: editing
status: draft
updated: 2026-11-04
flow: FLOW-EDIT-001
scenario: SCN-0004
domain: 编辑
valueStream: 文档生命周期
title: 处理磁盘上的外部变更
entries:
  - CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#fileChangedOnDisk
  - CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#startFileMonitor
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDocument
docs:
  - path: doc/design/architecture.md
    heading: 2.3 保存恒定 UTF-8（OQ-2 结论）
  - path: doc/requirements/REQ-0004-persistence.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-EXT-001
  - role: R2
    id: TC-EXT-002
  - role: R3
    id: TC-EXT-003
  - role: N1
    id: TC-EXT-004
---

# 处理磁盘上的外部变更

## 1. 场景与价值

文档打开期间，另一个程序修改了磁盘文件：本地干净时应用自动重载；本地有未保存修改时询问“保留我的修改/重新加载”；文件被删除时明确提示，不静默覆盖。

结果：外部编辑与本地编辑不会互相覆盖。

## 2. 入口

- `CMP-document-io#external-change`：`fileChangedOnDisk` / `startFileMonitor`。
- `CMP-app-shell#open-document`：打开时建立监听基线。

## 3. 运行序

流程定义：`FLOW-EDIT-001`（外部变更分支）。

1. 打开文件后记录修改时间/大小，建立文件监听。
2. 磁盘写入触发事件，防抖等待写入完成。
3. 本地干净：自动重载并重建基线。
4. 本地脏：弹窗让用户选保留或重载；保留则继续监听，重载则丢弃本地修改。
5. 文件被删除/不可读：提示并保留当前内容。

失败路径：

- 监听 fd 打开失败：不阻塞编辑，只失去自动重载。
- 重载读失败：保留当前内容并提示。

## 4. 不可变引用

- 脏文档不自动覆盖；干净文档可自动重载。
- 重载后基线为磁盘内容；保留后基线不变。
- 不改变保存口径（SCN-0003）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-EXT-001 | R1 | 人工 | 打开干净文档，外部写入 | 自动重载，标题/内容更新，不弹窗 | missing |
| TC-EXT-002 | R2 | 人工 | 本地编辑后外部写入，选“保留” | 本地修改保留，不重载 | missing |
| TC-EXT-003 | R3 | 人工 | 本地编辑后外部写入，选“重新加载” | 磁盘内容覆盖，脏标记消失 | missing |
| TC-EXT-004 | N1 | 人工 | 打开后删除文件 | 提示且保留当前内容，不崩溃 | missing |

3 正 1 反都只有人工方案，没有可执行 ID，故本卡 `draft`；不得据此把 REQ-0004 转 `delivered`。

## 6. 验证债

- 需要可注入的文件监听/写事件测试替身，才能把四条变成自动用例。
- 删除/权限错误路径需要构造。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README“文件外部变更监听”、`fileChangedOnDisk`。
