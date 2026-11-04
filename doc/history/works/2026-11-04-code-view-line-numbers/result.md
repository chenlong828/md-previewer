---
layer: history
module: editing
status: frozen
updated: 2026-11-04
---

# 工序 result：代码视图行号与按行阅读

## 1. 结论

已完成代码视图的逻辑行结构、静态行号、软换行、当前行高亮、全局行号开关，以及复制/查找/PDF 的保真约束。自动化全绿；2026-11-04 用户确认任务完成，真实菜单勾选、鼠标点击、深色主题和 PDF/打印行号人工核对通过（R8）。工序已收口归档。

需求卡 [REQ-0010](../../../requirements/REQ-0010-code-view-line-numbers.md) 转 `delivered`；场景 [SCN-0016](../../../design/scenarios/editing/document-lifecycle/view-code-file/scenario.md) 转 `verified`。

**裁决摘要**：blocker 0 / decision 7（已落测试与文档）/ hold 0（极端行数仅留观察项，不阻塞）。

## 2. 实际改动

| 层 | 文件 | 改动 |
|---|---|---|
| web | `web/src/code-view.js` | 完整高亮后按 `\n` 拆逻辑行；跨行 token 克隆；行号/软换行/当前行/开关；查找偏移映射到行块；空行 `<br>` 保复制 |
| web | `web/src/state.js` | `codeLineNumbers` 全局显示偏好 |
| web | `web/src/bridge.js` | `setCode` 新增 `lineNumbers` 选项；新增 `setCodeLineNumbers(visible)` |
| web | `web/src/typora.css` | 行网格、生成行号、当前行背景、软换行、空行高度、行号关闭/打印规则 |
| Swift | `DocumentWindowController.swift` | `codeLineNumbersVisible` 偏好、注入选项、菜单动作/校验、按偏好刷新 |
| Swift | `AppDelegate.swift` | 视图菜单「显示行号」、MenuID、勾选同步、跨窗口广播 |
| 测试 | `Selftest.swift` | 行结构文本重建 + 4 组新断言 |
| 文档 | `README.md`、`doc/*` | 需求、场景、组件规格、架构、索引、路线图同步 |

**未改**：抽屉过滤/目录树（用户已撤回该条）、Markdown 编辑器、`languages.js` 语法表、文件 IO、导出实现、`index.html`。

## 3. 验证证据（2026-11-04）

### 自动化

`./.build/debug/MDPreview --selftest` → **`SELFTEST PASSED`**（121 项 PASS；较上版 117 项 +4 条行号断言）。新增/相关断言：

```
PASS  代码视图 行号与软换行
PASS  代码视图 当前行点击与查找定位
PASS  代码视图 行号开关与复制文本
PASS  代码视图 空文件行号边界
PASS  代码视图 自动语言与高亮
PASS  代码视图 切换语言与纯文本
PASS  代码视图 未知语法回落纯文本
PASS  代码视图 查找命中与只读退出
PASS  代码视图 大文件降级纯文本
PASS  代码视图 双端语言清单一致(44 种)
PASS  代码视图 退出代码模式
```

断言覆盖：多行块注释（跨行 token）、240 字符长行（软换行/无横向溢出）、空行与末尾空行（选择文本 = 原文）、点击行 + ↑/↓ 当前行、⌘F 命中 `return` 行、行号关闭后空行高度/选择文本不含行号、空文件 0 行、非代码模式开关 no-op。

回归：

- `--drawer-test --dir=samples --fileA=samples/code-sample.py --fileB=samples/功能演示.md` → 全部既有断言通过（本工序未改抽屉）。
- `--multiwindow-test --fileA=/tmp/mdp-a.md --fileB=/tmp/mdp-b.md` → 窗口/表格断言通过；代码文件不再用于该测试的表格夹具。

### 截图

- `--screenshot /tmp/mdp-code-line-numbers-final.png samples/code-sample.py`：28 行行号右对齐、行号列与代码列分离、初始无当前行。
- `--screenshot /tmp/mdp-code-wrap-final.png /tmp/wrap-demo.py`：240 字符长行在内容列软换行，行号只出现一次、无横向代码滚动。
- 性能冒烟：9001 行 / 672 KB 纯文本代码文件 `--screenshot` 总耗时 4.5s（含固定 3.5s 等待），行号与滚动正常；超过 512 KB 仍走既有纯文本降级。

## 4. 人工核对（R8，2026-11-04 用户确认完成）

1. 视图 →「显示行号」：代码文档可用并勾选；Markdown 文档置灰；切换后所有代码窗口即时变化，新窗口继承。
2. 真实鼠标单击行：当前行背景出现；拖选文本不抢当前行；↑/↓/Home/End 在代码视图聚焦时移动当前行。
3. 深色主题下当前行背景与行号对比度。
4. PDF（⌘E）与打印（⌘P）包含当前开关下的行号；当前行背景不打印。
5. 极端长文件（接近 512 KB、行数很多）的打开/滚动流畅度。

## 5. 活结论落点

| 结论 | 落点 |
|---|---|
| 行号是表现层，复制/查找/导出保持原文 | [architecture.md §2.7](../../../design/architecture.md)、[CMP-code-view spec](../../../design/components/CMP-code-view/spec.md) `#line-numbers` / `#line-layout` |
| 行号偏好全局、默认开、菜单入口归 app-shell | [CMP-app-shell spec](../../../design/components/CMP-app-shell/spec.md) `#code-line-numbers-menu` |
| 当前行语义 = 点击/⌘F/方向键，会话级 | CMP-code-view spec、SCN-0016 运行序 |
| 空行 `<br>` / 末尾空行不补的复制口径 | CMP-code-view spec、selftest「行号开关与复制文本」 |
| 512 KB 上限不变；极端行数仅观察 | REQ-0010 约束、CMP-code-view 验证债 |
| 抽屉不改（用户撤回） | 本 brief §1、REQ-0010 澄清记录 |
