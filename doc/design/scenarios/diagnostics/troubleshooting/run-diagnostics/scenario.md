---
layer: design
module: diagnostics
status: designed
updated: 2026-11-10
flow: FLOW-DIAG-001
scenario: SCN-0015
domain: 诊断
valueStream: 排障
title: 运行无 GUI 诊断入口
entries:
  - CMP-diagnostics/Sources/MDPreview/main.swift#args
  - CMP-diagnostics/Sources/MDPreview/Selftest.swift#SelftestRunner.run
  - CMP-diagnostics/Sources/MDPreview/Screenshot.swift#ScreenshotRunner.run
docs:
  - path: doc/design/components/CMP-diagnostics/spec.md
    heading: 四个入口
  - path: doc/requirements/REQ-0007-diagnostics.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-DIAG-001
  - role: R2
    id: TC-DIAG-002
  - role: R3
    id: TC-DIAG-003
  - role: N1
    id: TC-DIAG-004
---

# 运行无 GUI 诊断入口

## 1. 场景与价值

维护者在 release 包或 CI 上运行三个通用入口：`--selftest` 无头自检、`--screenshot` 进程内截图、`--multiwindow-test` 多窗口/表格状态检查；以及一个定向回归入口 `--context-menu-test`（合成右键事件验证行列定位）。通过输出前缀与退出码判断成败。

结果：没有 GUI/线上灰度时也能复现与取证。

## 2. 入口

- `CMP-diagnostics#selftest`：`SelftestRunner.run`。
- `CMP-diagnostics#screenshot`：`ScreenshotRunner.run`。
- `CMP-diagnostics#multiwindow`：`main.swift` 的 `--multiwindow-test` 分支。
- `CMP-diagnostics#context-menu`：`main.swift` 的 `--context-menu-test` 分支（被测对象是 `EditorWebView` 右键坐标 + 表格菜单动作）。

## 3. 运行序

流程定义：`FLOW-DIAG-001`。

1. 启动参数命中 flag，不激活常规 GUI（selftest 用 `.prohibited`）。
2. 自检：逐项 `PASS/FAIL`，末行 `SELFTEST PASSED/FAILED`，退出 0/1。
3. 截图：等编辑器就绪→打开文档→渲染→`takeSnapshot`→写 PNG；阶段失败 2–7。
4. 多窗口：打开 A/B，断言窗口数与标题；表格定位/行列操作状态；退出 0/1。
5. 右键定位：临时受控文档 + 合成右键 → 真实监视器/坐标换算 → 捕获菜单 → 执行菜单项，断言作用在点击行；退出 0/1。
6. 环境钩子 `MDP_IMPORT_IMAGE` / `MDP_EDIT_IMAGE` 仅服务截图/诊断。

失败路径：

- 自检某项 FAIL：输出 FAIL 名称，退出 1，不静默跳过。
- 截图无文档/未就绪/快照失败：对应退出码，不留空文件。
- 多窗口缺文件/断言失败：输出 FAIL，退出 1。
- 右键定位拿不到受控表格/菜单未构建：输出 FAIL，退出 1。

## 4. 不可变引用

- 四个入口的 flag 语法、输出前缀、退出码（组件规格表）。
- 诊断面随 release 发布，不剥离。
- 诊断不修改用户文档；截图只读。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-DIAG-001 | R1 | 自动 | `--selftest` | 末行 `SELFTEST PASSED`，退出 0 | present |
| TC-DIAG-002 | R2 | 自动 | `--screenshot out.png sample.md` | 输出 `SCREENSHOT saved`，PNG 非空，退出 0 | present |
| TC-DIAG-003 | R3 | 自动 | `--multiwindow-test --fileA=a.md --fileB=b.md` | 两窗口/标题通过，退出 0 | present |
| TC-DIAG-004 | N1 | 自动 | 注入失败检查/缺文件 | 输出 FAIL、退出 1、不静默跳过 | missing |

3 正存在；失败路径反例未固化，暂 `designed`。第四个入口的右键定位断言归 SCN-0008 TC-TBL-005，不在此场景重复计数。

## 6. 验证债

- 需要“故意失败”的 fixture（坏检查项/缺文件/不可写输出）验证退出码。
- 截图阶段码 2–7 未逐条覆盖。

## 7. 变更记录

- 2026-11-04 五态补录，来源：CMP-diagnostics 规格、README、OQ-3 结论。
- 2026-11-10 增补 `--context-menu-test` 定向回归入口（右键行列定位）。
