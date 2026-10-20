---
layer: works
module: global
status: active
updated: 2026-10-20
---

# 收口(进行中): 左侧文件抽屉(树形目录)与目录模式

## 验收结果(对照 brief 验收标准,自动化部分全绿)

1. **树形目录与过滤** ✅ — selftest 目录扫描用例 6 项(lazy 定稿后重写):根/子层
   过滤(只留可展示 md,排除 b.txt/隐藏 .hidden.md)、排序(文件夹在前)、深层
   .markdown 扩展名、符号链接不跟随、根不可读抛错、descendant 定位。
   **语义随 brief 变更 1/2 演进**:「无 md 后代目录剪枝」「枚举预算/深度上限」
   已随 eager 模式一并废弃——lazy 下暂无 md 的目录也显示(展开为空),
   node_modules/包目录在单层入口跳过。
2. **窗口宽度收敛** ✅ — drawer-test 断言:展开后窗宽 = min(1000+240, 屏幕可视宽)
   (实测 1240),收起后缩回 1000;截图复核 @2x 像素宽 2480 = 1240pt 一致。
3. **目录模式** ✅ — drawer-test:仅 1 窗、directoryMode=true、fileURL=nil、
   抽屉展开、标题=目录名、树装载行数>0;CLI 目录参数/打开文件夹 ⌘⇧O/拖入目录
   经 openInNewWindow 统一路由(LaunchServices/文档链接同样收敛)。
4. **同窗覆盖打开** ✅ — drawer-test:抽屉双击打开后 documents 仍 1 个、
   fileURL=双击目标、退出目录模式、标题=文件名;第二次打开仍同窗覆盖。
   期间发现并修复**装载中打开请求永久滞留**缺陷(见下)。
5. **锚定下拉框与重锚契约** ✅(brief 变更 3)— drawer-test 真实仓库根:
   锚点下拉框条目 = 父级链(5/5,DirectoryTree.ancestorChain 面包屑缩进);
   抽屉双击打开保持锚点不重锚、树打开子层文件保持锚点(跨多层浏览)、
   非抽屉来源打开锚点外文件重锚到文件所在目录、下拉框选回原目录条目数复原;
   pendingOpen 暂存携带 reanchor 标志;selftest 增锚点链 2 项。
6. **lazy 点击展开链路** ✅(brief 变更 4 回归断言)— drawer-test 真实仓库根:
   点击 doc/ 展开三角 → 数据源内同步装载 5 子行、design 目录出现在树中
   (真实 GUI「点目录无反应」失效路径的守门断言)。
7. **回归** ✅ — selftest 101 项全绿(93+6 目录扫描+2 锚点链,2026-10-21 复核);
   multiwindow-test 核心断言通过(2 窗口/标题不重复;「定位表格」步骤经改动前
   release 二进制对照确认为无头环境性失败,与本次改动无关);drawer-test 真实
   仓库根 2026-10-21 复核全绿(无 key window 的 ⌘O 响应链断言按设计 SKIP)。

## 过程中发现并修复的缺陷

- **pendingOpenURL 永久滞留**(真实缺陷,drawer-test 红跑暴露):打开请求在
  编辑器注入进行中(isLoadingContent)到达时被暂存,而补载只挂在 ready 桥
  消息分支——ready 仅发生一次,此后暂存请求永不补载。实测 setMarkdown
  完成回调在编辑器冷启动期可延迟 ~1.6s,该窗口期真实存在(⌘O/双击均可能
  触发)。修复:注入完成后 drainPendingOpen 立即排空,按目录/文件分派;
  openDirectory 未就绪时并入同一暂存机制。
- **真实 GUI 点目录无反应**(真实缺陷,自动化未拦住,见 risks.md R8):
  lazy 首版的三段式异步装载与 AppKit 未展开条目子层缓存时序不合,真实点击
  展开失效而 harness 全绿。修复:装载改数据源内同步(展开取数时 readdir 该层),
  演进全程见 brief 设计决策变更 1–4。

## 结论落点表

| 结论 | 落点 |
|---|---|
| 抽屉/目录模式/宽度收敛/脏确认统一/暂存排空契约 | doc/design/architecture.md §2.4「文件抽屉与目录模式」 |
| lazy 按层装载(数据源内同步 readdir,废弃异步三段式与预算截断) | doc/design/architecture.md §2.4「装载模型为 lazy 按层」+ Sources/MDPreview/FileDrawerView.swift |
| 锚定下拉框与重锚契约(ancestorChain/双击不重锚/越界重锚/pendingOpen 携带 reanchor) | doc/design/architecture.md §2.4「锚定契约」+ Sources/MDPreview/DirectoryTree.swift(ancestorChain) |
| node_modules/包目录单层跳过(纯噪音过滤) | doc/design/architecture.md §2.4 跳过规则 + Sources/MDPreview/DirectoryTree.swift |
| 目录扫描与过滤单点(扩展名单源复用 markdownExtensions) | Sources/MDPreview/DirectoryTree.swift |
| 抽屉 UI 与刷新/选中/双击回调契约 | Sources/MDPreview/FileDrawerView.swift |
| 开合动画与窗口宽度收敛、目录模式、openDocument 统一 | Sources/MDPreview/DocumentWindowController.swift |
| 目录入参收敛路由/菜单 | Sources/MDPreview/AppDelegate.swift |
| 用户可见行为/已知边界(240pt 固定宽、手动刷新、目录模式可编辑) | 仓库根 README.md |
| 「打开最近使用」当前窗口打开(独立提交) | AppDelegate.openInCurrentWindowOrNew + README 多窗口条目 |

## 待人工实证(自动化无法覆盖)

1. **脏文档覆盖打开的确认 sheet**:双击树中文件/⌘O 时若当前文档有修改,
   弹「保存/取消/不保存」;保存后覆盖打开;取消留在原文档。(复用关闭确认
   同一 beginConfirmClose 路径,逻辑已由既有用例覆盖,交互需真人点验)
2. **⌘\\ 开合动画与窗口伸出/收敛的观感**(无头环境无 key window,响应链
   断言与动画需真机会话)。
3. **树形图标/深浅色观感**:截图 /tmp/drawer-shot.png(深色主题,抽屉区域
   内容方差显著)可复核。
