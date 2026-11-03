---
layer: design
module: editing
status: draft
updated: 2026-11-04
flow: FLOW-EDIT-002
scenario: SCN-0009
domain: 编辑
valueStream: 富文本编辑
title: 渲染数学公式与 Mermaid 图表
entries:
  - CMP-editor/web/src/editor.js#createEditor
  - CMP-editor/web/src/mermaid-view.js#getMermaidView
  - CMP-editor/web/src/bridge.js#window.mdbridge
docs:
  - path: README.md
    heading: 功能特性
  - path: doc/requirements/REQ-0002-editing.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-RICH-001
  - role: R2
    id: TC-RICH-002
  - role: R3
    id: TC-RICH-003
  - role: N1
    id: TC-RICH-004
---

# 渲染数学公式与 Mermaid 图表

## 1. 场景与价值

用户在文档里写行内/块级数学公式与 Mermaid 代码围栏，渲染视图直接显示公式/图表；点击 Mermaid 图表进入源码编辑，失焦自动重绘。

结果：技术文档的公式与流程图不用外部工具生成图片。

## 2. 入口

- `CMP-editor#render`：`editor.js` 装配 KaTeX / plugin-diagram。
- `CMP-editor#render`：`mermaid-view.js` 的 NodeView。
- `CMP-editor#init`：Markdown 注入后触发渲染。

## 3. 运行序

流程定义：`FLOW-EDIT-002`（富内容分支）。

1. 加载 Markdown，解析 `$...$` / `$$...$$` 与 ` ```mermaid `。
2. KaTeX 渲染行内/块级公式；失败显示错误文本，不影响其它节点。
3. Mermaid 代码围栏交给自定义 NodeView，渲染为 SVG。
4. 点击图表进入源码编辑；失焦/提交后重绘。
5. 导出/保存时按 Markdown 原文处理，不把 SVG 写回源码。

失败路径：

- 非法公式：显示错误占位，不崩溃、不阻塞编辑。
- 非法 Mermaid：显示错误，不覆盖源码。
- 大图/复杂图：渲染超时不应冻结编辑（需专项验证）。

## 4. 不可变引用

- 保存/导出只使用 Markdown 源码；渲染结果是派生视图。
- 代码围栏内容不被图片路径改写（SCN-0003/0011 的交叉约束）。
- Mermaid `securityLevel: 'loose'` 是已知安全取舍（architecture §1.2）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-RICH-001 | R1 | 截图/人工 | `--screenshot` + 含 `$E=mc^2$` 的样本 | 公式渲染可见，无源码泄漏 | missing |
| TC-RICH-002 | R2 | 截图/人工 | `--screenshot` + 块级 `$$…$$` | 块级公式居中/可读 | missing |
| TC-RICH-003 | R3 | 截图/人工 | `--screenshot` + mermaid 围栏 | SVG 出现；点击可进源码编辑，失焦重绘 | missing |
| TC-RICH-004 | N1 | 人工 | 非法公式/非法 mermaid | 显示错误占位，不崩溃、不改源码 | missing |

没有稳定的自动断言，故 `draft`；不得据此把 REQ-0002 转 `delivered`。

## 6. 验证债

- 需要像素/结构探针（DOM 节点存在、SVG 尺寸）而不是只靠肉眼截图。
- 非法输入的错误占位需要固定文案/选择器。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 数学/Mermaid、`mermaid-view.js`、architecture §1.2。
