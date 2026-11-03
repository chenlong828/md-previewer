---
layer: history
module: global
status: frozen
updated: 2026-11-04
---

# 工序 brief：App 图标自有化（MP 字标）

## 需求

把当前直接取自 `reference/Typora.app` 的图标换成 MDPreview 自己的字标：macOS 圆角方形、
界面同款系统字体（SF Pro）排「MP」，用户选定 **B 方向**——纸白底、M 墨黑、P 取界面链接蓝
`#4183c4`。目标尺寸覆盖 16–1024px，并保留可复现的生成脚本，后续微调改一处即可重出。

## 背景

- 现 `resources/AppIcon.icns` 抄自 Typora 参考包，既是他人品牌资产，也和本应用无关。
- 应用正文/界面字体为 `-apple-system`（SF Pro），字标沿用同一字体即可与 UI 同气质。
- 现 icns 只含 16/32/128/256 四档，缺少 512/1024，Retina 大图标会模糊。

## 目标 / 非目标

- **目标**：icns 含 10 个标准尺寸（16–1024，含 @2x）；生成脚本入库；应用包与 Dock 显示新图标。
- **非目标**：不改应用名、About 文案、窗口标题；不做深浅色双图标；不动前端资源与 favicon。

## 验收标准

1. `resources/AppIcon.icns` 经 `iconutil -c iconset` 往返后包含 16/32/64/128/256/512/1024 全部尺寸，
   且 1024 图为 `MP` 字标（白底、M 墨黑、P 蓝）。
2. 运行 `./build.sh release` 后，`dist/MDPreview.app/Contents/Resources/AppIcon.icns` 与
   `resources/AppIcon.icns` 字节一致；Info.plist 的 `CFBundleIconFile` 仍指向 AppIcon。
3. 16/32/64/128 小尺寸逐一目检：无接缝/脏边，字母光学居中；16px 允许糊但轮廓仍可辨。

## 设计口径（B 方向定稿）

| 项 | 值 |
|---|---|
| 画布 / 留白 | 1024 / 60（内容 904） |
| 圆角 | 内容宽 × 0.225 |
| 底 | `#FFFFFF → #F2F2F3` 垂直微渐变 + 顶部柔光 + 1px 内描边（黑 5%） |
| 字 | SF Pro Heavy（`NSFont.systemFont(weight: .heavy)`），字号 430/1024，字距 -0.035em |
| 颜色 | M `#2B2B2D`，P `#4183C4`（与 `--link-color` 同值） |

## 风险 / 已知取舍

- 16px 下「MP」两字母必然粘连（属正常现象，Finder 列表仍以文件名为主）。
- 白底图标在浅色桌面上依赖 1px 内描边与系统投影区分边界，已加描边兜底。
