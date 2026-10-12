---
layer: design
module: global
status: active
updated: 2026-10-14
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

### 2.1 ImagePathRewriter 正则改写的覆盖边界

- **决策**：图片路径改写采用单行正则匹配（`!\[...\](path "title")` 形态），
  仅处理围栏代码块之外的行；解析失败时**静默保留原文**。
- **覆盖边界（明确不支持的写法）**：
  1. 引用式图片 `![alt][ref]` 不改写（保存/加载保持原样）；
  2. 路径含嵌套括号 `![a](dir(1)/x.png)` 不改写；
  3. 路径内转义字符（如 `\ ` 空格转义）不展开；
  4. 跨行书写（`![alt](` 与路径分行）不改写。
- **理由**：覆盖以上长尾需引入完整 Markdown 内联解析，复杂度与收益不成比例；
  静默保留原文是安全退化——不改写最多导致图片不显示，不会破坏文件内容。
- **失效条件**：若用户群出现大量引用式图片/嵌套括号路径的文档，需升级为
  AST 级改写；静默策略需同步改为可提示（状态栏提示改写失败计数）。

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

## 3. 诊断面（OQ-3 结论：保留为官方诊断面并文档化）

诊断代码随 release 构建发布是**有意保留**：单机工具无线上灰度能力，官方
诊断面是问题排查的唯一手段。三个入口统一风格如下：

| 入口 | 语法 | 输出前缀 | 退出码 |
|---|---|---|---|
| 无头自检 | `MDPreview --selftest` | `PASS/FAIL  名称` 每行一项，末行 `SELFTEST PASSED/FAILED` | 0=全过 / 1=有失败 |
| 进程内截图 | `MDPreview --screenshot out.png [input.md]` | `SCREENSHOT …` | 0=成功；2/3/4/5/6/7=各阶段失败（见 Screenshot.swift） |
| 多窗口诊断 | `MDPreview --multiwindow-test --fileA=/path/a.md --fileB=/path/b.md` | `[MULTIWINDOW] PASS/FAIL 检查项` + info 行 | 0=全过 / 1=有失败 |

- web 侧诊断留痕：`window.__exportedHTML`（自检轮询用，页面级临时变量）。
- WebLocator（`#filePath` 唯一用点）仅服务于诊断/开发定位，W3 已限定在
  Util.swift 单点。

## 4. 桥协议

- JS → Swift：`window.webkit.messageHandlers.mdbridge.postMessage({op, ...})`，
  op 集合见 `DocumentWindowController.handleBridgeMessage`。
- Swift → JS：`window.mdbridge.*` 方法调用；异步方法返回 Promise，
  **Promise 不可跨桥序列化**，跨桥取值须页侧 `.then` 落到全局变量后由原生轮询
  （自检 D2 即此模式）。
- 命令转发：菜单/右键 → `performEditorAction` → spec.jsCommand →
  `formatCommand`/`tableCommand`；milkdown 命令为**位置参数**形态
  （如 `wrapInHeadingCommand(2)`），payload 标量需 `.fragmentsAllowed` 序列化。
- markdownUpdated listener 经 200ms lodash debounce 异步到达；并发编辑窗内
  会产生携带中间态的过期回调，消费方（Swift 脏标记）依赖 web 侧"过期过滤 +
  同步基线"保证只收到与当前 doc 同步的报告（W5-T3）。
