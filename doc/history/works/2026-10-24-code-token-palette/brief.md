---
layer: history
module: global
status: frozen
updated: 2026-10-24
---

# 工序: 代码高亮 token 调色板自有化（浅/深双值、单套规则）

## 用户提交（2026-10-24）

- **现象**：深色（dark）模式下，代码块里部分符号（`：`、`<`、`>`、`=` 等）在
  灰色背景上显示成浅色 / 白色块。
- **复现**：系统深色 → 打开任一含高亮语言（python / js / json 等）的围栏代码块
  → 运算符位置出现浅色矩形；切换浅色模式不明显。
- **根因**：`web/src/main.js` 整份引入了 Prism 官方浅色主题
  `prismjs/themes/prism.css`；其中 `.token.operator` / `.token.entity` /
  `.token.url` 带 `background: hsla(0, 0%, 100%, .5)`。`typora.css` 的暗色段
  是**差量补丁**，只覆盖这些 token 的 `color`，没有覆盖 `background`——白色底
  穿透到深色代码块（`0.5×#fff + 0.5×#333 = #999`）。
- **实测**：深色截图 `#999` 像素 29572，聚成 56 个 26×24 CSS px、填充率
  0.85–0.9 的实心矩形；DOM 计算样式 `.token.operator` 背景
  `rgba(255,255,255,0.5)`。同一补丁还漏了 `builtin` / `doctype` / `variable`：
  深色下沿用浅色值（如 python `str`/`int` 为 `#690` 深绿）。
- **影响面**：所有 Prism 高亮语言；浅色模式因白底叠在 `#f8f8f8` 上几乎不可见。
- **定级**：P3（单主题文件内部的配色来源重构；不改桥协议 / schema / 解析序列化 /
  热路径；副作用是移除一个只服务该 CSS 的依赖）。

## 决策

- 采用方案 B（用户 2026-10-24 确认「更彻底」）：**调色板自有化**——一套规则 +
  浅/深两组 CSS 变量，删除对 `prismjs/themes/prism.css` 的整份依赖，并移除
  因此不再被任何代码引用的 `prismjs` 依赖。
- **不采用 A**（单条 `background: none` 覆盖）：只堵当前缺陷；第三方主题的浅色
  规则仍在，下一次未覆盖项会再次静默回落。
- **不采用两份主题文件**（`light.css` / `dark.css`）：模板重复、改一处漏一处，
  与现有 `data-theme` + CSS 变量机制形成第三套真源；且导出 HTML 内联全部样式，
  两份主题会让导出体积翻倍却仍无切换开关。
- **变量按语义组切分**：同组在浅/深共用一个变量；任一主题需要独立配色的类
  （selector、important、attr-value、regex、variable、number/property 等）拆成
  独立组。分组差异即「浅色主题的配色语义」到「Nord 调色板」的映射表。
- **不变量**：token 一律不设背景（`.token { background: none }`），底色唯一来源
  是 `pre` 的 `--code-fence-bg`；token 不设 `text-shadow`。
- **深色补齐历史漏项**：`doctype`、`builtin`、`variable` 按浅色主题的分组语义
  映射到深色调色板（而不是继续回落浅色值）。

## 非目标

- 不改浅色配色：逐类照抄 Prism 默认主题，实测 31 类色值零差异。
- 不改深色既有色相：保留现有 Nord 值，只补漏项。
- 不改高亮引擎（仍是 Milkdown plugin-prism / refractor）、token 类名、导出格式。
- 不做主题可配置 / 用户自定义调色板。

## 落点

- `web/src/typora.css`：新节「代码高亮 token 调色板」替换原「Prism 代码高亮暗色
  适配」块（两张变量表 + 分组规则 + 非颜色语义）。
- `web/src/main.js`：删除 `prismjs/themes/prism.css` import。
- `web/package.json` / `web/package-lock.json`：移除 `prismjs`（仅被该 CSS 使用）。
- `Sources/MDPreview/Selftest.swift`：新增 `checkTokenPalette`（13 组 29 类，
  浅/深各一条）+ 合成 span 探针 `paletteProbeJS`；主题段各调用一次。
- 文档：`design/architecture.md` §2.6；`history/pitfalls.md` P8；
  `plan/roadmap.md` 登记。

## 验收场景

1. **深色白块消失**：含 `= < > : && ->` 的代码块中，深色截图 `#999` 像素由
   29572 降到 ~0；渲染样本 118 个 token 全部无背景、无阴影。
2. **深色完整覆盖**：每个 token 类解析到深色值（含历史漏项 `doctype` →
   `#7f8c98`、`builtin` → `#a3be8c`、`variable` → `#d08770`），不再有浅色值回落。
3. **浅色零回归**：浅色下 31 类 token 色值与改动前逐类一致；唯一差异是运算符
   白底移除（`#fcfcfc` → `#f8f8f8`，肉眼不可辨）。
4. **断言可红可绿**：selftest 全绿（106 项，含新增 2 条）；把 `prism.css` 重新
   import 到 `typora.css` 之后时，调色板断言变红（已实测）。

## 风险与回滚

- 风险：深色下 `builtin` / `variable` / `doctype` 颜色变化属预期内的修正，
  用户会在 dark 模式看到轻微色差（深绿→Nord 绿、亮橙→Nord 橙）。
- 回滚：恢复 `prism.css` import 与旧暗色覆盖块、恢复 `prismjs` 依赖即可；
  不涉数据迁移。
