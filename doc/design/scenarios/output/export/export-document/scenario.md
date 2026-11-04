---
layer: design
module: output
status: designed
updated: 2026-11-04
flow: FLOW-OUT-001
scenario: SCN-0014
domain: 输出
valueStream: 导出
title: 导出 PDF、独立 HTML 并打印
entries:
  - CMP-export/Sources/MDPreview/DocumentWindowController.swift#exportPDF
  - CMP-export/Sources/MDPreview/DocumentWindowController.swift#exportHTML
  - CMP-export/Sources/MDPreview/DocumentWindowController.swift#printDocument
  - CMP-kernel-output/web/src/kernel/components/output/export.js#exportStandaloneHTML
docs:
  - path: README.md
    heading: 功能特性
  - path: doc/requirements/REQ-0005-export.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-OUT-001
  - role: R2
    id: TC-OUT-002
  - role: R3
    id: TC-OUT-003
  - role: N1
    id: TC-OUT-004
---

# 导出 PDF、独立 HTML 并打印

## 1. 场景与价值

用户从「文件 → 导出」选择 PDF/HTML，或按 ⌘E 导出 PDF、走系统打印：PDF 覆盖完整文档高度，HTML 内联样式资源，打印内容与当前渲染一致。

结果：文档可脱离编辑器分发/打印，长文不截断。

## 2. 入口

- `CMP-export#pdf`：`exportPDF`。
- `CMP-export#html`：`exportHTML` / `exportStandaloneHTML`。
- `CMP-export#print`：`printDocument`。

## 3. 运行序

流程定义：`FLOW-OUT-001`。

1. 取当前渲染内容；源码模式下按实现临时切回渲染或按源码导出。
2. PDF：测量完整文档高度，分页截取并写文件；长文档不截断。
3. HTML：取 HTML，内联样式资源；图片仍 file://。
4. 打印：调用 `window.print()`，系统打印面板。
5. 导出完成：提示保存路径；不修改文档、不改变脏标记。

失败路径：

- 用户取消保存面板：无文件产生，不报错。
- 写盘失败/空间不足：明确报错，不留半文件。
- 打印面板取消：不修改文档。

## 4. 不可变引用

- PDF 以完整文档高度为准，不按视口截断。
- HTML 样式内联，但不承诺图片自包含。
- 导出不触发保存/不改变文档内容。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-OUT-001 | R1 | 自动 | `--selftest` | `PASS PDF 导出` | present |
| TC-OUT-002 | R2 | 自动 | `--selftest` | `PASS 大文档 PDF 完整性` | present |
| TC-OUT-003 | R3 | 自动 | `--selftest` | `PASS D2 导出 HTML 标题` | present |
| TC-OUT-004 | N1 | 人工/自动 | 打印；写盘失败/取消保存 | 打印一致；失败不留半文件；取消无副作用 | missing |

3 正存在；打印与失败路径未固化，暂 `designed`。

## 6. 验证债

- 打印内容一致性没有自动断言，只能人工记录。
- 导出中断/只读目录的失败路径。
- HTML 内联样式的完整性（无外部 css 依赖）需要静态检查。

## 7. 变更记录

- 2026-11-04 五态补录，来源：README 导出、selftest PDF/HTML、`export.js`。
