---
layer: design
module: global
status: current
updated: 2026-11-04
---

# 系统架构与设计取舍

MDPreview 是 Typora 风格的 macOS Markdown 所见即所得编辑器：Swift/AppKit 壳 +
WKWebView 承载 Milkdown 7.7（ProseMirror）前端。本文记录跨模块的现行设计
取舍，每条包含**决策、理由、失效条件**；细节实现以代码注释为准。

> **2026-10-24 文档下沉 / 2026-11-04 五态迁移**：诊断面原 §3 于 10-24 下沉为独立文档，
> 11-04 迁至 [components/CMP-diagnostics/spec.md](components/CMP-diagnostics/spec.md) 并补组件卡；
> 桥协议由 §4 顺延为 §3；`history/` 冻结件中的旧编号（§3/§4）不回改，按小节标题对应。

```
┌────────────────────────────────────────────┐
│  Swift/AppKit 壳                            │
│  窗口/菜单/文件 IO/脏标记/文件监听/PDF 导出    │
│  DocumentWindowController ── EditorWebView  │
│        │  WKScriptMessageHandler 桥         │
│        ▼                                    │
│  WKWebView(本地 web/dist,无网络依赖)         │
│  Milkdown 7.7 (ProseMirror)                 │
│   ├ preset-commonmark / preset-gfm          │
│   ├ plugin-diagram + 自定义 Mermaid NodeView │
│   ├ plugin-math (KaTeX) / plugin-prism      │
│   └ clipboard / trailing / listener         │
└────────────────────────────────────────────┘
```

## 1. 安全取舍

### 1.1 WebView 全盘文件读授权

- **决策**：`loadFileURL(_:allowingReadAccessTo: URL(fileURLWithPath: "/"))`，
  即授予 WebView 全盘只读访问（DocumentWindowController、Selftest 同口径）。
- **理由**：
  1. Markdown 文档中的图片与文档内链接可指向任意位置（`~/Pictures`、外置卷、
     其他项目目录），读授权范围无法在加载前静态确定——收窄需扫描全文图片引用
     并动态计算目录并集，且用户运行时新增图片会再次失效；
  2. 文档内链接可跳转打开其他目录的 .md 文件，收窄会破坏跨目录跳转；
  3. WebView 内的页面代码只能读 `file://` 内容，无法调用 Swift 侧文件写接口，
     暴露面为"只读 + 需主动构造恶意文档"。
- **收窄评估结论**：**暂不收窄**。收窄到"文档目录 + 图片目录"需实现目录并集
  扫描与运行时重授权，复杂度高且无法覆盖绝对路径图片/外置卷场景；当前定位为
  单用户本地文档工具，接受该只读暴露面。
- **失效条件**：若产品定位变为"打开不可信第三方分发的文档"（如作为邮件附件
  预览器、接收陌生人文档），必须收窄授权或引入内容安全过滤，否则本地文件
  （密钥、配置）可被恶意文档内的脚本经 `file://` 读取。

### 1.2 mermaid `securityLevel: 'loose'`

- **决策**：mermaid 初始化采用 `securityLevel: 'loose'`（editor.js）。
- **理由**：`strict`（默认）会拦截 HTML 标签与事件绑定，导致折叠、点击交互等
  常见流程图语法无法渲染，与 Typora 体验目标冲突；渲染内容为用户自己编写的
  本地文档，非跨站注入场景。
- **失效条件**：同 1.1——若用于打开不可信文档，loose 模式允许图内 HTML/事件
  脚本执行，需切换 `strict` 或对 mermaid 源做白名单过滤。

### 1.3 桥接口面收敛

- **决策（2026-11-04 起为 v2）**：Swift↔JS 仅一条通道、两个固定入口——JS 侧
  `window.__mdHostChannel.post(json)`（壳注入，唯一宿主感知点），壳侧单一
  `mdbridge` messageHandler；所有能力经 op 名寻址（单一清单
  `web/src/kernel/contract/ops.js`），命令名双端一致由 selftest 遍历校验。
- **产品路径不执行注入脚本**：壳侧只剩两处 `evaluateJavaScript`——`KernelClient`
  的帧投递与诊断档取数（自检/截图/调试）。v1 的 `window.mdbridge` 仅在测试门面
  （`__MDP_TEST__`）下安装，产品 bundle 不暴露。
