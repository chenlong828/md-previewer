---
layer: history
module: global
status: frozen
updated: 2026-10-24
---

# 工序结果：列表 Tab 缩进输出标准 4 空格

## 交付

| 落点 | 内容 |
|---|---|
| `web/src/list-indent.js`（新增） | `fourSpaceListItem` mdast `listItem` handler：首行标记单空格、续行/嵌套 `max(4, 标记宽+1)` 空格；复刻 GFM 任务列表复选框语义 |
| `web/src/editor.js` | `remarkStringifyOptionsCtx` 去掉 `listItemIndent: 'one'`，`handlers.listItem` 注入上述 handler |
| `Sources/MDPreview/Selftest.swift` | 新增 `testListIndent()` 三条断言（Tab 端到端 4 空格、多级 4/8、任务列表复选框） |
| `README.md` | 「已知边界」补保存格式：每级 4 空格、首行紧凑、旧 2 空格文件保存时规范化 |
| `doc/design/architecture.md` | 新增 §2.5 序列化契约（决策/理由/单点/陷阱/保存即规范化） |
| `doc/history/pitfalls.md` | 新增 P7（`listItemIndent:'tab'` 补齐首行 + 覆盖 handler 顶掉 GFM 复选框） |
| `doc/plan/open-questions.md` | 新增 OQ-6（顺带发现的有序列表起始序号归一化，未领取） |
| `doc/plan/roadmap.md` | 本工序登记为已完成 |

## 根因

`web/src/editor.js` 显式设置 `listItemIndent: 'one'`（mdast-util-to-markdown 的
「内容列」模式），每级嵌套只缩进标记宽 + 1（`- ` → 2 空格）。Tab 键本身的嵌套
由 Milkdown `listItemKeymap` 的 `SinkListItem` 完成，解析、渲染、桥协议均正确，
缺陷只在序列化输出宽度。

## 方案取舍

- 不用 `listItemIndent: 'tab'`：实测会把首行标记也补到 4 列
  （`- a` → `-   a`、`1. a` → `1.  a`），不是标准形态。
- 自定义 handler 必须复刻 GFM 复选框：`handlers.listItem` 覆盖会顶掉
  `mdast-util-gfm-task-list-item` 注册的 listItem handler，否则保存丢 `[x]`。
- 不改 remark-stringify 的 `extensions` 通道（它只读 processor data 的
  `toMarkdownExtensions`，用户传参无效），也不新增 npm 依赖（避免
  `mdast-util-to-markdown` 版本漂移），只用公共 state API。
- 解析兼容：4 空格缩进是合法 CommonMark 嵌套；2 空格旧文件照常解析，
  只有用户保存时才按新口径落盘。

## 验收（红→绿）

1. **红**（修复前，`listItemIndent:'one'`）：

   ```
   FAIL  列表 Tab 嵌套-缩进 → "- alpha\n  - beta\n- gamma\n\n<br />\n"
   FAIL  列表多级嵌套-缩进 → "- a\n  - b\n    - c\n\n<br />\n"
   FAIL  任务列表复选框 → "- [x] done\n  - [ ] nested\n\n<br />\n"
   ```

2. **绿**（修复后）：

   ```
   PASS  列表 Tab 嵌套-每级 4 空格且首行紧凑
   PASS  列表多级嵌套-4/8 空格
   PASS  任务列表复选框与 4 空格缩进
   SELFTEST PASSED
   ```

   全量：`--selftest` **104 PASS / 0 FAIL**（原 101 项 + 新增 3 项）。

3. **真实 WKWebView 按键路径**（进程内最小复现器：AppKit `sendEvent` → WKWebView
   → JS，光标在第二项按 Tab）：

   ```
   修复前: "- a\n  - b\n- c\n\n<br />\n"
   修复后: "- a\n    - b\n- c\n\n<br />\n"
   ```

4. **风格/依赖门禁**：`npx eslint src` 0 error；web 构建与 `.app` 组装通过
   （`./build.sh debug`）。

## 验收三件套核对

- **目标**：列表 Tab 嵌套保存为每级 4 空格、首行紧凑 ✅
- **非目标**：未改解析/渲染/桥/菜单/Tab 绑定，未引入可配置缩进、未用字面 Tab ✅
- **验收场景**：1) Tab 端到端 4 空格 ✅；2) 多级 4/8 空格 ✅；3) 首行紧凑
  （断言 `!contains("-   alpha")`）✅（`100.` 长度规则在 mdast 层原型验证，
  见 OQ-6）；4) 任务列表复选框保留 ✅；5) 既有 selftest 全绿 ✅

## 结论落点表

| 结论 | 落点 |
|---|---|
| 序列化格式契约（每级 4 空格、首行紧凑、保存即规范化） | `doc/design/architecture.md` §2.5 |
| 用户可见格式承诺 | `README.md`「已知边界」 |
| 缩进规则实现单点（含取舍注释） | `web/src/list-indent.js` |
| 陷阱：mdast `'tab'` 补齐首行 / 覆盖 handler 顶掉 GFM 复选框 | `doc/history/pitfalls.md` P7 |
| 防复发断言 | `Sources/MDPreview/Selftest.swift` `testListIndent()` |
| 顺带发现：有序列表起始序号归一化（未领取） | `doc/plan/open-questions.md` OQ-6 |
| 工序状态 | `doc/plan/roadmap.md` |

## 遗留

- 保存会把既有 2 空格缩进列表规范化成 4 空格（整文件格式化 diff），属本工序
  预期行为，已在 README 与 §2.5 写明；不做静默改写，只有用户保存才落盘。
- 有序列表 `100.` 起始序号在编辑器往返后归一化为 `1.`（既有缺陷，与缩进修复
  无关），已登记 OQ-6，未在本工序改动。
