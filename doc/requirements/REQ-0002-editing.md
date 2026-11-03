---
layer: requirements
module: editing
status: accepted
updated: 2026-11-04
---

# REQ-0002：单窗口所见即所得 Markdown 编辑

**类型**：feature

## 1. 场景叙述

当用户打开一篇 Markdown 时，直接在排版结果上编辑：标题、引用、列表、代码块、表格、数学公式、Mermaid 图表都以最终样式呈现；需要看源码时用 ⌘/ 切换，需要定位时用 ⌘F 查找，需要改表格时用格式/右键菜单插入行列。

结果是：一次只开一个文档、不切预览分栏，也能完成日常 Markdown 写作与结构编辑。

## 2. 价值

不做的后果：用户要在源码与预览之间反复切换，或者只能看到纯文本；表格/数学/图表无法所见即所得，编辑长文档的注意力被界面切换切碎。

## 3. 非目标

- 不做多标签、分栏预览、协同编辑、移动端。
- 不手写 Markdown 解析器；复用 Milkdown/remark 生态。
- 不做 Vim/Emacs 键位、插件市场、自定义主题编辑器。
- 不做源码模式的语法高亮/补全（只做原文编辑与保存一致）。

## 4. 行为约定

- 单窗口单文档；⌘N 新建、⌘O/最近文件替换当前文档。
- 格式命令由 `EditorCommands` 单一命令表驱动，菜单与右键共用。
- 源码模式与渲染模式保存取一致内容；列表保存为每级 4 空格，首行标记紧凑。
- 查找在渲染与源码模式都可用，显示 `当前/总数`，Enter/Shift+Enter 跳转。
- 表格命令只对表格内光标生效；表格外 no-op。
- 数学/ Mermaid/代码高亮全部本地渲染，不依赖网络。

## 5. 影响场景

| 场景 | 状态 | 本次新增/修改的断言 |
|---|---|---|
| [SCN-0005 格式命令](../design/scenarios/editing/rich-editing/format-commands/scenario.md) | designed | 标题/正文/引用/列表/代码/分割线命令可执行，菜单与桥一致 |
| [SCN-0006 文档内查找](../design/scenarios/editing/rich-editing/find/scenario.md) | designed | 命中计数、跳转、高亮、关闭；无命中不报错 |
| [SCN-0007 源码模式](../design/scenarios/editing/rich-editing/source-mode/scenario.md) | designed | 显示原文、编辑回写、保存一致；非法内容不破坏文档 |
| [SCN-0008 表格编辑](../design/scenarios/editing/rich-editing/table-edit/scenario.md) | designed | 插入/删除行列、整表删除、表格外 no-op |
| [SCN-0009 数学与图表](../design/scenarios/editing/rich-editing/math-mermaid/scenario.md) | draft | KaTeX/Mermaid 渲染与源码编辑重绘；截图/人工 |

## 6. 验收归属

需求不另立测试。验收 = 上述 5 个场景全部 `verified` + 第 4 节约束未被违反。

当前 5 个场景均未全部 verified（0009 仅 draft），所以本卡保持 `accepted`，不转 `delivered`。

## 7. 澄清记录

- 2026-11-04 五态补录：从 README、`architecture.md` §2 与既有 selftest 反推；不新增功能范围。
- 场景优先级：格式/查找/源码/表格先补反例；数学/图表先补稳定截图断言。

## 8. 状态

`accepted`；待 5 个场景全部 verified 后转 `delivered`。
