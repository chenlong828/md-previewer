---
layer: design
module: shell
component: CMP-app-shell
status: active
updated: 2026-11-04
---

# CMP-app-shell 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L2 整合；技术边界 + 应用编排
- 业务价值：为使用者提供「一个进程、一个 Dock 图标、多个文档窗口」的 macOS 应用外壳；没有它，文件无法被打开到正确的窗口，菜单/快捷键/最近文件也没有统一入口。
- 负责：应用启动与参数路由、窗口创建/替换/关闭、菜单与快捷键、最近文件、缩放与外观的应用、退出前的脏文档确认。
- 不负责：文件内容读写（`CMP-document-io`）、编辑器内部行为（`CMP-editor`）、抽屉树（`CMP-drawer`）、导出实现（`CMP-export`）。
- 内部逻辑：`AppDelegate` 维护文档窗口集合与打开路由；`DocumentWindowController` 承载单文档窗口；`EditorCommands` 是菜单/右键共用的命令表。
- 拥有的数据：窗口 frame、最近文件列表、缩放比例、外观锁定；不拥有文档正文。
- 变化轴：打开方式的增减（CLI/拖放/Finder/⌘O/最近）、窗口模型、菜单命令表。
- 公开契约（含能力 ID）：
  - `CMP-app-shell#open-document`：按文件/目录参数打开；外部打开默认新窗口，⌘O/最近文件在当前窗口替换。
  - `CMP-app-shell#new-window`：⌘N 创建空白文档窗口。
  - `CMP-app-shell#multi-window`：单进程、单 Dock、每文档独立窗口。
  - `CMP-app-shell#recent-files`：最近文件列表与清除。
  - `CMP-app-shell#menu-commands`：`EditorCommands` 为菜单与右键的唯一命令真源。
  - `CMP-app-shell#zoom`：⌘+ / ⌘− / ⌘0，比例持久化。
  - `CMP-app-shell#appearance`：跟随系统或锁定浅/深色。
  - `CMP-app-shell#quit`：有脏文档时先确认，取消则不退出。
- 入口：
  - `CMP-app-shell/Sources/MDPreview/main.swift#args`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applicationDidFinishLaunching`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#openInNewWindow`
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDocument`
  - `CMP-app-shell/Sources/MDPreview/EditorCommands.swift#EditorCommands`
- 依赖：`CMP-document-io`（打开/保存）、`CMP-editor`（内容面）、`CMP-drawer`（目录导航）、`CMP-export`（导出）、`CMP-diagnostics`（测试入口）。
- 冷热属性：冷路径；不进入编辑输入热路径。
- 尺寸预算：目标 ≤120k token；当前约 1.1k 行（main 362 + AppDelegate 476 + EditorCommands 104 + 窗口编排部分），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --multiwindow-test --fileA=a.md --fileB=b.md`；菜单/缩放用 `--selftest`。
- 验证计划：多窗口数量/标题、菜单命令注册表完整、缩放应用、深色主题切换、退出脏确认（人工）。
- 删除测试：删掉后没有窗口与打开路由，复杂度不会消失只会散落到每个文件 → 真边界。

## 公开契约细节

- `open-document` 的 `reanchor` 语义：外部打开（CLI/拖放/Finder/最近）重锚到文件所在目录；抽屉内双击不重锚。
- `multi-window` 的不变量：同一文档不在两个窗口同时打开；目录模式只占一个窗口；⌘O 与最近文件替换当前窗口。
- `quit` 的错误模式：用户取消则 `applicationShouldTerminate` 返回 `.terminateCancel`，不丢未保存内容。
- `menu-commands` 的不变量：`EditorCommands.all` 的动作集合与菜单/右键实际动作一致；新增命令只改一处。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#multi-window` | `--multiwindow-test`：窗口数为 2、标题不重复 |
| `#menu-commands` | `--selftest`：「命令注册表完整」「桥命令名双端一致」 |
| `#zoom` | `--selftest`：「缩放应用」 |
| `#appearance` | `--selftest`：「深色主题切换」 |
| `#open-document` / `#quit` | 人工：CLI/拖放/⌘O/最近 + 脏文档退出 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 最近文件 | `AppDelegate.addRecentFile` | 菜单 | 单进程 |
| 窗口 frame / 缩放 / 外观 | 本组件 | 本组件 | UserDefaults |
| 文档正文 | `CMP-document-io` | 本组件只传引用 | 不复制 |

## 删除测试

删掉本组件，窗口/菜单/最近文件/退出确认没有替代归属，复杂度集中而非消失 → 保留为真边界。
