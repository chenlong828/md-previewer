---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 决策：组件切分与场景清点（2026-11-04）

## 背景

五态树就位后，`design/` 只有全局架构与诊断组件，业务组件与用户场景缺失；`REQ-0001` 的影响场景仍是“待新建”。需要一次清点把已实现能力落到组件、需求、场景三层，并明确哪些只是文档补录、哪些已有验证。

## 决策

1. **7 个组件**：`CMP-app-shell`、`CMP-document-io`、`CMP-editor`、`CMP-drawer`、`CMP-image`、`CMP-export`、`CMP-diagnostics`。按“窗口/文件 IO/编辑面/导航/图片/输出/诊断”切分，每个有独立契约、数据所有权、预算与单独运行入口。
2. **8 张需求卡**：`REQ-0001`～`REQ-0008`。`REQ-0001` 保持 `accepted`；`REQ-0002`～`REQ-0008` 本轮全部 `accepted`，不预先标 `delivered`。
3. **15 个场景**：`SCN-0001`～`SCN-0015`，按 `editing / media / navigation / output / diagnostics` 五个领域、八个价值流组织。每个场景有入口、运行序、不可变引用、3 正 1 反测试方案。
4. **验证门**：只有影响场景全部 `verified`，REQ 才从 `accepted` 转 `delivered`。当前无场景 `verified`；抽屉、图片显示编辑、图片导入清理为 promotion candidate，需按 3+1 复跑。
5. **组件目录名**：统一 `components/CMP-<name>/spec.md`；原 `components/diagnostics/` 迁为 `components/CMP-diagnostics/`。
6. **不新增场景的领域**：App 图标、构建脚本、文档迁移、DFX 安全边界不做业务场景；安全取舍留在 `architecture.md` §1。

## 被否方案

- **5 组件**：把 `CMP-document-io`、`CMP-export` 并入 `CMP-app-shell`。否：文件编码/保存规范化与导出有独立契约和测试入口，合并后壳组件变成杂物间。
- **按功能拆 12+ REQ**：格式/查找/源码/表格/数学各一张。否：需求应表达用户结果，场景才拆细；8 张卡足以承接 15 个场景。
- **8 个核心场景**：只做抽屉、编辑、图片、导出、诊断。否：已实现旅程覆盖不全，文件生命周期与显示偏好没有归属。
- **先标 delivered 再补测试**：否；违反“需求验证后转”，会把文档状态当宣传。

## 影响

- `doc/design/components/` 新增 6 份规格、迁移 1 份；`doc/design/scenarios/` 新增 15 份。
- `doc/requirements/` 新增 7 张、更新 `REQ-0001`；README 树与阅读顺序更新。
- 验证债进入各场景 §6 与工序 result；不因建卡而消失。
- 组件切分是 P1，已由用户 2026-11-04 确认 7 组件 / 15 场景 / 验证后转。

## 待办

- 按场景 §5 的 3+1 逐条复跑；优先抽屉与图片两组。
- 补外部变更、编码/尾换行、打印、打开路径、诊断失败路径的可执行用例。
- 场景全部 verified 后，逐张把 REQ 转 `delivered`。
