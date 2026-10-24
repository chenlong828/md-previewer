---
layer: plan
module: global
status: current
updated: 2026-10-24
---

# 技术债修复路线图

来源：2026-10-12 全仓库只读技术债审计（Swift 壳 + Milkdown 前端，共 40 项发现）。
发现不在此处复制——每项发现只登记在唯一承接它的工序 brief 里（一处一事）；
本文件只维护批次、优先级、依赖与工程量。2026-10-20 起功能开发工序也在本表登记
（优先级列标「功能」，技术债 P0–P3 编号仅用于审计批次）。

## 工序总览

技术债审计批次（W1–W7）全部完成，2026-10-14 收口归档至 history/works/；
2026-10-20 起为功能工序。

| 工序 | 主题 | 优先级 | 工程量 | 依赖 | 状态 |
|---|---|---|---|---|---|
| [2026-10-12-fix-latent-defects](../history/works/2026-10-12-fix-latent-defects/brief.md) | 3 个疑似缺陷（正确性） | P0 | M | 无 | ✅ 已完成 |
| [2026-10-12-remove-dead-code](../history/works/2026-10-12-remove-dead-code/brief.md) | 死代码与不可达分支清理 | P1 | S | 建议在 W1 后（同文件区域） | ✅ 已完成 |
| [2026-10-12-consolidate-duplication](../history/works/2026-10-12-consolidate-duplication/brief.md) | 重复知识与重复实现收敛 | P1 | M | W2（先删死再合并，避免合并死物） | ✅ 已完成 |
| [2026-10-12-structure-governance](../history/works/2026-10-12-structure-governance/brief.md) | main.js 拆分 + 菜单构建表驱动 + lint | P2 | L | W1–W3（内容变更稳定后再动结构） | ✅ 已完成 |
| [2026-10-12-timing-contracts](../history/works/2026-10-12-timing-contracts/brief.md) | 时序耦合与魔法延时治理 | P2 | L | W3（同在 DocumentWindowController 密集改动） | ✅ 已完成 |
| [2026-10-12-deps-and-build](../history/works/2026-10-12-deps-and-build/brief.md) | 依赖、构建与许可卫生 | P3 | S–M | 无硬依赖 | ✅ 已完成 |
| [2026-10-12-tests-and-security-doc](../history/works/2026-10-12-tests-and-security-doc/brief.md) | 自检可靠性 + 安全取舍显式化 | P3 | M | 无硬依赖，建议收尾 | ✅ 已完成 |
| [2026-10-20-image-support](../history/works/2026-10-20-image-support/brief.md) | 图片支持（相对路径显示/源码编辑块/粘贴拖放导入落盘） | 功能 | M | 无 | ✅ 已完成（已归档） |
| [2026-10-20-image-cleanup](../history/works/2026-10-20-image-cleanup/brief.md) | 图片资源生命周期（撤销不残留、关闭统一 GC 清理） | 功能 | S | 图片支持 | ✅ 已完成（已归档） |
| [2026-10-20-file-drawer](../works/2026-10-20-file-drawer/brief.md) | 文件抽屉与目录模式（lazy 按层装载、锚定下拉框、同窗覆盖打开） | 功能 | L | 无 | 🔄 收口中（自动化全绿，待人工实证） |
| [2026-10-21-portable-kernel](../history/works/2026-10-21-portable-kernel/brief.md) | 可移植内核与壳契约（桥协议 v2、路径语义入内核；评审有条件通过，决策 D1–D5） | 功能 | M–L | 无 | ⏸ 暂缓（评审+规格已归档，零实施；恢复时从存档重启） |
| [2026-10-22-doc-split](../works/2026-10-22-doc-split/brief.md) | design 文档按读者下沉（architecture.md 拆出 image/drawer/诊断面） | 文档 | S | 无 | 🔄 执行中（§3 诊断面已下沉；§2.1/§2.4 与收口待做） |
| [2026-10-24-list-indent-four-space](../history/works/2026-10-24-list-indent-four-space/brief.md) | 列表 Tab 嵌套的 markdown 缩进（2 空格 → 标准 4 空格，首行标记不补齐） | 缺陷 | S | 无 | ✅ 已完成（已归档） |

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

