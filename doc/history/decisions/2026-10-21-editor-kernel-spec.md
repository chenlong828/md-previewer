---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

> **归档注记（2026-10-21）**：本规格经评审产出后，用户决定暂缓实施——第二次门
> 未走、零代码落地。按工序收口冻结存档于此，不得作为现行设计依据。恢复壳工作
> 时从本档重启：先复核 §9 决策 D1–D5 与 §1.2 不变量仍然有效，再升格 design/
> 走第二次门。

# 编辑器内核（editor-kernel）架构规格

MDPreview 的目标架构：**每平台一个原生壳（macOS=Swift/AppKit+WKWebView；
Windows/Linux 各自另建），共享一个可移植的 JS 逻辑内核**（Milkdown/ProseMirror
编辑器 + markdown 文本语义 + 桥契约实现）。本规格定义内核/壳分界、桥契约 v2、
数据所有权与验证计划。现行 macOS 实现向本规格迁移的方案见 §4.6 与 §7；
迁移完成前，`design/architecture.md` §4 描述的 v1 桥仍是现行真相。

## 1. 业务能力与约束

### 1.1 内核承载的业务能力

| 能力 | 服务对象 | 失败语义 | 冷/热 |
|---|---|---|---|
| 所见即所得 Markdown 编辑（渲染/输入/撤销/格式化/表格） | 文档作者 | 输入不丢、序列化往返一致（不变量 I1） | 热 |
| 源码模式切换与两态内容单一真相源 | 文档作者 | 保存口径恒一致（不变量 I2） | 热 |
| 文档内查找（渲染态/源码态） | 文档作者 | 计数恒为数字，未就绪报 -1 | 热 |
| 统计（词/字符） | 文档作者 | 防抖合并，最终一致 | 热 |
| 独立 HTML 导出（样式内联） | 文档作者 | 资源内联失败退化为引用 | 冷 |
| 图片引用文本语义（显示改写/保存还原/引用收集/落盘命名约定） | 文档作者 + 壳 | 解析失败静默保留原文（安全退化，architecture.md §2.1） | 冷（随装载/保存/GC） |
| 图片粘贴/拖入的识别与导入编排 | 文档作者 | 失败由壳弹窗，内核只清挂起表（幂等） | 冷 |
| 视图配置（主题/缩放/标题） | 文档作者 | 输入夹取（缩放 0.5–3） | 热 |

**壳承载的能力**（每平台实现，内核经契约调用）：窗口与多窗模型、菜单/快捷键/右键
菜单、文件读写与编码探测（UTF-8/GB18030）、外部变更监听、脏确认流、保存面板与
最近文件、图片落盘与 GC 执行、PDF 导出与打印、文件抽屉/目录树、拖放、诊断入口、
webview 装配。安全取舍（全盘读授权、mermaid loose）随壳定位决定，内核不携带。

### 1.2 关键约束

- 内核**零宿主感知**：除 §4.5 传输面两个符号外，不得出现任何宿主/引擎专有标识。
- 三平台三引擎（WKWebView / WebView2 / WebKitGTK）：构建 target 取最保守分母
  `safari16.4`，单产物多壳复用；引擎差异（字体/IME/打印/剪贴板）记壳侧冒烟项。
- 不变量（最不能破的三条）：
  - **I1** 序列化往返一致：加载文本 → 渲染 → 保存口径文本，内容语义不丢；
    解析不出的写法静默保留（architecture.md §2.1 同口径）。
  - **I2** 保存口径单一：保存/基线/统计对「当前内容」的取值同源（R1 教训）。
  - **I3** 磁盘唯一写入口是壳：内核不发任何持久化动作，只提交意图（importImage
    请求、getResourceRefs 引用集）。
- 最痛失败 → 验证重点：跨平台语义漂移（→黄金夹具）、契约版本错配（→握手拒绝）、
  桥消息异常（→显式错误码，不静默）。

### 1.3 变化轴（封在哪个模块后面）

| 变化轴 | 封装位置 |
|---|---|
| 新宿主平台/新壳 | transport 适配（壳侧注入）+ 壳本体；契约不动 |
| 路径风格/资源 URL scheme | PathPolicy 端口（§4.4）单点 |
| 编辑能力（命令/插件/档位） | core 内 + 契约 op 表版本化扩展 |
| markdown 生态升级（milkdown 大版本） | core 内；契约不出现框架类型 |

## 2. 模块地图

