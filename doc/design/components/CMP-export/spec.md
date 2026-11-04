---
layer: design
module: output
component: CMP-export
status: active
updated: 2026-11-04
---

# CMP-export 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L2 整合；业务能力（输出）
- 业务价值：把当前文档变成可分发/可打印的产物：完整 PDF、独立 HTML、系统打印；没有它，用户只能截屏或手工复制。
- 负责：PDF 导出（完整文档高度、分页）、独立 HTML（内联样式资源）、打印（WKWebView window.print）；代码文档以 `#code-view` 为 PDF/打印内容面。
- 不负责：编辑器渲染（`CMP-editor`）、文件保存（`CMP-document-io`）、图片资源打包（`CMP-image`）、代码文档的 HTML 导出（REQ-0009 非目标，菜单禁用）。
- 内部逻辑：`DocumentWindowController` 测量/截取长文档并写 PDF；`export.js` 取 HTML 并内联样式；`printDocument` 调用系统打印。
- 拥有的数据：导出文件（用户选择路径）；不拥有文档正文。
- 变化轴：导出格式、PDF 分页/尺寸、HTML 内联范围。
- 公开契约（含能力 ID）：
  - `CMP-export#pdf`：导出完整文档 PDF；长文档不截断；代码文档取 `#code-view` 的几何测量。
  - `CMP-export#html`：导出独立 HTML；样式内联；图片仍为 file:// 引用。
  - `CMP-export#print`：调用系统打印面板；打印内容与当前渲染一致（代码文档即 `#code-view`，`@media print` 关闭缩放与内边距）。
- 入口：
  - `CMP-export/Sources/MDPreview/DocumentWindowController.swift#exportPDF`
  - `CMP-export/Sources/MDPreview/DocumentWindowController.swift#exportHTML`
  - `CMP-export/Sources/MDPreview/DocumentWindowController.swift#printDocument`
  - `CMP-export/web/src/export.js#exportStandaloneHTML`
- 依赖：`CMP-editor`（渲染/HTML）、`CMP-code-view`（代码文档内容面）、`CMP-app-shell`（保存面板/命令）、`CMP-image`（图片引用）。
- 冷热属性：冷路径；导出期间不得阻塞编辑输入。
- 尺寸预算：目标 ≤120k token；当前约 300 行（DocumentWindowController 导出段 + export.js 76 + 支撑），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；PDF 也由「PDF 导出」「大文档 PDF 完整性」覆盖。
- 验证计划：PDF/大文档/HTML 标题用 selftest；代码文档 PDF/打印用人工记录（2026-11-04 人工核对通过；验证债见 SCN-0016 §6）；导出失败路径待补。
- 删除测试：删掉后输出能力消失，复杂度转移到用户手工操作 → 真边界。

## 公开契约细节

- `#pdf` 的不变量：按完整文档高度导出，不因视口高度截断；导出失败明确报错，不留下半文件。
- `#html` 的不变量：样式内联，不依赖本地 css；图片仍为 file://，不伪装成自包含。
- `#print` 的不变量：打印内容与当前渲染一致；不改文档。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#pdf` | `--selftest`：「PDF 导出」「大文档 PDF 完整性」 |
| `#html` | `--selftest`：「D2 导出 HTML 标题」 |
| `#print` | 人工：系统打印面板与输出预览 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| PDF/HTML 文件 | 本组件 | 用户 | 单次导出 |
| 导出临时测量 | 本组件 | 本组件 | 不持久化 |

## 验证债

打印没有自动化；导出失败/中断没有反例。相关场景最高 `designed`。

## 删除测试

删掉后 PDF/HTML/打印没有归属 → 真边界。
