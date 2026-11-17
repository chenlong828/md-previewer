---
layer: history
module: navigation
status: frozen
updated: 2026-11-13
---

# 工序结果：文件抽屉显示隐藏文件开关（P2）

## 1. 结论

- 抽屉头部新增第三个图标按钮（锚点控件右侧、Home 左侧）：`eye.slash` 表示当前不显示
  隐藏条目，点击后变 `eye` 并用强调色，再点恢复。
- 隐藏口径与 Finder 一致：扫描层向 `FileManager` 取 `isHidden` 资源键，因此 `.` 前缀与
  `chflags hidden` 标记都识别；`node_modules`、包目录、符号链接仍跳过，文件仍只列
  Markdown/代码。
- 偏好单值 `UserDefaults["fileDrawerShowsHidden"]`（默认 false）：切换写盘、重扫当前根层、
  回调 `AppDelegate.applyDrawerShowHiddenToAllDocuments` 广播所有窗口；广播路径只应用
  状态不写盘（写入口唯一）。新窗口按记忆初始化。
- 切换时可见目录展开态由既有 `rescan` 的 capture/restore 保持；未装载根的窗口只同步按钮。

## 2. 落点

| 文件 | 改动 |
|---|---|
| `Sources/MDPreview/DirectoryTree.swift` | `scanLevel(of:includeHidden:)`；隐藏判定走 `isHidden` 资源键（单点） |
| `Sources/MDPreview/FileDrawerView.swift` | 按钮 + 状态 + 偏好读写 + 重扫 + 诊断入口；头部布局改三按钮 |
| `Sources/MDPreview/DocumentWindowController.swift` | 抽屉回调挂广播；`applyDrawerShowHiddenPreference` |
| `Sources/MDPreview/AppDelegate.swift` | `applyDrawerShowHiddenToAllDocuments` 跨窗口分发 |
| `Sources/MDPreview/Selftest.swift` | 目录扫描显示隐藏用例、隐藏目录子层、抽屉开关视图级 4 项 |
| `Sources/MDPreview/main.swift` | drawer-test 三按钮几何 + 开关断言；multiwindow 跨窗口同步断言 |

## 3. 验证

| 门 | 命令 | 结果 |
|---|---|---|
| Web 门禁 | `cd web && npm run verify` | lint 0 error；禁边 43 文件；87 项全过 |
| 无头自检 | `dist/MDPreview.app/... --selftest` | **135 PASS / 0 FAIL**（+6） |
| 右键回归 | `--context-menu-test` | 12 PASS |
| 抽屉集成 | `--drawer-test --dir=/tmp/drawerhidden …` | **40 PASS / 0 FAIL**（包内连跑两次稳定） |
| 多窗口 | `--multiwindow-test` | 15 PASS（含跨窗口同步开/关） |
| 打包 | `./build.sh` | web + Node 门禁 + release Swift + 组装签名通过 |

## 4. 顺带修复的既有测试问题（同属抽屉/自检，非本功能）

1. **drawer-test 启动时序**：固定 0.8s 后切目录模式，打包环境首屏装载更慢时锚点断言
   跑在回填之前；改为等 `isReady && !isLoadingContent`，并等锚点条目数=父级链。
2. **Home 置灰断言竞态**：原以「锚点条目数变化」当收敛信号，新旧链条目数相同（3/3）
   时立即退出；改为等目标状态（按钮置灰）。基线 0.6.0 同样会红，已实证。
3. **selftest 帧布局**：PDF 用例结束后把 webview 置 `translatesAutoresizingMaskIntoConstraints
   = false`，而它没有约束；后续任何 Auto Layout 通过都会把它压成 0 宽（新增抽屉视图
   触发后暴露）。改为保持帧驱动并复位 frame。

## 5. 文档落点

| 结论 | 落点 |
|---|---|
| 需求与三选一确认 | `REQ-0014`（accepted：SCN-0001 既有验证债未清） |
| 场景与 3+1 测试 | `SCN-0020`（verified）；`SCN-0001` 过滤口径补注 |
| 契约与偏好单写入口 | `CMP-drawer` 规格 `#hidden-toggle` / `#scan-level` |
| 跨窗口分发 | `CMP-app-shell` 规格 `#drawer-hidden-toggle` |
| 行为取舍 | `architecture.md` §2.4 |
| 路线图 | `plan/roadmap.md` 本工序行 |

## 6. 未决

- 2026-11-17 用户确认提交并推送本版本；工序 `closed`，已归档 `history/works/`。
- 隐藏条目里非可打开文件（`.env`、`.gitignore`）仍不进树（产品口径，非缺陷）。
