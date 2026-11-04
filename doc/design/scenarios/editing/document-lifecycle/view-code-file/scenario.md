---
layer: design
module: editing
status: verified
updated: 2026-11-04
flow: FLOW-EDIT-001
scenario: SCN-0016
domain: 编辑
valueStream: 文档生命周期
title: 打开并查看代码文件
entries:
  - CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#openDocument
  - CMP-code-view/Sources/MDPreview/FileSupport.swift#kind(for:)
  - CMP-code-view/web/src/code-view.js#showCode
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#buildMenus
docs:
  - path: doc/design/architecture.md
    heading: 2.7 代码文档：只读源码视图
  - path: doc/requirements/REQ-0009-code-view.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-CODE-001
  - role: R2
    id: TC-CODE-002
  - role: R3
    id: TC-CODE-003
  - role: N1
    id: TC-CODE-004
---

# 打开并查看代码文件

## 1. 场景与价值

用户打开一个代码文件（⌘O / 抽屉 / 拖放 / 命令行 / 最近文件），应用按扩展名识别语言并显示只读高亮源码；用户切换高亮语言或关成纯文本、滚动阅读、⌘F 查找、⌘E 导出 PDF。关闭或换文件时不弹保存确认。

结果：读代码与读 Markdown 共用同一窗口、同一套查找/缩放/主题，不必换应用。

本场景不覆盖 Markdown 的打开/编辑/保存（SCN-0002）与外部变更冲突（SCN-0004）；代码文档恒只读，无脏标记概念。

## 2. 入口

- `CMP-document-io#open-document`：`DocumentWindowController.openDocument` 按 `FileSupport.kind` 分派。
- `CMP-code-view#kind`：`FileSupport.kind(for:)` / `codeLanguages`（扩展名 → 语言）。
- `CMP-code-view#set-code`：`window.mdbridge.setCode` / `setCodeLanguage`。
- `CMP-app-shell#menu-commands`：视图 → 高亮语言子菜单（自动 / 纯文本 / 语言表）。

## 3. 运行序

流程定义：`FLOW-EDIT-001`。

1. 打开：扩展名命中语言表 → 读文本（UTF-8/GB18030）→ 判定是否超 512 KB → `setCode(text, {language, allowHighlight})`。
2. 渲染：`#code-view` 出现、`#app` 隐藏；语言未知或超限时纯文本；token 使用 `typora.css` 调色板。
3. 只读：无脏基线；保存/另存为/格式命令/源码模式/插入图片/HTML 导出在菜单与代码路径双重禁用；状态栏显示「只读 · 语言」。
4. 切换语言：视图菜单勾选并 `setCodeLanguage(id)` 重绘；「自动」回到扩展名语言，「纯文本」去掉高亮；文件内容不变。
5. 查找：⌘F 在同一查找栏内检索，命中计数与上一处/下一处逐处定位（选区高亮）。
6. 导出：⌘E PDF 以 `#code-view` 为内容面测量高度；⌘P 打印同口径。
7. 关闭：直接关闭；不触发图片资源清理；外部变更自动重载并保留当前语言选择。

失败路径：

- 扩展名不在语言表：不进入装载，弹「不支持的文件类型」，原窗口内容不变。
- 文件不可读/编码识别失败：明确报错，不进入代码视图。
- 文件超过 512 KB：仍显示全文，但不高亮，状态栏标注「文件过大，未高亮」。
- 大文件仍可切换语言：视图不变（纯文本）且状态栏保持提示。

## 4. 不可变引用

- `architecture.md` §2.7 代码文档只读与语言表单一来源。
- `CMP-code-view` 的 `#kind` / `#set-code` / `#language-switch` 契约。
- `CMP-document-io#open` 的编码识别口径（UTF-8 → GB18030）；代码文档不写盘。
- `CMP-editor#theme-zoom` 的主题/缩放变量（`data-theme`、`--app-zoom`）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-CODE-001 | R1 | 自动 | `--selftest` | `PASS 代码视图 自动语言与高亮` | present（2026-11-04 全绿） |
| TC-CODE-002 | R2 | 自动 | `--selftest` | `PASS 代码视图 切换语言与纯文本` | present（2026-11-04 全绿） |
| TC-CODE-003 | R3 | 自动 | `--selftest` | `PASS 代码视图 查找命中与只读退出` | present（2026-11-04 全绿） |
| TC-CODE-004 | N1 | 自动 | `--selftest` | `PASS 代码视图 未知扩展名不装载` | present（2026-11-04 全绿） |

配套断言：`PASS 代码视图 双端语言清单一致`、`PASS 代码视图 大文件降级纯文本`、`PASS 代码视图 未知语法回落纯文本`。

## 6. 验证债

- PDF / 打印只做人工截图与 DOM 几何核对，未固化为自动断言。
- 真实 GUI 下的窗口标题、状态栏文案与菜单置灰靠人工记录（R8：无头环境不覆盖真实交互时序）。

## 7. 变更记录

- 2026-11-04 新建（REQ-0009，P1 工序 `2026-11-04-code-file-view`）。
- 2026-11-04 3+1 自动化断言全绿（`--selftest` 117 项中的 11 条），转 `verified`；真实 GUI 走查经用户 2026-11-04 人工核对通过，记录在 `result.md`。
