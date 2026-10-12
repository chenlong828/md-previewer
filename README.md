# MDPreview

一款 **Typora 风格**的 macOS Markdown 所见即所得编辑器。打开即编辑,渲染结果即编辑界面 —— 像增强版记事本一样简单:一次只开一个文件,没有多标签页。

![架构](https://img.shields.io/badge/arch-Swift%20%2B%20WKWebView-blue) ![license](https://img.shields.io/badge/license-MIT-green)

## 功能特性

- **所见即所得编辑**:基于 [Milkdown](https://milkdown.dev)(ProseMirror)渲染,直接在排版结果上编辑,无需预览分栏
- **完整 Markdown 支持**:GFM 表格、任务列表、删除线、引用、代码块、图片、链接、分割线
- **代码高亮**:Prism,支持 Swift / Python / JS / Rust / Go / Java / C / C++ / SQL / Bash / YAML / TOML / JSON / Dart / Kotlin 等常用语言
- **数学公式**:KaTeX,行内 `$E=mc^2$` 与块级 `$$…$$`
- **Mermaid 图表**:流程图 / 时序图 / 饼图等,点击图表进入源码编辑,失焦自动重绘(仿 Typora 交互)
- **源码模式**:`⌘/` 在渲染视图与 Markdown 源码间切换
- **文档内查找**:`⌘F` 呼出查找栏,`Enter`/`Shift+Enter` 在命中项间跳转并高亮当前项,实时显示 `当前/总数`,源码模式同样可用
- **多窗口**:每个文档独立窗口(⌘N 新建、拖放/Finder/命令行均开新窗;⌘O 在当前窗口替换打开),单进程单 Dock 图标(Typora 同款模型)
- **表格编辑**:格式 → 表格 子菜单与右键菜单,支持在光标所在单元格上/下插入行、左/右插入列,删除所在行/列/整表(插入后光标自动落入新表首个单元格)
- **文件能力**:UTF-8 / GB18030 自动识别、脏标记(基线对比:纯查看不弹保存询问,撤销回原文自动恢复干净)、代理图标、文件外部变更监听(自动重载或提示保留)
- **导出**:PDF(`⌘E`)、独立 HTML(内联全部样式资源)、打印
- **格式菜单**:加粗/斜体/删除线/行内代码/链接、H1–H3/正文、引用、有序/无序列表、代码块、数学块、表格(含行列操作)、分割线
- **右键菜单**:彻底替换系统默认菜单,只保留已实现功能 — 撤销/重做、剪切/拷贝/粘贴/全选、查找、源码模式、常用格式、插入表格/分割线;光标在表格内时追加行列操作;右键即定位光标
- **命令注册表**:菜单栏与右键菜单共用同一份命令定义(EditorCommands),新增命令只改一处,行为/快捷键/可用条件天然一致
- **缩放**:`⌘+` / `⌘-` / `⌘0`,持久化
- **自适应宽度**:正文 100% 跟随窗体宽度变化,收缩下限 860px(窄于下限出现横向滚动,避免表格/代码排版爆炸),缩放下视觉下限恒定
- **深浅色**:跟随系统外观实时切换,可在「视图 → 外观」锁定
- **最近文件**、拖拽 `.md` 文件打开、命令行 `open MDPreview.app --args 文件.md`

## 构建

依赖:macOS 13+、Xcode/Swift 5.9+、Node.js ≥ 18。

```bash
./build.sh            # 构建 web 资源 + Swift release 编译 + 组装 dist/MDPreview.app
open dist/MDPreview.app --args /path/to/xxx.md
```

开发调试:

```bash
cd web && npm install --registry=https://registry.npmmirror.com --cache ./.npm-cache && node build.mjs
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.modulecache \
  swift build --disable-sandbox --manifest-cache none --cache-path ./.spm-cache
./.build/debug/MDPreview --selftest      # 无头自检(30 项断言)
./.build/debug/MDPreview --screenshot out.png doc.md   # 进程内截图(无需屏幕录制权限)
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

- Swift → JS:`window.mdbridge.{init, setMarkdown, getMarkdown, setTheme, setZoom, toggleSource, undo, redo, formatCommand, insertTable, exportStandaloneHTML, …}`
- JS → Swift:`webkit.messageHandlers.mdbridge.postMessage({op: boot|ready|changed|stats|sourceMode|jserror, …})`

**设计取舍**:Markdown 解析/渲染完全复用 Milkdown/remark 生态(不手搓解析器);Mermaid SVG 渲染按官方 recipe 以自定义 NodeView 实现(plugin-diagram 7.7 仅提供 schema);Typora 仅复用其 CSS 排版参数与交互逻辑。

## 目录结构

```
Sources/MDPreview/     Swift 壳(main / AppDelegate / DocumentWindowController
                       / EditorWebView / Selftest / Screenshot / Util)
web/                   前端资源(src/main.js、src/typora.css、build.mjs、index.html)
resources/             Info.plist、AppIcon.icns(取自 reference/Typora.app)
samples/               功能演示文档
dist/                  构建产物 MDPreview.app
build.sh               一键构建
```

## 已知边界

- 单窗口单文档,无多标签(有意为之)
- 图片粘贴尚未实现
- 打印依赖 WKWebView 的 `window.print()`,部分系统版本弹窗行为可能略有差异
