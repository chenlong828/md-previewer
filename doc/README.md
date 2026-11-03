<!-- 文档树导航页：位于文档根，不属五态中的任何一态，故不带 layer/status frontmatter -->

# 文档导航

本树按「五态分离」组织：位置即状态。分层规则见 `.agents/skills/doc-layout-spec`（技能不在文档树内）。

## 当前实际存在的结构

```
doc/
├── README.md
├── requirements/                       ← 需求：为什么做
│   ├── REQ-0001-file-drawer.md
│   ├── REQ-0002-editing.md
│   ├── REQ-0003-image.md
│   ├── REQ-0004-persistence.md
│   ├── REQ-0005-export.md
│   ├── REQ-0006-windows.md
│   ├── REQ-0007-diagnostics.md
│   └── REQ-0008-appearance.md
├── plan/                               ← 调度：接下来做什么
│   ├── roadmap.md
│   ├── risks.md
│   └── open-questions.md
├── design/                             ← 真相：系统现在是什么
│   ├── architecture.md
│   ├── components/
│   │   ├── CMP-app-shell/spec.md
│   │   ├── CMP-document-io/spec.md
│   │   ├── CMP-editor/spec.md
│   │   ├── CMP-drawer/spec.md
│   │   ├── CMP-image/spec.md
│   │   ├── CMP-export/spec.md
│   │   └── CMP-diagnostics/spec.md
│   └── scenarios/
│       ├── editing/document-lifecycle/   ← 3 个
│       ├── editing/rich-editing/         ← 5 个
│       ├── editing/appearance/           ← 1 个
│       ├── media/image/                  ← 2 个
│       ├── navigation/file-drawer/       ← 1 个
│       ├── navigation/windows/           ← 1 个
│       ├── output/export/                ← 1 个
│       └── diagnostics/troubleshooting/  ← 1 个
├── works/                              ← 执行：正在做什么
│   ├── 2026-10-20-file-drawer/         ← 文件抽屉（收口中）
│   ├── 2026-10-22-drawer-anchor-and-resize/ ← 抽屉锚点与宽度（收口中）
│   ├── 2026-10-22-doc-split/           ← design 文档下沉（执行中）
│   └── 2026-11-04-scenario-inventory/  ← 已实现场景/组件清点（执行中）
└── history/                            ← 记忆：怎么走到这里的
    ├── decisions/
    ├── works/                          ← 已归档工序（含 2026-11-02-app-icon）
    └── pitfalls.md
```

- **反占位**：`requirements/`、`design/components/`、`design/scenarios/` 均有真实卡片；`design/scenarios/_index.md` 为生成物，生成器接入前不手建；不预建空目录。
- **全局设计文档**：`architecture.md` 用 `status: current`；本地 `doc-layout-spec` 已补「全局设计文档 | draft / current」状态行（2026-11-04 项目内扩展，主本未动）。
- **组件与场景**：组件规格带 `component: CMP-xxx`，状态 `planned/active/retired`；场景带 `flow` 与 `scenario: SCN-xxxx`，状态 `draft/designed/verified/deprecated`。
- **需求状态纪律**：新需求卡先 `accepted`；只有影响场景全部 `verified`，才转 `delivered`。当前 8 张 REQ 均为 `accepted`，验证债见各场景卡 §6。

## 阅读顺序

1. **要了解“为什么做”** → `requirements/`：8 张需求卡，从 [REQ-0001 文件抽屉](requirements/REQ-0001-file-drawer.md) 到 [REQ-0008 显示偏好](requirements/REQ-0008-appearance.md)；每张写场景、价值、非目标与影响场景。
2. **要了解“接下来修什么”** → [plan/roadmap.md](plan/roadmap.md)：工序总览与状态。
3. **要了解“哪些风险在悬着”** → [plan/risks.md](plan/risks.md)；跨工序未决问题查 [plan/open-questions.md](plan/open-questions.md)。
4. **要了解系统现状** → [design/architecture.md](design/architecture.md)（安全/行为取舍、桥协议）；组件契约从 `design/components/` 进入，诊断面见 [CMP-diagnostics](design/components/CMP-diagnostics/spec.md)。
5. **要看用户旅程** → `design/scenarios/`：15 个场景，按 领域/价值流/场景 分层；每个带入口、运行序、3+1 测试与验证债。
6. **要领取一个任务** → `works/<工序ID>/brief.md`，从 roadmap 表进入对应工序目录；新工序按 brief/result 模板写，P1/P2 另加 `review.md`。
7. **要做平台壳或动桥协议** → 先读存档 [history/decisions/2026-10-21-editor-kernel-spec.md](history/decisions/2026-10-21-editor-kernel-spec.md)：内核/壳分界、桥协议 v2 契约与迁移方案（2026-10-21 评审暂缓，恢复时从存档重启工序）。
8. **要查历史结论或踩过的坑** → `history/decisions/`、`history/works/`、[history/pitfalls.md](history/pitfalls.md)。

## 约定

- 工序目录名即工序 ID：`YYYY-MM-DD-<短名>`，立项日命名，归档不改名。
- 收口是归档前置条件：closed 工序整目录移入 `history/works/`，frontmatter 改 `layer: history` / `status: frozen`。
- `history/` 冻结只读；唯一例外是坑档案允许更新存续状态。
- 现行文档不把归档件当设计依据；活结论先蒸馏进 `design/`。
- 五态迁移的决策与遗留见 [2026-11-04-five-state-migration.md](history/decisions/2026-11-04-five-state-migration.md)；组件/场景清点见 [2026-11-04-component-scenario-inventory.md](history/decisions/2026-11-04-component-scenario-inventory.md)。
