---
layer: design
module: media
component: CMP-image
status: active
updated: 2026-11-04
---

# CMP-image 组件规格

## 组件卡

- 状态：active（2026-11-04 收缩：路径语义移出，见下）
- 单元：组件
- 层 / 类型：L1 领域；业务能力（图片资源生命周期）
- 业务价值：让本地图片「导入得进来、布局稳定、关闭时清得干净、点开能改」；没有它，粘贴截图与相对路径图片退化为一串手工文件操作。
- 负责：粘贴/拖放/菜单导入的**落盘执行**（`ImageStore.import`，mime 定扩展名、序号命名、冲突后缀、不覆盖）、`resource/<md文件名>/` 布局、关闭时 GC 的**执行**（按壳取到的引用集合删盘、非图片不动、空目录连带移除）、图片 NodeView 的渲染与整块源码编辑（`web/src/kernel/components/editor/image-view.js`）。
- 不负责：图片路径的加载/保存改写与引用解析（**已移交 `CMP-kernel-semantics`**）、粘贴载荷识别与导入编排（`CMP-kernel-media#import`）、文档正文读写（`CMP-document-io`）、通用编辑命令（`CMP-editor`）、代码文档（无图片面：导入/插入/清理全部 no-op）。
- 内部逻辑：Swift `ImageStore` 做导入/命名/目录布局/删盘；`DocumentWindowController.performImport` 把核的 `importImage` 请求翻成 `ImageStore.import` 并以响应回填 `{ok, src}`；web `core/image-paste.js` 识别载荷并发请求，`core/image-view.js` 提供 NodeView。**规则在 `semantics`，本组件只执行与呈现。**
- 拥有的数据：`resource/<md文件名>/` 下的图片文件与目录布局；唯一写入口是导入与 GC；不拥有 Markdown 正文，也不拥有引用解析结果。
- 变化轴：图片格式与 mime→扩展名映射、resource 布局、GC 策略、NodeView 交互。
- 公开契约（含能力 ID）：
  - `CMP-image#for-load`：**已移除**（2026-11-04）。原「相对路径 → 可加载 file://」改写现由 `CMP-kernel-semantics#for-load` 提供，存在性由壳的 `resolveResources` 作答。
  - `CMP-image#for-save`：**已移除**（2026-11-04）。原「file:// → 相对路径」还原现由 `CMP-kernel-semantics#for-save` 提供，经 `getSaveMarkdown` op 取用。
  - `CMP-image#import`：剪贴板位图/图片文件/菜单导入 → 落盘到 resource 目录，返回插入用的 `src`（绝对 `file://`）；失败原样抛错由壳弹窗。
  - `CMP-image#cleanup`：关闭时按引用集合删盘；非图片保留；目录清空连带移除；代码文档不触发。
  - `CMP-image#node-view`：图片整块源码编辑；提交/失焦生效，Esc/非法语法还原，清空删除。
- 入口：
  - `CMP-image/Sources/MDPreview/ImageStore.swift#import`（落盘与命名，含 `directory(for:)`、`isImageFile`）
  - `CMP-image/Sources/MDPreview/ImageStore.swift#cleanUnreferenced`（GC 执行，入参是壳取到的 `referenced: Set<String>`）
  - `CMP-image/Sources/MDPreview/DocumentWindowController.swift#performImport`（内核 `importImage` 请求的应答方）
  - `CMP-image/web/src/kernel/semantics/markdown.js#applyForLoad`（**引用解析与改写**，归 `CMP-kernel-semantics`；列出以示归属转移）
  - `CMP-image/web/src/kernel/components/media/image-paste.js#setupImagePaste`（载荷识别与请求编排）
  - `CMP-image/web/src/kernel/components/editor/image-view.js#getImageView`（NodeView）
