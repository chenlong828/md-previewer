---
layer: requirements
module: diagnostics
status: accepted
updated: 2026-11-10
---

# REQ-0007：官方诊断面

**类型**：quality

## 1. 场景叙述

当 release 包在用户机器上出问题时，维护者可以用无 GUI 入口取证：`--selftest` 跑无头自检、`--screenshot` 进程内截图、`--multiwindow-test` 验证多窗口与表格状态，以及 `--context-menu-test` 定向回归右键行列定位；入口统一 flag 语法、输出前缀与退出码。

结果是：单机工具没有线上灰度时，仍能复现、取证、定位，而不是只靠用户口头描述。

## 2. 价值

不做的后果：release 出问题只能让用户复述；没有进程内截图就无法看到渲染差异；没有无头自检就无法在 CI/远程机器回归。

## 3. 非目标

- 不做远程遥测、日志上传、崩溃上报、自动诊断包。
- 不做 GUI 诊断面板；诊断面是 CLI。
- 不保证诊断入口覆盖所有业务分支；只覆盖已声明的检查项。

## 4. 行为约定

- 入口随 release 构建发布，不剥离到独立 target。
- `--selftest`：`PASS/FAIL 名称`，末行 `SELFTEST PASSED/FAILED`；0=全过/1=有失败。
- `--screenshot`：`SCREENSHOT …`；0=成功，2–7=阶段失败。
- `--multiwindow-test`：`[MULTIWINDOW] PASS/FAIL`；0=全过/1=有失败。
- `--context-menu-test`：`[CONTEXTMENU] PASS/FAIL`；0=全过/1=有失败；只生成临时受控文档，不改用户文档。
- 环境钩子 `MDP_IMPORT_IMAGE` / `MDP_EDIT_IMAGE` 只服务诊断，不进入正常用户路径。

## 5. 影响场景

| 场景 | 状态 | 本次新增/修改的断言 |
|---|---|---|
| [SCN-0015 运行诊断](../design/scenarios/diagnostics/troubleshooting/run-diagnostics/scenario.md) | designed | 入口可运行、输出前缀/退出码、失败路径明确；失败码反例待补 |

## 6. 验收归属

验收 = SCN-0015 `verified` + 第 4 节约束未被违反。失败路径未固化，故保持 `accepted`。

## 7. 澄清记录

- 2026-11-04 五态补录：从 `CMP-diagnostics` 规格、README 与 OQ-3 结论反推。
- 入口已有成功路径；下一步补“故意失败时退出码/输出”的反例。
- 2026-11-10 增补 `--context-menu-test`（表格行列右键定位回归）。

## 8. 状态

`accepted`；待 SCN-0015 verified 后转 `delivered`。
