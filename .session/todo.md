# 技术债修复 · 会话子任务板(2026-10-12)
来源: doc/plan/roadmap.md 七工序;一个修改点一项。状态: [ ] 待办 [~] 进行中 [x] 完成

全部完成(2026-10-14),工序目录已归档至 doc/history/works/。

## W1 fix-latent-defects(P0)
- [x] W1-D1 单一真相源: getMarkdown/markClean/setMarkdown/source-input 源码模式口径统一 + selftest 红绿守门
- [x] W1-D2 导出 HTML 标题接文件名: pushInitialContent 传名 + mdbridge.setTitle + updateTitle 同步
- [x] W1-D3 _init 先解析 opts 再建编辑器; OQ-1 定案 a: pluginSet 生效
- [x] W1-收口 边界验证(build+build+selftest) → result.md → brief closed

## W2 remove-dead-code(P1,14 处)
- [x] W2-S1 删死常量 markdownExtensions (DocWC:31)
- [x] W2-S2 删 savedEncodingName 三处赋值; OQ-2 定案 a: README 已知边界补 UTF-8 承诺
- [x] W2-S3 删 debugSummary() (DocWC:18)
- [x] W2-S4 删 setSourceModeCached() (DocWC:764)
- [x] W2-S5 删 Util.pathPart/titlePart (:92-104)
- [x] W2-S6 删 append(contextTarget:) 死参数 (EditorCommands:91)
- [x] W2-S7 删 Selftest 死消息 op:'jslog' (:216)
- [x] W2-J1 删死导入 editorStateCtx/callCommand/insertHardbreakCommand
- [x] W2-J2 删空 input 监听 (main.js:217-219)
- [x] W2-J3 删未用变量 table (main.js:506)
- [x] W2-J4 删注册表幻影命令×8 及失效导入
- [x] W2-J5 删无人调用桥 API: getTheme/getZoomInfo/debugParse/debugView/debugState
- [x] W2-J6 findInfo() 统一数字口径(-1=未就绪)
- [x] W2-收口 grep 验证无悬挂引用 + 构建 + selftest + bundle 体积 → result.md

## W3 consolidate-duplication(P1,9 处)
- [x] W3-K1 扩展名清单收敛: AppDelegate 唯一来源 + EditorWebView 引用 + plist 注释/断言(txt 取舍定案)
- [x] W3-K2 桥命令名双端规格: spec 携带 JS 命令名 + selftest 遍历校验
- [x] W3-K3 WebLocator 迁 Util.swift, DocWC 去复制
- [x] W3-K4 loadMarkdownContent/forceReload 合并单入口
- [x] W3-K5 isReady 单赋值路径
- [x] W3-K6 缩放夹取归属注明(JS 权威) + 860 断言读 CSS 变量
- [x] W3-K7 表格判定统一 isInTable 单源
- [x] W3-K8 任务列表 CSS 单机制(按 milkdown 7.7 实际 DOM 取舍)
- [x] W3-K9 全仓 #filePath 清点归一
- [x] W3-收口 构建 + selftest → result.md

## W4 structure-governance(P2)
- [x] W4-S1 main.js 拆职责模块 + state 显式单例(OQ-5 定案 a: esbuild 多模块,不迁 TS)
- [x] W4-S2 buildMenus 表驱动 + identifier 常量编译期可查
- [x] W4-S3 ESLint flat config 接入 0 error
- [x] W4-收口 拆分前后 selftest 留档 → result.md

## W5 timing-contracts(P2)
- [x] W5-T1 confirmClose 去RunLoop泵送改异步确认 + applicationShouldTerminate 异步化
- [x] W5-T2 魔法延时: PDF 0.35s 改信号驱动 / 缩放 1.2s 删盲等 / 监听防抖命名常量
- [x] W5-T3 脏抑制双机制收敛 generation counter
- [x] W5-T4 pendingOpenURL 删先读后弃分支
- [x] W5-T5 argvFileHandled 不变量注释+防御去重
- [x] W5-T6 状态栏拆字段渲染函数 + 监视器句柄数组管理 + 漂移注释修正
- [x] W5-收口 grep asyncAfter 审计 + selftest → result.md

## W6 deps-and-build(P3)
- [x] W6-H1 package.json 混版注释(math 7.5.9 原因)
- [x] W6-H2 undo/redo 归一 @milkdown/prose + 移除独立 prosemirror-* + dedupe 校验
- [x] W6-H3 补 LICENSE(MIT)
- [x] W6-H4 bundle minify:true + 本地 sourcemap(OQ-4 定案 a)
- [x] W6-H5 build.sh: codesign 硬失败 + registry 可覆盖 + README 参数去重
- [x] W6-H6 scripts/ 空目录删除 + Info.plist 版本注释 + CI 结论(不引入)
- [x] W6-收口 构建 + selftest → result.md

## W7 tests-and-security-doc(P3)
- [x] W7-Q1 waitForCollect 超时必 FAIL + 三处纯睡改条件轮询
- [x] W7-Q2 注册表断言结构性化(遍历+case 数一致) + README 计数解耦
- [x] W7-Q3 multiwindow-test 轮询断言 + PASS/FAIL 自判定
- [x] W7-Q4 诊断面收敛(OQ-3 定案 a): 三入口 flag/输出/退出码风格统一 + 文档化
- [x] W7-Q5 design/architecture.md 诞生: 安全与行为取舍条目(含 R5 暴露面评估)
- [x] W7-收口 selftest → result.md

## 汇总
- [x] 状态回改: roadmap 批次标记 / risks R1-R7 实证回改 / open-questions OQ1-5 结论落点
- [x] 归档: 7 工序目录移入 history/works/ (frontmatter: layer history, status frozen)