- 依赖：`CMP-kernel-semantics`（路径与引用规则）、`CMP-kernel-editor`（NodeView 宿主）、`CMP-kernel-media`（导入编排）、`CMP-document-io`（保存链路取 `getSaveMarkdown`）、`CMP-app-shell`（保存前提示、`resolveResources` 作答）。
- 冷热属性：冷路径；导入、GC、NodeView 打开都是低频动作。
- 尺寸预算：目标 ≤120k token；当前约 480 行（`ImageStore.swift` 169 + 控制器导入/GC 分支约 60 + web `image-paste`/`image-view` 250）；语义部分已移出（311 行归 `CMP-kernel-semantics`）。
- 单独运行：`./.build/debug/MDPreview --selftest`；真实粘贴用 `MDP_IMPORT_IMAGE` 钩子与截图。
- 验证计划：导入命名/冲突/拒绝、GC 四类用 selftest；路径改写/还原的字节级正确性由 Node 语义套件（45 项黄金对拍）承担，不再在 Swift 侧断言。
- 删除测试：删掉后图片落盘与 GC 执行没有归属，复杂度转移到文件层与编辑器 → 真边界。

## 公开契约细节

- `#import` 的不变量：剪贴板位图命名 `img_NNN.ext`（目录内最大序号 +1，mime 定扩展名），文件导入保留原名、冲突加 `-2`/`-3`；不覆盖既有文件；返回的 `src` 是绝对 `file://`，保存时由 `#for-save` 还原。
- `#import` 的错误模式：非图片、目录不可列举/不可写、未保存文档（无归属目录）→ 拒绝并由原生弹窗提示，绝不静默降级（静默当空目录会让序号回绕并覆盖既有图片）。
- `#cleanup` 的不变量：只删本组件管理的 resource 目录内、不在引用集合里的图片；引用集合由内核 `getResourceRefs` 提供（围栏内不算引用，字面与解码两口径取并集，宁多保护）；取不到集合时**保守跳过**，宁可不删。
- `#cleanup` 的错误模式：删盘失败只 `os_log` 不打断关闭；引用集合不可得也跳过并记日志。
- `#node-view` 的不变量：显示态按 `baseDir` 把 `file://` 相对化为原写法，提交时按 `baseDir` 解析回规范 `file://`；输入/输出对称，点开不动不产生脏标记。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#import` | `--selftest`：落盘 7 项（位图、命名、冲突、布局、非图片拒绝、不可列举拒绝、不覆盖） |
| `#cleanup` | `--selftest`：资源清理 4 项（孤儿删除、引用清空、空目录连带移除、无目录跳过）；引用集合经真内核 `getResourceRefs` 取得 |
| `#node-view` | `--selftest`：NodeView、点击编辑、提交、非法还原（反例）、清空删除 |
| `#for-load` / `#for-save` / 引用解析 | `cd web && npm test`：`web/test/semantics.test.js` 与 Swift 旧实现逐字节对拍 45 项（黄金件 `web/test/fixtures/semantics-golden.json`）；`web/test/core.test.js` 装载/保存/引用收集 3 项端到端；selftest「装载改写(内核改写+壳作答)」「保存口径(内核还原相对路径)」 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| `resource/<md>/` 图片 | 本组件导入/GC | 编辑器、导出 | 单文档单写入口 |
| resource 目录布局 | `ImageStore.directory(for:)` | 导入、GC、NodeView | 单一函数定义 |
| 引用集合 | 内核 `getResourceRefs`（派生） | 本组件 GC | 只读入参，不落状态 |
| 图片路径写法 | 壳（磁盘原文） | `CMP-kernel-semantics` | 本组件不改写 |

## 验证债

真实 ⌘V 粘贴（载荷→请求→落盘→回插全链路）依赖 `MDP_IMPORT_IMAGE` 截图钩子人工核对，selftest 只覆盖到「载荷识别 + 假壳应答」。GC 的「取不到引用集合则跳过」分支无负例断言。

## 删除测试

删掉后图片落盘、布局与 GC 执行没有替代归属 → 真边界。
