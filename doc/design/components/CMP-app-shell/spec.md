---
layer: design
module: shell
component: CMP-app-shell
status: active
updated: 2026-11-04
---

# CMP-app-shell 组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L2 整合；技术边界 + 应用编排
- 业务价值：为使用者提供「一个进程、一个 Dock 图标、多个文档窗口」的 macOS 应用外壳；没有它，文件无法被打开到正确的窗口，菜单/快捷键/最近文件也没有统一入口。
- 负责：应用启动与参数路由、窗口创建/替换/关闭、菜单与快捷键、最近文件、缩放与外观的应用、退出前的脏文档确认；**壳侧 v2 协议客户端 `KernelClient`**（帧编解码、id→completion 表、超时、内核请求应答）；「视图 → 高亮语言」菜单只做入口与勾选同步，语言判定归 `CMP-code-view`；「视图 → 显示行号」菜单只做入口/勾选与全局广播，偏好判定归 `CMP-code-view`；「视图 → 显示文档缩略图」菜单只做入口/勾选、偏好存储与全局广播，绘制/交互归 `CMP-minimap`。
- 不负责：文件内容读写（`CMP-document-io`）、编辑器内部行为（`CMP-editor`）、抽屉树（`CMP-drawer`）、导出实现（`CMP-export`）、缩略图绘制/内容投影/滚动定位（`CMP-minimap`）、帧格式与 op 校验（`CMP-kernel-contract`）、编辑与导出能力实现（`CMP-kernel-editor` / `CMP-kernel-output` 等六组件）、注入脚本（v2 起产品路径为零）。
- 内部逻辑：`AppDelegate` 维护文档窗口集合与打开路由；`DocumentWindowController` 承载单文档窗口并把菜单动作翻成 op（`kernel.send`）；`EditorCommands` 是菜单/右键共用的命令表；`KernelClient` 是协议客户端（`installScript` 注入 channel → `attach` → `send`/`receive`/`respond`，`info` 存握手结果）。
- 拥有的数据：窗口 frame、最近文件列表、缩放比例、外观锁定；不拥有文档正文。
- 变化轴：打开方式的增减（CLI/拖放/Finder/⌘O/最近）、窗口模型、菜单命令表。
- 公开契约（含能力 ID）：
  - `CMP-app-shell#open-document`：按文件/目录参数打开；外部打开默认新窗口，⌘O/最近文件在当前窗口替换。
  - `CMP-app-shell#new-window`：⌘N 创建空白文档窗口。
  - `CMP-app-shell#multi-window`：单进程、单 Dock、每文档独立窗口。
  - `CMP-app-shell#recent-files`：最近文件列表与清除。
  - `CMP-app-shell#menu-commands`：`EditorCommands` 为菜单与右键的唯一命令真源；`availableInCode` 标记只读代码文档下仍可用的命令（拷贝/全选/查找）。
  - `CMP-app-shell#highlight-language-menu`：视图 → 高亮语言子菜单；仅代码文档可用，勾选「自动/纯文本/语言 id」由窗口的当前选择同步。
  - `CMP-app-shell#code-line-numbers-menu`：视图 →「显示行号」；仅代码文档可用，勾选反映全局偏好；点击写入偏好并广播所有代码窗口，Markdown 窗口不受影响。
  - `CMP-app-shell#minimap-menu`：视图 →「显示文档缩略图」；Markdown 渲染面/代码面可用，源码模式置灰；勾选反映 `UserDefaults["minimapVisible"]`（默认 true）；点击写入偏好并广播所有窗口；不写文件、不产生 `changed`。
  - `CMP-app-shell#zoom`：⌘+ / ⌘− / ⌘0，比例持久化。
  - `CMP-app-shell#appearance`：跟随系统或锁定浅/深色。
  - `CMP-app-shell#quit`：有脏文档时先确认，取消则不退出。
  - `CMP-app-shell#protocol-client`：`KernelClient.send(op, payload, timeout, completion)` 发请求并按 `id` 回填；`receive(body)` 判别 v2 帧（`v==2` 才认）并分流为响应/通知/内核请求；内核请求由壳应答 `resolveResources`/`importImage`；握手响应记入 `info`。产品路径不执行注入脚本，诊断取数限 `evaluateForDiagnostics`。
