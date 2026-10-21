---
layer: history
module: global
status: frozen
updated: 2026-10-21
---

# 工序：可移植内核与壳契约（portable-kernel）

> 2026-10-21 收口归档：评审与规格完成、实施暂缓（零代码），见同目录 result.md。

## 需求

把「Swift/WKWebView 宿主能力」与「浏览器内 JS 编辑器能力」在设计层面拆开：
JS 部分成为可移植的逻辑内核，Windows / Linux 各自开发原生壳（与 macOS 壳同构：
本平台原生 UI + 系统 WebView）包裹同一内核。本工序只做设计与 macOS 侧契约化
重构，不启动任何新平台壳。

## 背景

- 2026-10-21 评审结论：方案**有条件通过**（评审全文见会话记录，结论蒸馏入
  存档规格 `../../decisions/2026-10-21-editor-kernel-spec.md` §9 决策记录）。四个条件：契约显式版本化、
  文本级语义单点归内核、内核测试面独立于任何 WebView、壳参考时序流程成文。
- 评审发现的最大风险 R1：图片路径语义（加载改写/保存还原/GC 引用收集/落盘命名）
  当前 Swift 与 JS 双头实现、靠注释与 selftest 维持同口径；壳数量增长后必然漂移。
- 现状桥为「隐式契约」：`window.mdbridge` 方法面无版本、无 schema，Swift 侧
  30 处 `callJS` 字符串拼接 + JSArgs 转义，Promise 不可跨桥（architecture.md §4）。

## 已定决策（2026-10-21，用户拍板）

1. markdown 文本级路径语义**收进内核**（壳只留文件系统执行权）；
2. 桥契约采用**统一 JSON 消息协议 v2**（双向信封 + requestId 关联，淘汰
   字符串拼 JS 方法调用）；
3. 规格对壳技术**中立**（WebView2 / WebKitGTK / Tauri 等不在本工序选定）。

## 验收标准

1. 目标规格冻结（现归档于 `../../decisions/2026-10-21-editor-kernel-spec.md`）：
   模块地图、契约 v2 op 表（含版本握手、
   错误码、PathPolicy 端口）、冷热路径卡、数据所有权矩阵、验证计划齐全，
   经走查后人工确认（第二次门）。
2. （实现期，确认后另立或续本工序）macOS 侧完成 v2 切换：
   内核 Node 契约套件 + 既有 selftest 全绿；`window.mdbridge` 字符串调用与
   JSArgs 全部下线；路径改写器 Swift 实现下线（黄金夹具迁入 Node 套件）。
3. README 与 architecture.md 的桥协议描述与实现一致（一处一事，指向 spec）。

## 领取的开放问题

无（自 plan/open-questions.md 领取：无）。本工序产生的开放问题登记在
spec §9（Windows 壳技术选型、自定义 resource scheme 必要性等，均属后续壳工序）。

## 非目标

- 不实现 Windows/Linux 壳；
- 不改编辑器功能面（拆分是纯契约化，行为不变）；
- 不推翻 design/architecture.md 已定稿的安全与行为取舍（全盘读授权、mermaid
  loose、原生抽屉等随壳各自携带，内核不重复约束）。
