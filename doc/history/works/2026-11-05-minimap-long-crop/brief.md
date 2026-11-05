---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 工序 brief：长文缩略图固定宽度裁切（P2）

## 1. 问题

2026-11-05 用户反馈：文档很长时，缩略图严格按高度 fit，页面宽度被压到远低于 120px，右侧出现大面积空白，内容变成不可读的窄条。截图见用户附件；`CMP-kernel-minimap` 当前只输出 `mode=fit`。

## 2. 决策

用户确认采用：

- fit 后页面宽度低于 **120px** 时切固定宽度裁切模式（`crop`）：`scale = 120 / pageWidth`，页面宽 120px，高度允许超过轨道。
- 轨道纵向裁切，页面按 `panTop` 平移；视口框在轨道里的位置与整篇滚动进度同步，顶部/底部分别对齐文档开头/结尾。
- 拖动对象是**蓝色视口框**；fit 按页面缩略高度 `contentHeight/docHeight` 换算；crop 把视口框当作整篇滚动条滑块，按 `railHeight - boxHeight` 1:1 跟手。
- 拖到轨道顶/底时直接夹到 `scrollTop=0` / `max`，保证“鼠标到底部看到最底部”。
- 短文档仍走原 `fit`，不改变已有总览体验。

## 3. 影响与契约

- 只改 `CMP-kernel-minimap` 内部几何与交互；`CMP-minimap` 用户行为同步。
- `minimapInfo.mode` 从 `fit|none` 扩为 `fit|crop|none`；新增 `panTop`、`panRange`。
- `contentTop` 在 crop 模式为负的页面平移量；`contentHeight` 为缩放后的整页高度，可大于轨道。
- 不改 source 契约（`{root, measure, scrollTo, snapshot}`）、host op 数量、Swift 偏好协议、快照脱敏。
- 不受影响：正文/代码渲染、查找、导出、主题、抽屉、双窗口。

## 4. 任务

| ID | 任务 | 状态 |
|---|---|---|
| T1 | `thumbnail.js` 增加 `fit/crop` 双模式 | 完成 |
| T2 | `viewport.js` 增加 `cropPanTop`，允许负 `contentTop`/超轨道 `contentHeight` | 完成 |
| T3 | `minimap.js` 接入 stage 平移、整篇进度视口、1:1 拖动与顶底夹取 | 完成 |
| T4 | Node 几何/集成测试（含 1:1 跟手）、selftest 断言放宽到 `fit|crop` | 完成 |
| T5 | REQ/SCN/组件规格/README 同步 | 完成 |
| T6 | 真机长文视觉与拖拽手感复核 | 完成；2026-11-05 用户确认好用 |

## 5. 验收

- 自动：`npm run verify` 全绿；新增长文 120px 裁切、`panTop` 平移、拖视口框顶底对齐用例。
- 自动：`--selftest` 通过，默认显示允许 `fit|crop`，短文档仍为 `fit`。
- 人工：长文轨道宽度保持约 120px；页面随正文滚动平移；拖视口框到顶/底与文档开头/结尾对齐，跟手不粘。
- 非目标：横向拖动、缩略图内编辑/选择、改变 120px 栏宽、Canvas 回退。
