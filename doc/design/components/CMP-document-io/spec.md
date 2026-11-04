---
layer: design
module: persistence
component: CMP-document-io
status: active
updated: 2026-11-04
---

# CMP-document-io 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1 领域；技术边界
- 业务价值：保证「打开的文件不坏、保存的文件可读」：编码识别、UTF-8 回写、尾换行、列表缩进规范化、脏基线与外部变更处理都在这里；没有它，编辑器只是内存里的临时文本。
- 负责：读文件并识别 UTF-8/GB18030；按 `CMP-code-view#kind` 分派装载路径（Markdown 进编辑器、代码进只读视图）；保存时取编辑器 Markdown、规范化、UTF-8 回写；维护脏基线与外部变更监听；关闭前保存确认；把图片路径改写/清理委托给 `CMP-image`。
- 不负责：Markdown 解析/渲染（`CMP-editor`）、窗口与菜单（`CMP-app-shell`）、图片文件落盘（`CMP-image`）。
- 内部逻辑：`TextFile.read/write` 负责字节与编码；`DocumentWindowController` 的 open/save/dirty/monitor 负责生命周期；保存规范化依赖编辑器的 `getMarkdown` 与图片路径 `forSave`。
- 拥有的数据：磁盘上的 Markdown 文件、当前编码名、脏基线、最后已知文件属性；唯一写入口是保存路径。
- 变化轴：编码支持、保存规范化规则、外部变更策略。
- 公开契约（含能力 ID）：
  - `CMP-document-io#open`：打开文件，返回文本与编码；UTF-8 优先，失败回退 GB18030；按 `FileSupport.kind` 分派 Markdown/代码，未知扩展名拒绝。
  - `CMP-document-io#code-readonly`：代码文档只读装载（无脏基线、不发 changed、关闭不弹保存）；外部变更自动重载并保留高亮语言选择。
  - `CMP-document-io#save`：保存当前内容；恒 UTF-8、补尾换行、图片路径 `forSave` 后写盘。
  - `CMP-document-io#dirty-baseline`：以保存/加载后的文档为干净基线；纯查看不误报。
  - `CMP-document-io#external-change`：磁盘变更时，干净则自动重载，脏则询问保留或重载。
  - `CMP-document-io#close`：关闭前处理脏文档；触发 `CMP-image#cleanup`。
- 入口：
  - `CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#openDocument`
  - `CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#saveDocument`
  - `CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#save`
  - `CMP-document-io/Sources/MDPreview/DocumentWindowController.swift#fileChangedOnDisk`
  - `CMP-document-io/Sources/MDPreview/Util.swift#TextFile`
- 依赖：`CMP-editor`（取 Markdown）、`CMP-code-view`（种类判定/代码装载目标）、`CMP-image`（路径改写/清理）、`CMP-app-shell`（窗口与退出）。
- 冷热属性：冷路径；保存/打开是低频同步动作。
- 尺寸预算：目标 ≤120k token；当前约 600 行（DocumentWindowController 的 open/save/monitor + Util.TextFile 300 行），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`（T3/D1）；打开/保存/编码用手工样本。
- 验证计划：T3 打开即脏、D1 markClean、源码保存一致；编码/尾换行/外部变更/关闭确认用人工记录。
- 删除测试：删掉后文档无法持久化，复杂度转移到每个调用方 → 真边界。

## 公开契约细节

- `open` 的不变量：不修改原文件；识别失败时明确报错，不静默当 UTF-8；扩展名未命中 `FileSupport` 时拒绝装载，不按 Markdown 解析。
- `code-readonly` 的不变量：代码文档无脏基线、无写入口；保存/另存为/HTML 导出在菜单与代码路径双重禁用；换文档或回到 Markdown 时重置语言选择。
- `save` 的不变量：输出恒 UTF-8；末尾恰好一个换行；图片路径已按 `CMP-image#for-save` 改写；写失败不破坏原文件（先写临时文件再替换，或等价原子策略）。
- `dirty-baseline` 的不变量：加载后、保存后、源码模式切换后基线一致；撤销回原文恢复干净。
- `external-change` 的错误模式：文件消失/不可读时保留当前内容并提示；脏冲突由用户决定，不自动覆盖。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#open` / `#save` | 人工：UTF-8、GB18030、含空格图片路径、无尾换行样本 |
| `#code-readonly` | `--selftest`：「代码视图 自动语言与高亮」「代码视图 未知扩展名不装载」「代码视图 退出代码模式」 |
| `#dirty-baseline` | `--selftest`：「T3 打开文件即脏回归」「D1 markClean 基线等于所见」 |
| `#save` 源码一致 | `--selftest`：「D1 源码模式保存取一致内容」 |
| `#external-change` | 人工：外部修改干净/脏文档两条路径 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| Markdown 文件 | 本组件 `save` | `CMP-editor`、导出 | 单写入口 |
| 编码名 / 脏基线 / 文件属性 | 本组件 | 本组件 | 单文档 |

## 验证债

编码识别、尾换行、外部变更与关闭确认目前没有可重复的自动化 3+1；在这些测试补齐前，相关场景最高 `designed`。

## 删除测试

删掉后打开/保存/脏标记没有归属，复杂度集中到本组件 → 真边界。
