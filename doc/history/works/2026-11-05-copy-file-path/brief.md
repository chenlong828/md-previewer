---
layer: history
module: editing
status: frozen
updated: 2026-11-05
---

# 工序 brief：文档右键拷贝文件路径

> 本记录为功能完成后的补录归档。原始需求经历了「点击标题栏文件名」方案的尝试与整体回滚，最终按文档右键菜单落地。

## 1. 需求

2026-11-05 用户提出：在文档右键菜单增加「拷贝文件路径到剪贴板」。

约束：

- 只对已保存文件生效；未保存文档和目录模式没有路径。
- 只写剪贴板，不写文件、不产生脏标记。
- 命令要进现有右键菜单，不另起一套。

## 2. 决策

- 复用 `EditorCommands` 注册表：新增 `copyFilePath` 命令，`inContextMenu: true`、`availableInCode: true`，不追加到菜单栏。
- `buildContextMenu` 在剪贴板组之后、查找组之前插入该项（`fileURL != nil`）；未保存/目录模式不生成。
- 路径统一用 `fileURL.standardizedFileURL.path`（绝对 POSIX 路径，无 `file://`）。
- 不提供 `file://` / 相对路径 / shell 转义变体，不做拷贝成功 toast。
- 测试用命名 `NSPasteboard`，不污染用户剪贴板。

## 3. 影响与契约

- 新增能力 `CMP-app-shell#copy-file-path`。
- 入口：`DocumentWindowController.buildContextMenu`、`copyFilePath`、`copyFilePathAction`。
- 只影响文档右键菜单与剪贴板；不影响文件 IO、编辑、保存、导出、缩略图、抽屉、标题栏。
- 未保存/目录模式走 `fileURL == nil` 分支：菜单项不出现，直接调用拷贝入口返回 false 且不清空剪贴板。

## 4. 任务

| ID | 任务 | 状态 |
|---|---|---|
| T1 | `EditorCommands` 注册 `copyFilePath`，右键菜单追加与校验 | 完成 |
| T2 | `copyFilePath` 写标准化绝对路径；未保存返回 false | 完成 |
| T3 | multiwindow-test：Markdown/代码菜单项、位置、路径写入、未保存反例 | 完成 |
| T4 | REQ-0012 / SCN-0018 / CMP-app-shell 规格 / roadmap / README 同步 | 完成 |
| T5 | `./build.sh debug` 重建 dist，并在打包二进制跑 multiwindow-test | 完成 |

## 5. 验收

- 自动：`--multiwindow-test` 4 项新增断言全过（菜单 2/2、位置、路径、未保存反例）。
- 自动：`--selftest` 全绿，命令注册表 34 条完整。
- 打包：`./build.sh debug` 通过（Node 86 项 + Swift + dist 组装）；打包二进制跑 multiwindow-test 全过。
- 人工：2026-11-05 用户确认右键菜单项可见、点击后路径正确。

## 6. 非目标

- 不做标题栏点击拷贝；不做相对路径/URL/文件名格式选择。
- 不做菜单栏入口、快捷键、拷贝历史或 toast。
- 不为未保存/目录模式伪造路径。
