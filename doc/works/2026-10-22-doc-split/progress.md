---
layer: works
module: global
status: active
updated: 2026-10-24
---

# 过程记录：§3 诊断面下沉（切片 1，2026-10-24）

## 切片选择

先切 §3 诊断面（19 行、无代码引用、与其它模块契约无关），验证「搬运 + 引用改写 +
迁移说明」流程；§2.1 图片与 §2.4 抽屉随后，README 去重与历史句出清留收口。

## 验收对照（本切片）

| brief 验收项 | 本切片结果 |
|---|---|
| 1 守恒 | 原 §3 正文 14 个非空行逐行一致（脚本比对 `git show HEAD:architecture.md` 与 `design/diagnostics.md`；差异仅标题后的边界空行）；architecture.md 264 → 248 行（-20 删除：§3 块 19 行 + §4 标题行；+4：§3 桥标题 1 + 迁移说明 3） |
| 2 链接可达 | 现行引用 2 处已改：[plan/open-questions.md](../../plan/open-questions.md) OQ-3 结论落点、[doc/README.md](../../README.md) 阅读顺序第 4 条；history/ 冻结件 3 处旧编号（pitfalls §4、kernel spec §4）不回改，由 architecture 首部迁移说明兜底 |
| 3 frontmatter | diagnostics.md：`layer: design`、`module: global`、`status: current`、`updated: 2026-10-24` |
| 4 去重 | 未做（README 框图/桥 op 列表属 §4 保留区，留收口切片） |
| 5 历史句出清 | 未做（§2.4「曾用 shouldExpand…已废弃」留 §2.4 切片） |
| 6 无新增事实 | 是：只搬正文 + 标题 + 迁移说明，未改语义 |

## 结构变化

- 新增 `design/diagnostics.md`（全局诊断面：三入口语法/前缀/退出码、环境钩子、
  web 侧诊断留痕、WebLocator 边界），正文自 architecture.md 原 §3 原样搬入。
- architecture.md：删除 §3；原 §4 桥协议顺延为 §3；首部补迁移说明
  （原 §3 去 diagnostics.md、桥协议 §4→§3、冻结件旧编号不回改）。
- 当前 architecture.md 章节：§1 安全取舍、§2 行为取舍（§2.1/2.1a/2.2/2.3/2.4/2.5）、
  §3 桥协议。

## 后续

1. §2.1 + §2.1a 图片 → `design/image/spec.md`（63 行）。
2. §2.4 抽屉与目录模式 → `design/drawer/spec.md`（56 行），同切片改
   [2026-10-20-file-drawer/result.md](../2026-10-20-file-drawer/result.md) 与
   [2026-10-22-drawer-anchor-and-resize/result.md](../2026-10-22-drawer-anchor-and-resize/result.md)
   的 §2.4 引用。
3. 收口切片：README 框图/桥 op 去重、§2.4 历史句迁出、写 result.md（含逐段守恒表与
   冻结件旧编号对照表）。
