---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

# 收口: 架构规格 skill 整合与评审

## 验收结果（对照 brief 验收标准）

1. **arch-design-spec 成稿** ✅ — 随 7773c9f 入库；5 组判据/3 条良好设计/4 级全部有落点（REVIEW 第 2 节映射表），冷热路径一级章节，P 级判定顺序+级别表+定级纪律+完成定义齐备。
2. **分工与裁决顺序** ✅ — design-before-coding（动手前怎么想）/ arch-design-spec（架构怎么定）/ dev-execution-spec（动手到交付怎么干）/ doc-layout-spec（文档放哪）四段各管一段，开篇互写分工；冲突裁决：内容判据归 arch、通用流程归 design、落位归 doc、执行交付归 dev。
3. **description** ✅（判据已修订）— 10-19 按「一句身份+方法+场景、100–140 字」评审瘦身（REVIEW 第 9 节）；10-21 用户改判据为「重点写何时使用+用来做什么，不做正文精简重复」，四 skill description 重写（7929328），dev-execution-spec 的 whenToUse 删除并入 description。
4. **执行纪律沉淀** ✅ — dev-execution-spec 新增（1b18016），高危确认与密钥禁区常驻上浮 `~/.dsh/AGENTS.md`；design-before-coding 补验收三件套与执行侧交接句。
5. **第 7 节 8 问** ✅ — 全部有用户结论，见下表。

## 第 7 节待确认问题结论（2026-10-21 用户逐条确认）

| # | 问题 | 结论 |
|---|---|---|
| 7.1 | 分层方向 | 确认当前取舍：L0 基础设施→L1 领域→L2 整合（整合=用例编排/组装层），调用图与源码依赖图分开 |
| 7.2 | P3 文件边界 | 确认：实质性跨文件/跨模块=P2，纯机械多文件（重命名/格式化/测试同步）可 P3 |
| 7.3 | 扇出计数 | 确认：排除横切工具（日志/指标/配置）与纯值类型，只数业务契约 |
| 7.4 | 复用规则 | 定稿为问答式判定：三问（同一业务语义？同一变化原因？公共契约稳定？）逐答，三「是」才抽模块库，任一「否」记录不抽理由——已落入 SKILL.md 第 6 步（0ebdc7c） |
| 7.5 | 冷热分类 | 确认：热/冷二分，不设温路径，混合路径契约边界拆分 |
| 7.6 | P1 人工门 | 确认：人参与切分/契约阶段+最终确认，形式可异步（两次介入） |
| 7.7 | skill 落位 | 由落位决策覆盖：项目级为准（见下节） |
| 7.8 | 「没有交隔」 | 确认=「没有交叠」：能力唯一 owner、规则单处实现、数据单写入口 |

## 后续决策（2026-10-21 用户交互确认）

- **skills 单一来源=项目级**：删除 `~/.dsh/skills/doc-layout-spec/` 全局副本，REVIEW 第 9/10 节挂着的「全局副本是否同步」一并了结；四 skill 只随仓库版本化。
- **硬拦截暂不配**：维持第 10 节「按项目实际技术栈落地时再配」；gitleaks/pre-commit/lint 清单留在 dev-execution-spec 第一节作建议。
- **description 字段策略**：单 description 字段（DSH 支持 but 不向模型目录展示 whenToUse，删除无损失）；description 内容重点=何时使用+用来做什么。
- **本工序归档**：REVIEW.md 移入本目录，补 brief/result，frontmatter 冻结。

## 结论落点表

| 结论 | 落点 |
|---|---|
| description 判据（何时使用+用来做什么，禁正文精简重复；取代 REVIEW 第 9 节判据） | 四个 `.agents/skills/*/SKILL.md` frontmatter（7929328） |
| 复用问答式判定 | `.agents/skills/arch-design-spec/SKILL.md` 第 6 步复用归位（0ebdc7c） |
| skill 单一来源=项目级 | `.agents/skills/`；`~/.dsh/skills/` 已清空 |
| 高危确认/密钥禁区常驻生效 | `~/.dsh/AGENTS.md` |
| 8 问定稿结论 | 本表上节 + 各 SKILL.md 正文既有取舍 |

## 遗留

- doc/README.md 导航页未登记本工序：该文件当前载有另一工序（portable-kernel）的未提交改动，为不混 diff 未动它；导航页如需收录归档工序，由其一并或后续单独提交。
- dev-execution-spec 第一节硬拦截表格为建议清单，未在项目内落地（见后续决策第二条）。
