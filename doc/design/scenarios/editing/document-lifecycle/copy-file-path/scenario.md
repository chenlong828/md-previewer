---
layer: design
module: editing
status: verified
updated: 2026-11-05
flow: FLOW-EDIT-001
scenario: SCN-0018
domain: 编辑
valueStream: 文档生命周期
title: 从文档右键菜单拷贝文件路径
entries:
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#buildContextMenu
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#copyFilePath
  - CMP-app-shell/Sources/MDPreview/EditorCommands.swift#EditorCommands
docs:
  - path: README.md
    heading: 主要功能
  - path: doc/requirements/REQ-0012-copy-file-path.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-COPY-001
  - role: R2
    id: TC-COPY-002
  - role: R3
    id: TC-COPY-003
  - role: N1
    id: TC-COPY-004
---

# 从文档右键菜单拷贝文件路径

## 1. 场景与价值

用户在已保存的文档正文上右键，菜单底部出现「拷贝文件路径到剪贴板」；点击后当前文件的绝对路径进入系统剪贴板，可直接粘贴到终端或其他应用。

结果是：拿到路径不必打开存储面板、切到 Finder 或手动拼目录，一次右键 + 一次点击完成。

## 2. 入口

- `CMP-app-shell#copy-file-path`：`DocumentWindowController.buildContextMenu` 在编辑命令之后追加菜单项。
- `CMP-app-shell#copy-file-path`：`DocumentWindowController.copyFilePath` 写剪贴板；`copyFilePathAction` 是菜单选择器。
- `CMP-app-shell#menu-commands`：`EditorCommands` 注册 `copyFilePath`（`inContextMenu: true`、`availableInCode: true`），与菜单共用同一份定义与校验。

## 3. 运行序

流程定义：`FLOW-EDIT-001`。

1. 打开已保存文件 → `fileURL` 非空。
2. 在正文上右键 → web 端 `contextMenuHandler` 先 `focusAt` 定位光标，再调用 `buildContextMenu(inTable:)`。
3. `buildContextMenu` 按注册表生成编辑命令组；`fileURL != nil` 时在剪贴板组之后插入「拷贝文件路径到剪贴板」，Finder 定位紧随其后（SCN-0019）。
4. 点击菜单项 → `copyFilePathAction` → `copyFilePath` → 清空并写入 `fileURL.standardizedFileURL.path`。
5. 菜单校验：`validateMenuItem` 命中注册表分支，`copyFilePath` 只判断 `fileURL != nil`，不要求编辑器就绪。

失败路径：

- 未保存的新文档 / 目录模式：`fileURL == nil`，菜单项不生成；直接调用 `copyFilePath` 返回 false，不清空剪贴板。
- 剪贴板写入失败：返回 false，不写文件、不弹窗；文档内容与脏标记不变。
- 打开后文件被移动/删除：仍拷贝打开时记录的 `fileURL` 路径，与窗口标题语义一致。

## 4. 不可变引用

- `EditorCommands` 是菜单栏与右键菜单的唯一命令真源；本命令不追加到菜单栏。
- 文档内容、脏标记、撤销栈、保存、导出、图片资源、抽屉、缩略图、窗口标题栏均不因本场景改变。
- 路径格式固定为绝对 POSIX 路径（`standardizedFileURL.path`），不提供 `file://`/相对路径变体。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-COPY-001 | R1 | 自动 | `--multiwindow-test` | `PASS 文档右键菜单含拷贝文件路径(2/2)`、`PASS Finder 定位位于拷贝路径之后(索引 8/9)`；Markdown 文档菜单有该项且 action/target 已接好 | present |
| TC-COPY-002 | R2 | 自动 | `--multiwindow-test` | 代码文档（`.py`）同样出现该项（`availableInCode`） | present |
| TC-COPY-003 | R3 | 自动 | `--multiwindow-test` | `PASS 右键拷贝文件路径(/tmp/mdp-a.md)`：写入值等于 `fileURL.standardizedFileURL.path`，无 `file://` 前缀 | present |
| TC-COPY-004 | N1 | 自动 | `--multiwindow-test` | `PASS 未保存文档不显示/不拷贝文件路径`：菜单无该项、`copyFilePath` 返回 false、剪贴板哨兵值不变 | present |

补充守门：`--selftest` 的「命令注册表完整」断言 `copyFilePath` 有对应 selector，无重无漏。

## 6. 验证债

- 未用真实鼠标模拟 `NSMenu` 弹层点击；菜单项的 action/target 与执行体 `copyFilePath` 已分别断言。2026-11-05 用户已手工验收：右键菜单项可见、点击后路径正确。
- 目录模式（无文档文件）与未保存文档共用 `fileURL == nil` 分支，反例覆盖未保存路径；目录模式未单独建用例。

## 7. 变更记录

- 2026-11-05 新建：用户否决标题栏点击方案，改为文档右键菜单「拷贝文件路径到剪贴板」；未保存文档不显示。
