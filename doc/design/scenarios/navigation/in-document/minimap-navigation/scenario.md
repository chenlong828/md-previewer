---
layer: design
module: navigation
status: designed
updated: 2026-11-04
flow: FLOW-NAV-003
scenario: SCN-0017
domain: 导航
valueStream: 文档内定位
title: 用右侧缩略图掌握全文并定位
entries:
  - CMP-minimap/web/src/minimap.js#createMinimap
  - CMP-minimap/web/src/minimap.js#setSource
  - CMP-minimap/web/src/minimap.js#setVisible
  - CMP-minimap/web/src/minimap.js#minimapInfo
  - CMP-editor/web/src/editor.js#createMarkdownMinimapSource
  - CMP-code-view/web/src/code-view.js#createCodeMinimapSource
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#toggleMinimapAction
docs:
  - path: doc/requirements/REQ-0011-document-minimap.md
    heading: 5. 影响场景
  - path: doc/design/components/CMP-minimap/spec.md
    heading: 公开契约细节
tests:
  - role: R1
    id: TC-MINI-001
  - role: R2
    id: TC-MINI-002
  - role: R3
    id: TC-MINI-003
  - role: N1
    id: TC-MINI-004
---

# 用右侧缩略图掌握全文并定位

## 1. 场景与价值

用户打开一篇超过一屏的 Markdown 文档，或一个只读代码文件；右侧出现整篇内容的真缩略图，当前视口用一个半透明蓝框标出。用户滚动正文时框同步移动；点击缩略图任意位置跳到目标附近，或按住视口框上下拖动连续定位。用户可以从「视图 → 显示文档缩略图」关闭，偏好跨窗口保留；源码模式与一屏内的短文档不显示。

结果：长文档不必靠系统滚动条盲找位置；用户先掌握整体结构，再直达目标，同时正文、复制、查找、文件内容与导出语义完全不变。

本场景不覆盖文件打开/保存（SCN-0002）、代码装载与高亮（SCN-0016）、抽屉（SCN-0001）与导出内容（SCN-0014）；缩略图只属于阅读辅助层，不写文件。

## 2. 入口

- `CMP-minimap#source`：组合根 `main.js` 把 `CMP-editor#minimap-source` 或 `CMP-code-view#minimap-source` 注入 `CMP-minimap`；源码模式注入 `null`。
- `CMP-minimap#visibility`：原生偏好经 `window.mdbridge.setMinimapVisible` 下发；有效显示在组件内计算。
- `CMP-minimap#viewport` / `#pointer`：滚动事件与缩略图栏指针事件。
- `CMP-editor#minimap-source`：Markdown 顶层块的几何、文字与图片投影（只读）。
- `CMP-code-view#minimap-source`：代码逻辑行的文本、几何与颜色投影（只读）。
- `CMP-app-shell#minimap-menu`：视图菜单项、勾选、偏好写入口、跨窗口广播。

## 3. 运行序

流程定义：`FLOW-NAV-003`。

1. 装载：文档打开后，组合根按当前内容面注入 source；`CMP-minimap` 读取 `measure()`，判断偏好、内容面与溢出（带 32px 滞回）。
2. 布局：有效显示时给 `body` 加 `minimap-shown`，正文预留 146px；⌘F 查找栏左移避让；右侧保留系统滚动条。
3. 绘制：按块类型与文字采样绘制内容层；最后绘制视口框；绘制模式为 `full`；超量时转 `compact`。
4. 滚动：正文滚动 → passive `scroll` 合并到 rAF → 只更新视口框；不重绘内容层、不测量整篇 DOM。
5. 定位：点击缩略图 → 目标点居中 → source `scrollTo`；在视口框内按下拖动 → 指针捕获 → 连续滚动 → 松开/取消释放。
6. 开关：视图 →「显示文档缩略图」→ 写 `UserDefaults["minimapVisible"]` → 广播所有窗口 → 每个窗口隐藏/显示并重排正文；勾选同步。
7. 内容变化：Markdown 编辑、代码切换语言/行号、图片/Mermaid 编辑结束 → MutationObserver/显式 `refresh` 防抖 250ms → 重新投影并绘制，保持当前滚动位置。
8. 外观/尺寸：主题、缩放、窗口尺寸、代码行号开关 → 重新测量并绘制；视口框保持当前比例。
9. 切换内容面：`setMarkdown` → Markdown source；`setCode` → 代码 source；源码模式 → `null` 并隐藏；返回渲染面时重新挂载。
10. 打印/导出：打印/PDF 隐藏缩略图并取消正文预留；HTML 导出只取编辑器内容，不含缩略图。

