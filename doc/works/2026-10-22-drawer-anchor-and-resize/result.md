---
layer: works
module: global
status: active
updated: 2026-10-22
---

# 收口: 抽屉锚点控件改版与宽度拖拽调整

## 验收结果(对照 brief 场景)

1. **锚点控件(场景 1)** ✅ — drawer-test:
   - 「锚点下拉框条目=父级链(5/5)」:条目集合与既有重锚契约不回归;
   - 「锚点菜单每条都带 Finder 文件夹图标」:`FinderIcon` 按真实路径取系统图标
     (桌面/文稿/Home/卷各有与 Finder 相同的图标),树与菜单共用同一单点;
   - 头部宽度账四条 + 一条总账全绿(按**对齐矩形**断言,避开 NSButton 的
     alignmentRectInsets 半像素差):控件贴左缘 0、右缘 = Home 左缘 − 4、
     Home 右缘 = 刷新左缘 − 4、刷新贴右缘 234(抽屉 240)、
     控件宽 = 240 − 22 − 22 − 8 − 6 = 182;
   - 菜单为「根 → 当前的平坦父级链 + 当前项勾选」(Finder 标题栏路径菜单同构),
     取代旧的面包屑缩进;选中经 `onAnchorSelected` 同一路径重锚。
2. **Home 按钮(场景 1 补充)** ✅ — drawer-test:「Home 按钮重锚到 Home 目录」、
   「Home 锚点菜单=Home 父级链(3/3)」、「已在 Home 时 Home 按钮置灰」。
3. **边界拖拽(场景 2)** ✅ — drawer-test 五条:拖 +80 → 320;窗口宽度不变(1240);
   抽屉视图宽 = 拖拽宽度;拖 +5000 夹到上界 480;拖回默认 240;
   `fileDrawerWidth` 落盘。另加**命中测试**:边界处的点击落在
   `DrawerResizeDivider` 上(不被 webView 吃掉)。真实 `sendEvent` 拖动在本机
   无头环境拿不到 key window,首次点击按 AppKit 语义被激活逻辑吞掉,故 SKIP
   (与既有「⌘O 响应链断言」同一环境限制),拖动数学经由与真实回调同一入口的
   `simulateDrawerResizeForDiagnostics` 覆盖。
4. **宽度记忆(场景 3)** ✅ — 收起后窗宽 = 收起前 − **当前**抽屉宽度(240 → 1000),
   展开按 `fileDrawerWidth` 复原;越界/缺失回落默认 240(`rememberedWidth`)。
5. **回归** ✅ — selftest 全绿(101 项,PASSED);release 构建通过并组装
   `dist/MDPreview.app`;release 二进制跑同一 drawer-test 全绿。
   `--multiwindow-test`:窗口数/标题不重复通过;「定位表格」两步仍为既有
   **无头环境性失败**(2026-10-21 已用改动前 release 二进制对照确认与抽屉无关),
   本次未触碰编辑器/焦点/selinfo 路径。

## 视觉核验(模型侧无法读图,改用像素探针核对几何与层次)

用临时 `--drawer-snapshot` 入口(已移除)把窗口内容渲染为 PNG,按 2x 采样:

| 项目 | 亮色 | 深色 | 窄抽屉 160pt |
|---|---|---|---|
| 药丸填充 vs 头部底 | 234 vs 253(Δ19) | 74 vs 60(Δ14) | 234 vs 253 |
| 药丸范围 | x 6→175.5,y 5→26.5(高 21.5) | 同左 | x 6→95.5 |
| 头部文件夹图标列 | 26→40(与树内图标 26 同列) | 同左 | 26→40 |
| 展开箭头 | x 159→166,y 10→20(贴药丸右缘) | 同左 | 贴药丸右缘 |
| Home / 刷新按钮 | 186→208 / 212→234(= 240−6) | 同左 | 106→128 / 132→154 |
| 分界线 | 1pt,亮色 216(两侧 240/255) | 亮线 61/64(两侧 40/43) | 随抽屉右缘 |

结论:控件不做固有宽度(旧 borderless 弹窗只包住文字的问题消失)、图标列与树对齐、
箭头不随名称长度漂移、按钮组贴右缘;明暗两种外观下药丸都有可见但克制的层次。

## 过程中发现并修正

- **`NSResponder.menu` 命名冲突**:控件内 `private let menu = NSMenu()` 触发
  「cannot override mutable property 'menu'」编译错误,改名 `anchorMenu`。
- **断言口径:frame vs 对齐矩形**:按钮 frame 含 `alignmentRectInsets`,按 frame
  断言会差 0.5pt 导致三条假 FAIL;改为按约束求解所用的对齐矩形断言后精确通过
  (不是放宽容差掩盖)。
- **Home 位置定稿**:左侧是「身份位」(图标须与树图标同列、名称贴左缘)、右侧是
  「动作位」;Home 与刷新同属无状态动作,故放右侧(详见 brief「已确认决策」)。
- **按钮间距 2pt → 4pt**:Home 换根有观感代价,不与刷新挤在一起;并把两个按钮
  热区从内在宽度(约 16.5pt)补到 22pt。

## 结论落点表

| 结论 | 落点 |
|---|---|
| 锚点控件契约(全宽铺满减按钮/菜单=根→当前+勾选/FinderIcon 单点) | doc/design/architecture.md §2.4「锚定契约」+ Sources/MDPreview/DrawerAnchorControl.swift |
| Home 按钮回到 Home(同一 onAnchorSelected 路径,已在 Home 置灰) | doc/design/architecture.md §2.4「锚定契约」+ Sources/MDPreview/FileDrawerView.swift |
| 抽屉宽度可拖拽(热区/夹取 160–480 且正文≥320/不动窗口宽/fileDrawerWidth 记忆) | doc/design/architecture.md §2.4「抽屉宽度可拖拽契约」+ Sources/MDPreview/DrawerResizeDivider.swift + DocumentWindowController.swift |
| 与 Finder 一致的图标口径(树与菜单共用) | Sources/MDPreview/FinderIcon.swift |
| 头部宽度账与菜单图标的自检守门 | Sources/MDPreview/main.swift(--drawer-test) |

## 已知边界(本次不回填)

- 不做「双击分界线复位默认宽度」;抽屉收起时边界不可拖(分隔条同隐);
  拖拽不下调窗口宽度(与开合的「向外伸出」语义分开)。
- 真实 `sendEvent` 拖动断言依赖 key window,无头环境 SKIP(命中测试与回调数学已覆盖)。