- 入口：
  - `CMP-app-shell/Sources/MDPreview/main.swift#args`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applicationDidFinishLaunching`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#openInNewWindow`
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#openDocument`
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleCodeLineNumbersAction`
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleMinimapAction`（planned，REQ-0011）
  - `CMP-app-shell/Sources/MDPreview/EditorCommands.swift#EditorCommands`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#buildMenus`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applyCodeLineNumbersToAllDocuments`
  - `CMP-app-shell/Sources/MDPreview/AppDelegate.swift#applyMinimapVisibilityToAllDocuments`（planned，REQ-0011）
  - `CMP-app-shell/Sources/MDPreview/KernelClient.swift#KernelClient`（`installScript`/`send`/`receive`/`respond`/`info`）
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#resolveResources`（内核 `resolveResources` 请求的应答方）
  - `CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#performImport`（内核 `importImage` 请求的应答方）
  - `CMP-app-shell/Sources/MDPreview/EditorWebView.swift#makeConfiguration`（注入 channel；`testFacade` 才装 `__MDP_TEST__` 门面）
- 依赖：`CMP-document-io`（打开/保存）、`CMP-editor`（内容面）、`CMP-drawer`（目录导航）、`CMP-export`（导出）、`CMP-diagnostics`（测试入口）、`CMP-kernel-contract`（帧格式/op 清单/错误码）、`CMP-kernel-transport`（channel 契约）、`CMP-kernel-semantics`（保存口径经 `getSaveMarkdown` 取用）；`CMP-minimap` 仅通过桥的 `setMinimapVisible` 入口联动，不直接 import。
- 冷热属性：冷路径；不进入编辑输入热路径。缩略图开关是低频菜单动作，广播只调用桥，不重绘正文。
- 尺寸预算：目标 ≤120k token；当前约 2.3k 行（main 362 + AppDelegate 523 + KernelClient 171 + 窗口编排 1527 + EditorCommands 104），缩略图菜单/偏好另计，实测待脚本。
- 单独运行：`./.build/debug/MDPreview --multiwindow-test --fileA=a.md --fileB=b.md`；菜单/缩放用 `--selftest`。
- 验证计划：多窗口数量/标题、菜单命令注册表完整、缩放应用、深色主题切换、退出脏确认（人工）；v2 握手/op 往返/内核请求应答与装载保存端到端由 selftest 断言。
- 删除测试：删掉后没有窗口与打开路由，复杂度不会消失只会散落到每个文件 → 真边界。

## 公开契约细节

