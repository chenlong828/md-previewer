<!-- 文档树导航页：位于文档根，不属四态中的任何一态，故不带 layer/status frontmatter -->

# 文档导航

本树按四态组织：现行真相（design/）、意图（plan/）、执行（works/）、记忆（history/）。
文档归属由路径与 frontmatter 推导，此处只给阅读顺序，不维护状态表。

## 阅读顺序

1. **要了解"接下来修什么"** → [plan/roadmap.md](plan/roadmap.md)：七个技术债修复工序
   的批次、依赖与工程量。
2. **要了解"哪些风险在悬着"** → [plan/risks.md](plan/risks.md)：3 个疑似缺陷级 +
   4 个结构性风险的存续条件与承接工序。
3. **要领取一个任务** → `works/<工序ID>/brief.md`，从 roadmap 表进入对应工序目录；
   跨工序决策先查 [plan/open-questions.md](plan/open-questions.md)。
4. **要了解系统现状** → 暂见仓库根 [README](../README.md)（架构图与桥协议）；
   design/ 现行文档随
   [2026-10-12-tests-and-security-doc](works/2026-10-12-tests-and-security-doc/brief.md)
   收口诞生（architecture.md，安全与行为取舍落点）。

## 约定

- 工序目录名即工序ID：`YYYY-MM-DD-<短名>`，立项日命名，归档不改名。
- `design/` 与 `history/` 按反占位纪律在内容诞生时创建，当前尚无内容。