- **理由**：接口面越小，注入/误用面越小；双端一致性由机器校验而非人工约定；
  注入脚本是 markdown 语义在壳侧复活的主要通道，v2 把它收成一条 JSON 帧。
- **失效条件**：绕过注册表直接拼写 JS 命令字符串的新代码（code review 关注点）。

## 2. 行为取舍

### 2.1 图片路径改写：语义单点在 web 内核（规则不变，2026-11-04 迁入）

> 位置变更：实现从 `Sources/MDPreview/Util.swift#ImagePathRewriter` 移到
> `web/src/kernel/semantics/{markdown,paths}.js`；Swift 侧实现已删除。
> 迁移时与旧实现做了逐字节对拍（15 用例 × 3 函数 = 45 项全等，黄金件
> `web/test/fixtures/semantics-golden.json`），因此下面的规则描述**仍逐字成立**。
> 存在性判定改由壳作答（`resolveResources`），内核不碰文件系统。

- **决策**:图片路径改写采用单行两段式解析(2026-10-20 图片支持工序重写):
  宽松捕获 `![alt](inner)`(inner 惰性匹配到首个 `)`,允许**空格与一层平衡
  括号**),再在 inner 内拆 `<>` 包裹目的地 / 尾部引号标题 / 裸路径;仅处理
  围栏代码块之外的行。加载时把存在的相对/根相对路径改写为 `%20` 编码的
  `file://` URL(消除 CommonMark 目的地不容空格的限制),解析失败或文件
  缺失时**静默保留原文**;保存时 file:// 还原为文档目录内相对路径(空格/
  括号以 `<>` 包裹,合法 CommonMark),目录外保留绝对路径。
- **基点契约**:`injectMarkdown` 以**文档 URL** 为唯一入参,目录由其内部
  推导(此前 openDocument 传文件 URL、forceReload 传目录,前者恒解析出
  `doc.md/resource/…` 不存在 → 相对路径图片全不显示,2026-10-20 修复)。
- **覆盖边界(明确不支持的写法)**:
  1. 引用式图片 `![alt][ref]` 不改写(保存/加载保持原样);
  2. 两层以上嵌套括号的路径不改写;
  3. 路径内转义字符(如 `\ ` 空格转义)不展开;
  4. 跨行书写(`![alt](` 与路径分行)不改写。
- **理由**:覆盖以上长尾需引入完整 Markdown 内联解析,复杂度与收益不成比例;
  静默保留原文是安全退化——不改写最多导致图片不显示,不会破坏文件内容。
  空格路径是 wechat-offline 等工具导出文档的常态,必须接住(实证样例
  `resource/…AI 六轮降价…/img_001.jpg`)。
- **失效条件**:若用户群出现大量引用式图片/深层嵌套括号路径的文档,需升级为
  AST 级改写;静默策略需同步改为可提示(状态栏提示改写失败计数)。

### 2.1a 图片显示/编辑/导入

- **决策**:图片节点以自定义 NodeView 渲染(web/src/kernel/core/image-view.js):正常态
  `<img>`;点击切换为**源码编辑块**(2026-10-20 二次定稿,替代三字段小表单)——
  与 mermaid 图「点选进编辑、失焦提交」同一交互模式:整块框起、宽度为编辑器
  100%、长路径自动换行,内容是该图的 markdown 源码 `![alt](path "title")`。
  失焦/Enter 解析提交,Esc 还原;地址清空即删除该图(可撤销);解析不出图片
  语法则还原不动。路径换算与文件同构:显示时 file:// 按 baseDir(文档目录,
  随 setMarkdown opts/setBaseDir 同步)相对化为原始写法,提交时相对路径按
  baseDir 解析回规范 file:// URL(%20 编码,与 Swift 加载改写同口径);输入/
  输出对称保证"点开不动=无脏标记"。
