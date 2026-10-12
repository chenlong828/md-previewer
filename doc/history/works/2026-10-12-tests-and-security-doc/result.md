---
layer: history
module: global
status: frozen
updated: 2026-10-14
---

# 工序收口：自检可靠性与安全取舍显式化

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| waitForCollect 超时必 FAIL；三处纯睡替换为条件轮询 | ✅ | 复核确认 `waitForCollect` 已有 `if !finished { fail(name) }`（先序已修复，本序复核锁定）；三处纯睡（mermaid 渲染等待、插入表格等待、查找计数等待）全部替换为 `waitForValue` 条件轮询（每拍发起 evaluate 并排空回调）；`sleepOrUntil` 死代码删除 |
| 断言不再锚定具体计数；README 与断言解耦 | ✅ | `>= 30` 已改为结构断言：`EditorAction` 改 `CaseIterable`，规格 action 集与 case 集全等（不重不漏）+ 全量 selector 可响应，通过行显示实际条数不锚定数字；860 断言读 CSS 变量比对（W3 完成）；README 不再复述断言计数，改为指向运行方式 |
| multiwindow-test 输出 PASS/FAIL 自判定 | ✅ | 重写为轮询编排：轮询等待 `inTableCached` 翻转（等 selinfo 信号而非盲等），统一 `[MULTIWINDOW] PASS/FAIL 检查项` 前缀，末尾 info 行，退出码 0=全过 / 1=有失败；实测两文件场景 8 项全 PASS、EXIT=0 |
| design/architecture.md 存在且含上述取舍条目 | ✅ | 新建 `doc/design/architecture.md`（design/ 首批文档）：§1 安全取舍（全盘读授权含收窄评估结论"暂不收窄"+失效条件、mermaid loose、桥接口面）、§2 行为取舍（rewriter 边界、尾换行、UTF-8 恒定）、§3 诊断面三入口表（语法/输出前缀/退出码，OQ-3=a 文档化收敛）、§4 桥协议；doc/README.md 导航已指向 |
| selftest 全部通过；`./build.sh` 通过 | ✅ | 63 PASS（较上序 +2：mermaid svg 就绪、查找计数就绪为新增条件轮询项）；`./build.sh` 完整跑通 |

## 各项治理落点

| 项 | 落点 |
|---|---|
| Q1 | `Selftest.waitForValue` 新增；三处纯睡替换；`sleepOrUntil` 删除 |
| Q2 | `EditorAction: CaseIterable` + action 集全等断言；README 计数解耦（W3 完成宽度断言读 CSS 变量，本序复核） |
| Q3 | `main.swift` multiwindow-test 段重写：信号轮询 + PASS/FAIL + 退出码 |
| Q4 | `design/architecture.md` §3 诊断面表：三入口统一语法/前缀/退出码（OQ-3=a 保留为官方诊断面并文档化；`window.__mdStage` 已在重构中消除） |
| Q5 | `design/architecture.md` §1/§2：全盘读授权（收窄评估：**暂不收窄**，理由=图片与文档链接可指向任意位置、静态定界不可行、暴露面为只读+需主动构造恶意文档）、mermaid loose、rewriter 四类不覆盖写法+静默退化安全性、尾换行补齐、UTF-8 恒定——每条含决策/理由/失效条件 |

## 结论落点表

| 活结论 | 落点 |
|---|---|
| 安全与行为取舍（决策/理由/失效条件） | [design/architecture.md](../../../design/architecture.md) |
| 诊断面三入口统一风格（OQ-3=a） | [design/architecture.md](../../../design/architecture.md) §3 |
| 全盘读授权收窄评估结论（暂不收窄） | [design/architecture.md](../../../design/architecture.md) §1.1 |
| selftest 可信门禁（超时必 FAIL、条件轮询） | `Sources/MDPreview/Selftest.swift` |

## 遗留

- 无。
