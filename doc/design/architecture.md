---
layer: design
module: global
status: current
updated: 2026-10-20
---

# 系统架构与设计取舍

MDPreview 是 Typora 风格的 macOS Markdown 所见即所得编辑器：Swift/AppKit 壳 +
WKWebView 承载 Milkdown 7.7（ProseMirror）前端。本文记录跨模块的现行设计
取舍，每条包含**决策、理由、失效条件**；细节实现以代码注释为准。

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

- **决策**：Swift↔JS 仅两个入口表面——JS 侧 `window.mdbridge`（唯一被调用
  对象）、Swift 侧单一 `mdbridge` messageHandler；命令名双端一致由 selftest
  遍历校验（命令注册表 + 表格命令名表）。
- **理由**：接口面越小，注入/误用面越小；双端一致性由机器校验而非人工约定。
- **失效条件**：绕过注册表直接拼写 JS 命令字符串的新代码（code review 关注点）。

## 2. 行为取舍

### 2.1 ImagePathRewriter 宽松解析与改写边界

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

- **决策**:图片节点以自定义 NodeView 渲染(web/src/image-view.js):正常态
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
  读取——任意规模目录树开销恒定,无截断。两条装载路径:点击展开走
  shouldExpand 拦截 + 后台装载续展(不阻塞主线程);选中定位走祖先链
  同步装载(低频,每层毫秒级)。rescan = 重读根层,已展开子层在恢复展开时
  按需重读(刷新天然回到磁盘现状)。跳过规则:隐藏条目/符号链接(防环)/
  `node_modules`/包目录(.app/.bundle,Finder 同款不透明语义)。
  语义取舍:lazy 下不做「无 md 后代目录剪枝」——暂无 md 的目录也显示
  (展开为空),文件仍只列可展示 md。
- **锚定契约**:抽屉头部下拉框列出当前锚点(`drawerRootURL`)到文件系统根的
  父级链(`DirectoryTree.ancestorChain`,纯路径逻辑),选中即重锚。锚点
  单字段两模式共用:目录模式 = 打开的目录;文件模式 = 最近一次锚定。
  打开来源决定重锚:抽屉双击 `openDocument(at:reanchor: false)` 不重锚
  (锚定祖先目录后跨多层打开的支撑),其余来源默认重锚为文件所在目录;
  目标不在锚点子树内时无条件重锚(越界防御)。`pendingOpen` 暂存携带
  reanchor 标志,装载中经排空的抽屉双击不丢失该语义;目录模式重锚后
  窗口标题跟随锚点。
- **窗口宽度收敛契约**:展开 → 优先向左伸出 drawerWidth(编辑器内容宽度不变);
  伸出后超出屏幕可视宽度则整体收敛到屏幕宽度(右缘保持,编辑器压缩)。
  收起 → 右缘保持宽度缩回(下限窗口 minSize)。启动时窗框超屏一次性收敛
  (跨屏拖动/外接屏拔除残留)。可见性 UserDefaults 全局记忆,跨窗口恢复。
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

## 3. 诊断面（OQ-3 结论：保留为官方诊断面并文档化）

诊断代码随 release 构建发布是**有意保留**：单机工具无线上灰度能力，官方
诊断面是问题排查的唯一手段。三个入口统一风格如下：

| 入口 | 语法 | 输出前缀 | 退出码 |
|---|---|---|---|
| 无头自检 | `MDPreview --selftest` | `PASS/FAIL  名称` 每行一项，末行 `SELFTEST PASSED/FAILED` | 0=全过 / 1=有失败 |
| 进程内截图 | `MDPreview --screenshot out.png [input.md]` | `SCREENSHOT …` | 0=成功；2/3/4/5/6/7=各阶段失败（见 Screenshot.swift） |
| 多窗口诊断 | `MDPreview --multiwindow-test --fileA=/path/a.md --fileB=/path/b.md` | `[MULTIWINDOW] PASS/FAIL 检查项` + info 行 | 0=全过 / 1=有失败 |

- 截图模式环境钩子 `MDP_IMPORT_IMAGE=<图片路径>` / `MDP_EDIT_IMAGE=1`:
  加载文档后执行一次「导入→落盘→插入」全链路 / 打开第一张图片的源码编辑块
  再截图(图片导入与编辑框几何的 e2e 验证口)。
- web 侧诊断留痕：`window.__exportedHTML`（自检轮询用，页面级临时变量）、
  `mdbridge.testImagePayload(data)`(剪贴板载荷识别,自检断言用)。
- WebLocator（`#filePath` 唯一用点）仅服务于诊断/开发定位，W3 已限定在
  Util.swift 单点。

## 4. 桥协议

- JS → Swift：`window.webkit.messageHandlers.mdbridge.postMessage({op, ...})`，
  op 集合见 `DocumentWindowController.handleBridgeMessage`
  (boot/ready/changed/stats/sourceMode/selinfo/jserror/importImage)。
- Swift → JS：`window.mdbridge.*` 方法调用；异步方法返回 Promise，
  **Promise 不可跨桥序列化**，跨桥取值须页侧 `.then` 落到全局变量后由原生轮询
  （自检 D2 即此模式）。
- 图片导入双向对(2026-10-20):JS→Swift `importImage`(requestId/kind=
  blob|file/mime/dataBase64/path),Swift→JS `onImageImported(requestId,
  {ok,src})`;插入唯一入口是 `insertImageCommand`(formatCommand 转发)。
- 命令转发：菜单/右键 → `performEditorAction` → spec.jsCommand →
  `formatCommand`/`tableCommand`；milkdown 命令为**位置参数**形态
  （如 `wrapInHeadingCommand(2)`），payload 标量需 `.fragmentsAllowed` 序列化。
- markdownUpdated listener 经 200ms lodash debounce 异步到达；并发编辑窗内
  会产生携带中间态的过期回调，消费方（Swift 脏标记）依赖 web 侧"过期过滤 +
  同步基线"保证只收到与当前 doc 同步的报告（W5-T3）。
