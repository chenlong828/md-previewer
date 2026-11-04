---
layer: history
module: navigation
status: frozen
updated: 2026-11-05
---

# 设计评审批次：右侧文档缩略图（P1）

> 对应 brief：[brief.md](brief.md)；需求 [REQ-0011](../../../requirements/REQ-0011-document-minimap.md)；场景 [SCN-0017](../../../design/scenarios/navigation/in-document/minimap-navigation/scenario.md)；组件 [CMP-minimap](../../../design/components/CMP-minimap/spec.md)。
> 结论：**第一门有条件通过**（条件见 §4）。用户已确认并转入实现；**实现后复审见 §6**，最终门已于 2026-11-05 通过。

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
| 真缩略图的实现 | **只读 DOM 克隆 + 顶左等比缩放（fit）**，不截图（2026-11-05 修订） | 临时编辑态/内存通过脱敏与单份副本控制；被否：Canvas 采样（保真不足）、截图（只能截视口） |
| 组件边界 | 新增 `CMP-minimap`，source 投影由 `CMP-editor` / `CMP-code-view` 提供，组合根注入 | 比“组件内直接查 DOM”多一层契约；被否：把缩略图塞进两个内容面（复制核心） |
| 布局 | 固定 120px，正文预留 146px，保留 8px 系统滚动条；v1 不做宽度拖拽 | 占用正文宽度；被否：悬浮覆盖正文（遮挡）、独立窗口（超出需求） |
| 场景归属 | 新增 `SCN-0017`，放 `navigation/in-document` | 新增 value stream；被否：塞进 SCN-0002/0016（一个需求跨两个旅程，断言分散） |
| 源码模式 | 不显示，菜单置灰，返回渲染面重挂 source | 少一个入口；被否：源码模式也用 textarea 投影（范围膨胀） |

### Verified sound

| 区域 | 证据 |
|---|---|
| 导出隔离 | `web/src/export.js` 只取 `getHTML()`，缩略图 DOM 不进入；打印用 `@media print` 隐藏并取消预留 |
| 无脏变更 | 组件只读 source/滚动，不调 `markClean`、不写 `state.lastMarkdown`/`codeText`；selftest 断言 `changed` 计数不增 |
| 滚动热路径 | 滚动只更新视口框（rAF），快照防抖重建；滚动中不克隆 DOM、不测量整篇 |
| 代码面既有边界 | 代码只读、512 KB 上限、行结构/行号/查找不变；source 只读 `lineMeta`/`state.codeText` |
| 布局不放大预留 | `body` 不做 `zoom`，`--app-zoom` 只作用于 `#app`/`#code-view`；146px 预留保持视觉恒定 |
| 临时编辑态 | 脱敏移除 textarea/按钮等临时控件，不把编辑控件当正文 |
| 浏览器滚动权威 | 组件不维护第二份 scrollTop；`scrollTo` 夹取；点击越界不产生负滚动 |
| 菜单/数据所有权 | 偏好只在 `CMP-app-shell` 写 `UserDefaults`；组件只读投影；web 不回写 |
| 依赖 | 无新第三方依赖；DOM/Pointer Events/CSS transform 标准能力；source 普通对象无框架类型泄漏 |
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

1. 用户确认 §2 Decision now 的 5 项，尤其是 `CMP-minimap` + source 快照的切分、DOM 真缩略图方案、固定 120px。
2. 确认 `SCN-0017` 放在 `navigation/in-document`（新增 value stream），不塞进既有 SCN-0002/0016。
3. 确认实现顺序：T15 minimap 骨架 → T16/T17 source → T18 菜单/桥 → T19 验证；P1 设计门未过不写实现代码。

**用户确认**：2026-11-04 设计门通过；2026-11-05 实现验收通过。

## 5. 开放问题

- 视觉验收的“接近 compare.png”由用户在 verify 阶段判定；若要求更接近截图的字形精度，需要重开 Decision now（提高快照保真/缩放策略），不能悄悄加大采样成本。
- 真实拖拽手感、触控板惯性按 R8 列为人工点验，不作为自动化通过条件。

## 6. 实现后复审（2026-11-04）

用户确认 P1 设计后，实现按 v2 七组件结构落地。第一门的五项 Decision now 不变，但实现细节有一处重要修正：

| 项 | 第一门设想 | 实现落地 | 结论 |
|---|---|---|---|
| 缩略图归属 | 新组件 `CMP-minimap`，source 由 domain editor/code 的公开投影提供 | 领域卡 `CMP-minimap` + 实现组件 `CMP-kernel-minimap`；source 是 editor/code 的**内部工厂**，经 `minimapSources` 端口注入 | 保持“一个组件只干一件事”；避免把 source 提升为跨域公开契约 |
| source 形状 | 跨组件 `CMP-editor#minimap-source` / `CMP-code-view#minimap-source` | 不新增公开契约；`createMarkdownMinimapSource` / `createCodeMinimapSource` 只由 `assemble.js` 消费 | 领域卡不复制实现契约；`check-kernel` 禁跨组件 import |
| 协议 | `setMinimapVisible` + `minimapInfo` + `init.opts.minimapVisible` | 同上；`HOST_OPS` 39→41，握手 `protocolVersion=2` | 加法扩展，向后兼容 |
| 布局 | 120px 轨 + 146px 预留 | 同上；源码模式同步取消预留；动态读系统滚动条宽度 | 无变更 |
| 验证 | 3+1 自动化 + 人工 | Node 85 项；selftest 缩略图 4 组断言；Markdown/长代码截图已出 | 2026-11-05 用户验收通过 |

**复审四档**：

- **Blocker**：无。
- **Decision now**：维持“第七个功能组件”边界；2026-11-05 真缩略图实现改为 DOM 克隆 + 顶左 fit；source 工厂留在内容面内部；不把 minimap 逻辑塞进 `CMP-kernel-core`（该组件已退役）或 document。理由：缩略图是独立阅读能力，和文档会话/编辑面不是同一变化轴。
- **Verified sound**：`minimap.test.js` 覆盖顶左 fit/内容矩形/空白区不响应/按内容高度拖动/只读脱敏；`core.test.js` 覆盖 init 偏好与 op 往返；selftest 覆盖默认显示/正文预留/开关；`check-kernel` 43 文件通过；`./build.sh debug` 全绿。
- **Hold**：性能阈值未仪表化；键盘/无障碍未做。均不阻塞本次交付。

**最终门通过**：2026-11-05 用户确认 Markdown 与代码窗口效果并同意提交推送；SCN-0017 转 `verified`、REQ-0011 转 `delivered`，本工序归档。
