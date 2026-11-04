---
layer: works
task: W-KERNEL-CORE-SPLIT
status: done
updated: 2026-11-04
---

# 结果：内核按功能组件拆分

## 结论

`kernel/core/`（17 文件、2182 行、占内核 75%）解体为 **六个功能组件 + shared**，
组件间零 import、跨组件能力走 `shared/ports.js` 端口、禁边脚本把这条纪律钉进构建。
op 语义、协议帧、壳侧行为均未改变。

## 结构（终态）

```
web/src/kernel/
  transport/channel.js     L0 宿主通道（唯一宿主感知点）
  contract/                L1 信封 / op 清单 / 注册表 / 错误码
  semantics/               L1a 纯语义（零依赖）
  shared/{state,bus,ports} L1a 会话状态、通知与请求、端口注册表（零第三方依赖）
  components/
    document/  137 行   会话与文档：装载/取回/基线/主题/缩放/引用收集
    editor/   1046 行   编辑面：Milkdown 装配、命令、表格、统计、选区、NodeView、诊断 op
    code/      553 行   代码面：只读源码视图、语言、行号、代码内查找
    find/      304 行   查找：查找栏、遍历、ProseMirror 装饰
    output/    104 行   输出：独立 HTML、打印、内容几何
    media/      75 行   图片媒体：载荷识别、导入编排（不碰事务）
  assemble.js + ops.js    组合根内核侧：端口接线 + op 汇总（唯一装配点）
```

`kernel/core/` 已不存在。`currentMarkdown()` 回到 `shared/state.js`，引擎序列化经
`state.serialize` 钩子由 editor 注入——shared 因此保持零第三方依赖。

## 端口（8 个）

| 端口 | 提供方 | 消费方 |
|---|---|---|
| `findService` | find | editor / code |
| `searchSurface` | code | find |
| `codeSurface` | code | document |
| `codeLanguages` | code | editor |
| `editorSurface` | editor | document |
| `renderSurface` | editor | output |
| `imageInsertion` | editor | media |
| `mediaPaste` | media | editor / diagnostics |

装配单点：`assemble.js`。页面入口与测试组合根共用，杜绝「测试里另装一份」。
未装配即抛 `port not provided`，不静默降级。

## 验证（每批都跑，非终局补测）

| 门 | S1 | S2 | S3 | S4 |
|---|---|---|---|---|
| lint | 0 | 0 | 0 | 0 |
| check-kernel | OK 33 | OK 37 | OK 37 | OK 36 |
| Node 套件 | 78/78 | 78/78 | 78/78 | 78/78 |
| selftest | 115 PASS | 115 PASS | 115 PASS | 115 PASS |
| 粘贴 e2e | — | — | 通过 | 通过 |

粘贴 e2e（`MDP_PASTE_IMAGE`）在 S3、S4 各复验一次：插入实现从 media 移到 editor 端口后，
`paste → importImage → 落盘 → 插入` 全链路未退。

## 落地偏差（相对 brief）

1. **诊断 op 归 editor 而非 document**：它们读 ProseMirror 内部状态（命令表、表格、选区），
   放 document 会造成 document → editor 的反向依赖；归 editor 后该文件与命令表同址。
2. **`proseFind` 端口并入 `findService`**：同一个消费方（editor）需要插件、keymap 与计数，
   拆两个端口只会多一次装配。（原计划四个端口，实际八个。）
3. **`focusEditorView` 从 document/render 移入 editor**：焦点是编辑面知识，放 document 属错位。

## 已知未覆盖

- 打印与「另存为」的 baseDir 时序仍靠 CMP-app-shell 的人工清单（自动化成本高于收益）。
- 87 处 selftest `evaluate` 仍经 `window.mdbridge` 测试垫片（v1 兼容面），未随本次拆分收敛。
