---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 评审：可移植内核 v2 与桥协议切换（P1）

> 工序：[2026-11-04-kernel-v2](brief.md)；规格增量：[spec-delta.md](spec-delta.md)；结果：[result.md](result.md)。

- **定级**：P1（架构级）——改桥协议契约、模块切分与跨端边界，且删除既有实现（Swift `ImagePathRewriter`）。
- **评审时点**：第一次门（2026-11-04，落地前）定三决策与两次门；第二次门定「产品 op 化 + 诊断求值限定」（G1）与「四层切分 + 禁边脚本」（G2）。
- **结论**：**通过**。自动化断言全绿（Node 78 项、selftest 115 PASS），图片粘贴链路经真实壳 e2e 取证；两项未自动化（打印、另存为 baseDir 时序）转入 `CMP-app-shell` 人工清单。

## 1. 四档裁决

### Decision now（已定；冻结后改动需新工序）

| 决策 | 选择 | 备选与否决理由 | 落点 |
|---|---|---|---|
| 发布形态 | 一次切换：内核先绿，再切壳，不留 v1/v2 并行开关 | 长期双通道等于两套契约同时活，契约测试永远分叉 | architecture §3 |
| 协议 | 单通道 JSON 帧 v2（`{v,op,id,payload}` + 回显 id + 五错误码），握手拒绝即禁用 | 保留 v1 方法面需双份 selftest 与双份文档 | architecture §3 |
| 语义归属 | 路径/markdown 语义全入 `semantics/`（纯函数），存在性由壳作答 | 留 Swift 一份则 Windows 壳必须重写一遍并长期对拍 | architecture §2.1、§4 |
| 模块切分 | 四层 transport/contract/semantics/core，依赖单向，禁边脚本进构建 | 单文件内核无法阻止宿主符号四处扩散 | architecture §4 |
| 契约清单 | 39 op / 7 通知 / 2 内核请求，单一清单 `contract/ops.js` | op 名散落在壳与页两侧必然漂移 | architecture §3 |
| 图片导入方向 | 内核发 `importImage` 请求（请求-应答），壳不再反向回灌 `onImageImported` | 回灌需内核暂存选区状态，跨两次异步易错位 | architecture §3 |
| 资源问答 | `resolveResources` 必带 `baseDir`，壳不猜当前文档目录 | 让壳猜目录在未保存/另存场景误判引用缺失（真实壳验证时抓到） | architecture §3 |
| 测试宿主 | jsdom + `FakeShell`（Q3 决策） | 无 DOM 的契约测试测不到 Milkdown 装配 | spec-delta §6 |
| v1 残余 | `window.mdbridge` 降级为测试门面（`__MDP_TEST__`），产品 bundle 不暴露 | 直接删会让 87 处自检脚本一起改，风险大于收益 | review §2 说明 |

### Blocker（零）

未发现数据丢失、不可逆迁移或默认行为错误路径。壳侧 markdown 解析已彻底移除，`grep ImagePathRewriter Sources/` 无命中；产品路径无「壳读正文再改写」的入口。

### Verified sound（查过且确认）

| 区域 | 怎么查 | 结果 |
|---|---|---|
| 语义等价 | `web/test/fixtures/semantics-golden.json`（由 Swift 旧实现生成的 15 用例） | 三函数 45 项逐字节一致 |
| 契约 | `web/test/contract.test.js`（18 项） | 信封校验、未知 op、坏 payload、握手拒绝、id 回显、通知无 id 全绿 |
| 层禁边 | `node check-kernel.mjs`（进构建） | 25 文件；宿主符号只在 transport；第三方只在 core |
| 端到端装载/保存 | selftest「装载改写(内核改写+壳作答)」「保存口径(内核还原相对路径)」 | 真实 WKWebView 内改写与还原均正确 |
| 资源 GC | selftest「资源清理-…(集合=4)」 | 引用集合来自内核，壳只做差集；围栏内引用不计 |
| 图片粘贴 | `MDP_PASTE_IMAGE` e2e：paste → v2 请求 → 落盘 → 插入 | `resource/doc/img_001.png` 落盘，节点 `src=file:///…/img_001.png` |
| 只读代码文档 | selftest 代码视图组 | 代码文档不发 `changed`，行号/语言 op 生效 |

### Deliberately not done（明示不做，非遗漏）

- **打印与另存为时序**无自动化：打印弹系统对话框无法在无人值守下断言；另存为后 `setBaseDir` 依赖真实保存动作。两项列入 `CMP-app-shell` 人工清单。
- **自检脚本仍在用测试门面**：87 处 `evaluate` 调 `window.mdbridge.*`，属测试专用路面，迁移到 v2 请求为后续清理项。
- **Windows 壳代码**：按用户决策只提供参照物（契约文档、壳侧参照序、可运行 Node 套件、最小装配示例），不在本工序实现。

## 2. 人参与记录

- 2026-11-04 第一次：三项决策（一次发布切换 / 含参照物不含 Windows 代码 / minimap 暂停排队）。
- 2026-11-04 第二次：G1 产品 op 化 + 诊断求值限定；G2 方案 A 四层 + 禁边脚本。
