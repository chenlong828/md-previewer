---
layer: design
module: editing
status: designed
updated: 2026-11-04
flow: FLOW-EDIT-001
scenario: SCN-0003
domain: 编辑
valueStream: 文档生命周期
title: 保存时规范化 Markdown
entries:
  - CMP-document-io/Sources/MDPreview/Util.swift#TextFile
  - CMP-editor/web/src/list-indent.js#fourSpaceListItem
  - CMP-image/Sources/MDPreview/Util.swift#ImagePathRewriter
docs:
  - path: doc/design/architecture.md
    heading: 2.2 保存无条件补尾换行
  - path: doc/design/architecture.md
    heading: 2.3 保存恒定 UTF-8（OQ-2 结论）
  - path: doc/design/architecture.md
    heading: 2.5 Markdown 序列化：列表每级 4 空格
  - path: doc/requirements/REQ-0004-persistence.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-NORM-001
  - role: R2
    id: TC-NORM-002
  - role: R3
    id: TC-NORM-003
  - role: N1
    id: TC-NORM-004
---

# 保存时规范化 Markdown

## 1. 场景与价值

用户保存不同来源的 Markdown：UTF-8 或 GB18030、有/无尾换行、2 空格或 4 空格列表、含空格图片路径。应用统一输出可读、可 diff 的 UTF-8 文本。

结果：同一文档多次保存不产生无意义 diff；旧格式文件能打开，保存后按当前口径规范化。

## 2. 入口

- `CMP-document-io#save`：`TextFile.write`。
- `CMP-editor#get-markdown`：`list-indent.js` 的 4 空格序列化。
- `CMP-image#for-save`：图片路径还原。

## 3. 运行序

流程定义：`FLOW-EDIT-001`（保存分支）。

1. 取当前 Markdown。
2. 图片路径 `forSave` 还原为相对路径；含空格用 `<>` 包裹。
3. 列表序列化：每级 4 空格，首行标记紧凑（`- a` 不补成 `-   a`）。
4. 末尾补一个换行。
5. UTF-8 写盘；重建干净基线。

失败路径：

- GB18030 打开后保存：转为 UTF-8（应用不做原编码保存）。
- 写盘失败：保留原文件，不产生半文件。

## 4. 不可变引用

- UTF-8 输出恒定；原编码不回写。
- 尾换行恰好一个。
- 列表每级 4 空格；2 空格旧文件可打开。
- 图片路径规则归 `CMP-image`，本场景只断言“保存后仍可加载”。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-NORM-001 | R1 | 自动 | `--selftest` | `PASS 列表 Tab 嵌套-每级 4 空格且首行紧凑` | present |
| TC-NORM-002 | R2 | 自动 | `--selftest` | `PASS 列表多级嵌套-4/8 空格` | present |
| TC-NORM-003 | R3 | 自动 | `--selftest` | `PASS 任务列表复选框与 4 空格缩进` | present |
| TC-NORM-004 | N1 | 人工 | GB18030/无尾换行/2 空格样本各存一次 | 保存后 UTF-8、尾换行 1 个、列表 4 空格；不损坏内容 | missing |

3 正存在；编码/尾换行/旧缩进反例未固化，暂 `designed`。

## 6. 验证债

- GB18030 样本、无尾换行样本、2 空格旧文件没有自动化往返测试。
- 需要一条“保存两次字节一致”的幂等断言。

## 7. 变更记录

- 2026-11-04 五态补录，来源：`architecture.md` §2.2/§2.3/§2.5、selftest 列表用例。
