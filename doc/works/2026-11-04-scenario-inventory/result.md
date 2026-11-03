---
layer: works
module: global
status: active
updated: 2026-11-04
---

# 工序 result：已实现场景与组件清点

## 交付

| 类别 | 数量 | 位置 |
|---|---:|---|
| 组件规格 | 7 | `doc/design/components/CMP-{app-shell,document-io,editor,drawer,image,export,diagnostics}/spec.md` |
| 需求卡 | 8 | `doc/requirements/REQ-0001…0008`，全部 `accepted` |
| 场景卡 | 15 | `doc/design/scenarios/`，13 `designed` + 2 `draft` |
| 决策记录 | 1 | [2026-11-04-component-scenario-inventory.md](../../history/decisions/2026-11-04-component-scenario-inventory.md) |
| 导航/调度 | — | `doc/README.md` 树与阅读顺序、`roadmap.md` 工序行、`OQ-7` |

`CMP-diagnostics` 由 `components/diagnostics/` 迁为 `components/CMP-diagnostics/`；README、architecture、open-questions、doc-split 与迁移决策中的链接同步更新。

## 验证

- 15 个场景、7 个组件、8 张需求卡的 frontmatter 字段齐全；场景 `R1/R2/R3/N1` 角色各一条，共 60 个测试 ID，无重复。
- 所有组件入口的 `CMP-xxx/<path>` 文件存在；所有相对链接可达（`README.md` 按约定不带 frontmatter，frontmatter 检查跳过）。
- 未执行 3+1 复跑；没有场景标 `verified`，8 张 REQ 均未转 `delivered`。

## 状态与验证债

- 本次工序的“文档清点”完成；roadmap 标“收口中”，因为 3+1 复核与人工实证未做。
- promotion candidate：`SCN-0001`（抽屉）、`SCN-0011`（图片显示/编辑）、`SCN-0012`（图片导入/清理）已有完整自动入口，复跑记录后可升 `verified`。
- draft：`SCN-0004`（外部变更，全人工）、`SCN-0009`（数学/Mermaid，无稳定断言）。
- 其余 10 个 `designed` 场景的缺口见各卡 §5/§6；偿还顺序登记在 [OQ-7](../../plan/open-questions.md#oq-7-场景验证债的偿还顺序)。

## 结论落点

| 结论 | 落点 |
|---|---|
| 7 组件切分与拒绝 5 组件/12+ REQ/8 核心场景 | 决策记录 |
| 需求验证后转 `delivered` | 决策记录、README、各 REQ §8 |
| 15 个场景的入口/运行序/3+1 | 各 `scenario.md` |
| 组件契约/数据所有权/预算 | 各 `spec.md` |
| 验证债与偿还顺序 | 各场景 §6、OQ-7、本 result |

## 下一步

1. 按 OQ-7(a) 复跑抽屉 + 图片两组，登记复跑证据；全绿后升 `SCN-0001/0011/0012`。
2. 按 OQ-7(b) 补文件编码/尾换行/外部变更的自动用例，打通 `REQ-0004`。
3. 场景全部 verified 后逐张转 REQ；未转前不更新 roadmap 为“已完成”。
