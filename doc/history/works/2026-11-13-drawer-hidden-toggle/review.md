---
layer: history
module: navigation
status: frozen
updated: 2026-11-13
---

# P2 设计评审：文件抽屉显示隐藏文件开关

## 1. 定级

**P2（组件内新能力 + 一条窗口级分发）**。理由：

- 触碰 `CMP-drawer` 的公开能力（新增 `#hidden-toggle`，`#scan-level` 增默认参数）并新增
  `CMP-app-shell` 的广播入口（`applyDrawerShowHiddenToAllDocuments`），属“跨文件/跨组件”；
- 不改模块切分、数据所有权、热路径与依赖方向；不新增第三方依赖；偏好键是新增单值；
- 失败可只回退本工序 diff，无迁移。

## 2. 阻断项

**无。** 未发现数据丢失或默认行为错误：默认 `includeHidden=false` 与旧行为逐条一致
（既有 6 项目录扫描断言全绿），偏好缺失按 false。

## 3. 现在必须定的决策（已定，用户三选一）

| 决策 | 选择 | 理由 |
|---|---|---|
| 隐藏口径 | Finder 口径：`isHidden` 资源键（含 `.` 前缀与 `chflags hidden`） | 用户选择；与 Finder ⌘⇧. 一致；一次 `resourceValues` 取全部属性，不为隐藏再读一遍 |
| 偏好范围 | 全局单值 `UserDefaults["fileDrawerShowsHidden"]` | 用户选择；与缩略图/行号同口径；新窗口按记忆初始化 |
| 入口形态 | 抽屉头部第三个图标按钮 | 用户选择；抽屉是导航面，开关属于抽屉自身，不占主菜单 |
| 写盘与广播分工 | 抽屉写偏好并重扫；AppDelegate 只分发状态 | 写入口唯一，防广播回环；其它窗口不装载根时不触发扫描 |
| 噪音规则 | 不随开关变化（node_modules/包/符号链接仍跳过） | 这些是噪音过滤，不是“隐藏”；放开会引入大目录与环 |

## 4. 验证结论（verified sound）

- **默认行为不变**：既有目录扫描 6 项断言逐条通过；`includeHidden` 默认参数不改变旧调用。
- **口径正确**：`.hidden.md`、`.hidden-dir/`、`setResourceValue(isHiddenKey)` 标记文件在开关
  打开后都出现，且 `b.txt`/`loop`/`node_modules`/`MyApp.app` 仍不出现。
- **偏好**：开→写盘、关→复位；新窗口按记忆显示 4 行；视图级用例收尾清理偏好，不污染环境。
- **跨窗口**：multiwindow 断言一窗切换后两窗状态同步（开/关）；未装载根的窗口只同步状态。
- **回归**：selftest 135、drawer-test 40、context-menu 12、multiwindow 15、web 87 全绿；
  包内连跑稳定。

## 5. Hold（不阻塞）

- 隐藏条目里非可打开文件仍不进树（与「只列可打开文件」契约一致）。
- 未做「隐藏文件/隐藏目录」两个独立开关、按目录记忆、主菜单入口（用户未选，登记为非目标）。
- 未做真实鼠标点击按钮的像素级断言；自动门走 `toggleHiddenAction` 同一路径。

## 6. 人工门

P2 人最终确认已通过：2026-11-17 用户确认提交并推送本版本。
