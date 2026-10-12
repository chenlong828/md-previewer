---
layer: works
module: global
status: closed
updated: 2026-10-12
---

# 工序：疑似缺陷修复（正确性优先）

承接 2026-10-12 技术债审计中 3 个"疑似真缺陷"级发现。修复前先在 selftest
写出可复现断言（红→绿），修复后断言留作回归守门。风险定性见
[risks.md R1](../../plan/risks.md)。

## 问题清单

### D1 源码模式下保存写盘陈旧内容（对应审计 #21，R1）

- 现象：文档内容两个真相源——编辑器 doc 与源码模式 textarea。
  `web/src/main.js:887` `getMarkdown()` 只读编辑器 doc；`web/src/main.js:1097`
  `requestStats()` 却在源码模式下读 textarea。源码模式编辑后 ⌘S，
  Swift `fetchMarkdown`（`Sources/MDPreview/DocumentWindowController.swift:271-275`）
  取到旧内容写盘并 `markClean()`（main.js:881-885）把旧内容设为基线。
- 佐证分叉：PDF 导出专门处理了源码模式（`inSourceModeIf`，
  DocumentWindowController.swift:451-455），保存路径没有。
- 方向：统一"当前文档内容"单一真相源——getMarkdown 在源码模式下返回
  textarea 内容，或源码模式编辑实时同步进编辑器 doc；两案择一，执行时定。

### D2 导出 HTML 标题恒为 "MDPreview"（对应审计 #22）

- 现象：`exportStandaloneHTML` 取 `document.title`（main.js:821），而
  `pushInitialContent` 传 `"title": ""`（DocumentWindowController.swift:208），
  `_init` 落到默认值 `'MDPreview'`（main.js:864）——文件名从未传给 web 层。
- 方向：`pushInitialContent`/`init` 传入当前文件名；`exportHTML` 前刷新。
  无文件名时保留 "MDPreview" 兜底。

### D3 `_init` 内部顺序颠倒：配置在创建之后才生效（对应审计 #23，含 #1）

- 现象：`createEditor()`（main.js:257-306）先跑，`opts` 后解析（main.js:854-867）：
  首帧主题按默认 light 应用后再纠正（深色系统用户开窗瞬间 mermaid 按浅色初始化，
  靠 `setTheme` 二次 `replaceAll` 重绘兜底，多一次全文档重排）；
  `opts.plugins`（pluginSet）同样因此从未生效——见 [OQ-1](../../plan/open-questions.md)。
- 方向：`_init` 先解析 opts（theme/zoom/plugins/title）再创建编辑器；
  pluginSet 修复 or 删除按 OQ-1 结论执行。

## 验收标准

- [x] selftest 新增断言：源码模式编辑 → 模拟保存取回的内容与 textarea 一致；
      markClean 后基线等于所见内容（先红后绿）
- [x] selftest 新增断言：带 title 的 init 后，exportStandaloneHTML 的 `<title>` 等于传入值
- [x] 深色系统模拟下，init 首帧即按 dark 初始化 mermaid（无二次重绘痕迹）
- [x] OQ-1 按结论执行（修复生效或删除分支），`MDP_PLUGINS` 不再是死配置
- [x] 既有 selftest 全部通过；`./build.sh` 构建通过

## 依赖与顺序

- 无前置依赖，批次一首先执行。
- 同文件区域后续工序：W2（死代码清理）建议等本序收口后开工。
