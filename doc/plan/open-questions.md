---
layer: plan
module: global
status: current
updated: 2026-10-12
---

# 跨工序开放问题

工序立项时从这里领取；被领取的问题标注去向工序ID；关闭时记结论与落点，不删除条目。

## OQ-1 pluginSet「无 diagram 轻量模式」是修复还是删除？

- **背景**：`web/src/main.js:260` 在 createEditor 内读取 `state.pluginSet`，而 `_init`
  在创建完成之后（:856）才赋值 `opts.plugins`——首次也是唯一一次 init 恒为 `'full'`。
  `useMath/usePrism/useDiagram` 条件加载与 Selftest 的 `MDP_PLUGINS` 环境变量
  （Selftest.swift:102）实际不可达。
- **选项**：a) 调整 `_init` 顺序使配置真正生效（保留轻量模式能力）；
  b) 删除 pluginSet 全套条件分支，声明当前只有 full 档。
- **状态**：开放。已登记去向 → W1（时序修复属 W1；选 a/b 影响是否删分支）。

## OQ-2 文件保存编码承诺：仅 UTF-8 还是按原编码回写？

- **背景**：`savedEncodingName`（DocumentWindowController.swift:28）三处赋值零读取，
  实际 `TextFile.write`（Util.swift:22）恒定 UTF-8。GB18030 文件一经保存即被转码，
  该语义缺口被一个假变量掩盖。
- **选项**：a) 承诺仅 UTF-8 输出 → 删除死变量并在 README「已知边界」写明；
  b) 实现原编码保存（GB18030 回写）→ 变量转正并补测试。
- **状态**：开放。已登记去向 → W2（删除动作在 W2，选 b 则从 W2 拆出独立需求）。

## OQ-3 诊断面（debug 桥与三个测试入口）保留为官方能力还是剥离？

- **背景**：`mdbridge.debugParse/debugView/debugState/getTheme/getZoomInfo` 无调用方；
  `--selftest`、`--screenshot`、`--multiwindow-test` 三套诊断入口与 Selftest/Screenshot
  源文件随 release 二进制发布（build.sh 无条件编译区分）。
- **选项**：a) 承认它们是官方诊断面 → 文档化 + 收敛入口风格；
  b) 剥离到独立测试 target / 条件编译 → 生产二进制不含。
- **状态**：开放。已登记去向 → W7（删除无人调用的 debug API 在 W2 先行，结构性剥离属 W7）。

## OQ-4 生产 bundle 的 minify/sourcemap 策略

- **背景**：`web/build.mjs:16-17` `minify:false, sourcemap:false`——生产包 9.1MB 未压缩，
  而 index.html 的 jserror 上报拿到的栈因无 map 难以定位，两头不占。
- **选项**：a) minify:true + sourcemap（文件名带 hash，不上传 map，仅本机排障）；
  b) 保持可读 bundle（体积换可调试性）并接受体积。
- **状态**：开放。已登记去向 → W6。

## OQ-5 main.js 拆分粒度与是否引入类型检查

- **背景**：`web/src/main.js` 1147 行单文件、八块职责、`state` 对象字段中途动态添加
  （pluginSet、suppressChange 不在初始字面量）。当前无 ESLint、无类型检查。
- **选项**：a) 按职责拆 esbuild 多模块（bridge/find/tables/mermaid/export/stats/editor）+ ESLint + JSDoc；
  b) 直接迁 TypeScript（成本高，长期收益大）。
- **状态**：开放。已登记去向 → W4。
