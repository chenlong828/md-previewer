---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 结果：右侧文档缩略图与定位（已交付并归档）

## 1. 结论

- **自动门通过**：`npm test` 85/85；`--selftest` 全绿，含缩略图诊断/默认显示/正文预留/开关。
- **人工门通过**：2026-11-05 用户确认 Markdown 与代码窗口效果，同意提交推送；SCN-0017 转 `verified`、REQ-0011 转 `delivered`，本工序 `closed` 并归档到 `history/works/`。
- **实现边界**：缩略图是第七个内核功能组件 `CMP-kernel-minimap`；Markdown/代码 source 工厂留在 `CMP-kernel-editor` / `CMP-kernel-code` 内部，经 `assemble.js` 的 `minimapSources` 端口注入；偏好归 `CMP-app-shell`。
- **2026-11-05 路线修订**：Canvas 采样改为 DOM 克隆 + 顶对齐 + fit；定位改按页面实际缩略矩形，轨道空白区不响应。
- **残余观察**：快照耗时尚未仪表化；键盘/无障碍导航未做，均不阻塞交付。

## 2. 实际改动

| 区域 | 改动 |
|---|---|
| 内核组件 | 新增 `web/src/kernel/components/minimap/`：`minimap.js`、`thumbnail.js`、`viewport.js`、`visibility.js`、`ops.js`、`index.js`、`minimap.css`；`renderer.js`（Canvas）已退场 |
| 装配 | `assemble.js` 提供 `minimapSurface` / `minimapSources`；`ops.js` 挂两个 op；`page.js` 启动；`document/init` 应用偏好 |
| 快照 | `components/editor/editor.js#createMarkdownMinimapSource`；`components/code/code-view.js#createCodeMinimapSource`；`shared/readonly-clone.js` 脱敏/去交互/SVG 引用重写 |
| 契约 | `contract/ops.js` 39→41；新增 `setMinimapVisible` / `minimapInfo`；握手 `protocolVersion=2` |
| 壳 | 视图菜单「显示文档缩略图」；`UserDefaults["minimapVisible"]`；跨窗口广播；源码模式置灰 |
| 测试 | `web/test/minimap.test.js`、`core.test.js` 缩略图用例、`contract.test.js` payload 校验、`Selftest.swift` 缩略图断言 |

## 3. 验证证据

- `cd web && npm run lint && npm test`：85 项全绿；`check-kernel` 43 个内核文件通过。
- `./build.sh debug`：前端构建 + 85 项测试 + Swift 编译 + `.app` 组装全绿。
- `--selftest`：`PASS 缩略图诊断(minimapInfo)`、`PASS 缩略图 默认显示(快照数, fit, 顶左)`、`PASS 缩略图 正文预留生效`、`PASS 缩略图 开关隐藏/恢复`；`SELFTEST PASSED`。
- `--screenshot`：Markdown 长文（`.build/minimap-dom-fit.png`）与长代码（`.build/minimap-dom-code.png`）均出现右侧轨道且顶左对齐；短代码文件正确不显示。
- 宽度策略 selftest 已按缩略图预留调整：`appW >= (viewportWidth - reserve)`。

## 4. 收口记录

1. 用户已完成 Markdown/代码窗口人工验收（2026-11-05）。
2. PDF/打印由 `@media print` 规则隐藏缩略图并取消正文预留；按用户确认收口。
3. 残余观察：快照重建/滚动耗时未仪表化；键盘/无障碍导航未做。
4. 收口：SCN-0017 → `verified`、REQ-0011 → `delivered`，`review.md` 记录最终门，工序归档到 `history/works/`。

## 5. 结论落点

| 结论 | 落点 |
|---|---|
| 第七个功能组件与两个端口 | `design/architecture.md` §4；`CMP-kernel-minimap/spec.md` |
| 领域行为与实现分离 | `CMP-minimap/spec.md`；`CMP-kernel-minimap/spec.md` |
| 41 op 与 init 偏好 | `CMP-kernel-contract/spec.md`；`CMP-kernel-document/spec.md`；`CMP-app-shell/spec.md` |
| source 内部化 | `CMP-kernel-editor/spec.md`；`CMP-kernel-code/spec.md` |
| 场景/需求状态 | `SCN-0017` §5/§6；`REQ-0011` §8 |
