---
layer: history
module: editing
status: frozen
updated: 2026-11-05
---

# 结果：文档右键拷贝文件路径

## 1. 结论

- 文档右键菜单新增「拷贝文件路径到剪贴板」，位于剪贴板组之后、查找组之前。
- 仅已保存文件出现；Markdown 与代码文档都可用。
- 点击写入 `fileURL.standardizedFileURL.path`（绝对 POSIX 路径），不写文件、不产生 `changed`。
- 未保存/目录模式不生成菜单项；直接调用拷贝入口返回 false，且不清空剪贴板。
- 命令注册在 `EditorCommands`，复用现有菜单构建与校验，没有第二套菜单来源。

## 2. 验证

- `swift build -c debug`：通过。
- `--selftest`：`SELFTEST PASSED`；命令注册表 34 条完整（含 `copyFilePath`）。
- `--multiwindow-test`：
  - `PASS 文档右键菜单含拷贝文件路径(2/2)`
  - `PASS 拷贝文件路径位于剪贴板组之后(索引 8)`
  - `PASS 右键拷贝文件路径(/tmp/mdp-a.md)`
  - `PASS 未保存文档不显示/不拷贝文件路径`
- `./build.sh debug`：Node 86 项通过；Swift debug 构建；`dist/MDPreview.app` 重新组装并签名。
- 打包二进制直接跑 multiwindow-test：同样全过（含 4 项新增断言）；确认不是只在 `.build/debug` 里生效。
- 人工验收：2026-11-05 用户确认右键菜单项可见、点击后路径正确。

## 3. 文档落点

- 需求：[REQ-0012](../../../requirements/REQ-0012-copy-file-path.md)（delivered）
- 场景：[SCN-0018](../../../design/scenarios/editing/document-lifecycle/copy-file-path/scenario.md)（verified）
- 组件契约：[`CMP-app-shell#copy-file-path`](../../../design/components/CMP-app-shell/spec.md)
- 路由：`doc/plan/roadmap.md`、`doc/README.md`、根 `README.md`

## 4. 收口

- 本工序为 P3 小改动，按 `dev-execution-spec` 免写 `review.md`；无 blocker/decision/hold。
- 代码与文档已收口；人工验收已确认；**尚未提交**（等提交指令）。
- 用户实际运行的是 `dist/MDPreview.app`；本次已重建该包，需退出旧进程后重新打开验证。
- 教训：上一轮只构建 `.build/debug` 就宣称完成，用户运行的 dist 包仍是旧二进制，菜单项自然看不到；交付验证必须落在用户实际运行的产物上。
