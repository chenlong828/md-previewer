---
layer: works
module: global
status: active
updated: 2026-10-20
---

# 收口: 图片支持(显示/编辑/粘贴/拖放)

## 验收结果(对照 brief 验收标准)

1. **显示** ✅ — 样例《AI 六轮降价后为何要治理价格》(路径含空格/全角冒号/加号)
   10 张图全部 `naturalWidth=1080, complete=true` 加载,截图像素分析出现 27 条
   宽色带;《低延迟C++…》(无空格路径)同样全图加载。受控三变体文档
   (无空格/空格/一层括号)全部渲染。
2. **编辑框** ✅(2026-10-20 二次定稿为源码编辑块) — selftest 行为往返:
   NodeView 渲染 → 点击出**源码编辑块**(整块框起、宽度=编辑器 100%、长路径
   自动换行,内容 `![alt](path "title")` 与文件写法同构,baseDir 相对化展示)
   → 改源码 Enter/失焦提交 doc 更新 → 非法语法还原不动 → 清空源码即删图。
   实测钩子(MDP_EDIT_IMAGE)几何断言:盒宽 930px=正文栏满宽;长路径实测
   换行为 4 行(盒高 127px@2x)。
3. **粘贴/导入** ✅ — e2e(MDP_IMPORT_IMAGE 钩子,真实控制器):图片复制到
   `resource/doc/img_001.jpg`、光标处插入、渲染 1080px。剪贴板位图识别、
   base64 编码、落盘命名(img_NNN 递增/mime 定扩展名)、同名冲突后缀均为
   selftest 单元用例;真实 ⌘V 粘贴的 web 事件链路由同一段代码承载,留一次
   人工手感验证。
4. **保存往返** ✅ — selftest:空格路径 加载→%20 file://、保存→`<>` 包裹相对
   路径(定点)、二次加载一致;标题保留/还原;缺失文件/远程图不改写;代码围栏
   不受影响。
5. **回归** ✅ — selftest 全量 89 项 PASS(含既有 katex/mermaid/表格/查找/PDF/
   脏标记用例;85 项 + 收口后评审加固新增 4 项,见下节),eslint 干净。

修复过程中发现并纠正的**既有缺陷**:openDocument 传文件 URL 当 baseURL、
forceReload 传目录——两入口不一致导致相对路径图片在真实应用里**从来**都
不显示(selftest 以目录为基准隔离测试,从未暴露)。契约已单点化:
`injectMarkdown(docURL)` 内部推导目录(design/architecture.md §2.1 基点契约)。

## 结论落点表

| 结论 | 落点 |
|---|---|
| ImagePathRewriter 宽松两段式解析、%20 改写、`<>` 保存定点、injectMarkdown 基点契约 | design/architecture.md §2.1 |
| 图片源码编辑块交互(点选进编辑/失焦提交/清地址即删/路径相对化⇄规范化对称换算) | design/architecture.md §2.1a |
| 导入落盘约定 resource/<md文件名>/、img_NNN、原名保留 | design/architecture.md §2.1a(单点实现在 ImageStore.swift) |
| importImage/onImageImported 桥对、插入唯一入口 insertImageCommand、setBaseDir | design/architecture.md §4 |
| 截图模式 MDP_IMPORT_IMAGE / MDP_EDIT_IMAGE e2e 钩子、testImagePayload 诊断面 | design/architecture.md §3 |
| 功能特性/已知边界(多图取第一张、未保存先保存、导出不内联图片) | 仓库根 README.md |
| 坑:双入口 base 参数不一致 | history/pitfalls.md P2(已消失,实证 2026-10-20) |
| ImageStore 失败契约(目录列举失败抛错,防序号回绕覆盖) | design/architecture.md §2.1a + history/pitfalls.md P3(已消失,实证 2026-10-20) |

## 收口后评审加固(2026-10-20,对照工作原则评审发现的三项)

1. **ImageStore 静默覆盖缺陷(红→绿守门)** — 评审发现 `existingFiles` 以
   `try? ?? []` 兜底:目录可写但不可列举(chmod 0o300)时列目录静默得空表,
   `img_NNN` 序号回绕到 001,`.atomic` 写盘**静默覆盖**既有图片。先写最小
   复现用例实证红跑中 img_001.png 确被覆盖(数据丢失级),再修复为列举失败
   原样抛错,复跑转绿。新增用例:「图片落盘-不可列举目录拒绝(防覆盖)」、
   「图片落盘-不可列举时既有图片未被覆盖」。失败契约记入 architecture.md
   §2.1a,防复发判据记入坑档案 P3。
2. **窄窗口几何断言** — 编辑列收缩下限(--editor-max-width,窄窗横向滚动为
   设计行为)前提下,新增用例断言 480px 窗宽时:源码编辑块可打开、长路径在
   块内换行(scrollWidth≤clientWidth)、不超正文栏、页面横向溢出不超过
   `#app` min-width 计算值(读计算样式,不复制 CSS 常量)。一次通过,
   未暴露 CSS 缺陷,未改产品代码。
3. **交付截图敏感信息检查** — 两张 verify-example-*.png 入库前以 Vision OCR
   全文扫描:内容均为公众号公开文章,无个人路径/邮箱/密钥/电话/证件号。

## 遗留(2026-10-20 用户定稿:以下明确不做/暂缓)

- 图片缩放编辑:不做——默认 max-width:100% 与文档同宽(typora.css 既有的
  `[data-type="image"] img` 规则即此语义),无缩放交互。
- 导出 HTML 内联图片:不做,导出件图片保持 file:// 引用(README 已知边界)。
- 一次粘贴多张图片:暂缓(现状取第一张)。
