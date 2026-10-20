---
layer: works
module: global
status: active
updated: 2026-10-20
---

# 收口(进行中): 左侧文件抽屉(树形目录)与目录模式

## 验收结果(对照 brief 验收标准,自动化部分全绿)

1. **树形目录与过滤** ✅ — selftest 新增 6 项目录扫描用例:根/子层过滤
   (只留可展示 md,排除 b.txt/隐藏 .hidden.md)、排序(文件夹在前)、
   深层 .markdown 扩展名、无 md 后代目录剪枝、符号链接不跟随、深度上限
   (浅层保留深层截断)、根不可读抛错、descendant 定位。
2. **窗口宽度收敛** ✅ — drawer-test 断言:展开后窗宽 = min(1000+240, 屏幕可视宽)
   (实测 1240),收起后缩回 1000;截图复核 @2x 像素宽 2480 = 1240pt 一致。
3. **目录模式** ✅ — drawer-test:仅 1 窗、directoryMode=true、fileURL=nil、
   抽屉展开、标题=目录名、树装载 2 行;CLI 目录参数/打开文件夹 ⌘⇧O/拖入目录
   经 openInNewWindow 统一路由(LaunchServices/文档链接同样收敛)。
4. **同窗覆盖打开** ✅ — drawer-test:抽屉双击打开后 documents 仍 1 个、
   fileURL=双击目标、退出目录模式、标题=文件名;第二次打开仍同窗覆盖。
   期间发现并修复**装载中打开请求永久滞留**缺陷(见下)。
5. **回归** ✅ — selftest 99 项全绿(93+6);multiwindow-test 核心断言通过
   (2 窗口/标题不重复;「定位表格」步骤经改动前 release 二进制对照确认为
   无头环境性失败,与本次改动无关)。

## 过程中发现并修复的缺陷

- **pendingOpenURL 永久滞留**(真实缺陷,drawer-test 红跑暴露):打开请求在
  编辑器注入进行中(isLoadingContent)到达时被暂存,而补载只挂在 ready 桥
  消息分支——ready 仅发生一次,此后暂存请求永不补载。实测 setMarkdown
  完成回调在编辑器冷启动期可延迟 ~1.6s,该窗口期真实存在(⌘O/双击均可能
  触发)。修复:注入完成后 drainPendingOpen 立即排空,按目录/文件分派;
  openDirectory 未就绪时并入同一暂存机制。

## 结论落点表

| 结论 | 落点 |
|---|---|
| 抽屉/目录模式/宽度收敛/脏确认统一/暂存排空契约 | doc/design/architecture.md §2.4「文件抽屉与目录模式」 |
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
