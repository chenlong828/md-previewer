---
layer: design
module: editing
status: verified
updated: 2026-11-04
flow: FLOW-EDIT-001
scenario: SCN-0016
domain: 编辑
valueStream: 文档生命周期
title: 打开并查看代码文件（行号与按行阅读）
entries:
  - CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#openDocument
  - CMP-code-view/Sources/MDPreview/FileSupport.swift#kind(for:)
  - CMP-code-view/web/src/code-view.js#showCode
  - CMP-code-view/web/src/code-view.js#setCodeLineNumbers
  - CMP-code-view/Sources/MDPreview/DocumentWindowController.swift#toggleCodeLineNumbersAction
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#buildMenus
docs:
  - path: doc/design/architecture.md
    heading: 2.7 代码文档：只读源码视图
  - path: doc/requirements/REQ-0009-code-view.md
    heading: 5. 影响场景
  - path: doc/requirements/REQ-0010-code-view-line-numbers.md
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
  - role: R1
    id: TC-CODE-005
  - role: R2
    id: TC-CODE-006
  - role: R3
    id: TC-CODE-007
  - role: N1
    id: TC-CODE-008
---

# 打开并查看代码文件（行号与按行阅读）

## 1. 场景与价值

用户打开一个代码文件（⌘O / 抽屉 / 拖放 / 命令行 / 最近文件），应用按扩展名识别语言并显示只读高亮源码；左侧按逻辑行显示行号，长行软换行；点击行或 ⌘F 跳转时高亮当前行；可从视图菜单开关行号。用户还可切换高亮语言或关成纯文本、滚动阅读、⌘F 查找、⌘E 导出 PDF。关闭或换文件时不弹保存确认。

结果：读代码与读 Markdown 共用同一窗口、同一套查找/缩放/主题，不必换应用；长代码可直接按行号定位，复制/查找/导出仍保持原文语义。

本场景不覆盖 Markdown 的打开/编辑/保存（SCN-0002）与外部变更冲突（SCN-0004）；代码文档恒只读，无脏标记概念。抽屉过滤不在本场景（REQ-0001）；行号只属于 `#code-view`，不进入 Markdown 围栏代码块。

## 2. 入口

- `CMP-document-io#open-document`：`DocumentWindowController.openDocument` 按 `FileSupport.kind` 分派。
- `CMP-code-view#kind`：`FileSupport.kind(for:)` / `codeLanguages`（扩展名 → 语言）。
- `CMP-code-view#set-code`：`window.mdbridge.setCode` / `setCodeLanguage`；`opts.lineNumbers` 携带行号偏好。
- `CMP-code-view#line-numbers`：`window.mdbridge.setCodeLineNumbers(visible)` / `codeInfo()`。
- `CMP-app-shell#menu-commands`：视图 → 高亮语言子菜单（自动 / 纯文本 / 语言表）；视图 →「显示行号」。
- `CMP-code-view#line-layout`：`code-view.js` 的行拆分、行号生成内容、软换行、当前行。

## 3. 运行序

流程定义：`FLOW-EDIT-001`。

1. 打开：扩展名命中语言表 → 读文本（UTF-8/GB18030）→ 判定是否超 512 KB → `setCode(text, {language, allowHighlight, lineNumbers})`。
2. 渲染：`#code-view` 出现、`#app` 隐藏；高亮结果按 `\n` 拆成逻辑行；语言未知或超限时纯文本按行拆；token 使用 `typora.css` 调色板。
3. 行号：每行左侧生成行号（CSS `::before`，不进入文本）；行号宽度按总行数位数；当前开关为全局偏好，默认开；空文件 0 行。
4. 阅读：长行软换行且无横向代码滚动；行号对齐逻辑行首；点击行或按 ↑/↓/Home/End 高亮当前行（只读、无光标）。
5. 只读：无脏基线；保存/另存为/格式命令/源码模式/插入图片/HTML 导出在菜单与代码路径双重禁用；状态栏显示「只读 · 语言」。
6. 切换语言：视图菜单勾选并 `setCodeLanguage(id)` 重绘；「自动」回到扩展名语言，「纯文本」去掉高亮；文件内容与行号偏好不变。
7. 查找：⌘F 在同一查找栏内检索，命中计数与上一处/下一处逐处定位（选区高亮），命中行成为当前行；关闭查找保留当前行。
8. 开关行号：视图 →「显示行号」切换；所有代码窗口即时生效并记忆；复制/查找文本不变；Markdown 窗口该项置灰。
9. 导出：⌘E PDF 以 `#code-view` 为内容面测量高度；⌘P 打印同口径；行号随开关出现。
10. 关闭：直接关闭；不触发图片资源清理；外部变更自动重载并保留当前语言选择。

