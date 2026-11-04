---
layer: history
module: editing
status: frozen
updated: 2026-11-04
---

# P2 设计评审：代码视图行号与按行阅读

## 1. 定级

**P2（兼容性契约增量）**。理由：

- 触碰 `CMP-code-view` 的公开 DOM 形态与桥增量（`setCode` 选项、`setCodeLineNumbers`），并新增 `CMP-app-shell` 菜单入口；不触碰模块切分、数据所有权、schema、热路径。
- 既有 `#code-view > code` 选择器、语言 class、token class、`setCode`/`setCodeLanguage`/`isCodeMode`/`codeInfo` 都保留；新增能力为向后兼容。
- 没有不可逆迁移，失败时可只回退这一工序的 diff。

## 2. 阻断项

**无。** 未发现会迫使改动组件切分、破坏只读约束或污染 Markdown 编辑路径的阻断项。

## 3. 现在必须定的决策（已定）

| 决策 | 选择 | 理由 |
|---|---|---|
| 行号实现 | CSS `::before` 生成内容 | 不进入 `textContent`/复制/查找；不新增文本节点 |
| 行结构 | 每个逻辑行一个 `.code-line`，完整高亮后按 `\n` 拆 | 软换行/行号对齐/当前行都需要行边界；避免按行重解析导致多行 token 误判 |
| 当前行语义 | 点击行、⌘F 命中行、↑/↓/Home/End；无初始行 | 只读面没有光标；不跟随滚动，避免阅读时高亮乱跳 |
| 空行复制 | 非末行空行放 `<br>`，末行空行不放 | 浏览器会丢空块行；末行补 `<br>` 会多一个换行（已用选择断言实测） |
| 偏好范围 | 全局 `UserDefaults`，默认开，跨窗口 | 阅读偏好，不写文件、不产生 `changed`；符合菜单“显示行号”语义 |
| 行号关闭 | 只改布局类，不重绘 token | 开关是偶发操作，重绘会打断选区/查找 |
| 软换行 | `pre-wrap` + `overflow-wrap:anywhere`，无横向代码滚动 | 用户四项全选；长 token 不能撑破正文 |

## 4. 验证结论

- **文本保真**：逐行 `.code-line-content` 以 `\n` 拼接 = `state.codeText`；多行块注释、长行、空行、末尾空行均通过。
- **复制保真**：`Range.selectNodeContents` + `Selection.toString()` = 原文；行号不出现；空行不丢。
- **查找保真**：偏移仍按原文本计算，映射到行块；⌘F 命中行成为当前行；关闭查找保留当前行。
- **开关**：非代码模式 no-op；关闭只改 class/display；`codeInfo` 同步；再开恢复；不触发 `changed`。
- **回归**：既有代码视图断言、抽屉、双窗口、PDF 导出全部零失败。
- **几何**：长行 `scrollWidth <= clientWidth + 1`；行号列与内容列分离；初始无当前行。

## 5. 不接受的复杂度（本次不做）

- 虚拟化/分块渲染：512 KB 上限内典型代码文件线性 DOM 可接受；极端单字符行只登记观察项。
- 行号文本节点、逐行重新高亮、独立 gutter DOM + 宽度测量：都会引入复制污染/多行 token 破坏/布局漂移。
- 行号逐文件持久化、行号写入导出 HTML、Markdown 围栏代码块行号：与“阅读偏好/只读面”边界不符。
- 行号点击跳转外部编辑器、折叠/minimap/LSP：超出本需求。

## 6. 人工门（已通过）

1. 真实 GUI 菜单勾选、Markdown 置灰、跨窗口广播。
2. 真实鼠标点击/拖选、方向键当前行。
3. 深色主题对比度。
4. PDF/打印行号与当前行背景。
5. 接近 512 KB 的多行文件打开/滚动。

2026-11-04 用户确认任务完成，以上人工项通过：SCN-0016 → `verified`，REQ-0010 → `delivered`，工序收口归档。
