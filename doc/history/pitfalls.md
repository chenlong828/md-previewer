---
layer: history
module: global
status: frozen
updated: 2026-10-20
---

# 坑档案

每条坑三个必填字段：现象、存续条件、对策落点。已消失的坑标注实证日期，条目保留防复发。

## P1 milkdown markdownUpdated 经 200ms debounce 异步到达，防抖窗内回调携带中间态

- **现象**：milkdown listener 插件对每次 docChanged 事务各建一个 lodash.debounce(200ms)
  定时器，flush 时序列化的是**事务捕获时的 doc**；并发编辑（如"编辑后立即打开新文件"）
  会产生携带过期内容的迟到回调。消费方若拿它当"当前内容"，会出现打开文件即报脏、
  保存基线错乱（D1-b 误报，实证 2026-10-12）。
- **存续条件**：仍在。该机制是 milkdown 7.7 的固有行为，升级或替换 listener 机制前持续存在。
- **对策落点**：
  - web 侧单一脏机制：基线由 `setMarkdown`/`markClean` **同步**落定，listener 回调先做
    过期过滤（`markdown === currentMarkdown()`）再报 dirty——`web/src/editor.js`、
    `web/src/bridge.js`（W5-T3，实证 2026-10-14）；
  - 测试侧断言前用"桥消息静止"窗口（`Selftest.settleBridge`，连续 quiet 秒无新上报）
    排空旧事务尾窗，杜绝"断言跑在迟到回调前面"；
  - 机制说明沉淀于 design/architecture.md §4。

## P2 injectMarkdown 双入口 base 参数不一致,相对路径图片在真实应用全不显示

- **现象**:同一路径改写器,无头自检全绿,真实应用里所有相对路径图片都不显示
  (2026-10-20 实证:受控文档三变体全部保持原样)。根因是 `openDocument` 把
  **文件 URL** 传给 `injectMarkdown(baseURL:)`、`forceReload` 传**目录**——
  前者解析出 `doc.md/resource/…`,fileExists 恒 false,改写静默放弃。隔离的
  改写器单测以目录为基准,从未覆盖这条真实装配缝。
- **存续条件**:已消失(2026-10-20)。契约单点化:`injectMarkdown(docURL)` 收
  文档 URL、内部唯一推导目录,两个调用点同构;截图模式 dom 探测(images 数组
  含 src/naturalWidth)可对真实装配做显示断言。
- **对策落点**:
  - 契约写明于 design/architecture.md §2.1「基点契约」;
  - 同类风险判据:同一数据(路径解析基准)的推导点必须唯一,调用方传领域实体
    (docURL),不在调用点各自推导派生值;
  - selftest 的改写器单测仍不覆盖 openDocument 装配缝——显示类问题优先用
    `--screenshot` + dom 探测在真实装配上验证。

## P3 ImageStore 目录列举失败静默当空目录,img 序号回绕覆盖既有图片

- **现象**:评审发现 `existingFiles` 以 `try? ?? []` 兜底——目录可写但不可列举
  (如 chmod 0o300,缺 r 位)时,列目录静默得空表,`img_NNN` 序号回绕到 001,
  `.atomic` 写盘**静默覆盖**既有图片。selftest 最小复现实证(红跑):第二次
  导入后 img_001.png 内容确被覆盖,属数据丢失级,非理论风险。
- **存续条件**:已消失(2026-10-20)。`existingFiles` 改为原样抛错,命名函数与
  `ImageStore.import` 顺次传播,失败由原生弹窗提示;红→绿用例守门
  (「图片落盘-不可列举目录拒绝(防覆盖)」「既有图片未被覆盖」)。
- **对策落点**:
  - 失败契约写明于 design/architecture.md §2.1a「导入落盘约定」;
  - 同类风险判据:`try? ?? 空值` 兜底 IO 失败前,先问"空值会让下游推导出
    错误业务结果吗"——序号/去重/命名类推导对空表敏感,必须抛错。

## P4 URL(string:) 对「未编码非 ASCII + 合法 %XX」混排 file URL 再转义合法 %XX

- **现象**:资源清理用例红跑中,`file:///…/文档/abs%20ref.png` 经
  `URL(string:)` 解析后 `.path` 得到字面 `"abs%20ref.png"`(空格未还原)——
  描述输出显示 `%20` 被再转义成 `%2520`,解码后与真实文件名 `abs ref.png`
  错位,该引用判定失配、文件被误删(2026-10-20 实证)。根因:当 URL 字符串
  同时含未编码非 ASCII 与合法 %XX 时,Foundation 的新解析器进入宽容编码
  模式,把已合法的 `%` 一并转义;纯 ASCII 的 %XX(如自家产生的
  absoluteString)则解析正确——所以保存往返用例从未暴露。
- **存续条件**:仍在。这是 Foundation 运行时行为,不随本仓库代码变化;
  凡「混排 file URL → 文件系统路径」的解析点都要绕开 `URL(string:)`。
- **对策落点**:
  - `ImagePathRewriter.percentDecodedPath`:file:// 之后手工分段
    百分号解码(`removingPercentEncoding`,非法序列保原文),已编码/未编码/
    文件名含字面 % 三种形态都得正确路径;
  - `resolveForSave` 同口径加固(保存链路同一缺陷类,selftest 保存往返守门);
  - `addingPercentEncoding(.urlQueryAllowed)` 不含 `%`(RFC 3986 字面集),
    不能用来"补编码"含 % 的串——会把合法 %XX 变 %25XX;
  - 引用与候选路径比较前双侧 `standardizedFileURL` 规范化(./ 前缀引用
    与目录列举路径失配会误删,红跑实证);
  - 判定用例:selftest「资源清理-孤儿删除且被引用/非图片保留」(%20 编码
    与 ./ 前缀分支)。
