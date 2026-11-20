---
layer: works
module: shell
status: active
updated: 2026-11-20
---

# 工序结果：Dock 右键菜单切换已打开窗口

## 1. 交付内容

- Dock 图标右键菜单顶部按窗口创建顺序列出所有已打开窗口：标题 = 窗口标题，当前窗口带勾选，
  悬停提示为完整路径。
- 点击条目：激活应用、恢复最小化、目标窗口置前并成为 key window。
- 条目在每次展开菜单时重建（`applicationDockMenu` 是系统每次显示的调用点；Dock 菜单不触发
  `menuWillOpen` / `menuNeedsUpdate`，因此不做跨展开缓存）。
- 窗口关闭后条目立即消失；同名「未命名」窗口靠 `representedObject` 区分，不靠标题查找。
- 标准项（选项 / 显示所有窗口 / 隐藏 / 退出）仍由 macOS 附加，未自建。

## 2. 验收结果

| 门 | 命令 | 结果 |
|---|---|---|
| 场景 3+1（自动） | `./.build/debug/MDPreview --dockmenu-test` | 8 项全 PASS，exit 0 |
| 菜单/缩放/协议回归 | `./.build/debug/MDPreview --selftest` | `SELFTEST PASSED` |
| 多窗口/右键/抽屉回归 | `--multiwindow-test --fileA=… --fileB=…` | 15 项全 PASS，exit 0 |
| 右键定位回归 | `--context-menu-test` | 12 项全 PASS，exit 0 |
| 打包 | `./build.sh debug` | 前端 87 项 + Swift 编译 + 签名通过 |

`--dockmenu-test` 实际输出：

```text
[DOCKMENU] info active=false count=3 titles=["dock-a.md", "dock-b.md", "未命名"]
[DOCKMENU] PASS 条目数与窗口数一致(3/3)
[DOCKMENU] PASS 条目按创建顺序指向各窗口且标题一致(["dock-a.md", "dock-b.md", "未命名"])
[DOCKMENU] PASS 当前窗口单条勾选(1 条)
[DOCKMENU] PASS 勾选跟随当前窗口切换
[DOCKMENU] PASS 点击条目前置并恢复最小化窗口
[DOCKMENU] PASS 关闭的窗口从菜单消失(2 条)
[DOCKMENU] PASS 同名「未命名」窗口各自成条
[DOCKMENU] PASS 同名条目按 representedObject 定位到各自窗口
```

自检进程未被系统激活（`active=false`），自动断言以应用内最前窗口（`orderedWindows`）等价
“当前窗口”；真实激活态的 key window 与菜单呈现由人工点验覆盖。

## 3. 结论落点

| 结论 | 落点 |
|---|---|
| 能力契约、入口与不变量 | [CMP-app-shell#dock-menu](../../design/components/CMP-app-shell/spec.md) |
| 运行序、3+1 用例与验证债 | [SCN-0021](../../design/scenarios/navigation/windows/dock-window-switch/scenario.md)（`verified`） |
| 需求与非目标 | [REQ-0015](../../requirements/REQ-0015-dock-menu-window-switch.md)（`accepted`，待人工点验转 `delivered`） |
| 用户可见说明 | `README.md` 主要功能 / [doc/README.md](../../README.md) 导航 |
| 工序登记 | [roadmap](../../plan/roadmap.md) |

## 4. 未决与后续

- 真实右键 Dock 图标的菜单展开、条目位置与勾选视觉无法自动断言，待用户点验一次。
- 点验通过后：REQ-0015 → `delivered`，工序收口并整目录归档到 `history/works/`。
- 已知取舍：同名文件（例如两个不同目录下的 `note.md`）在菜单里标题相同，靠悬停提示与点击
  目标区分；用户已确认不加目录括注，保持菜单精简。

## 5. 变更文件

- `Sources/MDPreview/AppDelegate.swift`：`applicationDockMenu` / `rebuildDockMenu` /
  `focusDocumentWindow` / `dockCurrentDocument`。
- `Sources/MDPreview/DocumentWindowController.swift`：`revealTargetURL` 由 private 放宽为
  组件内可读（供条目 tooltip），行为不变。
- `Sources/MDPreview/main.swift`：新增 `--dockmenu-test` 自检分支（自备临时文档）。
- 文档：REQ-0015、SCN-0021、CMP-app-shell 规格、roadmap、doc 导航、README。
