---
layer: works
module: global
status: closed
updated: 2026-11-02
---

# 工序结果：App 图标自有化（MP 字标）

## 交付

| 落点 | 内容 |
|---|---|
| `resources/AppIcon.icns` | 新图标，10 档标准尺寸 16–1024（含 @2x），313 KB |
| `resources/icon/render-icon.swift` | 生成器：AppKit 逐尺寸矢量渲染 + `iconutil` 打包；设计口径写在头注释 |
| `README.md` | 目录结构行由「取自 reference/Typora.app」改为「MP 字标，由 render-icon.swift 生成」 |
| `doc/plan/roadmap.md` | 本工序登记为已完成（待归档） |

`build.sh` 与 `Info.plist` 无需改动：前者原本就复制 `resources/AppIcon.icns`，后者的
`CFBundleIconFile` 仍为 `AppIcon`。

## 设计定稿（B 方向）

| 项 | 值 |
|---|---|
| 画布 / 留白 | 1024 / 60（内容 904，与旧 Typora 图标的 0.88 占比一致） |
| 圆角 | 内容宽 × 0.225 |
| 底 | 纸白 `#FFFFFF → #F2F2F3` 微渐变 + 顶部柔光 + 1px 黑 5% 内描边 |
| 字 | SF Pro Heavy（界面同款 `-apple-system`），字号 430/1024，字距 -0.035em |
| 颜色 | M `#2B2B2D`；P `#4183C4`（与 `--link-color` 同值） |

渲染方式：每个尺寸按矢量几何**原生渲染**，而不是从 1024 缩放——实测 16/32px 明显更清晰。

## 验收

1. **icns 结构**：`iconutil -c iconset` 往返成功，得到 10 个条目：
   `16x16`、`16x16@2x(32)`、`32x32`、`32x32@2x(64)`、`128x128`、`128x128@2x(256)`、
   `256x256`、`256x256@2x(512)`、`512x512`、`512x512@2x(1024)`；
   1024 图为白底 MP 字标（M 墨黑 / P 蓝）。
2. **应用包**：`./build.sh release` 通过（web 构建 + Swift release + 组装 + ad-hoc 签名）。
   `dist/MDPreview.app/Contents/Resources/AppIcon.icns` 与 `resources/AppIcon.icns`
   MD5 均为 `bfb299abb2a198631d16c1ae362f15bf`；`CFBundleIconFile=AppIcon`；
   `codesign --verify --deep --strict` OK；包内 `--selftest` 全绿（SELFTEST PASSED）。
3. **系统取图**：`NSWorkspace.icon(forFile:)` 读取 bundle 图标渲染正常
   （`preview/finder-512.png`，即 Finder/Quick Look 所见），确认不是缓存旧图。
4. **小尺寸目检**：16 / 32 / 64 / 128px 逐档查看（`preview/final-sizes.png`）：
   圆角、描边无接缝；字母按 cap height 光学居中；16px 两字母粘连属预期，
   32px 起可辨「MP」。

## 验收三件套核对

- **目标**：自有 MP 字标替换 Typora 借图，覆盖 16–1024 全部尺寸，生成过程可复现 ✅
- **非目标**：未改应用名 / About 文案 / 窗口标题；未做深浅色双图标；未动前端与 favicon ✅
- **验收场景**：1) icns 10 档齐全 ✅；2) release 包图标字节一致且签名有效 ✅；
  3) 16–128px 目检无脏边、居中正确 ✅

## 结论落点表

| 结论 | 落点 |
|---|---|
| 图标几何、配色、字重、字距的唯一真源 | `resources/icon/render-icon.swift` 头注释 |
| 重新生成方式（一条命令） | 脚本头注释用法；`README.md` 目录结构指路 |
| 图标已成为应用品牌资产、不再引用参考包 | `README.md` 目录结构 |
| 工序状态 | `doc/plan/roadmap.md` 工序总览 |

不新增 `doc/design/` 文档：图标是单文件构建资产，无跨模块契约与运行时行为，
把口径放在生成脚本头注释可避免「一处一事」被文档复制破坏。

## 遗留

- 待用户确认后归档：`doc/works/2026-11-02-app-icon/` → `doc/history/works/`，
  frontmatter 改 `layer: history` / `status: frozen`，目录名不变。
- 若后续想要深色 / 实心 / 无底等变体，改脚本顶部常量重跑即可，不影响应用逻辑。
- `dist/MDPreview.zip` 为 10-27 的旧打包产物（gitignored），本次未重压；需要分发时再打包。
