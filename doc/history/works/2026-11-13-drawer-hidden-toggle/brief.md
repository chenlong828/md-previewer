---
layer: history
module: navigation
status: frozen
updated: 2026-11-13
---

# 工序 brief：文件抽屉显示隐藏文件开关（功能 / P2）

## 1. 问题与目标

用户在文件抽屉里看不到以 `.` 开头的文件/目录（以及 Finder 里标记为隐藏的条目），
需要反复切到 Finder 或命令行。目标：抽屉头部加一个按钮开关，一键切换是否显示
隐藏文件与隐藏目录；开关状态全局记忆。

## 2. 决策（用户 2026-11-13 三选一确认）

| 问题 | 选择 |
|---|---|
| 隐藏口径 | **Finder 口径**：`.` 前缀或 Finder 隐藏标记（`URLResourceValues.isHidden`，含 `chflags hidden`）；`node_modules`/包目录/符号链接仍跳过 |
| 开关状态 | **全局记忆**：写 `UserDefaults["fileDrawerShowsHidden"]`（默认 false），所有窗口同步，重启保持 |
| 按钮位置 | **抽屉头部图标按钮**：锚点控件右侧、Home 左侧；`eye.slash`=隐藏中，`eye`=已显示，激活时用强调色 |

设计要点：

- 隐藏判定单点在 `DirectoryTree.scanLevel(of:includeHidden:)`：一次 `resourceValues`
  同时取 `isDirectory/isSymbolicLink/isRegularFile/isPackage/isHidden`，按同一口径
  过滤；不新增第二套隐藏判定（与 Finder 一致）。
- `FileDrawerView` 持有当前状态与按钮；点击 → 写偏好 → `rescan()`（根层重扫 +
  恢复可见展开态）→ 回调控制器广播所有窗口。广播走
  `AppDelegate.applyDrawerShowHiddenToAllDocuments`，与缩略图/行号偏好同款模式；
  抽屉的 `setShowsHidden(_:)` 只应用状态与重扫，不写偏好、不再广播（防回环）。
- 只列可打开文件（Markdown/代码）的规则不变；隐藏文件里非可打开类型仍不出现，
  隐藏目录可展开但内容同样按可打开类型过滤。
- 空态文案不变（“无 Markdown 文件”）。

## 3. 影响与契约

- 组件：`CMP-drawer`（扫描口径 + 头部按钮 + 偏好）与 `CMP-app-shell`（跨窗口广播、
  诊断入口几何断言）。
- 公开契约：新增 `CMP-drawer#hidden-toggle`；`CMP-drawer#scan-level` 增加
  `includeHidden` 参数（默认 false，保持既有调用方语义）。
- 不受影响：打开/保存、锚点/重锚、宽度拖拽、双击打开、编辑器/导出/缩略图。

## 4. 任务

| ID | 任务 | 类型 | 组件 | 状态 |
|---|---|---|---|---|
| T1 | `DirectoryTree.scanLevel` 增加 Finder 口径隐藏过滤参数 | change | CMP-drawer | 完成 |
| T2 | 抽屉头部第三个图标按钮 + 偏好读写 + 重扫 | change | CMP-drawer | 完成 |
| T3 | 跨窗口广播 + drawer-test 头部几何（三按钮）与开关断言 | change | CMP-app-shell | 完成（含 3 处既有测试时序修复） |
| T4 | selftest：隐藏口径扫描用例 + 抽屉视图开关用例 | change | CMP-drawer | 完成（+6 项） |
| T5 | 需求/场景/规格/架构/路线图同步与工序归档 | doc | — | 完成（归档待用户点验） |

## 5. 验收

- `--selftest`：新增「目录扫描-隐藏口径（Finder 标记也识别）」「目录扫描-显示隐藏后
  仍跳过 node_modules/包/符号链接」「抽屉-显示隐藏开关（行数/偏好/按钮状态）」。
- `--drawer-test`：头部三按钮几何；隐藏按钮存在、切换后偏好与按钮状态正确。
- `cd web && npm run verify` 不回归。
- 人工：抽屉里切换后隐藏文件立即出现/消失，跨窗口同步，重启保持。

## 6. 非目标

- 不做文件/目录分开两个开关；不做按目录记忆；不做排序/搜索变化；
  不解禁符号链接跟随；不改变 `node_modules`/包目录跳过规则。
