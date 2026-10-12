---
layer: history
module: global
status: frozen
updated: 2026-10-14
---

# 坑档案

每条坑三个必填字段：现象、存续条件、对策落点。已消失的坑标注实证日期，条目保留防复发。

## P1 milkdown markdownUpdated 经 200ms debounce 异步到达，防抖窗内回调携带中间态

- **现象**：milkdown listener 插件对每次 docChanged 事务各建一个 lodash.debounce(200ms)
  定时器，flush 时序列化的是**事务捕获时的 doc**；并发编辑（如"编辑后立即打开新文件"）
  会产生携带过期内容的迟到回调。消费方若拿它当"当前内容"，会出现打开文件即报脏、
  保存基线错乱（D1-b 误报，实证 2026-10-12）。
- **存续条件**：仍在。该机制是 milkdown 7.7 的固有行为，升级或替换 listener 机制前持续存在。
- **对策落点**：
  - web 侧单一脏机制：基线由 `setMarkdown`/`markClean` **同步**落定，listener 回调先做
    过期过滤（`markdown === currentMarkdown()`）再报 dirty——`web/src/editor.js`、
    `web/src/bridge.js`（W5-T3，实证 2026-10-14）；
  - 测试侧断言前用"桥消息静止"窗口（`Selftest.settleBridge`，连续 quiet 秒无新上报）
    排空旧事务尾窗，杜绝"断言跑在迟到回调前面"；
  - 机制说明沉淀于 design/architecture.md §4。