```
┌────────────────────────── 壳（每平台一份，本仓库外） ──────────────────────────┐
│ 窗口/菜单/文件 IO/监听/脏确认/落盘·GC 执行/PDF·打印/抽屉/诊断/偏好              │
│ 传输适配：注入 window.__mdHostChannel + 调 window.__mdKernel.receive()         │
└───────────────▲───────────────────────────────┬──────────────────────────────┘
                │ editor→host（通知/请求）        │ host→editor（请求/响应）
┌───────────────┴───────────────────────────────▼──────────────────────────────┐
│ 编辑器内核（JS，可移植）                                                       │
│  transport/   通道适配：__mdHostChannel 封装 + receive() 单入口 + 错误钩子安装  │
│  contract/    消息泵：信封校验、op 注册表、id 关联、版本握手、错误码            │
│  semantics/   markdown 文本语义（纯函数）：路径改写 load/save、引用收集、       │
│               落盘命名约定；PathPolicy 默认实现（posix/win32）                 │
│  core/        编辑器能力：editor/find/find-bar/tables/stats/selinfo/          │
│               mermaid-view/commands/export/image-view/image-paste/state       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 模块卡：contract

- 层/类型：L1；技术边界模块（契约唯一实现点）
- 业务价值：为内核与所有壳提供**同一份可版本化、可符合性测试的协议**；没有它，
  每个壳都要从 Swift 调用点反推语义（现状之痛）。
- 负责：信封（v/op/id/payload）构造与校验、op 分发、请求-响应 id 关联、
  版本握手、错误码；向 core 暴露 `notify()` / `callHost()`，向 transport 暴露
  `receive()`。
- 不负责：任何 markdown 语义、任何 DOM/编辑器逻辑、传输细节。
- 变化轴：协议版本演进（op 增删、错误码扩充）。
- 公开契约：§4.1–4.3。
- 验证：op 表全量契约测试（§8）。
- 删除测试：删掉则协议语义散落 core/壳两侧——真边界。

### 模块卡：semantics

- 层/类型：L1a（领域基础）；纯函数库
- 业务价值：markdown 文本级语义的**唯一实现**，跨壳零漂移（评审 R1 的收口点）。
- 负责：`rewriteForLoad(text)`（宽松捕获/平衡括号/`<>`/静默保留，规则同
  architecture.md §2.1）、`restoreForSave(md)`、`collectResourceRefs(md)`、
  `nextResourceName({existing, mime})`（`img_NNN.ext`、冲突 `-2`、mime 定扩展名）、
  相对⇄绝对换算中**文本侧**（baseDir 前缀匹配、还原原始写法）。
- 不负责：文件系统（存在性/落盘/删除）、URL 可加载性（PathPolicy 的 scheme 组装
  除外——见模块卡 PathPolicy 归属说明）。
- 变化轴：路径规则长尾（引用式图片、AST 级改写升级，architecture.md §2.1 失效条件）。
- 验证：黄金夹具 + 属性测试（§8）；与 Swift 旧实现对拍迁移（§4.6）。
- 删除测试：删掉则规则回到每壳一份——真边界。

### 模块卡：transport

- 层/类型：L0；防腐层
- 业务价值：内核唯一的宿主感知点；新壳接入成本 = 注入两个符号。
- 负责：`window.__mdHostChannel.post(json)` 的容错封装、`window.__mdKernel.receive`
  单入口暴露、onerror/console.error/unhandledrejection → `jserror` 通知安装
  （迁自 index.html 内联脚本，宿主标识从此退出内核资产）。
- 不负责：消息语义（透传给 contract）。
- 变化轴：传输机制（postMessage/IPC 自定义桥）。
- 验证：缺 channel 时 boot 失败可见（严格失败，不静默降级）。
- 删除测试：删除后 core 直接摸宿主对象——真边界（防腐价值）。

### 模块卡：core

- 层/类型：L1b（领域能力）；业务模块群
- 业务价值：编辑器全部用户可感能力；Milkdown 投入的载体。
- 负责：§1.1 表中除语义类外的全部能力；`state` 单例（显式声明全部字段，沿用
  现行纪律）。
- 不负责：路径文本规则（调 semantics）、桥格式（调 contract）、文件系统。
- 变化轴：编辑能力与 markdown 生态。
- 验证：Node 契约套件（命令注册表一致性、源码模式保存口径、查找/统计）。
- 删除测试：即产品本体，不可删。

### 壳参考职责（每平台对照实现，非本仓库模块）

按 macOS 现行实现裁剪的**壳最小集**（阶段 1 MVP）：webview 装配 + 传输适配、
开/编/存（含编码探测与补尾换行）、脏标记与外部变更监听、图片粘贴落盘（调
semantics 命名约定）、右键菜单与命令转发、诊断冒烟。**阶段 2**：抽屉/目录模式、
PDF/打印、最近文件。壳必须遵守的时序流程见 §5 路径卡（boot/ready/pendingOpen
暂存排空/装载中守卫——W5 时序契约的跨平台化）。

## 3. 依赖矩阵

内核内部（方向自上而下，禁止反向与同层横调）：

| 调用方 | 被调方 | 契约 | 方式 | 路径 | 失败处理 |
|---|---|---|---|---|---|
| core | contract | notify()/callHost() | 同步/异步 | 热+冷 | callHost 超时由调用方语义决定（仅 importImage 类偶发路径有超时） |
| core | semantics | 纯函数 | 同步 | 热（装载/提交）+冷 | 解析失败静默保留原文（I1） |
| contract | transport | post/receive | 同步 | 全部 | 缺 channel：boot 前抛可见错误 |
| semantics | （无） | — | — | — | 纯函数，零依赖 |

跨契约（内核↔壳）依赖见 §4 op 表。

**禁止边**：
- `core`、`semantics`、`contract` 出现宿主符号（`window.webkit`、
  `chrome.webview` 等）——仅 `transport/` 豁免（lint 守门，§8）；
- `semantics` import core/contract（纯度守门）；
- 契约 payload 出现第三方类型（ProseMirror/Milkdown 对象跨桥——payload 只允许
  JSON 原语/数组/对象）；
- 壳解析/改写 markdown 文本（语义越界，R1 复发点）；
- 内核发起任何持久化（I3）。

扇出：core → (contract, semantics) = 2；壳 → contract 单通道。均在预算内。

## 4. 契约清单（桥协议 v2）

### 4.1 契约卡：消息信封 v2

- 目的：内核与壳之间唯一通信形态，取代「字符串拼 JS 方法调用 + evaluateJavaScript
  返回值」（v1）。
- 签名（JSON 文本，双向同构）：

```
请求：  {"v":2,"op":"<名称>","id":"<唯一串>","payload":{...}}
响应：  {"v":2,"id":"<原id>","ok":true,"payload":{...}}
        {"v":2,"id":"<原id>","ok":false,"error":{"code":"...","message":"..."}}
