---
layer: works
module: global
status: active
updated: 2026-10-12
---

# 工序：依赖、构建与许可卫生

小项合集，各项互相独立，可拆可合执行。涉及策略取舍的两项见
[open-questions.md](../../plan/open-questions.md)。

## 问题清单

### H1 milkdown 混版无注释（审计 #29，R4）

- 位置：`web/package.json:16` `@milkdown/plugin-math` 7.5.9 vs 其余 7.7.0。
- 动作：package.json 加注释字段说明混版原因（7.7 addRow*Command no-op 缺陷，
  表格命令已自实现）；确认 math 7.5.9 与 core 7.7.0 兼容性依据一并写明。

### H2 双 ProseMirror 来源（审计 #30，R3）

- 位置：package.json 同时含 `@milkdown/prose`（:21）与独立
  `prosemirror-history`（:27）、`prosemirror-tables`（:28）、`prosemirror-view`（:29）；
  main.js:63 的 undo/redo 用独立 prosemirror-history。
- 动作：undo/redo 改从 `@milkdown/prose/history` 取用（或 esbuild alias 强制归一），
  移除独立 prosemirror-* 依赖；加安装后 dedupe 校验脚本防回归。

### H3 缺 LICENSE 文件（审计 #31）

- 现状：README 徽章与 Info.plist 版权行均声称 MIT，仓库无 LICENSE/NOTICE。
- 动作：补 LICENSE（MIT，版权人按仓库所有者署名）。

### H4 bundle minify/sourcemap 策略（审计 #32）

- 位置：web/build.mjs:16-17 `minify:false, sourcemap:false`——生产 9.1MB 未压缩，
  jserror 栈又因无 map 难定位（index.html:22-32）。
- 动作：按 [OQ-4](../../plan/open-questions.md) 结论执行（默认方向：minify:true +
  本地 sourcemap 不随包分发）。

### H5 构建脚本小刺（审计 #33）

- `build.sh:34` `codesign --force --sign - … || true` 吞签名失败 → 改为失败即报
  （ad-hoc 签名失败应当中断构建）。
- `build.sh:11` npm registry 硬编码 npmmirror → 提取为环境变量可覆盖，README 同步。
- Swift 构建参数在 build.sh:17 与 README 各一份 → README 引用 build.sh 不再复述参数。

### H6 仓库杂物（审计 #34）

- `scripts/` 空目录删除（反占位）。
- Info.plist `CFBundleVersion` 与 `CFBundleShortVersionString` 双处硬编码 1.0.0
  → 保持双键但提取说明注释，或引入构建时注入（执行时定，避免过度工程）。
- 无 CI：可选项，若引入则最小流水线 = `node build.mjs` + `swift build` + selftest；
  不强制，结论进 result。

## 验收标准

- [ ] package.json 混版有注释；独立 prosemirror-* 依赖移除或 alias 归一且有校验
- [ ] LICENSE 文件存在且与 README/Info.plist 声明一致
- [ ] bundle 策略按 OQ-4 落地；产物可运行、selftest 通过
- [ ] codesign 失败会中断构建；registry 可环境变量覆盖
- [ ] `scripts/` 已删；版本号来源唯一或注明

## 依赖与顺序

- 无硬依赖；涉及 package.json 与 build.sh，与 W4（web/src）不冲突，可并行。
