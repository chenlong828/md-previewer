---
layer: design
module: navigation
component: CMP-drawer
status: active
updated: 2026-11-04
---

# CMP-drawer 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L2 整合；业务能力（文件导航）
- 业务价值：让用户在单窗口里浏览并打开同目录/相邻目录的 Markdown 与代码文件，而不必反复 ⌘O；没有它，目录模式与跨文件浏览不成立。
- 负责：左侧抽屉 UI、树形数据源、按层懒加载、锚点父级链、Home/刷新、宽度拖拽与记忆、双击同窗打开。
- 不负责：文件内容读写（`CMP-document-io`）、窗口替换策略（`CMP-app-shell`）、Markdown 渲染（`CMP-editor`）、代码渲染（`CMP-code-view`）。
- 内部逻辑：`DirectoryTree` 负责扫描/锚点链；`FileDrawerView` 负责 outline 数据源与行视图；`DrawerAnchorControl` 负责父级菜单；`DrawerResizeDivider` 负责宽度拖拽。
- 拥有的数据：当前锚点根、展开节点、抽屉宽度/开合状态；不拥有文件内容。
- 变化轴：树过滤规则（可打开文件种类）、锚点语义、宽度约束、目录模式入口。
- 公开契约（含能力 ID）：
  - `CMP-drawer#open-close`：⌘\ 开合；开合状态跨窗口记忆。
  - `CMP-drawer#scan-level`：只读当前层；展开时同步读下一层；跳过隐藏/符号链接/`node_modules`/包目录；只列可打开文件（Markdown + 代码，`FileSupport.isOpenable` 单一判定）。
  - `CMP-drawer#anchor`：显示根到当前目录的父级链；选中父级即重锚；抽屉双击保持锚点。
  - `CMP-drawer#open-file`：双击在当前窗口覆盖打开；脏文档先确认。
  - `CMP-drawer#resize`：拖拽边界 160–480pt，正文不窄于 320pt。
  - `CMP-drawer#home-refresh`：Home 回到用户目录；刷新重扫当前根。
- 入口：
  - `CMP-drawer/Sources/MDPreview/FileDrawerView.swift#load`
  - `CMP-drawer/Sources/MDPreview/DirectoryTree.swift#scanLevel`
  - `CMP-drawer/Sources/MDPreview/DirectoryTree.swift#ancestorChain`
  - `CMP-drawer/Sources/MDPreview/DrawerAnchorControl.swift#update`
  - `CMP-drawer/Sources/MDPreview/DrawerResizeDivider.swift`
  - `CMP-drawer/Sources/MDPreview/FinderIcon.swift#folder`
  - `CMP-drawer/Sources/MDPreview/DocumentWindowController.swift#openDirectory`
- 依赖：`CMP-app-shell`（窗口/焦点）、`CMP-document-io`（打开目标）、`CMP-code-view`（`#kind` 过滤判定）、`CMP-image` 无关。
- 冷热属性：冷路径；扫描在后台队列，不阻塞编辑输入。
- 尺寸预算：目标 ≤120k token；当前约 858 行（FileDrawerView 455 + Anchor 201 + DirectoryTree 112 + Divider 76 + Icon 14），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --drawer-test --dir=<tmp> --fileA=<tmp>/a.md --fileB=<tmp>/b.md`。
- 验证计划：目录扫描/锚点链用 selftest；抽屉 UI/宽度/目录模式用 drawer-test；真实鼠标拖拽在无头环境 SKIP 时以命中测试与回调数学替代。
- 删除测试：删掉后目录导航与目录模式消失，复杂度集中 → 真边界。

## 公开契约细节

- `#scan-level` 的不变量：lazy 下不递归后代；根不可读抛错；排序文件夹在前；`.markdown` 也识别。
- `#anchor` 的不变量：外部/⌘O/最近打开重锚到文件所在目录；抽屉内双击不重锚；从子层打开保持原锚点。
- `#open-file` 的不变量：同窗覆盖，不新增窗口；目录模式打开文件后退出目录模式。
- `#resize` 的错误模式：夹取后仍满足正文 ≥320；松手后从当前宽度续算；记忆写 `fileDrawerWidth`。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#scan-level` | `--selftest`：目录扫描 6 项（lazy 根层、过滤排序、node_modules、子层、descendant、根不可读） |
| `#anchor` | `--selftest`：锚点链 2 项；`--drawer-test`：条目数=父级链、保持锚点、重锚 |
| `#open-file` | `--drawer-test`：双击后仍 1 窗口、fileURL、标题、退出目录模式 |
| `#resize` | `--drawer-test`：160–480、正文 ≥320、宽度记忆、命中测试 |
| `#home-refresh` | `--drawer-test`：Home 重锚、刷新重扫 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 锚点根 / 展开节点 | 本组件 | 本组件 | 单窗口 |
| 宽度 / 开合 | `FileDrawerView` | 窗口控制器 | UserDefaults |

## 删除测试

删掉后文件树、锚点、目录模式没有替代归属 → 真边界。