通知：  {"v":2,"op":"<名称>","payload":{...}}          // 无 id，无响应
```

- 不变量：响应必须回显请求 id；payload 只含 JSON 原语/数组/对象；消息按到达顺序
  处理（单通道串行，不定义乱序语义）。
- 错误码（版本化，可扩充）：`unknown_op` / `bad_payload` / `not_ready` /
  `unsupported_version` / `internal`。**not_ready 取代 v1 的静默返回 undefined**
  （v1 中 ready 前 setMarkdown 等被无声丢弃，时序缺陷不可见）。
- 幂等/顺序/并发：请求默认不幂等；显式标注幂等的 op（importImage）以 id 为幂等键；
  同一 id 的重复请求必须返回同一结果且不产生副作用（壳落盘按 id 去重）。
- 超时/取消：协议层不设超时；调用方（壳）负责 UI 级超时与取消，取消=放弃等待，
  不回灌。
- 兼容性/废弃：`v` 字段每消息携带；版本不匹配在握手时拒绝（§4.5），不做运行期
  静默兼容。v1→v2 迁移见 §4.6。

### 4.2 契约卡：editor → host op 表

通知（无 id）：

| op | payload | 说明 |
|---|---|---|
| boot | `{}` | 页面脚本就绪 |
| ready | `{}` | init 完成（壳 isReady 唯一置位点，沿用现状） |
| changed | `{dirty: bool}` | 内容/脏变化（防抖过期过滤后，沿用现行口径） |
| stats | `{words, chars}` | requestStats 或防抖驱动 |
| sourceMode | `{value: bool}` | 源码模式切换后 |
| selinfo | `{inTable: bool}` | 光标进出表格（右键菜单可用性） |
| jserror | `{message, where?, stack?}` | 内核已捕获的运行时错误 |

请求（带 id）：

| op | payload → 响应 | 说明 |
|---|---|---|
| resolveResources | `{refs: string[]} → {resources: {ref → {url: string\|null, exists, isImage}}}` | **新增**。装载改写的文件感知点：内核解析候选引用后批量询问，壳以文件系统为准作答（宁多保护口径同现行 GC 收集） |
| importImage | `{kind: 'blob'\|'file', mime?, data?, path?} → {ok, src?, error?}` | 幂等键=消息 id（v1 的 requestId 即 id，语义不变）。失败壳已弹窗，响应仅置 ok:false |

### 4.3 契约卡：host → editor op 表（全部为请求）

会话与文档：

| op | payload → 响应 |
|---|---|
| init | `{markdown, opts:{theme, zoom?, plugins?, title?, baseDir?, pathStyle, protocolVersion}} → {ok, kernelVersion, protocolVersion, ops: string[]}` |
| setMarkdown | `{md, opts:{baseDir?}, flush?} → {ok}`（**md 为磁盘原文**，改写移入内核） |
| getMarkdown | `{} → {md}`（渲染态序列化：诊断/测试口径） |
| getSaveMarkdown | `{} → {md}`（**新增**，保存口径含路径还原，迁自 Swift forSave；I2 的保存取值点） |
| markClean | `{} → {ok}`（基线=当前内容，语义不变） |
| setBaseDir / setTitle / setTheme / setZoom / getZoom / toggleSource / focus | 同 v1 语义（payload 同名参数） |
| focusAt | `{x, y} → {ok, inTable}`（右键定位，同步语义经请求-响应保持） |

命令与查找：

| op | payload → 响应 |
|---|---|
| undo / redo / requestStats | `{} → {ok}`（stats 经通知回） |
| formatCommand | `{name, payload?} → {ok}`（milkdown 位置参数形态不变） |
| tableCommand | `{name} → {ok}` |
| insertTable | `{row, col} → {ok}` |
| insertMarkdown / insertImage | `{md}` / `{src, alt, title} → {ok}` |
| openFindBar / closeFindBar / findNext / findPrev | `{} → {ok}` |
| findInfo | `{} → {active, query, count}` |
| exportStandaloneHTML | `{} → {html}` |
| getResourceRefs | `{} → {refs: string[]}`（**新增**，GC 引用收集，迁自 Swift referencedLocalImagePaths；壳比对目录后执行删除） |

诊断档（版本单列；壳可选择不暴露入口，不影响主契约）：
`hasCommands` / `debugFocusTable` / `tableInfo` / `testImagePayload`，payload 同 v1。

### 4.4 契约卡：PathPolicy 端口

- 目的：URL 组装/解析与平台路径风格的唯一变异点；内核其余部分不出现
  `file://`、盘符、分隔符字面量。
