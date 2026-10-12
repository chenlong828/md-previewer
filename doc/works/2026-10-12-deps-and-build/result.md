---
layer: works
module: global
status: closed
updated: 2026-10-14
---

# 工序收口：依赖、构建与许可卫生

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| package.json 混版有注释；独立 prosemirror-* 依赖移除或 alias 归一且有校验 | ✅ | `//milkdown-versions` 注释字段（策略+兼容依据+重验要求）；`prosemirror-history/tables/view` 三个独立依赖移除，undo/redo 改 `@milkdown/prose/history`、样式改 `@milkdown/prose/{view,tables}/style/*`（exports 映射已查证）；`web/check-deps.mjs` 双规则校验（禁独立 prosemirror-*、嵌套拷贝白名单制）挂 postinstall |
| LICENSE 文件存在且与 README/Info.plist 声明一致 | ✅ | `LICENSE`（MIT，Copyright (c) 2026 chenlong）；README 徽章 MIT、Info.plist `NSHumanReadableCopyright` MIT 一致 |
| bundle 策略按 OQ-4 落地；产物可运行、selftest 通过 | ✅ | `minify: true, sourcemap: 'external'`（本地 .map 生成但不留 sourceMappingURL 引用）；bundle.js 9.59MB → **4.0MB**；build.sh 组装 .app 时 `find -name '*.map' -delete`；61 PASS |
| codesign 失败会中断构建；registry 可环境变量覆盖 | ✅ | `|| true` 与 `2>/dev/null` 移除，签名失败即断；`NPM_REGISTRY="${NPM_REGISTRY:-…}"` 可覆盖 |
| `scripts/` 已删；版本号来源唯一或注明 | ✅ | 空目录已删；Info.plist 双键加注释"同源手改、发版一起改"（单机工具构建注入属过度工程，决策成文） |

## 决策记录

- **math 7.5.9 混版兼容依据**（写入 `//milkdown-versions`）：7.5.9+7.7.0 为已知工作组合，selftest 行内/块级 KaTeX 渲染断言守门；npm 因 utils 例外版本产生嵌套拷贝属策略的一部分（校验脚本按白名单放行）。7.7 全家桶曾在 addRow*Command 引入回归，**统一版本前必须带行为断言重验**——注释直接给出重验条件，盲改即被 README+注释双重拦截。
- **OQ-4 结论 a 落地**：minify + external sourcemap。jserror 栈定位路径：仓库本地 `web/dist/bundle.js.map` 配合原始栈帧行号离线符号化；分发产物无 map（体积与源码暴露双收益）。
- **CI：不引入**。单机工具，最小流水线等价物已存在：`./build.sh` + `--selftest` 两条命令覆盖 web 构建/Swift 编译/组装/断言；引入 CI 平台依赖对当前规模是负资产。结论如后续开源再评估。
- **postinstall 的本机策略提示**：`npm warn install-scripts` 是本机 npm 配置的脚本审批策略，不影响仓库语义；check-deps 亦可 `node check-deps.mjs` 手动跑（README 无需展开）。

## 结论落点表

| 活结论 | 落点 |
|---|---|
| milkdown 版本策略与重验条件 | `web/package.json` `//milkdown-versions` + [risks.md R4](../../plan/risks.md) |
| ProseMirror 单一来源契约与校验 | `web/check-deps.mjs`（postinstall）、`web/src/bridge.js`、`web/src/main.js` 导入注释 |
| bundle 策略（OQ-4=a） | `web/build.mjs` 注释、`build.sh` map 剔除 + [open-questions.md OQ-4](../../plan/open-questions.md) 回写 |
| 版本号维护方式 | `resources/Info.plist` 版本键注释 |

## 遗留

- 无。
