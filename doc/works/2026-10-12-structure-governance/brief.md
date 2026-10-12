---
layer: works
module: global
status: closed
updated: 2026-10-12
---

# 工序：结构治理（main.js 拆分 + Swift 菜单表驱动 + lint）

前提是 W1–W3 的内容变更已收口——先让内容稳定，再动结构，避免拆分时搬运
注定要删/合的代码。拆分粒度与是否引 TS 见 [OQ-5](../../plan/open-questions.md)。

## 问题清单

### S1 `web/src/main.js` 1147 行单文件、八块职责（审计 #15）

- 现状职责块：编辑器装配（254-362）、源码模式（364-384）、查找插件与查找栏
  （386-766）、独立 HTML 导出（768-840）、桥 API（842-1138）、统计（106-124）、
  Mermaid NodeView（139-250）、启动消息（1140-1147）。
- `state` 对象字段中途动态添加：`pluginSet`、`suppressChange` 不在初始字面量
  （main.js:85-96），形状无静态表达。
- 方向（按 OQ-5 选 a 时的默认拆法）：`editor.js`（装配）、`bridge.js`（mdbridge 与
  post）、`find.js`（插件+查找栏）、`tables.js`（行列几何操作）、`mermaid-view.js`、
  `export.js`、`stats.js`；`state` 收敛为显式声明的模块级单例。
- 拆分为行为等价重构：selftest 全绿为门槛。

### S2 `buildMenus` 130 行手写 + 字符串 identifier 联动（审计 #18）

- 位置：AppDelegate.swift:248-374；`findMenu/updateMenuItem`（:175-188）靠
  `"viewMenu"`、`"appearance.auto"`、`"appearance.light/dark"`、`"recentsMenu"`、
  `"view.sourceMode"` 字符串递归查找，拼写错误无编译期保护。
- 方向：菜单项构建表驱动（identifier 也进 EditorCommands 风格的规格表），
  或至少提取 identifier 常量枚举；联动项（源码模式勾选态、外观三态）注册进
  统一的刷新入口。

### S3 两端 lint 门禁（审计 #34 的 lint 部分）

- 现状：无 ESLint（JS）、无 SwiftLint/SwiftFormat（Swift），质量门禁只有 selftest。
- 方向：`web/` 加 ESLint（flat config，no-unused-vars 直接可防 W2 清单类问题回归）；
  Swift 侧可选 SwiftLint，最低限度先加 `swift build` 警告清零目标。

## 验收标准

- [x] main.js 拆为职责单一模块，单文件不超过 ~300 行；esbuild 构建产物功能等价
- [x] selftest 全部通过（拆分前后各跑一次留档于本工序目录）
- [x] ESLint 接入且 0 error；`state` 形状静态声明
- [x] 菜单 identifier 编译期可查（常量/枚举），字符串裸引用清零
- [x] `./build.sh` 通过

## 依赖与顺序

- 前置：W1、W2、W3 全部收口。
- 与 W5 timing-contracts 无文件交集（本序主要动 web/src 与 AppDelegate 菜单构建，
  W5 动 DocumentWindowController 流程），可并行。