- 归属：**默认实现在内核 semantics 内**（`pathStyle: 'posix' | 'win32'` 参数化，
  init opts 传入），覆盖两平台的 `file://` 语义；壳的安全模型禁用 file:// 或需要
  自定义 resource scheme 时，经 init opts 注入覆盖实现（预留点，Q2）。
- 签名（纯函数，内核内 JS 接口，非桥 op）：
  `refToUrl(path, baseDir) → url`（分段编码、scheme 组装）；
  `urlToPath(url) → path`（解码，非法输入恒等返回）；
  `normalizePath(path)`（比对口径：分隔符/大小写，GC 与引用比对用）。
- 不变量：纯函数、不抛错、非法输入恒等返回；不触碰文件系统。
- 验证：posix/win32 双风格夹具 + 属性测试（任意串不抛错）。

### 4.5 契约卡：传输面与版本握手

- 传输面（壳必须提供，内核 bundle 求值前就位）：
  - `window.__mdHostChannel.post(json: string)` —— 内核→壳；
  - `window.__mdKernel.receive(json: string)` —— 壳→内核，内核暴露的**唯一**入口
    （v1 的 `window.mdbridge` 方法面退役）。
- 握手：壳发 `init{protocolVersion: 2}`；内核校验后响应
  `{kernelVersion, protocolVersion, ops}`。版本不匹配 → 内核回
  `unsupported_version` 且拒绝装载；壳收到后必须**显式报错停用**（禁止带着错配
  版本继续运行——评审 R2 的收口点）。壳与内核 bundle 的版本配对由壳的组装脚本
  校验（build.sh 等价物）。
- 契约测试：握手成功/版本拒绝/ops 清单与注册表全等。

### 4.6 v1 → v2 迁移（macOS，单壳同发切换）

