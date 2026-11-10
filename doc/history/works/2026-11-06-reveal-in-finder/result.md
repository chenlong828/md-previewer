---
layer: history
module: editing
status: frozen
updated: 2026-11-06
---

# 结果：文档右键在 Finder 中定位文件

## 1. 结论

- 文档右键菜单在「拷贝文件路径到剪贴板」下方新增「用 Finder 打开到指定位置」。
- 仅已保存文件出现；Markdown 与代码文档都可用。
- 点击复用文件菜单既有 Finder 命令，在 Finder 中选中当前文件。
- 文件菜单「在 Finder 中显示」的目录模式语义保持不变（定位抽屉根目录）。
- 未保存文档不生成菜单项；直接调用定位入口返回 false，且不拉起 Finder。

## 2. 验证

- `swift build -c debug`：通过。
- `--selftest`：`SELFTEST PASSED`；命令注册表 35 条完整（含 `revealInFinder`）。
- `--multiwindow-test`：
  - `PASS 文档右键菜单含拷贝文件路径(2/2)`
  - `PASS 文档右键菜单含 Finder 定位(2/2)`
  - `PASS Finder 定位位于拷贝路径之后(索引 8/9)`
  - `PASS 右键拷贝文件路径(/tmp/mdp-a.md)`
  - `PASS 右键在 Finder 中定位文件(/tmp/mdp-a.md)`
  - `PASS 未保存文档不显示/不拷贝/不定位`
- `./build.sh debug`：Node 86 项通过；Swift debug 构建；`dist/MDPreview.app` 重新组装并签名。
- 打包二进制直接跑 multiwindow-test：同样全过；确认不是只在 `.build/debug` 里生效。

## 3. 文档落点

- 需求：[REQ-0013](../../../requirements/REQ-0013-reveal-in-finder.md)（delivered）
- 场景：[SCN-0019](../../../design/scenarios/editing/document-lifecycle/reveal-in-finder/scenario.md)（verified）
- 组件契约：[`CMP-app-shell#reveal-in-finder`](../../../design/components/CMP-app-shell/spec.md)
- 路由：`doc/plan/roadmap.md`、`doc/README.md`、根 `README.md`

## 4. 收口

- 本工序为 P3 小改动，按 `dev-execution-spec` 免写 `review.md`；无 blocker/decision/hold。
- 代码与文档已收口；**尚未提交**（等提交指令）。
- 实际 Finder 弹窗复用既有文件菜单命令；自动测试用注入闭包验证传入 URL，用户可目检一次。