- `open-document` 的 `reanchor` 语义：外部打开（CLI/拖放/Finder/最近）重锚到文件所在目录；抽屉内双击不重锚。
- `multi-window` 的不变量：同一文档不在两个窗口同时打开；目录模式只占一个窗口；⌘O 与最近文件替换当前窗口。
- `quit` 的错误模式：用户取消则 `applicationShouldTerminate` 返回 `.terminateCancel`，不丢未保存内容。
- `menu-commands` 的不变量：`EditorCommands.all` 的动作集合与菜单/右键实际动作一致；新增命令只改一处；`availableInCode` 默认 false，代码文档只放行拷贝/全选/查找。
- `highlight-language-menu` 的不变量：菜单项 representedObject = auto/plaintext/语言 id；勾选与窗口 `highlightMenuSelection` 同步；非代码文档整组置灰；点击只重绘不写文件。
- `code-line-numbers-menu` 的不变量：菜单项 state 由 `DocumentWindowController.codeLineNumbersVisible` 单向派生；非代码文档置灰；切换写入 `UserDefaults["codeLineNumbersVisible"]` 并广播所有代码窗口；不写文件、不产生 `changed`；Markdown 窗口无效果。
- `minimap-menu` 的不变量：菜单项 state 由 `UserDefaults["minimapVisible"]` 单向派生；**key 不存在时按 true**（用 `object(forKey:) == nil` 判空或 `register(defaults:)`，不能直接用 `bool(forKey:)` 得到 false）；Markdown 渲染面/代码面可用，源码模式置灰；切换只写偏好并广播所有窗口，不重建编辑器、不写文件、不产生 `changed`；源码模式返回渲染面后按偏好恢复；窗口初始化通过 `init` opts 传入偏好，代码文档切换沿用同一值。
- `open-document` 的打开面板类型 = `FileSupport.openableUTTypes`（Markdown + 代码），与抽屉过滤/链接拦截同源。
- `protocol-client` 的不变量：`receive` 只消费 `v==2` 的帧，非 v2 一律返回 false 交旧处理器（迁移期兼容）；响应必按 id 结算并取消超时；未知 id 只记日志不崩；壳体不解析 markdown、不拼 JS 命令字符串（命令一律经 `formatCommand`/`tableCommand` 的 payload 传递）。
- `protocol-client` 的错误模式：超时（默认 10s，GC 路径显式 2s）以 `KernelError(code:"timeout")` 回填；`unsupported_version`/`not_ready` 由调用方记录到 `os_log`，不做静默重试。
- 诊断求值限定（G1）：产品路径只剩 `KernelClient` 的帧投递与 `evaluateForDiagnostics`（仅 `Selftest.swift`/`Screenshot.swift`/`main.swift` 的调试分支调用）；Windows 壳不实现后者。
- 测试门面：`window.mdbridge` 只在 `__MDP_TEST__` 下由页面入口安装，产品 bundle 不暴露；门面只服务既有自检脚本，不是契约。

## 验证计划

| 契约 | 测试 |
|---|---|
| `#multi-window` | `--multiwindow-test`：窗口数为 2、标题不重复 |
| `#menu-commands` | `--selftest`：「命令注册表完整」「桥命令名双端一致」 |
| `#zoom` | `--selftest`：「缩放应用」 |
| `#appearance` | `--selftest`：「深色主题切换」 |
| `#highlight-language-menu` | `--selftest`：「代码视图 语言表覆盖扩展名」「代码视图 双端语言清单一致」；勾选/置灰人工 |
| `#code-line-numbers-menu` | `--selftest`：「代码视图 行号开关与复制文本」；勾选/跨窗口广播人工（R8，2026-11-04 用户确认） |
| `#minimap-menu` | `--selftest`：「缩略图 代码面与开关」：菜单动作切换偏好、广播所有窗口、源码模式置灰；勾选/跨窗口继承人工（R8） |
| `#open-document` / `#quit` | 人工：CLI/拖放/⌘O/最近 + 脏文档退出 |
| `#protocol-client` | `--selftest`：「v2 握手响应」「v2 握手(protocolVersion=2, ops=39)」「v2 op 往返(getState)」「装载改写(内核改写+壳作答)」「保存口径(内核还原相对路径)」；协议层本身由 `web/test/contract.test.js` 18 项覆盖（不依赖 WebView） |

## 数据所有权与预算

| 数据 | 写入口 | 读方 | 一致性 |
|---|---|---|---|
| 最近文件 | `AppDelegate.addRecentFile` | 菜单 | 单进程 |
| 窗口 frame / 缩放 / 外观 | 本组件 | 本组件 | UserDefaults |
| 文档正文 | `CMP-document-io` | 本组件只传引用 | 不复制 |
| 代码行号显示偏好 | `CMP-code-view`（控制器静态入口） | 本组件菜单勾选 | 单一来源，本组件不另存 |
| 缩略图显示偏好 | 本组件（`UserDefaults["minimapVisible"]`，默认 true） | 本组件菜单勾选、各窗口 `setMinimapVisible` | 单一来源；`CMP-minimap` 只读投影 |
| 待决请求（id → completion + 超时句柄） | 本组件 `KernelClient.send` | 响应到达时结算 | 单实例；超时与响应二者先到者结算 |
| 握手结果（kernelVersion/protocolVersion/ops） | 本组件 `recordHandshake` | 自检断言、错误上报 | 单次握手，不重试 |

## 删除测试

删掉本组件，窗口/菜单/最近文件/退出确认没有替代归属，复杂度集中而非消失 → 保留为真边界。