1. 内核侧：contract/transport 落地，semantics 移植 Swift 改写器（对拍迁移：以
   Swift 现行实现跑同批夹具，输出逐字节一致后下线 Swift 版——黄金夹具来自
   selftest 既有场景与 architecture.md §2.1 覆盖边界）。
2. 壳侧：`callJS("window.mdbridge.…")` 30 处 → `send(op, payload)` + id 关联；
   `handleBridgeMessage` → receive 分发；JSArgs 转义与 Promise 跨桥规避
   （architecture.md §4）随之下线。
3. selftest：内核侧断言迁 Node 套件；壳侧保留装载/保存/粘贴 e2e。
4. 单部署单元内同发，无存量第三方依赖 → 无版本共存与废弃周期负担；
   `protocolVersion` 字段保留为将来壳/内核独立升级的钉子。

## 5. 冷热路径与资源隔离

| 路径卡 | 触发/频率 | SLA | 桥往返 | 失败语义 |
|---|---|---|---|---|
| 编辑输入（热） | 每次按键 | 下一帧可见 | **0**（通知单向，200ms 防抖） | 防抖过期回调丢弃，最新必有跟进（现行口径） |
| 文档装载（热，偶发可感） | 打开/重载 | 本地 fs + 1 次往返 | setMarkdown + resolveResources（批，1 次） | fs 探测失败按 exists:false 处理 → 静默保留原文（I1）；装载中壳 pendingOpen 暂存排空语义不变 |
| 右键/命令（热） | 交互 | 同步感 | 1 次（focusAt/命令） | not_ready 显式报错，不静默 |
| 图片导入（冷） | 粘贴/拖入 | 壳定（建议 5s） | 1 次（importImage） | 幂等 id；失败壳弹窗、内核清挂起表；不进编辑主路径 |
| GC（冷，关闭时） | 每窗关闭 | 不阻断关闭 | 1 次（getResourceRefs） | 失败仅日志；宁多保护不误删 |
| 导出 HTML（冷） | 菜单 | 秒级 | 1 次 | 资源内联失败退化为引用 |

资源隔离：导入/GC/导出不得内联进装载与输入路径（现状成立，规格固化）；
桥为单通道串行消息泵，偶发路径的慢响应不阻塞通知送达。

## 6. 数据所有权矩阵

| 数据 | 所有者（唯一写入口） | 读方 | 备注 |
|---|---|---|---|
| 编辑器文档（显示态） | core（ProseMirror doc / 源码 textarea） | getMarkdown/getSaveMarkdown | I2 单一真相源 |
| 保存口径文本 | semantics.restoreForSave（纯函数派生） | 壳保存 | 无状态派生，非第二真相 |
| 脏基线 baselineMarkdown | core state（setMarkdown/markClean 同步落定） | changed{dirty} | 壳只消费布尔，不自算 |
| 磁盘文件 | 壳 | 内核经 init/setMarkdown 单向下发 | I3 |
| `resource/<md名>/` 目录 | 壳（落盘/删除执行） | 内核经 resolveResources/getResourceRefs | 命名规则=semantics.nextResourceName |
| 主题/缩放/源码模式/标题 | core state | 壳经 op 写、经通知读 | — |
| baseDir | 壳单向下发（init/setMarkdown/setBaseDir） | semantics/core 单点消费 | 内核不落第二副本 |
| 偏好持久化（缩放/外观/抽屉） | 壳（UserDefaults 等价物） | — | 平台本地 |

## 7. 装配、复用与组合根

- 内核组合根：`main.js`（transport 装配 → contract 建立 → boot 通知），沿用现状
  单入口；壳组合根：各壳启动装配（注入 channel → 装载内核资产 → init 握手）。
  模块内部禁止按环境分支挑选实现（pathStyle 走 init 参数，不探测 UA）。
- 复用归位：文本语义一律 semantics；禁止 core 内出现路径风格分支；
  壳间禁止复制语义代码——缺什么说明 semantics 端口少收了什么。
- 无胶水：壳不出现「取 A 拼 B 再调 C」的文本加工；壳侧只有 fs 执行与 OS 编排。
- 状态：内核模块级可变状态限于 `state` 单例显式字段（现行纪律延续）；
  挂起表（importImage pending）为请求级状态，按 id 生命周期管理。

## 8. 验证计划与 CI 门禁

**内核可移植性的验收定义：Node 契约套件（jsdom + mock host channel）不依赖任何
WebView 全绿。**

