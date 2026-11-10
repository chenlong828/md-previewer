---
layer: design
module: editing
status: verified
updated: 2026-11-06
flow: FLOW-EDIT-001
scenario: SCN-0019
domain: 编辑
valueStream: 文档生命周期
title: 从文档右键在 Finder 中定位文件
entries:
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#buildContextMenu
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#revealInFinder
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#revealTargetURL
  - CMP-app-shell/Sources/MDPreview/EditorCommands.swift#EditorCommands
docs:
  - path: README.md
    heading: 主要功能
  - path: doc/requirements/REQ-0013-reveal-in-finder.md
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

# 从文档右键在 Finder 中定位文件

## 1. 场景与价值

用户在已保存的文档正文上右键，菜单里「拷贝文件路径到剪贴板」下方有「用 Finder 打开到指定位置」；点击后 Finder 打开并选中当前文件。

结果是：从阅读位置直接跳到文件的管理位置，重命名、移动、查看同级文件都不用再按目录逐层找。

## 2. 入口

- `CMP-app-shell#reveal-in-finder`：`DocumentWindowController.buildContextMenu` 在 `fileURL != nil` 时把该项挂在拷贝路径下方。
- `CMP-app-shell#reveal-in-finder`：`DocumentWindowController.revealInFinder` 调用 `NSWorkspace.activateFileViewerSelecting`；`revealInFinderAction` 是菜单选择器。
- `CMP-app-shell#reveal-in-finder`：`revealTargetURL` 统一文件模式 / 目录模式的目标：文件模式用 `fileURL`，目录模式用 `drawerRootURL`。
- `CMP-app-shell#menu-commands`：`EditorCommands` 注册 `revealInFinder`（`inContextMenu: true`、`availableInCode: true`），与拷贝路径共用同一份命令定义。

## 3. 运行序

流程定义：`FLOW-EDIT-001`。

1. 打开已保存文件 → `fileURL` 非空。
2. 在正文上右键 → `buildContextMenu(inTable:)` 生成编辑命令组；`fileURL != nil` 时在剪贴板组之后插入 `[copyFilePath, revealInFinder]`。
3. 菜单顺序：拷贝文件路径 → 用 Finder 打开到指定位置 → 查找…。
4. 点击 Finder 项 → `revealInFinderAction` → `revealInFinder` → `revealTargetURL`（文件模式为当前文件）→ `NSWorkspace.activateFileViewerSelecting([standardizedFileURL])`。
5. 菜单校验：`validateMenuItem` 命中注册表分支，`revealInFinder` 只判断 `revealTargetURL != nil`；文件菜单的目录模式因此仍可用。

失败路径：

- 未保存的新文档：`fileURL == nil`，右键菜单不生成两项；直接调用 `revealInFinder` 返回 false，不拉起 Finder。
- 目录模式：右键菜单不生成（没有文件路径）；文件菜单「在 Finder 中显示」仍按 `drawerRootURL` 定位抽屉根目录。
- 文件打开后被移动/删除：仍把打开时记录的 URL 交给 Finder；不额外做恢复或报错。

## 4. 不可变引用

- 复用文件菜单既有 `revealInFinderAction`，不新增第二套 Finder 调用。
- 文件菜单「在 Finder 中显示」的目录模式语义保持不变：目录模式定位抽屉根目录。
- 文档内容、脏标记、撤销栈、保存、导出、图片资源、抽屉、缩略图、标题栏均不因本场景改变。
- 右键菜单只在已保存文件出现；不伪造未保存文档的路径。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-FIND-001 | R1 | 自动 | `--multiwindow-test` | `PASS 文档右键菜单含 Finder 定位(2/2)`、`PASS Finder 定位位于拷贝路径之后(索引 8/9)`；Markdown 菜单项在拷贝路径下方且 action/target 已接好 | present |
| TC-FIND-002 | R2 | 自动 | `--multiwindow-test` | 代码文档（`.py`）同样出现 Finder 项（`availableInCode`） | present |
| TC-FIND-003 | R3 | 自动 | `--multiwindow-test` | `PASS 右键在 Finder 中定位文件(/tmp/mdp-a.md)`：注入闭包收到 `standardizedFileURL`，不真的拉起 Finder | present |
| TC-FIND-004 | N1 | 自动 | `--multiwindow-test` | `PASS 未保存文档不显示/不拷贝/不定位`：菜单无两项、`revealInFinder` 返回 false、回调未触发 | present |

补充守门：`--selftest` 的「命令注册表完整」断言 `revealInFinder` 有对应 selector，无重无漏。

## 6. 验证债

- 未用真实鼠标模拟 `NSMenu` 弹层点击；菜单项 action/target、`revealInFinder` 的 URL 参数均已断言，实际 Finder 弹窗由既有 `NSWorkspace` 命令完成。
- 目录模式的文件菜单行为未新写自动化用例；沿用既有命令，本次只保证 registry 校验不误禁用（`revealTargetURL` 分支）。

## 7. 变更记录

- 2026-11-06 新建：在拷贝路径下方增加「用 Finder 打开到指定位置」，复用文件菜单既有 Finder 命令。
