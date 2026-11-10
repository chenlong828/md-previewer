---
layer: history
module: editing
status: frozen
updated: 2026-11-10
---

# P2 设计评审：表格行列操作的右键定位

## 1. 定级

**P2（跨组件缺陷修复，无公共契约/schema/依赖变化）**。理由：

- 缺陷横跨 `CMP-app-shell`（右键坐标换算）与 `CMP-kernel-editor`（`focusAt`、表格插入选区委），
  属“实质性跨文件/跨组件”，按定级纪律不降为 P3；
- 但 host op 数量与 payload 未变：`focusAt` 仍返回 `{ok, inTable}`，`tableInfo` 仅**新增**诊断字段
  `row/col`（0 起算），`tableCommand` 命令名不变；不触碰模块切分、数据所有权、热路径与依赖方向；
- 失败可只回退本工序 diff（Swift 坐标单点 + 两处 JS 行为），无迁移步骤。

## 2. 阻断项

**无。** 未发现数据丢失、默认行为不可逆或契约自相矛盾。原缺陷本身（右键作用到错误行）在修复前
已由 `--context-menu-test` 红跑复现，属可回归的业务错误，现已清零。

## 3. 现在必须定的决策（已定）

| 决策 | 选择 | 理由 |
|---|---|---|
| 坐标换算口径 | flipped 视图直接用 `convert` 结果，非 flipped 才减高度 | WKWebView `isFlipped == true` 已由运行时探针确认；二次翻转会把 y 镜像到视口中线 |
| 右键后的 DOM caret | `focusAt` 设置选区后 `view.focus()` | 原生菜单吞掉鼠标事件，WebKit 不会放 caret；只有 state 选区时用户看不到“当前行” |
| 插入行列的选区 | 插入后把光标放进新单元格 | SCN-0008 既有约定“光标落入新位置”；连续插入沿同方向累积，删除才能命中刚插入的行 |
| 菜单呈现可测试性 | `EditorWebView.presentContextMenu` 注入点，默认系统弹出 | 不替换产品路径，仅让自检捕获菜单、避开阻塞式菜单跟踪（与 `revealInFinder(using:)` 同款注入手法） |
| 诊断字段 | `tableInfo` 增 `row/col` | 让“光标落在点击行”可直接断言，不再靠间接推断；字段为增量、仅诊断面消费 |

## 4. 验证结论（verified sound）

- **坐标**：`--selftest`「右键定位 窗口坐标=页面坐标 Δ(0.0,0.0)」；`--context-menu-test` 的
  `convert` 往返与 `elementFromPoint` 命中同一单元格，覆盖第 1/2/3 行与左上内边距。
- **行为**：合成真实右键事件 → 真实监视器 → `focusAt` → 构建菜单 → 执行菜单项；第 1 行插入
  空行紧随其后、第 2/3 行删除只删该行、第 2 列删除只删该列；插入后 caret 进入新行。
- **内核语义**：`web/test/core.test.js` 连续两次插入的 `row/col` 递增（1→2、1→2），删除新行
  后原数据行保留；selftest 同口径断言 + 表格外 no-op（TC-TBL-004）。
- **回归**：`npm run verify`（lint + 禁边 + 87 项）、`--selftest` 129 项、`--context-menu-test`
  12 项、`--multiwindow-test` 全绿；表格外行为、只读代码文档、拷贝路径/Finder 菜单均未受影响。

## 5. Hold（不阻塞，本次不做）

- 共享 1px 分隔线恰好压线的点击归属仍按 `posAtCoords` 就近决定；不新增启发式重定位。
- 右键菜单无行高亮浮层；“当前行”靠 caret 呈现。
- 若将来改用 `WKWebView.pageZoom`，需按 pageZoom 折算坐标；登记在 architecture §2.8 失效条件。

## 6. 人工门

P2 人最终确认已通过：自动门全绿；2026-11-10 用户在本机 `dist/MDPreview.app` 真机右键验收通过。