- **导入落盘约定**(ImageStore 单点定义):粘贴截图/图片文件路径、拖入图片
  文件、格式→插入图片菜单,统一把图片复制到 `<文档目录>/resource/<md文件名>/`,
  剪贴板位图命名 `img_NNN.ext`(目录内序号递增,mime 定扩展名),文件导入保留
  原名(冲突加 `-2` 后缀);编辑器内插入的 src 为绝对 file:// URL,保存时由
  ImagePathRewriter 还原为相对路径。落盘失败(目录不可列举/不可写、非图片等)
  一律原样抛错、由原生弹窗提示,绝不静默降级——序号命名依赖目录列举,静默
  当空目录会让序号回绕、`.atomic` 写盘覆盖既有图片(selftest 防覆盖用例守门)。
- **关闭清理(资源 GC)**:`windowWillClose` 唯一钩子,此刻磁盘内容是权威
  终态(保存/放弃决策已在 windowShouldClose→beginConfirmClose 完成)。判定
  复用 ImagePathRewriter 的同一套行规则与目的地解析(只读收集器
  `referencedLocalImagePaths`,围栏内不算引用,零解析重复):目录内 UTType
  为图片且不被引用 → 删除,非图片文件一律不动;目录清空连带移除
  `resource/<md文件名>/`,随之为空亦移除 `resource/`。撤销粘贴的孤儿文件由
  本机制在关闭时清除——撤销不立即删盘(⌘⇧Z 重做会指向已删文件破图,用户
  2026-10-20 定稿关闭时统一 GC)。引用与候选路径双侧经 `standardizedFileURL`
  规范化比对(消解 `./` 冗余段);相对引用按改写器原样与 CommonMark %XX
  解码两种口径收集(均以文件实际存在为准,宁多保护不误删)。file:// 目的地
  解码用手工分段(`percentDecodedPath`),不用 URL(string:)(混排内容会再
  转义合法 %XX,坑档案 P4)。清理失败 os_log 不打断关闭。
- **路径分离**:导入是偶发慢路径——web 捕获阶段拦截 paste(非图片载荷放行给
  milkdown clipboard 文本链路)→ 桥 op `importImage` → 原生落盘 → 回灌
  `onImageImported(requestId,{ok,src})` → 恢复粘贴时刻选区插入节点;失败由
  原生弹窗,web 只清挂起表。未保存文档(无归属目录)原生弹「请先保存」。
