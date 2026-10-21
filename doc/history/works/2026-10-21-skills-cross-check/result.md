---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

# result：四技能交叉确认与排冲突

## 验收结果

- 验收标准 1：通过——design 补 arch 交接句后，四技能引用闭合为 design → arch → dev → doc，arch 与 dev 双向互认 P 级门。
- 验收标准 2：通过——验收三件套定义唯一在 design 第一步（dev 引用）；高危/密钥清单权威唯一在全局 AGENTS.md（dev 只留执行细则）；地图产物归一（架构任务只画一张分层模块地图）。
- 验收标准 3：通过——arch「两份既有 skill」改为三份并补 dev；doc「两份 skill 配合使用」改为四技能分工。
- 验收标准 4：通过——见下方结论落点表。

## 结论落点表

落点为 `.agents/skills/`（skill 以 skill 形式存在，不属文档树）：

| # | 结论 | 落点 |
|---|---|---|
| 1 | design 正文补 arch 交接句（原只有 description 提及，正文单向缺针） | design-before-coding/SKILL.md 第七步末 |
| 2 | design「小/中/大」与 arch「P0–P3」双标尺桥接：各量各的，不一致按更重一档 | design-before-coding/SKILL.md 按任务规模裁剪 |
| 3 | design「数据只有一个权威来源」与 arch「数据单家」互引 | design-before-coding/SKILL.md 核心原则 |
| 4 | arch 开头「两份既有 skill」→「三份」，补 dev 分工条目 | arch-design-spec/SKILL.md 开头 |
| 5 | arch 协作节补 dev bullet；冲突裁决句补「执行纪律听 dev-execution-spec」 | arch-design-spec/SKILL.md 六 |
| 6 | 组件地图 vs 模块地图归一：同一修改只画一张，模块地图是组件地图的架构细化 | arch-design-spec/SKILL.md 六 |
| 7 | dev 高危/密钥清单去重：AGENTS.md 为唯一权威，本节只留执行细则与硬拦截 | dev-execution-spec/SKILL.md 五 |
| 8 | dev 补动工前 P 级门核对（P1 未确认不编码/P2 未确认不合并/P0 不写代码） | dev-execution-spec/SKILL.md 二 |
| 9 | doc 开头「两份 skill」→ 四技能分工句 | doc-layout-spec/SKILL.md 开头 |

## 确认无冲突（不改）

- whenToUse 四技能一致移除，frontmatter 统一为 name + description；
- description 触发词重叠（模块拆分/重构/评审两边都写）为真实重叠，分工在各自正文开头声明，不在 description 消歧；
- dev「先批量理解」与 design「第一动作是设计拆解」不冲突：前者管动手后的节奏，后者管动手前的设计，边界在双方正文开头声明。
