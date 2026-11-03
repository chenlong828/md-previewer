---
layer: works
module: global
status: active
updated: 2026-11-04
---

# 工序 brief：已实现场景与组件清点（五态补全）

## 需求

把 MDPreview 已经实现、已经上线验证的用户旅程整理为 `design/scenarios/` 场景卡，并补齐支撑它们的组件规格与需求卡：

- 7 个组件：`CMP-app-shell`、`CMP-document-io`、`CMP-editor`、`CMP-drawer`、`CMP-image`、`CMP-export`、`CMP-diagnostics`；
- 8 张需求卡：`REQ-0001`～`REQ-0008`，全部先 `accepted`；
- 15 个场景：`SCN-0001`～`SCN-0015`，按 领域 / 价值流 / 场景 三层。

需求状态纪律：**只有影响场景全部 verified，REQ 才从 `accepted` 转 `delivered`**。本轮不预先转；已有证据的抽屉、图片两组列为下一轮验证的 promotion candidate。

## 背景

- 五态文档树已就位，但 `design/` 只有 `architecture.md` 与 `CMP-diagnostics`，没有业务组件与场景；REQ-0001 的影响场景仍是“待新建”。
- 现有验证集中在 `--selftest`（101 项）、`--drawer-test`、`--multiwindow-test` 与历史工序 result；这些是场景卡的测试来源，不等于每个场景都已满足 3 正 1 反。
- 新版 `req-scenario-spec` 要求需求先落卡、场景再挂 3+1；新版 `arch-design-spec` 要求组件有契约、数据所有权、预算与独立验证入口。

## P1 确认

2026-11-04 用户确认：

- 组件切分：7 组件（不采用 5 组件精简版）；
- 场景范围：15 个全量；
- 需求状态：验证后再转 `delivered`，本轮全部 `accepted`。

组件切分属于 P1 结构决策；本确认记录作为该工序的人工确认门。

## 范围

- 新增 6 份组件规格（`CMP-diagnostics` 已存在，仅迁到 `CMP-` 目录名）；
- 新增 7 张需求卡；更新 `REQ-0001` 的影响场景；
- 新增 15 个场景卡，每个给出入口、运行序、不可变引用与 3+1 测试方案；
- 更新 `doc/README.md`、`doc/plan/roadmap.md` 的必要引用；
- 新增组件切分/场景清点的决策记录；
- 记录验证债：缺自动化、缺反例、只有人工证据的条目。

## 非目标

- 不改代码、不改桥协议、不改 UI 行为；
- 不新增测试实现；只把已有测试映射到场景，缺的记为 `missing`；
- 不整理 DFX 安全域（WebView 文件授权、mermaid loose、桥接口面）为场景；这些留在 `architecture.md` §1 作为架构 guard；
- 不把 App 图标、构建脚本、文档迁移本身做成业务场景；
- 不把 `REQ-0002`～`REQ-0008` 标 `delivered`；等对应场景 verified 后另行转；
- 不预建 `design/scenarios/` 空目录之外的任何占位。

## 验收标准

1. 7 个组件均有 `spec.md`，含组件卡、公开契约/能力 ID、入口、数据所有权、预算、单独运行命令、验证计划、删除测试。
2. `REQ-0001`～`REQ-0008` 均有卡；新卡状态全部 `accepted`，影响场景指向真实 SCN。
3. 15 个场景均有 `scenario.md`；frontmatter 含 `flow`、`scenario`、`domain`、`valueStream`、`title`、`entries`、`tests`；正文含入口、运行序、不可变引用、3+1 测试表。
4. 现行文档相对链接全部可达；frontmatter 的 layer/status 与目录一致。
5. `doc/README.md` 的结构树与阅读顺序反映新组件/场景；`REQ-0001` 的“待新建”改为真实 SCN。
6. 验证债清单可从场景卡与 result 汇总，不需要读代码才能知道缺什么。

## 任务表

| ID | 类型 | 组件 | 状态 | 装载清单 |
|---|---|---|---|---|
| T-2026-11-04-01 | design | 全部 | done | 本 brief、`arch-design-spec`、`doc-layout-spec` |
| T-2026-11-04-02 | change | CMP-app-shell / document-io / editor / drawer / image / export | done | 组件源码入口、`architecture.md` §1–§3 |
| T-2026-11-04-03 | change | requirements | done | `req-scenario-spec`、`REQ-0001`、README |
| T-2026-11-04-04 | change | scenarios | done | 15 个 SCN 模板、selftest/drawer/multiwindow 输出、历史 result |
| T-2026-11-04-05 | verify | 全部 | pending | 链接检查、frontmatter 检查、3+1 证据复核 |

## 装载清单

- `.agents/skills/arch-design-spec/SKILL.md`
- `.agents/skills/req-scenario-spec/SKILL.md`
- `.agents/skills/doc-layout-spec/SKILL.md`
- `doc/design/architecture.md`
- `doc/design/components/CMP-diagnostics/spec.md`
- `doc/requirements/REQ-0001-file-drawer.md`
- `Sources/MDPreview/Selftest.swift` 的 PASS 名称
- `doc/works/2026-10-20-file-drawer/result.md`、`doc/works/2026-10-22-drawer-anchor-and-resize/result.md`
- `doc/history/works/2026-10-20-image-support/result.md`、`doc/history/works/2026-10-20-image-cleanup/result.md`

## 验证债

- 文件打开/保存/关闭、GB18030 转 UTF-8、尾换行、外部变更监听：没有自动化 3+1；
- 格式命令、查找无命中、源码模式非法提交、表格外操作、缩放/宽度越界、导出失败：缺反例；
- 数学/Mermaid、打印、最近文件/CLI/拖放打开：主要靠人工或截图；
- 诊断三入口的失败路径未固化。

这些债在各场景卡的 `tests` 表与 `## 6. 验证债` 中逐条记录；没有偿还前，场景最高 `designed`，REQ 不转 `delivered`。
