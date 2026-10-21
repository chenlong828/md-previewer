---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

# 工序: 架构规格 skill 整合与评审（skills 体系四件套）

> 立项日取 2026-10-19（REVIEW 第 9 节 description 评审为最早可考日期）；实际收口归档 2026-10-21，补录本目录。

## 需求

1. 把用户提供的架构判据（5 组判据、3 条良好设计要求、P3/P2/P1/P0 分级、「冷热路径明晰」目标）整合为可执行、可裁剪、可检查的 skill；
2. 评审既有 skills 的 description 触发质量并按判据修订；
3. 用户 10-21 提供的五组开发过程规则（工作方式/验收/错误处理/安全边界/工作区卫生）沉淀为第四个 skill。

## 已核实的现状

- 既有 skill 两件：design-before-coding（动手前设计流程）、doc-layout-spec（文档四态布局）；
- SKILL.md 以 frontmatter（name/description/whenToUse）供 DSH 技能目录扫描；模型侧技能目录只读 description，whenToUse 不进目录。

## 领取的设计决策（要点，裁决全文见 REVIEW.md）

- 调用图与源码依赖图分开，化解「上层调用下层」与「依赖倒置」的冲突；
- 同层不相认的共享出口三通道：数据下沉数据服务、编排上提 L2、规则抽领域服务；
- 扇出只数业务契约（排除横切工具与纯值类型），硬上限 8、热路径 ≤5；
- 业务模块与技术边界模块分开，删除测试卡透传；
- 冷热二分，混合路径契约边界拆分，不设温路径；
- P 级定级顺序 + 人工门相称：P3 自动 / P2 终确认 / P1 参与设计+终确认 / P0 共同决策。

## 验收标准

1. arch-design-spec SKILL.md 成稿：原始条目无丢失、每条有可执行动作与可检查产物、冷热路径成一级章节、P 级决定流程重量与人工门；
2. 与 design-before-coding / doc-layout-spec（及后续 dev-execution-spec）的分工与冲突裁决顺序明确；
3. description 有明确判据并按判据修订到位；执行纪律 skill 落地，高危确认与密钥禁区常驻上浮全局 AGENTS.md；
4. REVIEW 第 7 节待确认问题全部有用户结论。

## 边界（本工序不做）

- 项目内 lint/hook 配置落地（按项目实际技术栈另行工序）；
- skills 体系在 doc/ 文档树的登记（skill 不属文档树，doc-layout-spec 自身即豁免条款的来源）。
