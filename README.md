# MDPreview

一款 **Typora 风格**的 macOS Markdown 所见即所得编辑器。打开即编辑,渲染结果即编辑界面 —— 像增强版记事本一样简单:一次只开一个文件,没有多标签页。

![架构](https://img.shields.io/badge/arch-Swift%20%2B%20WKWebView-blue) ![license](https://img.shields.io/badge/license-MIT-green)

## 功能特性

- **所见即所得编辑**:基于 [Milkdown](https://milkdown.dev)(ProseMirror)渲染,直接在排版结果上编辑,无需预览分栏
- **完整 Markdown 支持**:GFM 表格、任务列表、删除线、引用、代码块、图片、链接、分割线
- **图片**:本地相对路径图片正常显示(容忍路径含空格/括号,wechat-offline 导出文档实测);点击图片整块切换为源码编辑(宽度撑满编辑器、长路径自动换行,与文件写法同构),失焦或 Enter 提交、Esc 还原,清空地址即删图;⌘V 粘贴截图或图片文件路径、拖入图片文件、格式→插入图片…均自动把图片复制到文档旁 `resource/<md文件名>/` 并插入引用(与 wechat-offline 导出布局一致)
- **代码高亮**:Markdown 围栏代码块与代码文件共用 refractor/Prism 语法表,支持 Swift / Python / JS / TS / TSX / JSX / Rust / Go / Java / Kotlin / C / C++ / C# / Ruby / PHP / SQL / Bash / YAML / TOML / JSON / XML / HTML / CSS / Diff / Dockerfile 等 44 种语言;配色由 `typora.css` 的 token 调色板单一维护(浅/深两组)
- **代码文件查看**:直接打开常见代码文件(⌘O / 抽屉 / 拖放 / 命令行 / 最近文件)显示**只读高亮源码**,不进入 Markdown 编辑管线;左侧按逻辑行显示行号,长行软换行,点击行或 ⌘F 命中时高亮当前行,「视图 → 显示行号」可全局开关(跨窗口记忆);语言默认按扩展名推断,「视图 → 高亮语言」可切换语言或关成纯文本,状态栏显示「只读 · 语言」;⌘F 查找、⌘E PDF / ⌘P 打印均可用;行号只是阅读层,复制/查找/导出仍保持原文;超过 512 KB 的文件自动降级纯文本并在状态栏提示
- **数学公式**:KaTeX,行内 `$E=mc^2$` 与块级 `$$…$$`
- **Mermaid 图表**:流程图 / 时序图 / 饼图等,点击图表进入源码编辑,失焦自动重绘(仿 Typora 交互)
- **源码模式**:`⌘/` 在渲染视图与 Markdown 源码间切换
- **文档内查找**:`⌘F` 呼出查找栏,`Enter`/`Shift+Enter` 在命中项间跳转并高亮当前项,实时显示 `当前/总数`,源码模式同样可用
- **多窗口**:每个文档独立窗口(⌘N 新建、拖放/Finder/命令行均开新窗;⌘O 与「打开最近使用」在当前窗口替换打开),单进程单 Dock 图标(Typora 同款模型)
- **文件抽屉**:`⌘\` 开合左侧抽屉,树形展示当前文档所在文件夹(与 Finder 一致的文件夹图标;**按层懒加载**——展开目录时同步读取下一层(点击即出,任意规模目录树开销恒定);文件只列可打开的文件(Markdown 与代码文件),隐藏条目/符号链接/`node_modules`/包目录跳过,暂无 md 的目录也会显示);展开时窗口优先向左伸出,伸出后超出屏幕宽度则整体收敛到屏幕宽度;双击文件在**当前窗口**覆盖打开(脏文档先确认保存);顶部锚点路径控件铺满「抽屉宽 − 两个按钮」,显示当前根的文件夹图标/目录名/展开箭头,点击弹出带 Finder 文件夹图标、逐级缩进的父级链菜单,选中即把该父级锚定为抽屉根(方便跨多层浏览);右侧 **Home** 按钮一键回到当前用户 Home 目录、**刷新**按钮重扫文件夹;抽屉与正文之间的边界可**鼠标拖拽调宽**(160–480pt,并受「正文不窄于 320pt」二次夹取);宽度与开合状态均跨窗口记忆;命令行/⌘O/最近使用等外部方式打开文件时,锚点默认为文件所在目录,抽屉内双击不改变锚点
- **表格编辑**:格式 → 表格 子菜单与右键菜单,支持在光标所在单元格上/下插入行、左/右插入列,删除所在行/列/整表(插入后光标自动落入新表首个单元格)
- **文件能力**:UTF-8 / GB18030 自动识别、脏标记(基线对比:纯查看不弹保存询问,撤销回原文自动恢复干净)、代理图标、文件外部变更监听(自动重载或提示保留)
- **导出**:PDF(`⌘E`)、独立 HTML(内联全部样式资源)、打印
- **格式菜单**:加粗/斜体/删除线/行内代码/链接、H1–H3/正文、引用、有序/无序列表、代码块、数学块、表格(含行列操作)、分割线
- **右键菜单**:彻底替换系统默认菜单,只保留已实现功能 — 撤销/重做、剪切/拷贝/粘贴/全选、查找、源码模式、常用格式、插入表格/分割线;光标在表格内时追加行列操作;右键即定位光标
- **命令注册表**:菜单栏与右键菜单共用同一份命令定义(EditorCommands),新增命令只改一处,行为/快捷键/可用条件天然一致
- **缩放**:`⌘+` / `⌘-` / `⌘0`,持久化
- **自适应宽度**:正文 100% 跟随窗体宽度变化,收缩下限 860px(窄于下限出现横向滚动,避免表格/代码排版爆炸),缩放下视觉下限恒定
- **深浅色**:跟随系统外观实时切换,可在「视图 → 外观」锁定
- **最近文件**、拖拽 `.md`/代码文件打开、命令行 `open MDPreview.app --args 文件.md`;**目录模式**:参数传目录(或「文件 → 打开文件夹…」⌘⇧O、拖入文件夹)时右侧为空白编辑器、左侧抽屉树形导航,双击文件就地打开

## 构建

依赖:macOS 13+、Xcode/Swift 5.9+、Node.js ≥ 18。

```bash
./build.sh            # 构建 web 资源 + Swift release 编译 + 组装 dist/MDPreview.app
open dist/MDPreview.app --args /path/to/xxx.md      # 打开文件
open dist/MDPreview.app --args /path/to/folder      # 目录模式(抽屉导航)
```

开发调试(构建参数唯一来源是 build.sh,此处不复述):

```bash
./build.sh debug                        # debug 编译(参数见 build.sh,勿另抄)
./.build/debug/MDPreview --selftest     # 无头自检
./.build/debug/MDPreview --screenshot out.png doc.md   # 进程内截图(无需屏幕录制权限)
# 前端单跑:cd web && npm install --registry="$NPM_REGISTRY(默认 npmmirror)" && node build.mjs
```

## 架构

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
│   ├ plugin-math (KaTeX 0.16)                │
│   └ plugin-prism (代码高亮)                  │
│  typora.css(Typora github 主题参数)          │
└────────────────────────────────────────────┘
```

**桥协议**(Swift ⇄ JS):

- Swift → JS:`window.mdbridge.{init, setMarkdown, getMarkdown, setTheme, setZoom, toggleSource, undo, redo, formatCommand, insertTable, exportStandaloneHTML, setCode, setCodeLanguage, isCodeMode, codeInfo, …}`
- JS → Swift:`webkit.messageHandlers.mdbridge.postMessage({op: boot|ready|changed|stats|sourceMode|jserror, …})`

**设计取舍**:Markdown 解析/渲染完全复用 Milkdown/remark 生态(不手搓解析器);Mermaid SVG 渲染按官方 recipe 以自定义 NodeView 实现(plugin-diagram 7.7 仅提供 schema);Typora 仅复用其 CSS 排版参数与交互逻辑。

## 目录结构

```
Sources/MDPreview/     Swift 壳(main / AppDelegate / DocumentWindowController
                       / EditorWebView / FileSupport / Selftest / Screenshot / Util)
web/                   前端资源(src/main.js、src/code-view.js、src/languages.js、src/typora.css、build.mjs、index.html)
resources/             Info.plist、AppIcon.icns(MP 字标,由 resources/icon/render-icon.swift 生成)
samples/               功能演示文档与代码示例(code-sample.py)
dist/                  构建产物 MDPreview.app
build.sh               一键构建
```

## 已知边界

- 单窗口单文档,无多标签(有意为之)
- 代码文件为**只读查看**:不支持编辑/保存/撤销,不提供折叠、minimap 与 LSP;提供逻辑行行号、软换行与当前行高亮(行号开关为全局偏好,不写入文件,行号不进入复制/查找);代码文档没有源码模式切换(恒为纯源码);不做 Finder「打开方式」关联;不导出独立 HTML(PDF/打印可用);无扩展名文件(`Dockerfile`/`Makefile`)不识别为代码,需带扩展名;超过 512 KB 的文件只降级纯文本,不保证高亮
- 文件抽屉:宽度可拖拽调节,但不做「双击分界线复位默认宽度」;目录内容变化需手动点抽屉顶部刷新按钮(不做文件系统监听);树内不含新建/删除/重命名操作;`node_modules` 与包目录(.app/.bundle 等)整棵跳过;lazy 装载下无截断,但暂无 md 的空目录也会显示(展开为空)
- 目录模式下右侧为可编辑空白文档(与新建空文档一致),⌘S 走另存为;再次打开文件即自然退出目录模式
- 图片一次粘贴只取第一张;新建未保存的文档需先保存才能粘贴/插入图片(图片要落到文档旁 resource/ 目录)
- 含空格的图片路径保存后会规范为 `<>` 包裹写法(合法 CommonMark,各渲染器通用)
- **`resource/<md文件名>/` 由应用按引用管理**:关闭文档时自动清理目录内未被当前文档引用的图片(全清空时连同目录移除);目录内非图片文件不会被动;撤销粘贴产生的孤儿文件在关闭时清除(撤销不立即删盘,保证 ⌘⇧Z 重做可用);不支持多文档共享同一 resource 子目录
- 导出 HTML 仅内联样式资源,图片仍为 file:// 引用(需与文档同机查看)
- **保存恒定 UTF-8 输出**:打开时自动识别 UTF-8 / GB18030,但保存一律以 UTF-8 回写(GB18030 文件一经保存即被转码;应用不做原编码保存)
- 列表嵌套保存为**每级 4 空格**(Tab 等价的标准缩进;首行标记仍紧凑,`- a` 不补成 `-   a`);2 空格缩进的旧文件可正常打开,保存时按此口径规范化
- 保存时文件末尾无条件补一个换行符(工具行为,原文无尾换行时保存后会多出)
- 打印依赖 WKWebView 的 `window.print()`,部分系统版本弹窗行为可能略有差异
