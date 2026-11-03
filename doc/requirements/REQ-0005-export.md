---
layer: requirements
module: output
status: accepted
updated: 2026-11-04
---

# REQ-0005：导出与打印

**类型**：feature

## 1. 场景叙述

用户需要把当前文档发给别人或打印时，可以导出完整 PDF、导出独立 HTML，或直接调用系统打印；PDF 不因视口高度截断，HTML 内联样式资源，打印内容与当前渲染一致。

结果是：文档可以脱离编辑器被阅读/打印，不需要截屏或手工复制。

## 2. 价值

不做的后果：用户只能截屏或复制到 Word，长文档丢失分页；HTML 依赖本地 css，换机样式全丢；打印入口缺失。

## 3. 非目标

- 不保证 PDF 与 Typora/Word 逐像素一致；不做页眉页脚/目录模板。
- 不把图片打包进 HTML（仍为 file://，需同机查看）。
- 不做批量导出、导出队列、云上传。

## 4. 行为约定

- PDF：按完整文档高度导出；长文档不截断；失败明确报错，不留半文件。
- HTML：样式内联；不依赖本地 css；图片仍为 file://。
- 打印：走 WKWebView `window.print()`；打印内容与当前渲染一致。
- 导出不修改文档，不触发脏标记。

## 5. 影响场景

| 场景 | 状态 | 本次新增/修改的断言 |
|---|---|---|
| [SCN-0014 导出文档](../design/scenarios/output/export/export-document/scenario.md) | designed | PDF 完整、长文档不截断、HTML 内联样式、打印一致；导出失败/中断（反例） |

## 6. 验收归属

验收 = SCN-0014 `verified` + 第 4 节约束未被违反。打印与失败路径未自动化，故保持 `accepted`。

## 7. 澄清记录

- 2026-11-04 五态补录：从 README、`architecture.md` 与 selftest 的 PDF/HTML 用例反推。
- 打印为人工记录；不把“截图看起来对”当作自动验证。

## 8. 状态

`accepted`；待 SCN-0014 verified 后转 `delivered`。
