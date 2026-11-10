---
layer: history
module: global
status: frozen
updated: 2026-10-24
---

# 坑档案

每条坑三个必填字段：现象、存续条件、对策落点。已消失的坑标注实证日期，条目保留防复发。

## P1 milkdown markdownUpdated 经 200ms debounce 异步到达，防抖窗内回调携带中间态

- **现象**：milkdown listener 插件对每次 docChanged 事务各建一个 lodash.debounce(200ms)
  定时器，flush 时序列化的是**事务捕获时的 doc**；并发编辑（如"编辑后立即打开新文件"）
  会产生携带过期内容的迟到回调。消费方若拿它当"当前内容"，会出现打开文件即报脏、
  保存基线错乱（D1-b 误报，实证 2026-10-12）。
- **存续条件**：仍在。该机制是 milkdown 7.7 的固有行为，升级或替换 listener 机制前持续存在。
- **对策落点**：
  - web 侧单一脏机制：基线由 `setMarkdown`/`markClean` **同步**落定，listener 回调先做
    过期过滤（`markdown === currentMarkdown()`）再报 dirty——`web/src/editor.js`、
    `web/src/bridge.js`（W5-T3，实证 2026-10-14）；
  - 测试侧断言前用"桥消息静止"窗口（`Selftest.settleBridge`，连续 quiet 秒无新上报）
    排空旧事务尾窗，杜绝"断言跑在迟到回调前面"；
  - 机制说明沉淀于 design/architecture.md §4。

## P2 injectMarkdown 双入口 base 参数不一致,相对路径图片在真实应用全不显示

- **现象**:同一路径改写器,无头自检全绿,真实应用里所有相对路径图片都不显示
  (2026-10-20 实证:受控文档三变体全部保持原样)。根因是 `openDocument` 把
  **文件 URL** 传给 `injectMarkdown(baseURL:)`、`forceReload` 传**目录**——
  前者解析出 `doc.md/resource/…`,fileExists 恒 false,改写静默放弃。隔离的
  改写器单测以目录为基准,从未覆盖这条真实装配缝。
- **存续条件**:已消失(2026-10-20)。契约单点化:`injectMarkdown(docURL)` 收
  文档 URL、内部唯一推导目录,两个调用点同构;截图模式 dom 探测(images 数组
  含 src/naturalWidth)可对真实装配做显示断言。
- **对策落点**:
  - 契约写明于 design/architecture.md §2.1「基点契约」;
  - 同类风险判据:同一数据(路径解析基准)的推导点必须唯一,调用方传领域实体
    (docURL),不在调用点各自推导派生值;
  - selftest 的改写器单测仍不覆盖 openDocument 装配缝——显示类问题优先用
    `--screenshot` + dom 探测在真实装配上验证。

## P3 ImageStore 目录列举失败静默当空目录,img 序号回绕覆盖既有图片

- **现象**:评审发现 `existingFiles` 以 `try? ?? []` 兜底——目录可写但不可列举
  (如 chmod 0o300,缺 r 位)时,列目录静默得空表,`img_NNN` 序号回绕到 001,
  `.atomic` 写盘**静默覆盖**既有图片。selftest 最小复现实证(红跑):第二次
  导入后 img_001.png 内容确被覆盖,属数据丢失级,非理论风险。
- **存续条件**:已消失(2026-10-20)。`existingFiles` 改为原样抛错,命名函数与
  `ImageStore.import` 顺次传播,失败由原生弹窗提示;红→绿用例守门
  (「图片落盘-不可列举目录拒绝(防覆盖)」「既有图片未被覆盖」)。
- **对策落点**:
  - 失败契约写明于 design/architecture.md §2.1a「导入落盘约定」;
  - 同类风险判据:`try? ?? 空值` 兜底 IO 失败前,先问"空值会让下游推导出
    错误业务结果吗"——序号/去重/命名类推导对空表敏感,必须抛错。

## P4 URL(string:) 对「未编码非 ASCII + 合法 %XX」混排 file URL 再转义合法 %XX

- **现象**:资源清理用例红跑中,`file:///…/文档/abs%20ref.png` 经
  `URL(string:)` 解析后 `.path` 得到字面 `"abs%20ref.png"`(空格未还原)——
  描述输出显示 `%20` 被再转义成 `%2520`,解码后与真实文件名 `abs ref.png`
  错位,该引用判定失配、文件被误删(2026-10-20 实证)。根因:当 URL 字符串
  同时含未编码非 ASCII 与合法 %XX 时,Foundation 的新解析器进入宽容编码
  模式,把已合法的 `%` 一并转义;纯 ASCII 的 %XX(如自家产生的
  absoluteString)则解析正确——所以保存往返用例从未暴露。
