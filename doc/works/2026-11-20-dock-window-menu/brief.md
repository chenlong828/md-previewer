---
layer: works
module: shell
status: active
updated: 2026-11-20
---

# 工序：Dock 右键菜单切换已打开窗口

> 需求卡：[REQ-0015](../../requirements/REQ-0015-dock-menu-window-switch.md)；
> 场景：[SCN-0021](../../design/scenarios/navigation/windows/dock-window-switch/scenario.md)。
> 本页是执行记录；why / 非目标 / 验收以卡为准。

## 1. 需求

多窗口下，Dock 图标右键菜单顶部列出当前所有已打开窗口（文件名，当前窗口带勾选），
点击即切换/前置；替代反复 ⌘` 或进「显示所有窗口」找窗口。形态参照 PowerPoint 的 Dock 菜单。

用户 2026-11-20 三选一确认：只列已打开窗口；文件名 + 勾选当前窗口；不加关闭/批量管理动作。

## 2. 组件设计（修改方案）

改动落在一个组件 `CMP-app-shell` 的 `AppDelegate`，不新增组件、不动桥协议与 web 层。

```
AppKit ──展开 Dock 菜单──▶ AppDelegate.applicationDockMenu
                               │ 返回（首次创建）dockMenu
                               ▼
                          rebuildDockMenu（菜单 delegate.menuNeedsUpdate 也走这里）
                               │ 逐 documents：标题 = window.title
                               │ 勾选 = (controller === currentDocument)
                               ▼
                          NSMenuItem(representedObject: DocumentWindowController)
                               │ 点击
                               ▼
                          focusDocumentWindow → activate + deminiaturize + makeKeyAndOrderFront
```

### 外部契约调整

- 新增能力 `CMP-app-shell#dock-menu`（条目集合、勾选规则、点击语义）；不改变既有能力。
- 无持久化结构、无配置项、无桥协议变更。

### 组件间关系

- `AppDelegate` 只读取既有 `documents` 与 `currentDocument`，不新增所有权；
  条目的 `representedObject` 是弱语义引用（菜单每次重建，不跨展开持有）。
- `DocumentWindowController` 不感知 Dock 菜单；标题与路径来自既有 `window.title` /
  `revealTargetURL`。

### 修改点与波及面

- 改：`AppDelegate`（Dock 菜单构建 + 动作 + 菜单 delegate 复用 `menuNeedsUpdate`）、
  `main.swift`（新增 `--dockmenu-test` 自检分支）。
- 不受影响：文件 IO、编辑器、抽屉、导出、缩略图、窗口打开/关闭路由、右键菜单。

## 3. 验收标准

- `--dockmenu-test` 3 正 1 反全绿（条目对应、勾选跟随、点击切换 + 最小化恢复、关闭后条目消失）。
- `--selftest` / `--multiwindow-test` 不回归。
- 人工：构建后右键 Dock 图标，确认条目位置、顺序与点击切换。

## 4. 任务表

| ID | 类型 | 组件 | 任务 | 状态 | 装载清单 |
|---|---|---|---|---|---|
| T1 | design | — | 需求卡、场景卡、修改方案（本页 §2） | 完成 | `AppDelegate.swift`、`DocumentWindowController` 标题/路径入口 |
| T2 | change | CMP-app-shell | `applicationDockMenu` + `rebuildDockMenu` + `focusDocumentWindow`；规格同步 | 完成 | 同 T1 + `doc/design/components/CMP-app-shell/spec.md` |
| T3 | verify | — | `--dockmenu-test` 落 3+1 断言并跑绿；SCN-0021 → verified、REQ-0015 → delivered | 完成（自动门全绿；人工点验待做） | `main.swift` 既有测试分支、`--multiwindow-test` |

## 5. 风险与边界

- Dock 菜单展开时机由 AppKit 决定：用「每次展开重建」而不是缓存条目，避免勾选/条目过期。
- 菜单动作在窗口已关闭时必须 no-op，不能误激活其它窗口。
- 同名窗口（两个「未命名」）靠 `representedObject` 区分，不靠标题查找。
- 真实 Dock 呈现无法自动断言，登记为人工验证债（场景卡 §6）。
