---
layer: history
module: global
status: frozen
updated: 2026-10-20
---

# 收口: 图片资源生命周期管理(撤销残留与关闭清理)

## 验收结果(对照 brief 验收标准)

1. **引用形态全覆盖** ✅ — selftest「资源清理-孤儿删除且被引用/非图片保留」:
   相对路径(`resource/文档/img_001.png`)、`<>` 包裹含空格
   (`<resource/文档/keep me.jpg>`)、`%20` 编码 file://、`./` 前缀 + %20
   相对路径(`./resource/文档/dot%20ref.png`)四种形态全部保护;
   同名写法只出现在代码围栏内的 `orphan.png` 被判孤儿删除。
2. **孤儿删/被引用与非图片保留** ✅ — 同用例:目录内 `notes.txt` 两轮清理
   均保留并撑住目录;引用清空后图片全删(逐文件名断言删除清单)。
3. **空目录连带移除** ✅ — 「空目录与resource连带移除」:目录内无任何文件时
   `resource/<md文件名>/` 与 `resource/` 都移除;「无目录安全跳过」:
   新建未保存文档(fileURL 为 nil 或目录不存在)调用安全、零副作用。
4. **回归** ✅ — selftest 全量 93 项 PASS(89 + 本工序 4),eslint 干净。
   过程中发现并修复引用判定缺陷,见下节。
5. **关闭钩子人工验证** ✅(2026-10-20 用户实证) — 真实应用两场景:
   粘贴→⌘Z 撤销→关闭(不保存)→resource/ 无残留;粘贴→保存→关闭→文件仍在。

## 过程中发现并修复的引用判定缺陷(两轮红→绿)

1. **`file://%XX` 混排被 URL(string:) 二次转义**:红跑中 `file:///…/文档/
   abs%20ref.png` 解析出的路径是字面 `"abs%20ref.png"`,与真实文件名错位 →
   误删。根因:URL 字符串同时含未编码非 ASCII 与合法 %XX 时,Foundation
   新解析器把合法 `%` 再转义成 `%25`(%20→%2520);纯 ASCII %XX 正常,故既有
   保存往返用例从未暴露。修复:`ImagePathRewriter.percentDecodedPath`
   手工分段百分号解码,引用收集器与 `resolveForSave`(同一缺陷类)统一切换。
2. **`./` 前缀引用失配**:红跑中 `![四](./resource/文档/dot%20ref.png)`
   未保护——`appendingPathComponent`/手工解码都保留冗余 `./` 段,与目录
   列举的干净路径比较失配;且相对目的地含 %20 时改写器口径(原样)根本
   找不到文件。修复:引用与候选双侧 `standardizedFileURL` 规范化后比对,
   相对引用按两种口径收集(改写器原样 + CommonMark %XX 解码,均以文件
   实际存在为准)——宁多保护不误删。沉淀坑档案 P4。

## 结论落点表

| 结论 | 落点 |
|---|---|
| 关闭清理契约(触发点/权威内容/判定/范围/失败语义/时机决策) | design/architecture.md §2.1a「关闭清理(资源 GC)」 |
| 清理实现单点(目录遍历/图片过滤/空目录移除) | Sources/MDPreview/ImageStore.swift `cleanUnreferenced` |
| 引用收集器(复用改写器解析,围栏内不算) | Sources/MDPreview/Util.swift `referencedLocalImagePaths` |
| 混排 file URL 手工解码 | Sources/MDPreview/Util.swift `percentDecodedPath` + history/pitfalls.md P4 |
| 用户可见行为/已知边界(撤销不立即删盘、非图片不动、不跨文档共享) | 仓库根 README.md |
