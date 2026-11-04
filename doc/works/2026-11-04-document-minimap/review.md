---
layer: works
module: navigation
status: active
updated: 2026-11-04
---

# 设计评审批次：右侧文档缩略图（P1）

> 对应 brief：[brief.md](brief.md)；需求 [REQ-0011](../../requirements/REQ-0011-document-minimap.md)；场景 [SCN-0017](../../design/scenarios/navigation/in-document/minimap-navigation/scenario.md)；组件 [CMP-minimap](../../design/components/CMP-minimap/spec.md)。
> 结论：**有条件通过**（条件见 §4）。这是 P1 第一次门（切分/契约），**用户确认前不编码**；实现后的最终门另记。

## 1. 走查范围

- 正常：长 Markdown / 代码文件 → 投影 → 视口 → 点击/拖动 → 菜单开关。
- 失败：短文档、源码模式、图片失败、超量、测量异常、点击越界、拖动取消。
- 扩展：新增块类型只加 source 字段 + renderer 分支；新增内容面只提供 source。
- 布局临界：显示/隐藏导致正文宽度变化，32px 滞回；缩放不放大预留；查找栏避让。
- 数据/状态：缩略图不写文档、不写脏基线、不发 `changed`；偏好只由原生写。
- 打印/导出：打印隐藏并取消预留；HTML 导出只取编辑器内容。
- 删除测试：删掉组件后两个内容面要各自重建缩略栏/视口/指针 → 真边界。

## 2. 四档裁决

### Blocker

无。

### Decision now

| 决策 | 选择 | 代价/被否方案 |
|---|---|---|
| 真缩略图的实现 | **Canvas 文字采样 + 图片缩略**，不复制 DOM、不截图 | 观感不是逐像素截图；被否：DOM clone（临时编辑态/长文内存/双份 DOM）、截图（只能截视口，无法覆盖全文） |
| 组件边界 | 新增 `CMP-minimap`，source 投影由 `CMP-editor` / `CMP-code-view` 提供，组合根注入 | 比“组件内直接查 DOM”多一层契约；被否：把缩略图塞进两个内容面（复制核心） |
| 布局 | 固定 120px，正文预留 146px，保留 8px 系统滚动条；v1 不做宽度拖拽 | 占用正文宽度；被否：悬浮覆盖正文（遮挡）、独立窗口（超出需求） |
| 场景归属 | 新增 `SCN-0017`，放 `navigation/in-document` | 新增 value stream；被否：塞进 SCN-0002/0016（一个需求跨两个旅程，断言分散） |
| 源码模式 | 不显示，菜单置灰，返回渲染面重挂 source | 少一个入口；被否：源码模式也用 textarea 投影（范围膨胀） |

### Verified sound

| 区域 | 证据 |
|---|---|
| 导出隔离 | `web/src/export.js` 只取 `getHTML()`，缩略图 DOM 不进入；打印用 `@media print` 隐藏并取消预留 |
| 无脏变更 | 组件只读 source/滚动，不调 `markClean`、不写 `state.lastMarkdown`/`codeText`；selftest 断言 `changed` 计数不增 |
| 滚动热路径 | 滚动只更新视口框（rAF），内容层防抖重绘；不复制 DOM、不在滚动中测量整篇 |
| 代码面既有边界 | 代码只读、512 KB 上限、行结构/行号/查找不变；source 只读 `lineMeta`/`state.codeText` |
| 布局不放大预留 | `body` 不做 `zoom`，`--app-zoom` 只作用于 `#app`/`#code-view`；146px 预留保持视觉恒定 |
| 临时编辑态 | 图片/Mermaid `editing` 用占位，不把源码 textarea 当正文 |
| 浏览器滚动权威 | 组件不维护第二份 scrollTop；`scrollTo` 夹取；点击越界不产生负滚动 |
| 菜单/数据所有权 | 偏好只在 `CMP-app-shell` 写 `UserDefaults`；组件只读投影；web 不回写 |
| 依赖 | 无新第三方依赖；Canvas/DOM 标准能力；source 普通对象无框架类型泄漏 |
| 删除测试 | 通过：两个内容面各自重建会复制核心复杂度，不消失 |

### Hold

| 事项 | 为什么不阻塞 | 去向 |
|---|---|---|
| 键盘焦点/无障碍导航 | v1 鼠标/触控板优先；正文本身仍可键盘滚动，缩略图是冗余视觉辅助 | 若后续要求，另立需求；`aria-hidden` + 鼠标交互先落地 |
| 精确采样阈值（4000 行/2000 块/200000px） | 不改变契约，只影响降级点 | verify 实测后调；写回组件规格 |
| 缩略图内查找命中/光标标记 | 非目标，加进去会改变语义 | 不进 v1 |
| 宽度拖拽/逐文档宽度 | 非目标，布局契约已固定 120px | 后续需求 |
| 真缩略图逐字可读 | 用户选择的观感是“缩小版页面”，不是逐字校对 | 以 compare.png 为目标；视觉验收见 SCN-0017 |

## 3. Breaking change 审查

冻结后再改会破坏兼容/需迁移的点：

1. `MinimapSource` 的字段形状（source 由两个内容面实现；改字段要同步两端）。
2. `setMinimapVisible` 桥名与 `init` 的 `minimapVisible` 选项（外部窗口/测试可能依赖）。
3. `UserDefaults["minimapVisible"]` key 与默认值（跨窗口偏好）。
4. 固定 120px / 146px 预留的布局契约（用户可见宽度；改变需视觉回归）。
5. `SCN-0017` / `REQ-0011` / `CMP-minimap` 的 ID（文档引用不可复用）。

处理：v1 冻结以上形状；实现中若必须改，先改 REQ/SCN/spec 与 brief，再改代码，并在本 review 追加记录。

## 4. 结论与确认

**结论：有条件通过。**

条件（均为 Decision now 档）：

1. 用户确认 §2 Decision now 的 5 项，尤其是 `CMP-minimap` + source 投影的切分、Canvas 真缩略图方案、固定 120px。
2. 确认 `SCN-0017` 放在 `navigation/in-document`（新增 value stream），不塞进既有 SCN-0002/0016。
3. 确认实现顺序：T15 minimap 骨架 → T16/T17 source → T18 菜单/桥 → T19 验证；P1 设计门未过不写实现代码。

**待用户确认**：2026-11-04 文档已出，未签字。

## 5. 开放问题

- 视觉验收的“接近 compare.png”由用户在 verify 阶段判定；若要求更接近截图的字形精度，需要重开 Decision now（DOM clone/其他方案），不能悄悄加大采样成本。
- 真实拖拽手感、触控板惯性按 R8 列为人工点验，不作为自动化通过条件。