失败路径：

- 扩展名不在语言表：不进入装载，弹「不支持的文件类型」，原窗口内容不变。
- 文件不可读/编码识别失败：明确报错，不进入代码视图。
- 文件超过 512 KB：仍显示全文，但不高亮，状态栏标注「文件过大，未高亮」；行号/软换行仍按纯文本行结构工作。
- 大文件仍可切换语言：视图不变（纯文本）且状态栏保持提示。
- 空文件：0 个逻辑行，不渲染行号，不报错；行号开关仍可切换。
- 行号 DOM 构建失败/高亮无 token：回落纯文本行结构，不阻塞打开。

## 4. 不可变引用

- `architecture.md` §2.7 代码文档只读与语言表单一来源。
- `CMP-code-view` 的 `#kind` / `#set-code` / `#language-switch` / `#line-numbers` / `#line-layout` 契约。
- `CMP-app-shell#code-line-numbers-menu` 的菜单入口与全局偏好广播。
- `CMP-document-io#open` 的编码识别口径（UTF-8 → GB18030）；代码文档不写盘。
- `CMP-editor#theme-zoom` 的主题/缩放变量（`data-theme`、`--app-zoom`）。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-CODE-001 | R1 | 自动 | `--selftest` | `PASS 代码视图 自动语言与高亮` | present（2026-11-04 全绿） |
| TC-CODE-002 | R2 | 自动 | `--selftest` | `PASS 代码视图 切换语言与纯文本` | present（2026-11-04 全绿） |
| TC-CODE-003 | R3 | 自动 | `--selftest` | `PASS 代码视图 查找命中与只读退出` | present（2026-11-04 全绿） |
| TC-CODE-004 | N1 | 自动 | `--selftest` | `PASS 代码视图 未知扩展名不装载` | present（2026-11-04 全绿） |
| TC-CODE-005 | R1 | 自动 | `--selftest` | `PASS 代码视图 行号与软换行` | present（2026-11-04 全绿） |
| TC-CODE-006 | R2 | 自动 | `--selftest` | `PASS 代码视图 当前行点击与查找定位` | present（2026-11-04 全绿） |
| TC-CODE-007 | R3 | 自动 | `--selftest` | `PASS 代码视图 行号开关与复制文本` | present（2026-11-04 全绿） |
| TC-CODE-008 | N1 | 自动 | `--selftest` | `PASS 代码视图 空文件行号边界` | present（2026-11-04 全绿） |

配套断言：`PASS 代码视图 双端语言清单一致`、`PASS 代码视图 大文件降级纯文本`、`PASS 代码视图 未知语法回落纯文本`。

## 6. 验证债

无未决验证债。PDF/打印行号与真实 GUI 交互（菜单勾选、跨窗口记忆、深色主题、鼠标点击）经用户 2026-11-04 确认完成；极端单字符行文件的 DOM 放大保留为观察项，512 KB 上限兜底，不阻塞验收。

## 7. 变更记录

- 2026-11-04 新建（REQ-0009，P1 工序 `2026-11-04-code-file-view`）。
- 2026-11-04 3+1 自动化断言全绿（`--selftest` 117 项中的 11 条），转 `verified`；真实 GUI 走查经用户 2026-11-04 人工核对通过，记录在 `result.md`。
- 2026-11-04 增补行号/软换行/当前行/开关断言（REQ-0010，P2 工序 `2026-11-04-code-view-line-numbers`）；转回 `active`。
- 2026-11-04 行号 4 条自动化断言全绿（`SELFTEST PASSED`），既有代码视图/抽屉/双窗口零回归；真实菜单勾选、鼠标点击、深色主题、PDF/打印行号经用户确认完成，转 `verified`；工序归档至 `history/works/2026-11-04-code-view-line-numbers/`。
