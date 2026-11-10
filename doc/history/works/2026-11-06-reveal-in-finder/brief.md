---
layer: history
module: editing
status: frozen
updated: 2026-11-06
---

# 工序 brief：文档右键在 Finder 中定位文件

> 本记录为功能完成后的补录归档。

## 1. 需求

2026-11-06 用户要求：在「拷贝文件路径到剪贴板」菜单项下面增加「用 Finder 打开到指定位置」，点击后打开 Finder 窗口并定位到当前阅读的文件。

约束：

- 只对已保存文件生效；未保存文档和目录模式没有文件路径。
- 只定位，不写文件、不产生脏标记。
- 复用既有 Finder 命令，不新增第二套实现。
- 文件菜单在目录模式下定位抽屉根目录的既有行为不能被破坏。

## 2. 决策

- 复用文件菜单既有的 `revealInFinderAction`，把执行体抽成可测试的 `revealInFinder(using:)`。
- 新增 `revealTargetURL` 统一目标：文件模式 `fileURL`，目录模式 `drawerRootURL`。
- `EditorCommands` 注册 `revealInFinder`：`inContextMenu: true`、`availableInCode: true`；右键菜单只在 `fileURL != nil` 时把 `[copyFilePath, revealInFinder]` 挂在剪贴板组之后。
- `validateMenuItem` 对 `revealInFinder` 使用 `revealTargetURL != nil`，保证文件菜单目录模式仍可用；`copyFilePath` 仍只认 `fileURL`。
- 测试通过注入闭包断言传给 Finder 的 URL，不在自动测试里真的拉起 Finder。

## 3. 影响与契约

- 新增能力 `CMP-app-shell#reveal-in-finder`。
- 入口：`DocumentWindowController.buildContextMenu`、`revealInFinder`、`revealTargetURL`、`revealInFinderAction`。
- 右键菜单新增一项，位于拷贝路径正下方；未保存/目录模式不生成。
- 文件菜单「在 Finder 中显示」语义不变：文件模式定位文件，目录模式定位抽屉根目录。
- 只影响右键菜单、Finder 选中项与文件菜单校验；不影响文件 IO、编辑、保存、导出、缩略图、抽屉、标题栏。

## 4. 任务

| ID | 任务 | 状态 |
|---|---|---|
| T1 | `EditorCommands` 注册 `revealInFinder`；右键菜单加入 `[copyFilePath, revealInFinder]` | 完成 |
| T2 | 复用并抽取 `revealInFinder` / `revealTargetURL`；校验不破坏目录模式 | 完成 |
| T3 | multiwindow-test：菜单项、拷贝下方位置、URL 参数、未保存反例 | 完成 |
| T4 | REQ-0013 / SCN-0019 / CMP-app-shell 规格 / roadmap / README 同步 | 完成 |
| T5 | `./build.sh debug` 重建 dist，并在打包二进制跑 multiwindow-test | 完成 |

## 5. 验收

- 自动：`--multiwindow-test` 5 项新增断言全过（Finder 菜单 2/2、位于拷贝下方、URL、未保存反例、拷贝路径回归）。
- 自动：`--selftest` 全绿，命令注册表 35 条完整。
- 打包：`./build.sh debug` 通过；打包二进制跑 multiwindow-test 全过。
- 人工：点击右键项确认 Finder 打开并选中当前文件（构建后确认）。

## 6. 非目标

- 不做第二套 Finder 调用；不改文件菜单目录模式的行为。
- 不做「文件已移动/删除」的恢复、报错或 toast。
- 不做新的 Finder 窗口/目录浏览布局。
