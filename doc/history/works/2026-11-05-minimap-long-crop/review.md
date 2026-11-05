---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 复审：长文缩略图裁切与视口跟随（P2）

> 对应 [brief.md](brief.md) / [result.md](result.md)；需求 [REQ-0011](../../../requirements/REQ-0011-document-minimap.md)；场景 [SCN-0017](../../../design/scenarios/navigation/in-document/minimap-navigation/scenario.md)；组件 [CMP-minimap](../../../design/components/CMP-minimap/spec.md) / [CMP-kernel-minimap](../../../design/components/CMP-kernel-minimap/spec.md)。

## 1. 复审范围

- 长文 fit 后宽度不足 120px 的固定宽裁切。
- 裁切画面的纵向平移、视口框位置、滚动条进度一致性。
- 拖动视口框的指针跟随、顶底夹取、短文 fit 回归。
- `minimapInfo` 新字段与既有 source/host op 契约兼容性。
- 真机长文视觉与触控板手感。

## 2. 四档裁决

### Blocker

无。

### Decision now

| 决策 | 选择 | 代价/被否方案 |
|---|---|---|
| 长文阈值 | fit 后宽度 `< 120px` 转 `crop`，固定 120px 宽、纵向裁切 | 长文不再看到整页全貌；被否：继续压窄整页（不可读） |
| 纵向映射 | `panTop = progress × (contentHeight − railHeight)`；视口框顶 = `progress × (railHeight − boxHeight)` | 内容会按整篇进度走，比逐页拖动快；被否：视口框居中（中段拖不动） |
| 拖动 | crop 按 `railHeight − boxHeight` 1:1 跟手；fit 保持按页面缩略高度 | 两套映射；被否：统一按页面高度（中段不同步） |
| 交互边界 | 点击仍按页面内容矩形定位；拖动只改视口框 Y | 点击不是滚动条式跳转；被否：同时改点击会破坏页面内容定位 |
| 协议 | 只扩 `minimapInfo` 的 `mode/panTop/panRange`；不改 source 契约、不加 host op | 诊断字段增加；被否：为裁切新增原生接口（无必要） |

### Verified sound

| 区域 | 证据 |
|---|---|
| 长文几何 | `minimap.test.js` 800x10000 → 120x1500；`cropPanTop` 中段/顶部/底部 |
| 指针跟手 | surface 测试拖 100px，视口框移动 100px；到底 `panTop=732`；回顶 0 |
| 短文回归 | `fit` 用例与 `--selftest` 默认显示通过，轨道内内容矩形不变 |
| 真机视觉 | 20 段长文截图：顶部/底部页面与轨道对齐，宽度约 120px |
| 自动门 | `npm run verify` 86/86；`check-kernel` 43 文件；`./build.sh debug`；`--selftest` |
| 用户验收 | 2026-11-05 用户确认“非常好用”，同意提交推送 |

### Hold

| 事项 | 为什么不阻塞 | 去向 |
|---|---|---|
| 极长文档快照耗时 | 当前几何与交互正确；快照预算仍是既有性能观察项 | 继续按 `CMP-kernel-minimap` 性能债观察 |
| 点击的滚动条式进度 | 本次只修拖动跟手；点击仍保持页面内容定位，避免改变既有语义 | 若用户要求，另立交互决策 |
| 触控板惯性/深色主题 | 自动门覆盖几何；真实手感属 R8 人工项 | 用户已在浅色长文确认，其余按既有验证债 |

## 3. Breaking change 审查

- `minimapInfo.mode` 从 `fit|none` 扩为 `fit|crop|none`，新增 `panTop`/`panRange`，为加法扩展。
- `contentTop` 在 crop 模式可为负；调用方不得再假设它恒为 0。
- source `{root, measure, scrollTo, snapshot}`、host op 数量、Swift 偏好协议均不变。
- `fit` 模式的几何、点击与拖动语义保持不变。

## 4. 结论

**最终门通过。** 长文裁切与视口跟随已实现、自动门与用户真机验收均通过；本工序 `closed` 并归档到 `history/works/`，SCN-0017 的 TC-MINI-008 记为已确认。
