---
layer: design
module: navigation
status: designed
updated: 2026-11-04
flow: FLOW-NAV-001
scenario: SCN-0001
domain: 导航
valueStream: 文件抽屉
title: 浏览文件抽屉并打开文档
entries:
  - CMP-drawer/Sources/MDPreview/FileDrawerView.swift#load
  - CMP-drawer/Sources/MDPreview/DirectoryTree.swift#scanLevel
  - CMP-drawer/Sources/MDPreview/DirectoryTree.swift#ancestorChain
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDirectory
docs:
  - path: doc/design/architecture.md
    heading: 2.4 文件抽屉与目录模式
  - path: doc/requirements/REQ-0001-file-drawer.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-DRAWER-001
  - role: R2
    id: TC-DRAWER-002
  - role: R3
    id: TC-DRAWER-003
  - role: N1
    id: TC-DRAWER-004
---

# 浏览文件抽屉并打开文档

## 1. 场景与价值

用户打开一个 Markdown 或目录后，从左侧抽屉浏览同目录文件：展开目录按层读取、顶部锚点显示父级链、Home/刷新可换根，双击文件在当前窗口打开。

结果：跨文件浏览不离开当前窗口，目录模式与单窗口模型成立。

本场景不覆盖文件内容读写、Markdown 渲染、图片资源；这些分别归 SCN-0002/0005/0011。

## 2. 入口

- `CMP-drawer#scan-level`：`FileDrawerView.load` / `DirectoryTree.scanLevel`。
- `CMP-drawer#anchor`：`DirectoryTree.ancestorChain` / `DrawerAnchorControl.update`。
- `CMP-app-shell#open-document`：`DocumentWindowController.openDirectory` 进入目录模式。

## 3. 运行序

流程定义：`FLOW-NAV-001`。

1. 打开文件或目录：外部打开默认新窗口；目录模式在当前窗口进入，右侧空白文档。
2. 抽屉装载根层：只扫当前层；过滤隐藏/符号链接/`node_modules`/包目录；文件夹在前，只列可打开 Markdown。
3. 展开目录：同步读取下一层并插入子行；lazy 不预读后代。
4. 锚点：显示根到当前目录的父级链；选中父级重锚；刷新重扫当前根；Home 切到用户目录。
5. 打开：双击文件在当前窗口覆盖打开；脏文档先确认；抽屉双击保持锚点，不重锚到文件所在层。
6. 宽度：拖拽 160–480pt，正文不窄于 320pt；宽度/开合跨窗口记忆。

失败路径：

- 根不可读：扫描抛错，抽屉不显示半棵树。
- 无 Markdown 的目录：仍显示（lazy 语义），展开为空。
- 装载中双击：请求暂存，装载完成后执行，不丢点击。

## 4. 不可变引用

- `architecture.md` §2.4 的锚点/重锚契约与窗口宽度收敛。
- 抽屉双击“同窗覆盖”语义；外部打开“新窗/重锚”语义。
- 目录树过滤：隐藏条目、符号链接、`node_modules`、包目录整棵跳过。
- Finder 图标来源：`FinderIcon` 单点，树与锚点菜单共用。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-DRAWER-001 | R1 | 自动 | `--selftest` | `PASS 目录扫描-lazy 根层装载,子目录未装载` | present（2026-10-21 全绿） |
| TC-DRAWER-002 | R2 | 自动 | `--selftest` | `PASS 锚点链-根到锚点完整父级序列` | present |
| TC-DRAWER-003 | R3 | 自动 | `--drawer-test --dir=<tmp> --fileA=<tmp>/a.md` | `[DRAWER] PASS 双击打开后仍 1 个窗口(同窗覆盖)` | present |
| TC-DRAWER-004 | N1 | 自动 | `--selftest` | `PASS 目录扫描-根不可读抛错` | present |

3 正 1 反均有执行入口；尚未按本卡逐条复跑，暂 `designed`。复跑全绿后升 `verified`，REQ-0001 才可转 `delivered`。

## 6. 验证债

- 真实鼠标拖拽在无头环境 SKIP，需以命中测试/回调数学替代并登记。
- 最近文件/⌘O 打开后的重锚只在 drawer-test 覆盖部分路径。

## 7. 变更记录

- 2026-11-04 五态补录，来源：`architecture.md` §2.4、drawer-test、file-drawer/drawer-anchor 工序 result。
