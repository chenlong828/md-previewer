---
layer: plan
module: global
status: current
updated: 2026-11-04
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
- **结论（2026-10-14）：a**。`_init` 先解析 opts 再 createEditor，pluginSet 条件加载
  真正生效；自检 `MDP_PLUGINS=no-diagram` 第二实例守门（OQ-1 轻量模式断言）。
  实证：W1 result.md。

## OQ-2 文件保存编码承诺：仅 UTF-8 还是按原编码回写？

- **背景**：`savedEncodingName`（DocumentWindowController.swift:28）三处赋值零读取，
  实际 `TextFile.write`（Util.swift:22）恒定 UTF-8。GB18030 文件一经保存即被转码，
  该语义缺口被一个假变量掩盖。
- **选项**：a) 承诺仅 UTF-8 输出 → 删除死变量并在 README「已知边界」写明；
  b) 实现原编码保存（GB18030 回写）→ 变量转正并补测试。
- **结论（2026-10-14）：a**。仅 UTF-8 输出：savedEncodingName 死变量已删，
  README「已知边界」写明 UTF-8-only 承诺；读取探测编码仅用于显示。
  取舍细节沉淀于 design/architecture.md §2.3。实证：W2 result.md。

## OQ-3 诊断面（debug 桥与三个测试入口）保留为官方能力还是剥离？

- **背景**：`mdbridge.debugParse/debugView/debugState/getTheme/getZoomInfo` 无调用方；
  `--selftest`、`--screenshot`、`--multiwindow-test` 三套诊断入口与 Selftest/Screenshot
  源文件随 release 二进制发布（build.sh 无条件编译区分）。
- **选项**：a) 承认它们是官方诊断面 → 文档化 + 收敛入口风格；
  b) 剥离到独立测试 target / 条件编译 → 生产二进制不含。
- **结论（2026-10-14）：a**。保留为官方诊断面并文档化：三入口
  （--selftest / --screenshot / --multiwindow-test）统一 flag 语法、输出前缀、
  退出码表，登记于 [design/components/CMP-diagnostics/spec.md](../design/components/CMP-diagnostics/spec.md)（2026-10-24 自
  architecture.md「诊断面」小节下沉）；无人调用的 debug 桥 API 已在 W2 删除，
  `window.__mdStage` 已在重构中消除。实证：W7 result.md。

## OQ-4 生产 bundle 的 minify/sourcemap 策略

- **背景**：`web/build.mjs:16-17` `minify:false, sourcemap:false`——生产包 9.1MB 未压缩，
  而 index.html 的 jserror 上报拿到的栈因无 map 难以定位，两头不占。
- **选项**：a) minify:true + sourcemap（文件名带 hash，不上传 map，仅本机排障）；
  b) 保持可读 bundle（体积换可调试性）并接受体积。
- **结论（2026-10-14）：a**。`minify: true` + external 本地 sourcemap
  （产物不带 sourceMappingURL 引用、组装 .app 时剔除 *.map，仓库本地留档供离线符号化）；
  bundle.js 9.59MB → 4.0MB。实证：W6 result.md。

## OQ-5 main.js 拆分粒度与是否引入类型检查

- **背景**：`web/src/main.js` 1147 行单文件、八块职责、`state` 对象字段中途动态添加
  （pluginSet、suppressChange 不在初始字面量）。当前无 ESLint、无类型检查。
- **选项**：a) 按职责拆 esbuild 多模块（bridge/find/tables/mermaid/export/stats/editor）+ ESLint + JSDoc；
  b) 直接迁 TypeScript（成本高，长期收益大）。
- **结论（2026-10-14）：a**。main.js 拆为 11 个职责模块（最大 bridge.js 282 行），
  state 字面量显式声明全部字段；接入 ESLint flat config 0 error；不迁 TypeScript。
  实证：W4 result.md（含拆分前后 selftest 留档）。

## OQ-6 有序列表起始序号在保存后归一化为 1

- **背景**：2026-10-24 列表缩进工序实测发现：输入 `100. a`（下嵌 `- b`）经编辑器
  往返后保存为 `1. a`——Milkdown 的 ordered_list 节点在 toMarkdown 时只输出
  `ordered: true, start: 1`（preset-commonmark `ordered-list.ts` 的 toMarkdown
  分支硬编码 `start: 1`），起始序号丢失、序号被重排。属既有缺陷，与本次
  缩进修复无关（自定义 handler 只按 `parent.start` 输出，mdast 层原型正确）。
- **选项**：a) toMarkdown 读取节点 `order` 属性输出真实 `start`（改 Milkdown 层
  序列化分支，补 selftest 往返断言）；b) 接受序号归一化，在 README「已知边界」写明。
- **待定**：未领取。建议按 a 处理（保存路径上的内容改写，用户可感知）；
  领取时注意与 P7 同源——覆盖/修改 mdast 序列化 handler 要先确认上游扩展行为。

## OQ-7 场景验证债的偿还顺序

- **背景**：2026-11-04 清点后，15 个场景中只有抽屉与图片两组具备完整 3+1 自动入口，文件生命周期/外部变更/打印/打开路径/诊断失败路径仍缺反例；8 张 REQ 全部停在 `accepted`，不能转 `delivered`。
- **选项**：a) 先复跑抽屉 + 图片两组（已有证据，成本最低），把 `SCN-0001/0011/0012` 升 `verified`；b) 先补文件编码/尾换行/外部变更的自动用例，打通 `REQ-0004`；c) 按 REQ 逐张推进，每张凑齐影响场景再转。
- **待定**：未领取。建议 a 先建立“复跑记录”模板，再按 b 补文件生命周期，最后处理打印/打开路径等人工项。
