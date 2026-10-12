---
layer: plan
module: global
status: current
updated: 2026-10-14
---

# 技术债修复路线图

来源：2026-10-12 全仓库只读技术债审计（Swift 壳 + Milkdown 前端，共 40 项发现）。
发现不在此处复制——每项发现只登记在唯一承接它的工序 brief 里（一处一事）；
本文件只维护批次、优先级、依赖与工程量。

## 工序总览（全部已完成，2026-10-14 归档至 history/works/）

| 工序 | 主题 | 优先级 | 工程量 | 依赖 | 状态 |
|---|---|---|---|---|
| [2026-10-12-fix-latent-defects](../history/works/2026-10-12-fix-latent-defects/brief.md) | 3 个疑似缺陷（正确性） | P0 | M | 无 | ✅ 已完成 |
| [2026-10-12-remove-dead-code](../history/works/2026-10-12-remove-dead-code/brief.md) | 死代码与不可达分支清理 | P1 | S | 建议在 W1 后（同文件区域） | ✅ 已完成 |
| [2026-10-12-consolidate-duplication](../history/works/2026-10-12-consolidate-duplication/brief.md) | 重复知识与重复实现收敛 | P1 | M | W2（先删死再合并，避免合并死物） | ✅ 已完成 |
| [2026-10-12-structure-governance](../history/works/2026-10-12-structure-governance/brief.md) | main.js 拆分 + 菜单构建表驱动 + lint | P2 | L | W1–W3（内容变更稳定后再动结构） | ✅ 已完成 |
| [2026-10-12-timing-contracts](../history/works/2026-10-12-timing-contracts/brief.md) | 时序耦合与魔法延时治理 | P2 | L | W3（同在 DocumentWindowController 密集改动） | ✅ 已完成 |
| [2026-10-12-deps-and-build](../history/works/2026-10-12-deps-and-build/brief.md) | 依赖、构建与许可卫生 | P3 | S–M | 无硬依赖 | ✅ 已完成 |
| [2026-10-12-tests-and-security-doc](../history/works/2026-10-12-tests-and-security-doc/brief.md) | 自检可靠性 + 安全取舍显式化 | P3 | M | 无硬依赖，建议收尾 | ✅ 已完成 |

## 批次与依赖链

```
批次一（P0 正确性）      W1
批次二（P1 减法收敛）    W2 ──→ W3
批次三（P2 结构时序）    W4、W5（W3 后可并行；W4 动 web/src/main.js，W5 动 Sources/，文件不相交）
批次四（P3 卫生收尾）    W6、W7（随时可插入；建议最后统一收口）
```

执行纪律：

- 每个工序收口时写 `result.md`，结论落点表登记每条活结论去向；归档前置条件是收口。
- W1 修复前先在 selftest 写出可复现断言（红→绿），防止"修了但没守住"。
- 三个疑似缺陷的定性见 [risks.md](risks.md)；跨工序决策见 [open-questions.md](open-questions.md)。

## 执行记录

- 2026-10-14：批次一至批次四（W1–W7）全部收口并归档至 [history/works/](../history/works/)；
  各工序验收实证见各目录 result.md；跨工序决策结论见 [open-questions.md](open-questions.md)，
  风险消除实证见 [risks.md](risks.md)。
