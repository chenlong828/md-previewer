---
layer: works
module: kernel
status: active
updated: 2026-11-04
---

# 工序 brief：内核 core 按功能组件拆分（P1）

> 承接 [2026-11-04-kernel-v2](../history/works/2026-11-04-kernel-v2/brief.md) 留下的债：
> 那次切换只做了「宿主解耦 + 语义单点」，编辑器本体连同 17 个文件整体搬进 `kernel/core/`，
> 结构未动。`core/ops.js` 442 行、26 个 import，是 39 个 op 的唯一聚合点。

## 1. 问题与证据

- **聚合点膨胀**：`core` 2182 行 / 17 文件（内核总量 2916 行，占 75%）；`core/ops.js` 单文件 442 行，
  同时持有会话、代码、命令、查找、导出、资源、诊断七类 op 的接线。
- **反向依赖三处**（拆分会立即变成循环）：
  1. `find-bar.js → code-view.js`（`findInCode`/`clearCodeFind`）；
  2. `export.js → editor.js`（`toggleSource`）；
  3. `editor.js → find-bar.js/find.js`（查找插件与命中计数）。
- **`CMP-kernel-core` 规格卡片自认是「组合模块、无独立对外契约」** —— 这是文档层面的自我否定，
  需按真实结构重切。

## 2. 决策（2026-11-04，用户确认）

- 粒度：**6 个功能组件 + shared**（不含独立的诊断组件；诊断 op 归 document）。
- 节奏：**分 4 批提交**，每批收尾时 Node 78 项与 selftest 115 PASS 不得下降。

## 3. 目标结构

```
web/src/kernel/
  transport/channel.js          L0  宿主通道（唯一宿主感知点）
  contract/                     L1  信封/op 清单/注册表/错误码
  semantics/                    L1a 路径与 markdown 语义（纯函数）
  shared/{state,bus,ports}.js   L1a 共享内核：会话状态、端口、通知/请求
  components/
    document/   L1b 会话与文档（init/setMarkdown/getSaveMarkdown/setBaseDir/主题/缩放/诊断 op）
    editor/     L1b 编辑面（Milkdown 装配、命令、表格、统计、选区、源码切换、NodeView 注册）
    code/       L1b 代码面（只读源码视图、高亮语言、行号、代码内查找）
    find/       L1b 查找（状态机、查找栏、遍历）
    output/     L1b 输出（独立 HTML 导出、打印、内容几何）
    media/      L1b 图片媒体（粘贴载荷识别、导入编排）
```

- **组合根**：`web/src/page.js` 仍唯一；各组件导出 `createXxxOps(deps)`，由组合根汇总注册。
- **跨组件一律走 `shared/ports.js`**：`searchSurface`（code 注册、find 消费）、
  `renderSurface`（editor 注册、output 消费）、`imageInsertion`（editor 注册、media 消费）。
  组件之间禁止互相 import，禁边脚本负责守门。

## 4. 批次

| 批次 | 内容 | 收尾判据 |
|---|---|---|
| S1 | 抽 `shared/`（state/bus/ports 雏形）；`core/ops.js` 拆成 `components/*/ops.js` 分片与装配 | ✅ 完成（2026-11-04，`41cf144`）：shared 层 + 六片装配；Node 78 + selftest 115 全绿；ops.js 已删除 |
| S2 | `code` 与 `find` 成组件迁移；`find → code` 改 `searchSurface` 端口 | 同上；两组件互不 import |
| S3 | `output` 与 `media` 迁出；`export → editor` 改 `renderSurface`；粘贴插入改 `imageInsertion` | 同上；端口注入由组合根完成 |
| S4 | `document` 与 `editor` 收口；`check-kernel.mjs` 升级为组件级禁边；组件规格与架构文档同步 | 同上；文档与结构一致 |

## 5. 验证

- 每批：`cd web && npm run verify`（lint + 禁边 + 78 项）+ `./build.sh debug` + `--selftest`（115 PASS）。
- 断言数只许增不许减；组件拆分不得改变任何 op 的语义（契约测试与 core 组测试即守门）。
- 禁边脚本在 S4 增加：组件间禁止互相 import；`shared/` 不得 import 任何组件。

## 5.1 端口设计（S2/S3 实现要点）

`shared/ports.js` 是依赖倒置的落点：组件在组合根装配时 `provide(name, impl)`，消费方 `use(name)`。四个端口：

| 端口 | 提供方 | 消费方 | 内容 |
|---|---|---|---|
| `searchSurface` | code | find | `findInCode(text) / clearCodeFind() / codeFindCount()`：代码面的查找实现 |
| `proseFind` | find | editor | ProseMirror 查找插件 + keymap + 命中计数回调（editor 装配时需要） |
| `renderSurface` | editor | output | `ensureRendered()`：导出前确保处于渲染模式（源码模式要切回） |
| `imageInsertion` | editor | media | `insertImageNode({src,alt,title})`：媒体组件只管落盘与载荷，插入动作归编辑面 |

规则：`shared/` 只存注册表与类型约定，不含实现；组件之间零 import，禁边脚本在 S4 增补规则
（`components/<a>/` 不得 import `components/<b>/`）。

## 6. 风险

- **迁移期双份路径**：`git mv` 后 import 全面改，容易漏改；以 lint + 构建失败兜底。
- **端口设计偏差**：若某个耦合不是「能力」而是「同一能力的两半」，应先合并能力再拆（S2/S3 时复核）。
- **尺寸反弹**：编辑面预估 ~600 行仍偏大，S4 后若 `editor` 组件超 800 行，需再评估是否把 NodeView 注册下沉。