| 模块 | 契约测试 | 规则/不变量 | 失败/降级 | 架构约束 |
|---|---|---|---|---|
| contract | op 表全量：成功/未知 op/坏 payload/not_ready/握手拒绝/id 回显 | 响应必回显 id；通知无响应 | unsupported_version 显式停用 | payload 无第三方类型（结构断言） |
| semantics | 改写 load/save 往返黄金夹具（空格/括号/`<>`/引用式/嵌套括号/跨行负例——§2.1 覆盖边界全量） | I1 往返属性测试：任意文本往返不丢内容；GC 引用收集宁多保护 | 解析失败静默保留 | 纯度：禁 import core/contract；零 fs/DOM 调用 |
| core | 命令注册表 ↔ 契约 ops 全等；源码模式保存口径；查找/统计口径 | I2；输入法组合中 Enter 不提交 | not_ready | 无宿主符号 |
| transport | 缺 channel boot 失败可见；错误钩子安装 | jserror 三源（onerror/console/unhandledrejection） | — | 仅本层允许宿主符号（lint） |
| PathPolicy | posix/win32 双风格夹具 | 纯函数不抛错 | 恒等返回 | 不触 fs |
| 壳（每平台冒烟） | 装载/保存/脏/图片粘贴/导出 e2e | 握手版本配对校验 | 显式报错停用 | 不解析 markdown（grep 守门） |

CI 门禁：Node 契约套件 + lint 架构规则 + macOS selftest（壳冒烟基准）。
观测：jserror 通知即内核侧观测面（现行口径延续）；桥错误码全量上日志。

## 9. 决策记录与开放问题

### 决策记录

| # | 决策 | 理由 | 否决的替代方案 |
|---|---|---|---|
| D1 | 各平台自研原生壳 + 共享 JS 内核（2026-10-21 用户定） | 原生平台质感 + Milkdown 投入保全 | Electron/Tauri 单壳跨平台（壳非原生/壳逻辑在 Rust）；Qt 原生重写编辑器（弃 Milkdown，渲染一致性无保）；全 Web UI（推翻 §2.4 原生抽屉定稿） |
| D2 | markdown 文本级语义收进内核（用户定） | 单一实现零漂移，壳最薄 | 各壳实现 + 黄金夹具（N 份实现 × N 份验证，漂移靠测试兜底） |
| D3 | 桥契约 = 统一 JSON 消息协议 v2（用户定） | 消除 JSArgs 转义、Promise 跨桥、无 schema 三缺口；契约可符合性测试 | 保留 window.mdbridge 方法面 + 仅抽象出站通道（改动小，但每壳重踩转义/schema 缺口） |
| D4 | 规格对壳技术中立（用户定） | 三引擎均支持 postMessage+执行 JS，契约无需预绑 | 在规格中预绑 WebView2/WebKitGTK 示例 |
| D5 | 内核本期不拆包/不拆仓库（建议，未永久） | 契约版本化已承担演进；单仓降低迁移摩擦 | 独立 npm 包/仓库（壳数量 ≥2 且独立发版时再评） |

### 开放问题（壳工序领取）

- **Q1** Windows/Linux 壳技术栈（WebView2+WinUI3/.NET、Tauri、GTK+WebKitGTK 直接绑定…）→ 各壳立项时定。
- **Q2** 是否需要自定义 resource scheme（某壳安全模型禁 file:// 时启用 PathPolicy 覆盖注入）→ 壳工序定。
- **Q3** Node 契约套件 DOM 环境选型（jsdom vs happy-dom）→ 实现期定，选择标准：ProseMirror 可运行 + 速度。
- **Q4** 大小写不敏感文件系统上 GC 引用比对的 normalizePath 口径 → semantics 夹具细化。

## 10. 分级与确认记录

- 定级：**P1**（模块切分 + 核心契约 + 跨平台数据语义归属变更）。
- 第一次门（边界与契约方向）：2026-10-21 评审通过，D2/D3/D4 用户确认；
  评审发现的 R1–R6 收口动作已分别落入 §2/§4/§5/§8。
- 第二次门（规格走查后最终确认）：待办——走查按 §1.2 三不变量 × §5 路径卡 ×
  「新增一个壳只动哪里」扩展场景执行；确认后本文件 status: review → current，
  实现期改动按 P2 逐项定级。
- 期间现行真相：architecture.md §4（v1 桥）保持有效直至 §4.6 迁移完成；
  迁移完成时同步改写 §4 指向本规格（一处一事）。
