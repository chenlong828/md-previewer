<!-- 文档树导航页：位于文档根，不属四态中的任何一态，故不带 layer/status frontmatter -->

# 文档导航

本树按四态组织：现行真相（design/）、意图（plan/）、执行（works/）、记忆（history/）。
文档归属由路径与 frontmatter 推导，此处只给阅读顺序，不维护状态表。

## 阅读顺序

1. **要了解"接下来修什么"** → [plan/roadmap.md](plan/roadmap.md)：工序总览表
   即任务入口，各工序状态以表内状态列为准（2026-10-12 技术债批次已全部
   收口归档；2026-10-20 起功能工序也在此登记）。
2. **要了解"哪些风险在悬着"** → [plan/risks.md](plan/risks.md)：跨工序活风险
   与已收口条目的台账（已消除条目保留作回归监控）。
3. **要领取一个任务** → `works/<工序ID>/brief.md`，从 roadmap 表进入对应工序目录；
   跨工序决策先查 [plan/open-questions.md](plan/open-questions.md)。
4. **要了解系统现状** → 仓库根 [README](../README.md)（架构图与桥协议）；
   跨模块设计取舍见 [design/architecture.md](design/architecture.md)
   （安全/行为取舍、诊断面、桥协议）。
5. **要做平台壳或动桥协议** → 先读存档
   [history/decisions/2026-10-21-editor-kernel-spec.md](history/decisions/2026-10-21-editor-kernel-spec.md)：
   内核/壳分界、桥协议 v2 契约与迁移方案（2026-10-21 评审暂缓，恢复时从存档重启工序）。

## 约定

- 工序目录名即工序ID：`YYYY-MM-DD-<短名>`，立项日命名，归档不改名。
- `history/`：已归档工序（`history/works/`）与坑档案（`pitfalls.md`）。
