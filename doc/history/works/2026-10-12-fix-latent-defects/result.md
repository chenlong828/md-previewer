---
layer: history
module: global
status: frozen
updated: 2026-10-14
---

# 工序收口：疑似缺陷修复（正确性优先）

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| selftest 断言：源码模式编辑 → 模拟保存取回内容与 textarea 一致；markClean 后基线等于所见（先红后绿） | ✅ | `D1 源码模式保存取一致内容`、`D1 markClean 基线等于所见`；修复前实测红（FAIL×2），修复后绿 |
| selftest 断言：init/setTitle 传入 title 后，exportStandaloneHTML 的 `<title>` 等于传入值 | ✅ | `D2 导出 HTML 标题`（修复前红：setTitle 不存在） |
| 深色系统模拟下 init 首帧即按 dark 初始化 mermaid（无二次重绘痕迹） | ✅（结构性） | `_init` 已改为先解析 opts 再建编辑器（见落点），DOM 主题与 mermaid.initialize 都在编辑器创建前按目标主题生效，原「light 先行 + setTheme 纠正」路径不存在；运行时守门由 `OQ-1 pluginSet 轻量模式生效` 承担（验证同一条顺序修复） |
| OQ-1 按结论执行（修复生效），MDP_PLUGINS 不再是死配置 | ✅ | 结论选 **a**（保留轻量模式能力并修复生效）；selftest 新增第二页面实例检查 `OQ-1 pluginSet 轻量模式生效`：no-diagram 档下 mermaid 围栏保持代码块、KaTeX 仍加载（修复前红：图表仍被装配） |
| 既有 selftest 全部通过；构建通过 | ✅ | 54 项 PASS，SELFTEST PASSED；`node build.mjs` + `swift build` 通过 |

## 结论落点表

| 活结论 | 落点 |
|---|---|
| D1 文档内容单一真相源：渲染模式读编辑器 doc、源码模式读 textarea，保存取回与干净基线同口径 | `web/src/main.js` `currentMarkdown()`；`mdbridge.getMarkdown()`、`mdbridge.markClean()` 均走该函数 |
| D1 衍生语义：退出源码模式时，若 textarea 内容未偏离基线，以注入后的序列化结果重设基线（源码原文与序列化产物的尾换行差异不算修改；已偏离则由 listener 按旧基线上报脏） | `web/src/main.js` `toggleSource(false)` 分支 |
| D2 导出标题来源：Swift 在 `pushInitialContent` opts 携带文件名；此后文件名变化经 `updateTitle()` 推送 `mdbridge.setTitle` 同步 web 层 document.title；无文件名时 web 层兜底 `"MDPreview"` | `Sources/MDPreview/DocumentWindowController.swift` `pushInitialContent`/`updateTitle`；`web/src/main.js` `mdbridge.setTitle()` |
| D3 `_init` 先解析 opts（theme/zoom/plugins/title）再创建编辑器；`applyMermaidTheme` 由 createEditor 按已解析主题执行一次 | `web/src/main.js` `mdbridge._init()` |
| OQ-1 定案 a：pluginSet 保留并修复生效（'full' | 'no-diagram'） | 结论回写 [open-questions.md OQ-1](../../../plan/open-questions.md)；实现见 `web/src/main.js` `_init` + `createEditor` |

## 坑记录（移交坑档案候选）

- **web 端 changed 上报经 milkdown listener 200ms debounce 异步到达**：旧事务的延迟回调可能在后续 `markClean` 之后才触发，与快速连续操作（自检序列）竞态。自检基建因此新增 `settleBridge`（桥消息静止等待，条件等待非纯睡）。存续条件：listener 的 debounce 实现仍在；对策落点：`Sources/MDPreview/Selftest.swift` `settleBridge` + 注释。

## 遗留

- `WEB-JS-ERROR: Script error.` 噪音在修复前基线即存在（index.html 的 window.onerror 对跨源脚本报无细节错误），非本序回归，不在七工序清单内，不处理。
