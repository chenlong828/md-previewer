---
layer: history
module: editing
status: frozen
updated: 2026-11-10
---

# 工序 brief：表格行列操作的右键定位（缺陷 / P2）

## 1. 问题

用户反馈：表格的「增加行、减少行」定位不准确，鼠标右键弹出菜单后，光标不在弹出前
的位置，无法明确「在/删除当前行」。顶部菜单栏发起同一操作时定位准确（光标是用户
自己放的），因此问题只在右键定位链路。

候选根因（待最小复现确认）：

1. `EditorWebView` 把右键窗口坐标换算成网页坐标时用了 `bounds.height - p.y`。
   `WKWebView` 是 flipped 视图（`isFlipped == true`），`convert(_:from:)` 返回的
   y 已经是「从视口顶部起算」的页面口径；再减一次高度会把点击点**垂直镜像**，
   `focusAt` 落到另一行/表格外，菜单里的行列操作就作用在错误行。
2. `focusAt` 只改 ProseMirror 的 state 选区，不把焦点交给编辑器；当编辑器当时
   没有 DOM 焦点时，页面里看不到点击处的 caret，用户无法确认「当前行」。
3. 插入行/列后没有把光标移进新单元格（SCN-0008 已约定“光标落入新位置”），
   连续操作时「当前行」停在旧行。

## 2. 决策

- 坐标换算收敛为 `EditorWebView` 单一入口 `pagePoint(forWindowPoint:)`：flipped
  视图直接采用 `convert` 结果，非 flipped 才做高度翻转；右键监视器只调这一个入口。
- `focusAt` 在设置选区后调用 `view.focus()`，让 DOM caret 与 state 选区一致，
  用户能在菜单弹出前看到「当前行」。
- 插入行/列后把选区放进新单元格起点（行/列插入共用一个定位辅助函数），
  连续插入沿同一方向累积，符合 SCN-0008「插入后光标落入新位置」。
- 新增 `--context-menu-test`：合成右键事件走真实监视器 → `focusAt` → 构建菜单 →
  执行菜单项，按**行的文本**断言作用在点击行；这是本次缺陷的回归门。

不做：新增右键菜单项、改变菜单文案/分组、行高亮浮层、单元格边界点击的启发式
重定位（先修主因，边界行为人工复核后另议）。

## 3. 影响与契约

- 组件：`CMP-app-shell`（`EditorWebView` 坐标换算 + 菜单呈现注入点、`main.swift`
  测试入口）与 `CMP-kernel-editor`（`focusAt`、`tables.js` 插入后选区委）。
- 场景：SCN-0008「编辑表格的行与列」。
- 契约：host op 数量与 payload 不变；`focusAt` 的 `{ok, inTable}` 返回形状不变；
  `EditorWebView` 只新增诊断/自检可替换属性 `presentContextMenu`（默认仍是
  `NSMenu.popUpContextMenu`），不改变产品路径。
- 不受影响：源文件读写、导出、查找、缩略图、抽屉、主题、代码视图。

## 4. 任务

| ID | 任务 | 状态 |
|---|---|---|
| T1 | 写 `--context-menu-test`（合成右键 + 捕获菜单 + 按行文本断言），先跑红 | 完成（红：菜单无行列项、caret=-1） |
| T2 | `EditorWebView` 坐标换算单点化并修正 flipped 视图的 y | 完成 |
| T3 | `focusAt` 后聚焦编辑器，caret 落在点击处 | 完成（移除该行会红，测试有分辨力） |
| T4 | 插入行/列后选区进入新单元格 | 完成（含“上方行插入导致位置漂移”修正） |
| T5 | 回归：`--selftest`、`web npm test`、`--context-menu-test` 全绿 | 完成（129 / 87 / 12） |
| T6 | 文档同步（SCN-0008、CMP-app-shell、CMP-kernel-editor、architecture、坑档案） | 完成 |

## 5. 验收

- `--context-menu-test`：右键第 1 行 → 光标在第 1 行 → 「在下方插入行」新空行紧随
  第 1 行；右键第 2 行 → 「删除所在行」删除第 2 行；右键第 3 行 → 删除第 3 行；
  右键第 2 列 → 「删除所在列」只移除第 2 列。
- 修复前同一入口为红（定位到错误行），修复后绿。
- `--selftest`：新增「插入行后光标进入新行」「表外行列命令 no-op」断言，全部 PASS。
- `cd web && npm run verify` 全绿。
- 人工：真实鼠标右键点不同行，caret 落在点击处，删除/插入作用于该行。

## 6. 风险

- 无头环境里合成右键事件依赖窗口为 key；拿不到 key window 时该测试 SKIP 并打印
  原因（与 drawer-test 的真实拖拽断言同口径），不伪装成通过。
- 坐标在页面缩放（CSS zoom）下仍是视口 CSS 像素；如将来改为 `WKWebView.pageZoom`，
  需按 pageZoom 折算，测试会先红。
