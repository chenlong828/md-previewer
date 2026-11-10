---
layer: requirements
module: shell
status: delivered
updated: 2026-11-06
---

# REQ-0013：文档右键在 Finder 中定位文件

**类型**：feature

## 1. 场景叙述

用户打开一个已保存的 Markdown 或代码文件，在正文上右键，选择「用 Finder 打开到指定位置」，Finder 打开并选中当前文件；用户可直接在 Finder 里重命名、移动、查看同级文件或拖拽。

未保存的新文档和目录模式没有文件路径，菜单里不出现该项。

## 2. 价值

不做的后果：想从当前文档跳到文件所在位置，必须切到 Finder 再按目录逐层找，或从标题栏代理图标间接进入；文件层级较深时路径成本很高。

## 3. 非目标

- 不新增第二套 Finder 实现：复用文件菜单既有的 `revealInFinderAction`。
- 不改变文件菜单「在 Finder 中显示」在目录模式下定位抽屉根目录的行为。
- 不为未保存文档 / 目录模式在右键菜单里伪造目标。
- 不打开新的 Finder 窗口去浏览整个目录；只选中当前文件。
- 不做“文件已移动/删除”的恢复、报错或 toast。
- 不写文件、不产生脏标记、不影响撤销栈。

## 4. 行为约定

- 菜单项固定为「用 Finder 打开到指定位置」，紧跟「拷贝文件路径到剪贴板」下方。
- 仅当窗口对应一个已保存文件时出现；Markdown 与代码文档都出现。
- 点击后调用 `NSWorkspace.activateFileViewerSelecting`，在 Finder 中选中当前文件。
- 未保存文档：右键菜单项不出现；直接调用定位入口返回 false，且不拉起 Finder。
- 目录模式：右键菜单项不出现；文件菜单既有入口仍定位抽屉根目录（不是本需求新增的右键入口）。
- 文件菜单的「在 Finder 中显示」保持原行为：文件模式定位文件，目录模式定位抽屉根目录。

## 5. 影响场景

| 场景 | 状态 | 本次新增/修改的断言 |
|---|---|---|
| [SCN-0019 从文档右键在 Finder 中定位文件（新建）](../design/scenarios/editing/document-lifecycle/reveal-in-finder/scenario.md) | verified | 菜单项出现、位于拷贝路径下方、传入当前文件 URL、未保存反例 |

受影响行为：文档右键菜单、Finder 选中项、文件菜单既有命令的校验。不影响文件 IO、编辑、保存、导出、缩略图、抽屉、标题栏。

## 6. 验收

验收 = SCN-0019 `verified` + §4 约束未被违反。

自动化：

- `--multiwindow-test`：Markdown/代码两个文档的 Finder 菜单项 2/2、位于拷贝路径之后、定位回调收到标准化文件 URL、未保存不显示且不定位。
- `--selftest`：命令注册表完整（含 `revealInFinder`），无响应缺失。

人工：点击菜单项，确认 Finder 窗口打开并选中当前文件（本次构建后确认）。

## 7. 澄清记录

- 2026-11-06 用户要求：在「拷贝文件路径」菜单项下面增加「用 Finder 打开到指定位置」，打开 Finder 窗口并定位当前阅读的文件。
- 2026-11-06 复用既有文件菜单的 `revealInFinderAction`；新增右键入口，不复制 Finder 调用。

## 8. 状态

`delivered`（SCN-0019 已 verified）。