- **存续条件**:仍在。这是 Foundation 运行时行为,不随本仓库代码变化;
  凡「混排 file URL → 文件系统路径」的解析点都要绕开 `URL(string:)`。
- **对策落点**:
  - `ImagePathRewriter.percentDecodedPath`:file:// 之后手工分段
    百分号解码(`removingPercentEncoding`,非法序列保原文),已编码/未编码/
    文件名含字面 % 三种形态都得正确路径;
  - `resolveForSave` 同口径加固(保存链路同一缺陷类,selftest 保存往返守门);
  - `addingPercentEncoding(.urlQueryAllowed)` 不含 `%`(RFC 3986 字面集),
    不能用来"补编码"含 % 的串——会把合法 %XX 变 %25XX;
  - 引用与候选路径比较前双侧 `standardizedFileURL` 规范化(./ 前缀引用
    与目录列举路径失配会误删,红跑实证);
  - 判定用例:selftest「资源清理-孤儿删除且被引用/非图片保留」(%20 编码
    与 ./ 前缀分支)。

## P5 打开请求暂存只挂在仅发生一次的 ready 桥消息,装载中到达的请求永久滞留

- **现象**:抽屉双击/⌘O 的打开请求在编辑器注入进行中(isLoadingContent)到达时
  暂存于 pendingOpenURL,而补载逻辑只挂在 ready 桥消息分支——ready 在页面
  生命周期仅发生一次,此后暂存请求永不补载。实测 setMarkdown 完成回调在
  编辑器冷启动期可延迟 ~1.6s,该窗口期真实存在(2026-10-20 drawer-test
  红跑实证:双击落入窗口期即永久无响应)。
- **存续条件**:已消失(2026-10-20)。注入完成后 drainPendingOpen 立即排空
  暂存请求(按目录/文件分派);openDirectory 未就绪时并入同一暂存机制。
- **对策落点**:
  - 契约写明于 design/architecture.md §2.4「装载暂存排空契约」;
  - 同类判据:一次性事件(ready/首次加载完成)不能作为暂存队列的唯一补载
    时机——排空点必须与页面生命周期事件无关。

## P6 NSOutlineView 懒加载三段式(shouldExpand 拦截+后台装载+续展)与子层缓存时序不合,真实点击展开失效

- **现象**:文件抽屉 lazy 首版用「shouldExpand 拦截返回 false + 后台 readdir +
  reloadItem 后 expandItem 续展」装载子层;真实 GUI 点击展开三角无反应,
  而 selftest/drawer-test 全绿——无头 harness 只能按调用链模拟
  (debugExpandByClick),复现不了真实点击与 NSOutlineView 对未展开条目
  子层缓存的时序组合,任何一环错拍即表现为「目录打不开」(2026-10-20 实证)。
- **存续条件**:已消失(2026-10-20)。装载改**数据源内同步**——
  numberOfChildrenOfItem 取数时 ensureLoaded 同步 readdir 该层,无拦截/
  无异步/无续展,与 AppKit 缓存时序彻底无关;选中定位同口径同步装载祖先链。
  代价评估:展开是单次点击低频动作,单层 readdir 毫秒级,同步可接受。
- **对策落点**:
  - 契约写明于 design/architecture.md §2.4「装载模型为 lazy 按层」;
  - 测试口径缺口登记为 [plan/risks.md R8](../plan/risks.md)(交互时序无头
    不可复现,交互类工序收口必附真人点验清单);
  - 同类判据:AppKit 数据源懒加载优先在数据源内同步供给,避免
    「拦截+异步+续展」的时序重组。

## P7 mdast `listItemIndent: 'tab'` 不是「4 空格缩进」,覆盖 handlers.listItem 还会顶掉 GFM 复选框

