---
layer: history
module: editing
status: frozen
updated: 2026-11-10
---

# 工序结果：表格行列操作的右键定位（P2）

## 1. 结论

用户反馈属实，根因是两处平台行为叠加，均已修复：

1. **页面坐标被二次翻转（主因）**：`EditorWebView` 用 `bounds.height - p.y` 换算右键坐标，
   但 `WKWebView.isFlipped == true`，`convert(_:from:)` 返回的 y 已是“从视口顶部起算”的
   页面口径；再减高度会把点击点垂直镜像到视口中线。表现：右键第 1 行，`focusAt` 定位到
   下方行甚至表格外 → 菜单不出现行列项 / 删除作用在别的行；菜单栏路径由用户自己放光标，
   所以准确。这是“顶部菜单准确、右键不准”的直接解释。
2. **右键后 DOM 没有 caret**：原生右键菜单吞掉 rightMouseDown/Up，WebKit 不会像左键那样把
   caret 放进 contenteditable；`focusAt` 只改 ProseMirror state 选区时不聚焦编辑器，用户
   看不到“当前行”。修复为设置选区后 `view.focus()`，DOM 光标与 state 选区一致。
3. 顺带补齐 SCN-0008 的既有约定：插入行/列后光标进入新单元格。连续两次「在下方插入行」
   现在沿同一方向累积；随后「删除所在行」删除的是刚插入的新行，而不是原行（此前连续插入
   会反向堆叠、删除命中旧行，属同一“定位不准”体验）。

## 2. 落点

| 文件 | 改动 |
|---|---|
| `Sources/MDPreview/EditorWebView.swift` | 新 `pagePoint(forWindowPoint:)` 单点换算（flipped 不二次翻转）；右键监视器改调它；新增 `presentContextMenu` 注入点（默认仍是系统菜单） |
| `web/src/kernel/components/editor/ops.js` | `focusAt` 设置选区后 `view.focus()` |
| `web/src/kernel/components/editor/tables.js` | 新增 `caretIntoCell`；插入行 → 光标进新行首格；插入列 → 按最终 doc 计算新单元格位置后进光标（避开上方行插入造成的位置漂移） |
| `web/src/kernel/components/editor/diagnostics-ops.js` | `tableInfo` 增 0 起算 `row/col`（仅诊断/自检消费） |
| `Sources/MDPreview/main.swift` | 新增 `--context-menu-test`：合成右键 → 真实监视器 → focusAt → 捕获菜单 → 执行项，按行文本断言 |
| `Sources/MDPreview/Selftest.swift` | 新增坐标换算/命中/光标行/插入跟随/表外 no-op 断言 |
| `web/test/core.test.js` | 新增连续插入行列的 row/col 累积断言 |

## 3. 验证

| 门 | 命令 | 结果 |
|---|---|---|
| Web 门禁 | `cd web && npm run verify` | lint 0 error；禁边 43 文件 OK；87 项全过（+1） |
| 无头自检 | `./.build/debug/MDPreview --selftest` | 129 PASS，`SELFTEST PASSED` |
| 右键端到端 | `./.build/debug/MDPreview --context-menu-test` | 12 PASS：第 1/2/3 行与内边距的 caret 行、插入/删除作用行、列删除 |
| 多窗口回归 | `--multiwindow-test --fileA=… --fileB=…` | 13 PASS（含表格 inTable、拷贝路径、Finder 定位） |
| 打包 | `./build.sh` | web 构建 + Node 门禁 + release Swift + 组装签名通过；包内 `--context-menu-test` 12 PASS |

**红→绿证据**：

- 修复前 `--context-menu-test` 红：菜单不含行列项（`inTable` 被镜像坐标判成 false）、
  `caretRow=-1`、删除/插入行数不变；修复后 12 项全绿。
- 单独移除 `focusAt` 的 `view.focus()` 重跑：行列命令仍作用于正确行，但
  “右键第 N 行 → 光标在第 N 行”全部红（`caretRow=-1`）——证明“菜单弹出前 caret 不可见”
  是独立缺陷，且测试对它有分辨力。

## 4. 结论落点表

| 结论 | 落点 |
|---|---|
| 右键坐标口径 / flipped 视图不二次翻转 / caret 可见性 | `design/architecture.md` §2.8；`CMP-app-shell` 规格 `#context-menu-position` |
| `focusAt` 聚焦语义；插入行列后选区进新单元格 | `CMP-kernel-editor` 规格 `#focus-at`、`#commands`、`#diagnostics` |
| 表格行列场景的失败路径与回归断言 | SCN-0008：运行序、不可变引用、TC-TBL-004～006 |
| 平台坑与判据 | `history/pitfalls.md` P9 |
| 工序状态与测试入口 | `plan/roadmap.md` 本工序行；README 开发自检命令 |

## 5. 未决 / 不阻塞

- 共享 1px 分隔线恰好压线的点击归属仍由 `posAtCoords` 就近决定；单元格内边距点击已验证。
- 右键菜单暂无行高亮浮层（当前行靠 caret 呈现）。
- 2026-11-10 用户真机验收通过（右键行列定位符合预期）；本工序 `closed`，已归档到 `history/works/`。
