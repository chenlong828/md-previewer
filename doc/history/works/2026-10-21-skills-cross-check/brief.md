---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

# brief：四技能交叉确认与排冲突

## 需求

四个技能（design-before-coding / arch-design-spec / dev-execution-spec / doc-layout-spec）经全局化评审定稿、单一来源定项目级后，做一次交叉确认：核对互相引用、职责边界、重复定义与过时表述，排除冲突。

## 背景

- 评审与定稿记录已归档：`history/works/2026-10-19-skills-review/`（第 7 节 8 问已于 2026-10-21 逐条确认）。
- description 判据定稿「何时使用 + 用来做什么」；whenToUse 字段全面移除（目录只读 description）；全局副本已删，技能单一来源定项目级。

## 验收标准

1. 四技能互相引用闭合且指向正确（design ↔ arch ↔ dev ↔ doc）；
2. 无同一事实两处权威（验收三件套、高危清单、地图产物各归一处）；
3. 过时表述清零（「两份 skill」式分工清单、缺技能的协作节）；
4. 交叉确认结果在 result.md 登记结论落点。
