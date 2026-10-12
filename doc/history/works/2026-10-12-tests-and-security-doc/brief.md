---
layer: history
module: global
status: frozen
updated: 2026-10-12
---

# 工序：自检可靠性与安全取舍显式化

两块内容：让 selftest 成为可信门禁（失败必报），把散落在注释里的安全/行为
取舍蒸馏为现行设计文档。后者将诞生 design/ 的第一批全局文档（反占位：
内容随本序收口落地，不提前建目录）。

## 问题清单

### Q1 selftest 等待基建缺陷（审计 #39）

- `waitForCollect`（Selftest.swift:446-454）超时后静默掉出循环，`name` 参数
  被 `_ = name` 丢弃——轮询未完成不记失败，全靠后续断言兜底。
- `sleepOrUntil(timeout:) { false }` 纯睡反模式（Selftest.swift:106, 210, 303）。
- 动作：waitForCollect 超时调用 `fail(name)`；三处纯睡改为对具体结果的
  waitFor 轮询（如 mermaid svg 数量、find-count 文本）。

### Q2 断言与文档三处硬编码漂移（审计 #39 后半，R7）

- `EditorCommands.all.count >= 30`（Selftest.swift:270）、README"30 项断言"、
  860px（typora.css / Selftest.swift:296 字符串断言 / README）。
- 动作：注册表完整性断言改为"遍历 all 全部响应 + 与 EditorAction case 数一致"，
  不再锚定具体数字；860 断言读 CSS 变量比对；README 不再复述断言计数
  （改为指向 selftest 运行方式）。

### Q3 `--multiwindow-test` 定时器编排（审计 #40）

- 位置：main.swift:27-79，0.8s→5.6s 定时器链 + `print` 人工判读。
- 动作（最小改）：轮询断言替代固定延时（等 `inTableCached` 翻转而非盲等），
  输出加统一前缀与 PASS/FAIL 判定；结构性剥离（独立测试 target）按
  [OQ-3](../../../plan/open-questions.md) 结论执行。

### Q4 测试/诊断代码随生产发布（审计 #16）

- 现状：Selftest.swift（490 行）、Screenshot.swift、`--multiwindow-test`、
  `window.__mdStage`（main.js:258, 307, 358）全部随 release 构建发布。
- 动作：按 OQ-3 结论——保留为官方诊断面则文档化 + 收敛三入口风格
  （flag 语法、输出格式、退出码表）；剥离则条件编译/独立 target。
  WebLocator 的归类错位已在 W3 解决。

### Q5 安全与行为取舍写入现行文档（审计 #35-38，R5）

把以下取舍蒸馏进 `design/architecture.md`（新建，module: global），
每条写明：决策、理由、失效条件：

- WebView 全盘读授权（DocumentWindowController.swift:138、Selftest.swift:96）
  与 mermaid `securityLevel: 'loose'`（main.js:133）——打开不可信文档的暴露面；
  评估收窄到"文档目录 + 图片目录"并在文档记录结论（无论收窄与否）。
- ImagePathRewriter 正则改写的覆盖边界（Util.swift:34-36：引用式图片、
  嵌套括号、转义不覆盖；失败静默）。
- TextFile.write 无条件补尾换行（Util.swift:22-26）——工具修改用户文件尾的隐式行为。
- 保存恒定 UTF-8（与 [OQ-2](../../../plan/open-questions.md) 结论联动）。

## 验收标准

- [x] waitForCollect 超时必 FAIL；三处纯睡替换为条件轮询
- [x] 断言不再锚定具体计数；README 与断言解耦
- [x] multiwindow-test 输出 PASS/FAIL 自判定
- [x] design/architecture.md 存在且含上述取舍条目（结论落点表登记）
- [x] selftest 全部通过；`./build.sh` 通过

## 依赖与顺序

- 无硬依赖；design/ 首批文档在本序收口时诞生。
- 建议排在批次末尾收尾：此时各序行为变化已定，取舍文档一次写全。
