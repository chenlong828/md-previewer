---
layer: plan
module: global
status: current
updated: 2026-11-10
---

# 技术债修复路线图

来源：2026-10-12 全仓库只读技术债审计（Swift 壳 + Milkdown 前端，共 40 项发现）。
发现不在此处复制——每项发现只登记在唯一承接它的工序 brief 里（一处一事）；
本文件只维护批次、优先级、依赖与工程量。2026-10-20 起功能开发工序也在本表登记
（优先级列标「功能」，技术债 P0–P3 编号仅用于审计批次）。

## 工序总览

技术债审计批次（W1–W7）全部完成，2026-10-14 收口归档至 history/works/；
2026-10-20 起为功能工序。

| 工序 | 主题 | 优先级 | 工程量 | 依赖 | 状态 |
|---|---|---|---|---|---|
| [2026-10-12-fix-latent-defects](../history/works/2026-10-12-fix-latent-defects/brief.md) | 3 个疑似缺陷（正确性） | P0 | M | 无 | ✅ 已完成 |
| [2026-10-12-remove-dead-code](../history/works/2026-10-12-remove-dead-code/brief.md) | 死代码与不可达分支清理 | P1 | S | 建议在 W1 后（同文件区域） | ✅ 已完成 |
| [2026-10-12-consolidate-duplication](../history/works/2026-10-12-consolidate-duplication/brief.md) | 重复知识与重复实现收敛 | P1 | M | W2（先删死再合并，避免合并死物） | ✅ 已完成 |
| [2026-10-12-structure-governance](../history/works/2026-10-12-structure-governance/brief.md) | main.js 拆分 + 菜单构建表驱动 + lint | P2 | L | W1–W3（内容变更稳定后再动结构） | ✅ 已完成 |
| [2026-10-12-timing-contracts](../history/works/2026-10-12-timing-contracts/brief.md) | 时序耦合与魔法延时治理 | P2 | L | W3（同在 DocumentWindowController 密集改动） | ✅ 已完成 |
| [2026-10-12-deps-and-build](../history/works/2026-10-12-deps-and-build/brief.md) | 依赖、构建与许可卫生 | P3 | S–M | 无硬依赖 | ✅ 已完成 |
| [2026-10-12-tests-and-security-doc](../history/works/2026-10-12-tests-and-security-doc/brief.md) | 自检可靠性 + 安全取舍显式化 | P3 | M | 无硬依赖，建议收尾 | ✅ 已完成 |
| [2026-10-20-image-support](../history/works/2026-10-20-image-support/brief.md) | 图片支持（相对路径显示/源码编辑块/粘贴拖放导入落盘） | 功能 | M | 无 | ✅ 已完成（已归档） |
| [2026-10-20-image-cleanup](../history/works/2026-10-20-image-cleanup/brief.md) | 图片资源生命周期（撤销不残留、关闭统一 GC 清理） | 功能 | S | 图片支持 | ✅ 已完成（已归档） |
| [2026-10-20-file-drawer](../works/2026-10-20-file-drawer/brief.md) | 文件抽屉与目录模式（lazy 按层装载、锚定下拉框、同窗覆盖打开） | 功能 | L | 无 | 🔄 收口中（自动化全绿，待人工实证） |
| [2026-10-21-portable-kernel](../history/works/2026-10-21-portable-kernel/brief.md) | 可移植内核与壳契约（桥协议 v2、路径语义入内核；评审有条件通过，决策 D1–D5） | 功能 | M–L | 无 | ⏸ 暂缓（评审+规格已归档，零实施；已由 2026-11-04-kernel-v2 接力） |
| [2026-10-22-doc-split](../works/2026-10-22-doc-split/brief.md) | design 文档按读者下沉（architecture.md 拆出 image/drawer/诊断面） | 文档 | S | 无 | 🔄 执行中（五态迁移后范围待重定；§2.1/§2.4 与收口待做） |
| [2026-10-24-list-indent-four-space](../history/works/2026-10-24-list-indent-four-space/brief.md) | 列表 Tab 嵌套的 markdown 缩进（2 空格 → 标准 4 空格，首行标记不补齐） | 缺陷 | S | 无 | ✅ 已完成（已归档） |
| [2026-10-24-code-token-palette](../history/works/2026-10-24-code-token-palette/brief.md) | 代码高亮 token 调色板自有化（浅/深双值单规则，移除 Prism 浅色整主题与 prismjs 依赖） | 缺陷/重构 | S | 无 | ✅ 已完成（已归档） |
| [2026-11-02-app-icon](../history/works/2026-11-02-app-icon/brief.md) | App 图标自有化（MP 字标替换 Typora 借图，16–1024 全尺寸 + 生成脚本） | 功能/视觉 | S | 无 | ✅ 已完成（已归档） |
| [2026-11-04-scenario-inventory](../works/2026-11-04-scenario-inventory/brief.md) | 已实现场景/组件清点（7 组件、10 REQ、16 场景；REQ 验证后转） | 文档 | M | 五态迁移 | 🔄 收口中（卡片已落，3+1 复核待做） |
| [2026-11-04-code-file-view](../history/works/2026-11-04-code-file-view/brief.md) | 代码文件只读查看 + 高亮语言切换（新组件 CMP-code-view；44 语言；6 入口面） | 功能 | M–L | 无 | ✅ 已完成（已归档；117 项 + 人工核对通过） |
| [2026-11-04-code-view-line-numbers](../history/works/2026-11-04-code-view-line-numbers/brief.md) | 代码视图行号与按行阅读（逻辑行结构、行号、软换行、当前行、全局开关） | 功能/P2 | S–M | 代码文件查看 | ✅ 已完成（已归档；121 项 + 人工核对通过） |
| [2026-11-04-document-minimap](../history/works/2026-11-04-document-minimap/brief.md) | 右侧文档缩略图与定位（新组件 CMP-minimap / CMP-kernel-minimap；Markdown + 代码；真缩略图 DOM 快照 + 顶左 fit；菜单开关） | 功能/P1 | M–L | 代码文件查看；kernel-v2 七组件结构 | ✅ 已完成（已归档；85 项 + selftest + 用户验收通过） |
| [2026-11-05-minimap-long-crop](../history/works/2026-11-05-minimap-long-crop/brief.md) | 长文缩略图固定 120px 宽裁切（fit 宽度不足时裁切；视口框按整篇进度 1:1 跟手、顶底对齐） | 缺陷/P2 | S | 2026-11-04-document-minimap | ✅ 已完成（已归档；86 项 + 用户确认手感） |
| [2026-11-05-copy-file-path](../history/works/2026-11-05-copy-file-path/brief.md) | 文档右键菜单「拷贝文件路径到剪贴板」（复用 EditorCommands 注册表；未保存/目录模式隐藏） | 功能/P3 | S | 无 | ✅ 已完成（已归档；selftest 注册表 + multiwindow 4 项 + dist 构建 + 用户验收通过） |
| [2026-11-06-reveal-in-finder](../history/works/2026-11-06-reveal-in-finder/brief.md) | 文档右键菜单「用 Finder 打开到指定位置」（复用文件菜单既有 revealInFinderAction；不写文件） | 功能/P3 | S | 2026-11-05-copy-file-path | ✅ 已完成（已归档；selftest + multiwindow 5 项 + 复用既有命令） |
| [2026-11-04-kernel-v2](../history/works/2026-11-04-kernel-v2/brief.md) | 可移植内核与桥协议 v2 落地（transport/contract/semantics/core 四层 + macOS 壳 v1→v2 一次切换；Windows 参照物） | 功能/架构 P1 | L | 存档规格 + 本次增量 | ✅ 完成并归档（2026-11-04；Node 78 项 + selftest 115 PASS；R9 关闭） |
| [2026-11-10-table-row-context-menu](../history/works/2026-11-10-table-row-context-menu/brief.md) | 表格行列操作右键定位（flipped WKWebView 页面坐标修正、caret 跟随插入；新增 `--context-menu-test`） | 缺陷/P2 | S | 无 | ✅ 已完成（已归档；`--context-menu-test` 12 项 + selftest 129 + 用户 2026-11-10 真机验收） |

## 批次与依赖链

```
批次一（P0 正确性）      W1
批次二（P1 减法收敛）    W2 ──→ W3
批次三（P2 结构时序）    W4、W5（W3 后可并行；W4 动 web/src/main.js，W5 动 Sources/，文件不相交）
批次四（P3 卫生收尾）    W6、W7（随时可插入；建议最后统一收口）
```

执行纪律：

- 每个工序收口时写 `result.md`，结论落点表登记每条活结论去向；归档前置条件是收口。
- W1 修复前先在 selftest 写出可复现断言（红→绿），防止"修了但没守住"。
- 三个疑似缺陷的定性见 [risks.md](risks.md)；跨工序决策见 [open-questions.md](open-questions.md)。

