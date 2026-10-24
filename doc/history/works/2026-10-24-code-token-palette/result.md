---
layer: history
module: global
status: frozen
updated: 2026-10-24
---

# 工序结果：代码高亮 token 调色板自有化

## 交付

| 落点 | 内容 |
|---|---|
| `web/src/typora.css` | 新节「代码高亮 token 调色板」：浅色 / 深色两张变量表（13 组）、分组规则（只写 `color`）、`.token { background: none }` 不变量、非颜色语义（namespace/entity/important/italic）；替换原「Prism 代码高亮暗色适配」差量补丁块 |
| `web/src/main.js` | 删除 `prismjs/themes/prism.css` 整份主题 import，留注释说明为何不引第三方主题 |
| `web/package.json` / `web/package-lock.json` | 移除 `prismjs` 依赖（删除后唯一引用点消失；lock 仅删根依赖行与包条目） |
| `Sources/MDPreview/Selftest.swift` | 新增 `tokenGroups` / `lightTokenColors` / `darkTokenColors` / `paletteProbeJS` 与 `checkTokenPalette`；主题切换段浅/深各断言一次 |
| `doc/design/architecture.md` | 新增 §2.6「代码高亮配色：token 调色板自有化（单一真源）」 |
| `doc/history/pitfalls.md` | 新增 P8（整份浅色主题 + 差量覆盖的漏项陷阱） |
| `doc/plan/roadmap.md` | 本工序登记为已完成（已归档） |

## 根因

`prismjs/themes/prism.css` 是**浅色**主题，其中 `.token.operator` / `.token.entity` /
`.token.url` 带 `background: hsla(0,0%,100%,.5)`（主题作者为浅色面板设计的强调底）。
`typora.css` 的暗色段只覆盖 `color`，于是白底在深色代码块上显影：`0.5×#fff +
0.5×#333 = #999`。同一份差量补丁还漏了 `doctype` / `builtin` / `variable`，深色下
沿用浅色值。

## 方案取舍

- 变量按「浅/深必须同色」的语义组切分，深浅需要不同配色的类拆独立组；因此一套
  分组规则即可覆盖两套配色，新增 token 类只需在变量表加一行（或复用同组变量）。
- 不保留 Prism 主题的 `pre/code[class*=language-]` 等规则：Milkdown 不在
  `pre`/`code` 上加 `language-*` class，这些规则与本项目从未匹配（含
  `text-shadow: 0 1px white`、`color: black`），属死规则，删除不改变渲染结果
  （实测 `text-shadow` 始终为 `none`）。
- 深色补齐漏项按浅色分组语义映射：`doctype` 跟随注释组、`builtin` 跟随字符串组、
  `variable` 跟随 number/常量组，而不是自创第四套分组。
- 保留 `prismjs` 之外的高亮链路不动：plugin-prism/refractor 只产 `token <类名>`
  span，不参与配色。

## 验收（红 → 绿）

1. **红**：把 `prismjs/themes/prism.css` 重新 import 到 `typora.css` **之后**
   （模拟「第三方浅色规则后来居上」），selftest 如实变红：

   ```
   FAIL  深色 token 调色板 → attr-value=rgb(0, 119, 170)≠rgb(163, 190, 140)、
         comment=rgb(112, 128, 144)≠rgb(127, 140, 152)、…（浅色值回落被逐类点名）
   ```

2. **绿**（恢复后）：

   ```
   PASS  Prism 代码高亮
   PASS  深色主题切换
   PASS  深色 token 调色板(13 组 29 类无背景/无阴影,色值一致)
   PASS  浅色 token 调色板(13 组 29 类无背景/无阴影,色值一致)
   SELFTEST PASSED
   ```

   全量 `--selftest`：**106 PASS / 0 FAIL**（原 104 + 新增 2）。

3. **真实应用截图（深色，`--screenshot`）**：同一文档、同一构建参数，
   `#999` 像素 **29572 → 29**（剩余为文字抗锯齿）；差异像素 34542（0.348%），
   包围盒 `x 235..1196 / y 375..1401` 全部落在代码块内；差异色对：`#999 → #333`
   29543 像素（白块移除）、`#669900 → #a3be8c` 1035 像素（builtin 深色修正）。

4. **浅色零回归**（WKWebView 快照，同文档浅色）：
   - 31 类 token 计算色值**逐类零差异**；
   - 像素差异 16728（0.465%），主色对 `#fcfcfc → #f8f8f8`（15169 像素）= 运算符
     白底移除，其余为字形边缘抗锯齿；无其他区域变化。

5. **深色完整覆盖**（同快照实测）：token 色值差异仅 3 类——`builtin`
   `#669900 → #a3be8c`、`doctype` `#708090 → #7f8c98`、`variable`
   `#ee9900 → #d08770`；渲染样本 118 个 token 带背景数 **24 → 0**，带阴影 0。

6. **构建与依赖门禁**：`npx eslint src` 0 error；`./build.sh debug` 与
   `./build.sh`（release + 组装 .app）通过；临时移走 `node_modules/prismjs` 后
   `node build.mjs` 仍成功（证明无隐藏 import）；`node check-deps.mjs` OK；
   lock 文件差异仅为根依赖行与 `node_modules/prismjs` 条目。

## 验收三件套核对

- **目标**：token 配色由本项目单一维护，浅/深各自完整，token 不再出现背景块 ✅
- **非目标**：未改浅色配色、未改深色既有色相、未改高亮引擎/token 类名/导出格式、
  未做可配置调色板 ✅
- **验收场景**：1) 深色白块消失（#999 29572→29）✅；2) 深色完整覆盖（含 3 类
  漏项修正）✅；3) 浅色零回归（31 类色值零差异）✅；4) 断言可红可绿 ✅

## 结论落点表

| 结论 | 落点 |
|---|---|
| 调色板单一真源、变量分组规则、不设背景不变量、失效条件 | `doc/design/architecture.md` §2.6 |
| 实现单点（变量表 + 分组规则） | `web/src/typora.css`「代码高亮 token 调色板」 |
| 陷阱：整份浅色主题 + 差量覆盖的静默漏项 | `doc/history/pitfalls.md` P8 |
| 防复发断言（13 组 29 类，浅/深） | `Sources/MDPreview/Selftest.swift` `checkTokenPalette` |
| 依赖卫生：`prismjs` 不再被引用 | `web/package.json` / `web/package-lock.json` |
| 工序状态 | `doc/plan/roadmap.md` |

## 遗留

- 导出独立 HTML 不带 `data-theme`，token 恒取浅色值（与改动前一致），不做导出主题
  选择；若将来要导出深色，需给导出文档加 `data-theme` 属性（一条即可，变量表已就绪）。
- 深色新模式让 `builtin` / `variable` / `doctype` 与旧观感略有差异，属本次预期修正；
  用户侧无迁移动作。
- 进行中的 doc-split 工序以 architecture.md 264 行为基线；本工序新增 §2.6 约 16 行，
  该工序收口重算行数即可（§2.6 与该工序「横切契约保留在 architecture.md」的判据一致）。
