---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 2026-11-04 文档树四态 → 五态迁移

> 2026-11-04 后续：已实现场景/组件清点已完成，见 [2026-11-04-component-scenario-inventory.md](2026-11-04-component-scenario-inventory.md)。本记录中“不预先创建场景”只约束迁移当时；后续按需求落场景卡不受此限。

## 背景

`.agents/skills` 已升级为五态版（`req-scenario-spec` 新增，`arch/design/dev/doc` 重写）。本仓库 `doc/` 仍是四态：`design/plan/works/history`，`design/` 平铺 `architecture.md` 与 `diagnostics.md`，没有 `requirements/`、`components/`、`scenarios/`；`works/` 里有已收口未归档的工序。技能与文档树继续分叉，会命中新版 `doc-layout-spec` 的多条违规信号。

## 决策

1. **文档根改五态**：`requirements/`、`plan/`、`design/`、`works/`、`history/`；位置即状态。
2. **design/ 收敛为三类**：`architecture.md`、`components/<id>/spec.md`、`scenarios/<domain>/<flow>/<scenario>/scenario.md`。`diagnostics.md` 迁入 `components/CMP-diagnostics/spec.md`，补组件卡、能力 ID 与单独运行命令；不并入 `architecture.md`，保留 2026-10-24 的读者下沉。
3. **`2026-11-02-app-icon` 归档**：closed 工序整目录移入 `history/works/`，frontmatter 改 `layer: history` / `status: frozen`，目录名不变；roadmap 链接与状态同步。
4. **`requirements/` 补录在飞需求；`design/scenarios/` 不预建**：为 `2026-10-20-file-drawer` 补 `REQ-0001`（accepted），作为 why / 非目标 / 验收的权威，`works/` 的 brief 引用它；已归档或已交付功能不反推 REQ 卡。首个 SCN 随组件边界确定后创建，避免空目录。
5. **存量 active 工序不改写历史字段**：`2026-10-20-file-drawer`、`2026-10-22-doc-split` 暂留 `works/`；新工序才按新版 brief/result/review.md 模板执行。
6. **全局设计文档状态**：`architecture.md` 用 `status: current`；本地 `doc-layout-spec` 已补「全局设计文档 | draft / current」行并修正 frontmatter 示例（项目内扩展，主本未动）。
7. **doc-split 的模块目录方案作废**：原计划的 `design/image/`、`design/drawer/` 由 `components/` 模型取代；该工序暂留 active，剩余下沉范围待重定，不在本次迁移中改写。

## 被否决的替代方案

- **保留四态、只换技能**：路径与状态继续分叉，新技能的违规信号全部命中。
- **`diagnostics.md` 并入 `architecture.md`**：撤销 2026-10-24 的读者下沉，`architecture.md` 回到混层状态。
- **预建 `requirements/`、`components/`、`scenarios/` 空目录**：违反反占位，路径与真实状态脱节。
- **为已交付功能补 REQ 卡**：事后编造 intake，且与现有可能重复；需求卡留给下一个真实需求。
- **把 `image`/`drawer` 一次拆成组件**：组件边界属 P1 结构决策，需要候选与确认，不能借文档迁移顺手定。

## 后果与待办

- 现行引用已更新：`architecture.md`、`doc/README.md`、`plan/open-questions.md`、`plan/roadmap.md`；`2026-10-22-doc-split` 的旧路径保留并加迁移注记。
- 需求层已有 `REQ-0001`（文件抽屉，accepted）；`SCN-0001` 待建，场景目录暂不预建。
- 组件边界仍只有 `CMP-diagnostics` 一个显式组件；是否把 image/drawer/shell 拆成组件，按 `arch-design-spec` 的 P1 另立工序。
- 场景索引生成器未接入；首个 SCN 出现时补 `_index.md`。
- 本地 `doc-layout-spec` 已补全局设计文档状态行；技能主本本次未动。
- `doc-split` 的剩余下沉范围待用户重定或关闭。