失败路径：

- 内容未就绪/空文档/无溢出：不显示，不占正文宽度，不报错。
- 源码模式：`setSource(null)`，隐藏并把菜单项置灰；返回渲染面后恢复。
- 图片/图表加载失败：该块画占位，不影响其他块、不抛 `jserror`。
- 测量/Canvas 异常：隐藏缩略图并 `console.warn` 一次；正文滚动与编辑不受影响。
- 超量内容：进入 `compact`，只画块/行密度；点击/拖动仍可用；不阻塞打开。
- 点击越界：夹取到 `[0, docHeight - viewportHeight]`；不出现负滚动或底部空白。
- 拖动中指针取消/离开：释放捕获并清状态，不残留“粘住”的滚动。
- 缩略图显示/隐藏临界：32px 滞回防止布局抖动。
- 原生调用早于 web ready：bridge guard 后丢弃/缓存；init 后的偏好为准。

## 4. 不可变引用

- `architecture.md` §2.4 的正文宽度/抽屉联动与 §2.7 的代码只读、512 KB 上限、行结构。
- `CMP-editor#get-markdown` / `#source-mode`：缩略图不改变文档内容与源码模式语义。
- `CMP-code-view#set-code` / `#line-layout` / `#large-guard`：代码文档只读、无脏、行结构是投影来源，不因缩略图重建或改写。
- `CMP-app-shell#open-document` / `#menu-commands`：菜单命令表与窗口路由不变；只新增一个勾选项。
- `CMP-document-io` 的保存/编码口径、`CMP-export` 的 PDF/打印/HTML 内容面不变。
- 桥协议既有 op 语义不变；新增 Swift→JS 可见性入口必须向后兼容。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-MINI-001 | R1 | 自动 | `--selftest` | `PASS 缩略图 Markdown 显示与投影`：长文出现 rail、`minimapInfo.visible=true`、`mode='full'`、block 数 >0、坐标有序、正文有 146px 预留 | missing |
| TC-MINI-002 | R2 | 自动 | `--selftest` | `PASS 缩略图 滚动同步与点击定位`：滚动后视口 top 比例一致；点击 50% 后滚动比例居中；越界夹取；滚动不增加 `redrawCount` | missing |
| TC-MINI-003 | R3 | 自动 | `--selftest` + `--multiwindow-test` | `PASS 缩略图 代码面与开关`：代码视图 `mode='code'`、行投影数量正确；菜单开关隐藏/显示并跨窗口生效；源码模式/短文档隐藏 | missing |
| TC-MINI-004 | N1 | 自动 | `--selftest` | `PASS 缩略图 超量与失败降级`：超量进入 `compact` 不抛错、仍可定位；图片失败占位；空文档/未就绪不显示；缩略图操作不增加 `changed` | missing |
| TC-MINI-005 | R1 | 人工 | `--screenshot` + 真机 | 深色主题、120px 视觉宽、正文/查找栏无遮挡；视觉接近 `compare.png` | missing |
| TC-MINI-006 | R2 | 人工 | 真机拖拽 | 视口拖动跟手、触控板惯性不抖、指针移出边界不粘住 | missing |
| TC-MINI-007 | N1 | 人工 | PDF/打印 | 缩略图不出现、正文无预留空白 | missing |

配套断言：既有 Markdown 编辑/保存/查找、代码视图行号/查找/大文件、主题缩放、抽屉、双窗口全部零回归；`minimapInfo()` 只暴露几何/模式，不暴露 DOM。

## 6. 验证债

- 组件与 source 尚未实现；TC-MINI-001～004 全部 `missing`。
- 真缩略图的视觉判断依赖人工（TC-MINI-005），不承诺逐字可读；以 `compare.png` 为目标。
- 真实拖拽/触控板惯性、深色主题、窗口缩放属于 R8 人工项（TC-MINI-006）。
- 性能阈值（内容层 ≤50ms、滚动 ≤1ms）需在 verify 任务实测；未达标先调采样上限，不改变交互语义。

## 7. 变更记录

- 2026-11-04 新建（REQ-0011，P1 设计工序 `2026-11-04-document-minimap`）；场景放在 `navigation/in-document`，覆盖 Markdown 渲染面与代码只读面；源码模式不覆盖。