- **边界**:一次粘贴只取第一张图片;手敲空格路径在编辑器内即时成图
  (milkdown input rule),相对 src 在保存+重载前可能破图;导出 HTML 不内联
  图片(保持 file:// 引用);图片缩放(width/height)需扩展 schema 与往返
  语法,未做。

### 2.2 保存无条件补尾换行

- **决策**：`TextFile.write` 在内容末尾无换行时自动补一个 `\n`（原子写）。
- **理由**：POSIX 文本文件约定以换行结尾，缺尾换行会让 diff 工具显示
  "\ No newline at end of file"、部分 CLI 工具解析异常；补尾是编辑器通用
  做法（Typora/VSCode 默认行为一致）。
- **失效条件**：若用户明确依赖"文件末尾无换行"的精确字节（如作为其他工具的
  输入 fixture），该隐式修改会造成困扰——届时需提供"保留原尾"设置项。

### 2.3 保存恒定 UTF-8（OQ-2 结论）

- **决策**：读取时探测编码（UTF-8 → GB18030 → 有损兜底）仅用于**显示**；
  保存恒定写 UTF-8，不做编码回写。
- **理由**：UTF-8 是事实标准；回写原编码需要维护编码状态并在另存为时做
  编码选择 UI，复杂度高；GB18030 文档另存后变为 UTF-8 是可接受的一次性迁移。
  该承诺已写入 README"已知边界"。
- **失效条件**：若出现"必须保持原编码"的用户场景（如文件被其他 GBK 系统
  消费），需在保存面板增加编码选择。

### 2.4 文件抽屉与目录模式

- **决策**:抽屉为原生 AppKit 侧栏(FileDrawerView + DirectoryTree 纯扫描),
  不进 web 层;目录内容是磁盘在扫描时刻的投影,权威永远在磁盘,刷新单点
  rescan,不做文件系统监听。**装载模型为 lazy 按层**(用户定稿,取代
  eager 全量扫描 + 预算截断):每次只 readdir 一层,展开目录时触发下一层
  读取——任意规模目录树开销恒定,无截断。装载在**数据源内同步**发生:
  NSOutlineView 展开取数(numberOfChildrenOfItem)时 ensureLoaded 同步
  readdir 该层,选中定位同口径同步装载祖先链——两者都是低频交互
  (单次点击),本地单层 readdir 毫秒级;node_modules/包已在单层跳过,
  无大目录单层阻塞风险。(曾用 shouldExpand 拦截 + 后台装载 + 续展的
  异步三段式,真实交互下受 AppKit 未展开条目子层缓存时序影响出现
  「目录打不开」,已废弃。)rescan = 重读根层,已展开子层在恢复展开时
  按需重读(刷新天然回到磁盘现状)。跳过规则:隐藏条目/符号链接(防环)/
  `node_modules`/包目录(.app/.bundle,Finder 同款不透明语义)。
  语义取舍:lazy 下不做「无 md 后代目录剪枝」——暂无 md 的目录也显示
  (展开为空),文件仍只列可展示 md。
- **锚定契约**:抽屉头部是锚点路径控件(`DrawerAnchorControl`):铺满「抽屉宽
  − Home/刷新两个按钮 − 间距」,显示当前锚点的 Finder 同款文件夹图标 + 目录名
  + 展开箭头;点击弹出当前锚点到文件系统根的父级链(`DirectoryTree.ancestorChain`,
  纯路径逻辑)菜单——每条带同一套 Finder 图标(FinderIcon 单点)、当前锚点勾选,
  并按链上序号 `indentationLevel` 逐级右移(图标与标题一起缩进,与下方大纲树
  共用「越深越右」的视觉语言),选中即重锚。右侧 Home 按钮把抽屉根切回
  `homeDirectoryForCurrentUser`(与菜单选择同一 `onAnchorSelected` 路径,已在
  Home 时置灰),刷新按钮重扫(单点 rescan)。锚点
  单字段两模式共用:目录模式 = 打开的目录;文件模式 = 最近一次锚定。
  打开来源决定重锚:抽屉双击 `openDocument(at:reanchor: false)` 不重锚
  (锚定祖先目录后跨多层打开的支撑),其余来源默认重锚为文件所在目录;
  目标不在锚点子树内时无条件重锚(越界防御)。`pendingOpen` 暂存携带
  reanchor 标志,装载中经排空的抽屉双击不丢失该语义;目录模式重锚后
  窗口标题跟随锚点。
- **窗口宽度收敛契约**:展开 → 优先向左伸出抽屉当前宽度(编辑器内容宽度不变);
  伸出后超出屏幕可视宽度则整体收敛到屏幕宽度(右缘保持,编辑器压缩)。
  收起 → 右缘保持宽度缩回(下限窗口 minSize)。启动时窗框超屏一次性收敛
  (跨屏拖动/外接屏拔除残留)。可见性 UserDefaults 全局记忆,跨窗口恢复。
- **抽屉宽度可拖拽契约**:抽屉与编辑器边界处由 `DrawerResizeDivider` 提供
  8pt 透明热区(跨边界各 4pt,只画 1pt 分界线,悬停/拖动加强并显示左右拖拽
  光标);拖动只上报位移增量,宽度状态、夹取与窗口联动归控制器——
  新宽度 = 起点宽度 + 位移,夹取 `[160, min(480, 窗体宽 − 320)]`(正文最小宽),
  拖动只改抽屉约束、不动窗口宽度(两侧重新分配空间)。宽度落盘
  `UserDefaults["fileDrawerWidth"]`(越界/缺失回落默认 240),开合动画与
  窗口伸缩一律按当前宽度;抽屉收起时分隔条同隐,边界不可拖。
- **覆盖打开的脏确认统一**:抽屉双击/⌘O/打开最近使用/文档内链接等所有
  程序内打开动作共用 openDocument(at:) 单一装载路径;脏文档先走
  beginConfirmClose(保存/取消/不保存,与关闭确认同一 sheet),确认后才覆盖。
  「不保存」= 放弃修改后继续打开;不再存在"丢弃并打开"的静默丢弃语义。
- **装载暂存排空契约**:编辑器未就绪或注入进行中(isLoadingContent)时,
  打开请求暂存于 pendingOpenURL;补载不再只依赖 ready 桥消息(ready 仅发生
  一次,装载中到达的请求会永久滞留)——注入完成后 drainPendingOpen 立即
  排空,按目录/文件分派。
- **目录模式语义**:fileURL=nil + directoryMode=true 表达;右侧走既有空文档
  路径(可编辑,⌘S 另存为),窗口标题与代理 URL 为目录;再次 openDocument
  自然退出目录模式。目录入参的收敛点在 AppDelegate.openInNewWindow
  (CLI/拖放/LaunchServices/文档链接统一路由),目录窗口 = 空文档窗口 +
  抽屉展开。

### 2.5 Markdown 序列化：列表每级 4 空格

- **决策**：保存 / 源码模式切回渲染时，列表嵌套每级缩进 **4 空格**（标准
  Tab 等价缩进），首行标记保持紧凑（`- a`、`1. a`，不是 `-   a`）。尺寸规则
  `max(4, 标记宽 + 1)`：`- ` / `1. ` 取 4，`100. ` 这类长标记取 5，保证续行
  不低于内容列、CommonMark 解析层级不变。
- **理由**：用户报告 2 空格输出「不是标准 markdown 缩进、只是多了一个 Tab
  字符」；4 空格是跨渲染器最不易误读的形态，也与「Tab = 一级缩进」的直觉一致。
- **实现单点**：`web/src/kernel/core/list-indent.js` 的 `fourSpaceListItem`，经
  `remarkStringifyOptionsCtx.handlers` 注入；解析、渲染、桥协议均不受影响。
- **失效条件与陷阱**：mdast 的 `listItemIndent: 'tab'` 并不是「4 空格缩进」——
  它同时把首行补到 4 列（`-   a`）。且覆盖 `handlers.listItem` 会顶掉 GFM
  任务列表 handler（选项层晚于 extensions 生效），复选框必须在自定义 handler
  内复刻，否则保存会吞掉 `[x]`（坑档案 P7）。
- **保存即规范化**：既有 2 空格缩进文件可正常解析，保存时输出 4 空格（与
  bullet/emphasis 规范化同一口径）；不做静默改写，只有用户保存才落盘。

### 2.6 代码高亮配色：token 调色板自有化（单一真源）

- **决策**：高亮 token 的配色由 `web/src/typora.css` 的「代码高亮 token 调色板」
  一节唯一维护——浅色、深色两张变量表（`13` 个语义组）+ 一组只写 `color` 的分组
  规则；不引入任何第三方整份主题（原 `prismjs/themes/prism.css` 已移除，随之不再
  被引用的 `prismjs` 依赖也已删除）。
- **理由**：第三方主题是浅色的，深色只能逐条打补丁，漏一条即静默回落成浅色值。
  实际发生过两类缺陷：`.token.operator` 的 50% 白底在深色代码块上变成浅色块
  （坑档案 P8）；`builtin`/`doctype`/`variable` 未覆盖，深色下沿用浅色值。变量表 +
  完整分组把「新增 token 类」变成一次显式加法，而不是靠记忆补丁。
- **不变量**：token 一律不设背景（`.token { background: none }`），代码块底色唯一
  来源是 `pre` 的 `--code-fence-bg`；token 不设 `text-shadow`。浅色值照抄原 Prism
  默认主题（视觉不变），深色值沿用 Nord 调色板。
- **实现单点**：变量表与规则同在 `web/src/typora.css`；高亮引擎仍是 Milkdown
  plugin-prism（Prism/refractor），只产出 `token <类名>` 的 span，不参与配色。
- **失效条件与陷阱**：新增 token 类未进入变量表不会报错，只会回落到正文色；因此
  selftest「token 调色板」断言按分组核对每个成员类的实测色值、背景与阴影（浅/深
  各一条），改色必须同步该断言表。重新整份引入第三方主题会让断言先红（已实测）。
- **导出**：独立 HTML 内联全部样式，导出文件不带 `data-theme`，token 恒取浅色值。

### 2.7 代码文档：只读源码视图（2026-11-04）

- **决策**：代码文件以**只读高亮源码**打开，与 Markdown 共用窗口/主题/缩放/查找，
  但不进 ProseMirror：页面多出第三个面 `#code-view`，`body.code-mode` 下隐藏
  `#app` 与 `#source-editor`。代码文档恒为「纯源码」，没有 WYSIWYG ⇄ 源码切换。
- **种类判定单一来源**：`Sources/MDPreview/FileSupport.swift` 的 `DocumentKind`
  与 `codeLanguages`（44 种语言/扩展名映射 + `plaintext` 伪语言）。打开面板、
  抽屉过滤、文档内链接拦截、打开分派、高亮语言菜单、Info.plist 断言全部派生自
  这里；web 侧 `web/src/kernel/core/languages.js` 注册 refractor 语法，selftest「双端语言
  清单一致」守门。
- **理由**：把代码塞进 Markdown 围栏块虽省事，但会让只读文件进入可编辑数据模型——
  一次 ⌘S 就把代码写成 md；且 ProseMirror 解析大文件成本高、围栏转义会改字符。
  独立只读面让「不写盘」成为结构约束，而不是靠禁菜单。
- **行号与按行阅读（2026-11-04）**：`#code-view > code` 内部改为每个**逻辑行**一个
  `.code-line` 块，高亮结果整体生成后按 `\n` 拆行（跨行 token 克隆同一属性），
  不按行重新解析。行号由 `.code-line-number::before { content: attr(data-line) }`
  生成，是表现层、不进入文本节点/复制/查找；空行用 `<br>` 保复制，末行空行不补。
  行内容 `white-space: pre-wrap` + `overflow-wrap: anywhere`，行号对齐逻辑行首，
  不产生横向代码滚动。当前行（点击/⌘F/方向键）只加 `.is-current`，会话级；
  行号开关为全局 `UserDefaults["codeLineNumbersVisible"]`（默认 true），菜单入口在
  `CMP-app-shell`，切换只改布局类、不重绘 token、不发 `changed`。
- **不变量**：
  - 代码文档 `isDirty` 恒 false、不发 `changed`、关闭不弹保存确认；保存/另存为/
    源码模式/插入图片/HTML 导出在菜单与代码路径双重禁用。
  - `setMarkdown` 必须先退出代码视图（`hideCode`）；`toggleSource` 在代码视图下
    no-op；`code-mode` 与 `source-mode` 互斥。
  - 高亮上限 512 KB（UTF-8 字节，`DocumentWindowController.codeHighlightByteLimit`）：
    超过则纯文本渲染 + 状态栏「文件过大,未高亮」；语言切换不改变降级状态。
  - token 配色仍走 §2.6 的调色板（`.token.*` 是全局类），代码视图不新建主题；
    `#code-view` 只覆盖 `pre/code` 的容器样式（背景/边框/内边距/缩放）。
  - 打开入口与 Markdown 完全一致（⌘O/抽屉/拖放/CLI/最近/文档链接）；外部打开
    仍新窗口、程序内覆盖当前窗口。
  - 代码查找用文本 Range 选区实现（命中计数 + 循环定位），不重建 DOM，避免打断
    token 结构；行结构下偏移仍按原文本计算，再映射到行内容文本节点。
  - 行结构是表现层：逐行 `.code-line-content` 以 `\n` 拼接必须等于 `state.codeText`；
    行号数字不进入复制/查找/HTML 导出；开关不改变文件字节、不产生 `changed`。
- **实现单点**：Swift `FileSupport` + `DocumentWindowController` 的 kind 分支与行号
  偏好入口；web `languages.js`（语法注册与 hast→DOM）、`code-view.js`
  （行拆/渲染/切换/当前行/查找/降级/开关）、`bridge.js`
  （`setCode`/`setCodeLanguage`/`setCodeLineNumbers`/`isCodeMode`/`codeInfo`/
  `hasLanguages`）。
- **失效条件**：新增语言只加 Swift 表会让「双端语言清单一致」先红；只加 web 注册
  会表现为「未知语法回落纯文本」而不是报错；`#code-view` 样式若写回 `pre` 全局
  规则会污染 Markdown 围栏代码块的底色/内边距；行号若改回文本节点会污染复制/
  查找，selftest 选择断言先红。
- **边界**：无扩展名文件（`Dockerfile`/`Makefile`）不识别；不做代码编辑、折叠、
  minimap 与 LSP；Markdown 围栏代码块没有行号；HTML 导出对代码文档不可用。

## 3. 桥协议（v2，2026-11-04 落地）

- **帧形状**（`web/src/kernel/contract/envelope.js`，v 恒为 2）：
  - 请求 `{v:2, op, id, payload}`；成功响应 `{v:2, id, ok:true, payload}`；
    失败响应 `{v:2, id, ok:false, error:{code,message}}`；通知 `{v:2, op, payload}`（无 id、不响应）。
  - 响应必回显请求 id；payload 只许 JSON 原语（递归校验）；单通道串行。
  - 错误码五种：`unknown_op` / `bad_payload` / `not_ready` / `unsupported_version` / `internal`。
- **握手**：首帧 `init` 的 `payload.opts.protocolVersion` 必须等于 2（缺=拒绝并置内核 disabled，
  不静默降级）；成功后回 `{kernelVersion, protocolVersion, ops:[...]}`，此前除 `init` 外的
  op 一律回 `not_ready`。
- **宿主 op（39 个，单一清单 `web/src/kernel/contract/ops.js`）**：
  会话 `init/setMarkdown/getMarkdown/getSaveMarkdown/markClean/setBaseDir/setTitle/setTheme/
  setZoom/getState/toggleSource/focus/focusAt`；代码视图 `setCode/setCodeLanguage/
  setCodeLineNumbers/codeInfo/hasLanguages`；命令 `undo/redo/requestStats/formatCommand/
  tableCommand/insertTable/insertMarkdown/insertImage`；查找 `openFindBar/closeFindBar/
  findNext/findPrev/findInfo`；输出 `exportStandaloneHTML/print/getContentSize`；
  资源 `getResourceRefs`；诊断 `hasCommands/debugFocusTable/tableInfo/testImagePayload`。
- **通知（7 个）**：`boot/ready/changed/stats/sourceMode/selinfo/jserror`。
- **内核发起的请求（2 个）**：
  - `resolveResources {refs[], baseDir}` → `{resources:{ref:[{url,exists,isImage,paths}]}}`：
    装载前问「这个引用指向哪个真实文件」。请求**自包含**（带 baseDir），壳不猜当前文档目录
    ——未保存/另存场景曾因此把引用误判为缺失。
  - `importImage {kind:'blob'|'file', mime?, data?|path?}` → `{ok, src?}`：粘贴落盘。
    取代 v1 的 `onImageImported` 反向回灌，选区快照在核内闭环。
- **命令转发**：菜单/右键 → `performEditorAction` → spec.jsCommand → `formatCommand`/
  `tableCommand` op，payload 直接作为 op payload（不再拼 JS 字面量）。
- **异步消息**：markdownUpdated listener 的 200ms debounce 与「过期过滤 + 同步基线」不变
  （W5-T3），仍是 `changed{dirty}` 的唯一来源。
- **壳侧实现**：macOS 见 `Sources/MDPreview/KernelClient.swift`（帧编解码/id 关联/超时/请求应答）；
  Windows 壳可参照 `web/test/support/fake-shell.js` 与 `web/test/support/dom.js` 的假壳，
  协议测试 `web/test/contract.test.js` 不依赖任何 WebView。

## 4. 内核分层与禁边（2026-11-04）

- **四层，依赖单向**：`transport` → `contract` → `semantics` / `core`。
  - `web/src/kernel/transport/channel.js`：唯一宿主感知点（`__mdHostChannel` / `__mdKernel`、
    jserror 三源）。缺 channel 时 boot 显式失败，不静默降级。
  - `web/src/kernel/contract/`：信封、op 清单与 payload 校验、注册表（id 关联/握手/错误码）。
  - `web/src/kernel/semantics/`：路径与 markdown 文本语义（装载改写/保存还原/引用收集/落盘命名），
    纯函数、零第三方依赖、不碰文件系统。
  - `web/src/kernel/core/`：编辑器与 39 个 op 的唯一实现；经 `core/bus.js`（`notify`/`hostCall`）
    与壳交互，不含宿主符号。
- **组合根** `web/src/page.js`：装配 transport → contract → 注册 core ops → 绑总线 →（测试环境）装门面。
- **禁边守门**：`web/check-kernel.mjs` 进构建（`build.sh`）：宿主符号只许出现在 `transport/`；
  层间 import 只许下行；第三方依赖只许出现在 `core/`（编辑器引擎本身）。违规即构建失败。
