---
layer: design
module: media
component: CMP-image
status: active
updated: 2026-11-04
---

# CMP-image 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L1 领域；业务能力（图片资源）
- 业务价值：让本地图片在 Markdown 里「显示得出来、导入得进来、关闭时清得干净」；没有它，粘贴截图和相对路径图片都会退化为手工文件操作。
- 负责：图片路径的加载/保存改写、粘贴/拖放/菜单导入落盘、`resource/<md文件名>/` 布局、关闭时孤儿清理、点击图片进源码编辑块；均限 Markdown 文档。
- 不负责：文档正文读写（`CMP-document-io`）、通用编辑命令（`CMP-editor`）、图片渲染框架本身（Milkdown NodeView）、代码文档（无图片面：导入/插入/清理全部 no-op）。
- 内部逻辑：`ImagePathRewriter` 做宽松解析与改写；`ImageStore` 做导入/命名/清理；web `image-paste.js` 识别载荷，`image-view.js` 提供 NodeView。
- 拥有的数据：`resource/<md文件名>/` 下的图片文件；唯一写入口是导入与清理；不拥有 Markdown 正文。
- 变化轴：图片格式、路径写法、resource 布局、清理策略。
- 公开契约（含能力 ID）：
  - `CMP-image#for-load`：把本地相对路径改写为可加载的 file://；容忍空格/括号，代码围栏不改。
  - `CMP-image#for-save`：把 file:// 还原为相对路径；含空格用 `<>` 包裹；缺失文件/远程图不改。
  - `CMP-image#import`：剪贴板位图/图片文件/菜单导入，复制到 resource 目录，返回插入引用。
  - `CMP-image#cleanup`：关闭时删除未被当前文档引用的图片；非图片保留；空目录移除；代码文档不触发清理。
  - `CMP-image#node-view`：图片整块源码编辑；提交/失焦生效，Esc/非法语法还原，清空删除。
- 入口：
  - `CMP-image/Sources/MDPreview/Util.swift#ImagePathRewriter`
  - `CMP-image/Sources/MDPreview/ImageStore.swift#import`
  - `CMP-image/Sources/MDPreview/ImageStore.swift#cleanUnreferenced`
  - `CMP-image/web/src/image-paste.js#setupImagePaste`
  - `CMP-image/web/src/image-view.js#getImageView`
- 依赖：`CMP-document-io`（保存时调用改写）、`CMP-editor`（插入节点/NodeView 宿主）、`CMP-app-shell`（保存前提示）。
- 冷热属性：冷路径；导入/清理是低频动作。
- 尺寸预算：目标 ≤120k token；当前约 500 行（ImageStore 169 + ImagePathRewriter 部分 + web 289），实测待脚本。
- 单独运行：`./.build/debug/MDPreview --selftest`；真实粘贴用 `MDP_IMPORT_IMAGE` 钩子与截图。
- 验证计划：路径改写/还原、空格/标题/围栏、导入命名/冲突/拒绝、清理四类用 selftest；真实 ⌘V 与截图人工记录。
- 删除测试：删掉后图片导入/清理/路径改写没有归属，复杂度转移到编辑器和文件层 → 真边界。

## 公开契约细节

- `#for-load` 的不变量：只改写图片节点目的地；代码围栏/行内代码不改；远程 URL 不改。
- `#for-save` 的不变量：保存后再次加载得到同一路径；含空格用 `<...>`；不把缺失文件写成坏路径。
- `#import` 的错误模式：非图片、不可列举目录、未保存文档 → 拒绝并提示；不覆盖既有文件。
- `#cleanup` 的不变量：只删本组件管理的 resource 目录内、未被当前 Markdown 引用的图片；非图片不动；目录为空才移除。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#for-load` / `#for-save` | `--selftest`：图片路径改写/还原 10 项（空格、标题、围栏、缺失、远程、`<>`） |
| `#import` | `--selftest`：落盘 7 项（位图、命名、冲突、布局、非图片拒绝、不可列举拒绝） |
| `#cleanup` | `--selftest`：资源清理 4 项 |
| `#node-view` | `--selftest`：NodeView、点击编辑、提交、非法还原（反例）、清空删除 |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| `resource/<md>/` 图片 | 本组件导入/清理 | 编辑器、导出 | 单文档单写入口 |
| 图片路径映射 | 本组件 | 保存/加载 | 一次改写 |

## 删除测试

删掉后图片资源生命周期没有替代归属 → 真边界。
