---
layer: history
module: global
status: frozen
updated: 2026-10-24
---

# 工序: 列表 Tab 缩进输出标准 4 空格

## Bug 报告(用户 2026-10-24 提交)

- **现象**:在所见即所得编辑区编辑 Markdown 列表,按 `Tab` 后列表层级确实变了
  (ProseMirror doc 嵌套正确),但保存出来的 `.md` 每级只缩进 **2 空格**
  (`- a` / `  - b`),不是标准的 **4 空格**(Tab 等价)缩进。用户侧观感是
  「只是加了个 Tab 字符、列表还是原来的」。
- **复现**:新建或打开含两项以上无序列表的文档 → 光标放到第二项行首 →
  按 `Tab` → 查看源码模式 / 保存后的 `.md`。
- **期望**:嵌套每级 4 空格;列表项首行标记仍紧凑(`- a`,不是 `-   a`)。
- **实际**:每级 2 空格(`- a\n  - b`)。
- **根因**:`web/src/editor.js` 的 `remarkStringifyOptionsCtx` 显式
  `listItemIndent: 'one'`——mdast-util-to-markdown 的「内容列」模式,
  每级缩进 = 标记宽 + 1(`- ` 即 2);解析、渲染、桥都正常,缺陷只在
  序列化输出。
- **影响面**:保存、源码模式切回渲染、一切走序列化的路径;已有 2 空格缩进
  文件能正常解析,保存时会被规范化为 4 空格(与现有「保存即规范化
  bullet/emphasis」同一行为)。
- **定级**:P3(单模块 web 序列化选项;不改公共契约 / schema / 依赖 /
  热路径;selftest 可覆盖)。

## 决策

- 目标缩进 = **每级 4 空格**(用户确认「标准 markdown 缩进」指 4 空格或一个
  Tab;取空格,避免字面 `\t` 与部分渲染器/linter 的兼容问题)。
- **不用** `listItemIndent: 'tab'`:该模式会把首行标记也补到 4 列
  (`-   a`、`1.  a`),不是标准形态;且 mdast 没有「首行紧凑 + 续行 4 空格」
  的现成选项。
- 用自定义 `listItem` handler 经 `remarkStringifyOptionsCtx.handlers` 注入:
  - 首行 `- ` / `1. ` 保持单空格;
  - 续行与嵌套行缩进 `max(4, 标记宽 + 1)`(长有序标记 `100.` 仍缩 5,
    保证不低于内容列、可被 CommonMark 解析);
  - 任务列表复选框沿用 GFM 语义(`node.checked` → `[x]` / `[ ]`):覆盖
    `handlers.listItem` 会替掉 GFM 扩展注册的 listItem handler,必须在
    自定义 handler 内复刻,否则保存会把复选框吞掉。

## 非目标

- 不改解析 / 渲染 / 桥协议 / 菜单;不改 Tab 键绑定(Milkdown
  `listItemKeymap` 的 `SinkListItem` 行为正确)。
- 不做「缩进宽度可配置」,不改用字面 Tab 字符。
- 不改写未保存的既有文件内容;仅在用户保存时按统一序列化输出。

## 落点

- 新增 `web/src/list-indent.js`:`fourSpaceListItem` handler(含任务列表复选框)。
- `web/src/editor.js`:`remarkStringifyOptionsCtx` 去掉 `listItemIndent: 'one'`,
  `handlers` 合并 `listItem`。
- `Sources/MDPreview/Selftest.swift`:新增列表缩进断言(Tab 端到端 + 多级/任务列表),
  先红后绿。
- 文档:`plan/roadmap.md` 登记;`README.md`「已知边界」补保存格式;
  `design/architecture.md` §2 补序列化契约;`history/pitfalls.md` 记
  `listItemIndent: 'tab'` 与 GFM handler 覆盖两个陷阱。

## 验收场景

1. **Tab 嵌套**:`- alpha` / `- beta` / `- gamma`,光标在第二项按 `Tab` →
   序列化为 `- alpha\n    - beta\n- gamma`,且不出现 `-   alpha`。
2. **多级嵌套**:注入 `- a\n  - b\n    - c\n` → 输出 `- a\n    - b\n        - c`
   (4/8 空格),重新解析层级不变。
3. **标记紧凑与长标记**:`- a` 保持单空格;`1. a` 下嵌套 4 空格;`100. a`
   下嵌套 5 空格(不低于内容列)。执行期修正:`100.` 的长度规则在 mdast 层
   原型验证(应用编辑器会把有序列表起始序号归一化为 1,属既有缺陷,已登记
   [plan/open-questions.md](../../../plan/open-questions.md) OQ-6,不在本工序范围)。
4. **任务列表不回归**:`- [x] done` / `- [ ] todo` 序列化仍保留复选框。
5. **既有回归**:selftest 全绿(sampleMarkdown 的 `[x]` 往返断言继续成立)。

## 风险与回滚

- 风险:覆盖 `handlers.listItem` 会屏蔽 GFM task-list handler → 已在 handler
  内复刻复选框逻辑,并由 selftest / sampleMarkdown 往返守门。
- 回滚:删除 `list-indent.js`、恢复 `listItemIndent: 'one'` 即可;不涉数据迁移,
  已保存的 4 空格文件仍可正常解析。