- **现象**:修「列表 Tab 嵌套只缩 2 空格」时,最直觉的两步都踩坑(2026-10-24 实证):
  1) 改 `listItemIndent: 'tab'` —— 它把首行标记也补到 4 列(`- a` → `-   a`、
     `1. a` → `1.  a`),不是标准形态;
  2) 改用 `handlers.listItem` 自定义 handler 后,若照抄默认 handler,任务列表
     保存会丢掉复选框(`- [x] done` → `- done`)——GFM 的 listItem handler 在
     选项层被顶掉(configure 顺序:extensions 先、options.handlers 后;
     而 remark-stringify 又只读 processor data 的 `toMarkdownExtensions`,
     用户传 `extensions` 无效)。
- **存续条件**:仍在。库行为不改就持续存在;凡用 `handlers` 覆盖 mdast 输出,
  都可能顶掉上游扩展(任务列表/脚注等)的同类 handler。
- **对策落点**:
  - `web/src/list-indent.js`:自定义 handler 内复刻复选框语义(`node.checked`),
    首行单空格 + 续行 `max(4, 标记宽+1)`;
  - selftest 三条断言守门(Tab 端到端 4 空格、多级 4/8 空格、任务列表复选框保留),
    实证见 [works/2026-10-24-list-indent-four-space](works/2026-10-24-list-indent-four-space/result.md);
  - 判据:凡为「输出格式」换 handler,先确认被顶掉的上游 handler 做了什么
    (grep `toMarkdownExtensions` 与同名 handler),并为本工序关心的每种语法
    各留一条断言,别只测自己改的那一种。

## P8 整份引入第三方浅色主题 + 差量暗色覆盖,未覆盖项静默回落

- **现象**:深色模式代码块里 `=` `<` `>` `:` 等运算符在灰色底上显示为浅色(`#999`)
  实心块,`builtin` / `doctype` / `variable` 在深色下沿用浅色主题值(2026-10-24 实测:
  暗色截图 `#999` 像素 29572,聚成 56 个 26×24 CSS px 矩形;`.token.operator`
  计算背景 `rgba(255,255,255,0.5)`,`0.5×#fff + 0.5×#333 = #999`)。
- **存续条件**:已消失(2026-10-24)。调色板自有化后 token 无背景、浅/深各自完整;
  若将来重新整份引入第三方浅色主题,坑即复活——selftest「token 调色板」断言会先红。
- **对策落点**:
  - `web/src/typora.css`「代码高亮 token 调色板」:浅/深两张变量表 + 完整分组规则,
    `.token { background: none }` 不变量;
  - `Sources/MDPreview/Selftest.swift` `checkTokenPalette`:13 组 29 类逐类核对
    实测色值/背景/阴影,浅/深各一条;
  - 机制与失效条件见 `design/architecture.md` §2.6;实证见
    [works/2026-10-24-code-token-palette](works/2026-10-24-code-token-palette/result.md)。

## P9 WKWebView 是 flipped 视图：右键坐标不能再翻转，原生菜单也不会替你放 caret

- **现象**：表格里右键某行 → 「删除所在行」作用在别的行，甚至菜单不出现行列项；顶部菜单栏
  发起同一命令却准确（用户 2026-11-10 实证）。两处平台行为叠加：
  1) `WKWebView.isFlipped == true`，`convert(_:from:)` 返回的 y 已是「从视口顶部起算」；
     再算 `bounds.height - p.y` 会把点击点镜像到视口中线（视口正中点恰好正确，掩盖了问题）。
  2) 原生右键菜单吞掉 rightMouseDown/Up，WebKit 不会像左键那样把 caret 放进 contenteditable；
     只有 state 选区而没有 DOM 焦点时，菜单弹出前看不到「当前行」。
- **存续条件**：仍在（平台行为）。凡在 WKWebView 上做「右键/屏幕坐标 → 文档位置」都必须
  走同一坐标口径；将来改用 `WKWebView.pageZoom` 或非 1:1 页面缩放时，点与 CSS 像素不再等值，
  需按 pageZoom 折算。
- **对策落点**：
  - `EditorWebView.pagePoint(forWindowPoint:)` 唯一换算点（flipped 不翻转），
    `focusAt` 设置选区后 `view.focus()` 让 DOM caret 落在点击处；
  - `--context-menu-test` 合成真实右键事件（含单元格内边距）断言「点击行 = 作用行」；
  - 机制写明于 `design/architecture.md` §2.8；场景断言见 SCN-0008 TC-TBL-005/006；
  - 同类判据：原生控件接管输入事件后，不要假设 Web 内容侧会收到同一交互带来的副作用
    （焦点/选区/滚动），需要壳显式重建。
