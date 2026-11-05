---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 结果：长文缩略图固定宽度裁切

## 1. 结论

- 长文 fit 后宽度不足 120px 时，`fitThumbnail` 返回 `crop`：固定 120px 宽，页面高度允许超过轨道。
- `cropPanTop` 按整篇滚动进度线性计算纵向平移；视口框顶 = 进度 × (轨道高 − 框高)，顶部/底部严格对齐；`stage.top` 承担平移。
- crop 拖动把视口框当作整篇滚动条滑块，指针与视口框 1:1 跟手；指针到轨道顶/底分别夹到文档开头/结尾。
- 短文档仍走 `fit`，原有总览、点击和拖动语义不变。
- 自动门已过；2026-11-05 用户真机确认长文视口 1:1 跟手、顶底对齐，同意提交推送。

## 2. 验证

- `cd web && npm run verify`：86 项通过；`check-kernel` 43 个文件。
- 新增测试：
  - `fitThumbnail` 长文 `crop` 几何：800x10000 → 120x1500。
  - `cropPanTop` 中部按整篇进度平移（4500/9000 → 1250），底部 2500，顶部 0。
  - crop 几何：负 `contentTop`、`railTop`；`scrollTopForThumbDrag` 指针位移 1:1 映射轨道进度。
  - surface：长文 `mode=crop`、初始 120px 宽、滚动后 `panTop≈398`、拖 100px 视口框移动 100px、拖到轨道底 `panTop=732`、拖回顶部 0。
- `./build.sh debug` 通过；`--selftest` 缩略图断言通过（示例文档为 `fit`, 轨道 120x800）。
- 视觉截图（20 段长文，本地 `.build`）：顶部 `.build/minimap-20-rail-right.png` 页面顶边/视口框对齐轨道顶；底部 `.build/minimap-20-bottom-right.png` 页面底边/视口框对齐轨道底；缩略页宽约 120px。

## 3. 收口

- 用户 2026-11-05 确认长文拖拽手感，同意提交推送。
- 本工序 `closed`，归档到 `history/works/`；SCN-0017 的 TC-MINI-008 同步转为已确认。
