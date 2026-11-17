---
layer: design
module: navigation
status: verified
updated: 2026-11-13
flow: FLOW-NAV-001
scenario: SCN-0020
domain: 导航
valueStream: 文件抽屉
title: 在文件抽屉切换显示隐藏条目
entries:
  - CMP-drawer/Sources/MDPreview/FileDrawerView.swift#setShowsHidden
  - CMP-drawer/Sources/MDPreview/FileDrawerView.swift#toggleHiddenAction
  - CMP-drawer/Sources/MDPreview/DirectoryTree.swift#scanLevel
  - CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applyDrawerShowHiddenToAllDocuments
docs:
  - path: doc/design/architecture.md
    heading: 2.4 文件抽屉与目录模式
  - path: doc/requirements/REQ-0014-file-drawer-hidden-toggle.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-HIDDEN-001
  - role: R2
    id: TC-HIDDEN-002
  - role: R3
    id: TC-HIDDEN-003
  - role: N1
    id: TC-HIDDEN-004
---

# 在文件抽屉切换显示隐藏条目

## 1. 场景与价值

用户在文件抽屉头部点「显示隐藏文件与隐藏目录」按钮，树里立即出现 `.git`、`.github`、
`.config` 等隐藏目录与 `.env.example` 等隐藏文件；再点一次恢复隐藏。开关是全局偏好：
其它窗口同步切换，重启后保持。

结果：项目里的隐藏文档与配置可以直接在应用内浏览，不必切到 Finder（⌘⇧.）或命令行。

本场景不覆盖打开/保存内容、锚点重锚、宽度拖拽；这些归 SCN-0001。

## 2. 入口

- `CMP-drawer#hidden-toggle`：`FileDrawerView.toggleHiddenAction` / `setShowsHidden`。
- `CMP-drawer#scan-level`：`DirectoryTree.scanLevel(of:includeHidden:)`。
- `CMP-app-shell`：`AppDelegate.applyDrawerShowHiddenToAllDocuments`（跨窗口广播）。

## 3. 运行序

流程定义：`FLOW-NAV-001`（显示隐藏分支）。

1. 抽屉初始化：按 `UserDefaults["fileDrawerShowsHidden"]`（默认 false）设置按钮外观与扫描口径。
2. 用户点按钮：写偏好 → 更新按钮（`eye`/`eye.slash` + 提示 + 强调色）→ 重扫当前根层，
   可见目录的展开态保持 → 回调控制器广播所有窗口。
3. 扫描：`includeHidden == false` 跳过隐藏条目；`true` 时按 Finder 口径（`.` 前缀或
   `isHidden` 资源键）放行，但仍跳过符号链接、`node_modules`、包目录与非可打开文件。
4. 其它窗口收到广播：只应用状态与按钮（根层未装载则不扫描），下次装载按新口径执行。
5. 重启/新窗口：从偏好初始化，树按记忆口径显示。

失败路径：

- 根目录不可读：扫描抛错，抽屉显示空态（与 SCN-0001 同口径），开关仍可切换。
- 隐藏目录无权限：展开为空，不重试、不弹错。
- 偏好缺失/类型不对：按 false（不显示隐藏条目）处理。

## 4. 不可变引用

- 可打开文件过滤单点：`FileSupport.isOpenable`，隐藏开关不改变文件类型口径。
- 噪音跳过规则不变：符号链接、`node_modules`、包目录。
- 锚点/重锚、双击同窗打开、宽度拖拽、空态文案不变。
- 隐藏口径与 Finder 一致（`isHidden` 资源键），不另造第二套判定。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-HIDDEN-001 | R1 | 自动 | `--selftest` | 默认只显示可见条目（1 行）；打开后隐藏文件/隐藏目录出现（4 行）且偏好落盘 | present |
| TC-HIDDEN-002 | R2 | 自动 | `--selftest` | 目录扫描 `includeHidden: true` 放行 `.` 前缀与 Finder 标记，`node_modules`/包/符号链接仍跳过 | present |
| TC-HIDDEN-003 | R3 | 自动 | `--drawer-test` + `--multiwindow-test` | 按钮默认关、打开落盘、关闭复位；跨窗口同步开/关 | present |
| TC-HIDDEN-004 | N1 | 自动 | `--selftest` | 关闭后回到 1 行且偏好复位；偏好记忆对新窗口生效（4 行） | present |

## 6. 验证债

- 真实鼠标点击按钮与跨窗口视觉同步未做像素级断言（自动门走同一 action 路径）。
- Finder 隐藏标记由测试用 `setResourceValue(isHiddenKey)` 构造；`chflags hidden` 走同一资源键，未单独造例。

## 7. 变更记录

- 2026-11-13 新建：文件抽屉隐藏条目开关（REQ-0014）。
