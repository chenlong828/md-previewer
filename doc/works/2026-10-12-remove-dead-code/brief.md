---
layer: works
module: global
status: active
updated: 2026-10-12
---

# 工序：死代码与不可达分支清理

纯减法批次：只删除经 grep 验证零引用的代码，不改行为。每删一处前先验证
"定义处即唯一引用处"；涉及语义承诺的删除（编码、诊断面）先看
[open-questions.md](../../plan/open-questions.md) 的对应条目。

## 问题清单

### Swift 侧（Sources/MDPreview/）

| 项 | 位置 | 说明 |
|---|---|---|
| 死常量 `markdownExtensions` | DocumentWindowController.swift:31 | 全仓库唯一引用处即定义；内含重复 `"mdown"`。真正的扩展名清单收敛在 W3 |
| 只写不读 `savedEncodingName` | DocumentWindowController.swift:28, 174, 625 | 删除动作属本序；背后"是否按原编码保存"的语义决策见 [OQ-2](../../plan/open-questions.md) |
| 无人调用 `debugSummary()` | DocumentWindowController.swift:18 | |
| 无人调用 `setSourceModeCached()` | DocumentWindowController.swift:764 | |
| 死函数 `pathPart` / `titlePart` | Util.swift:92-104 | 被 `replaceImages` 内联逻辑取代的遗留 |
| 死参数 `append(contextTarget:)` | EditorCommands.swift:91 | 所有调用点均省略 |

### JS 侧（web/src/main.js）

| 项 | 位置 | 说明 |
|---|---|---|
| 死导入 `editorStateCtx` | main.js:5 | |
| 死导入 `callCommand` | main.js:59 | |
| 死导入 `insertHardbreakCommand` | main.js:22 | 导入后从未注册、从未调用 |
| 空 `input` 监听 | main.js:217-219 | 监听体为空注释 |
| 未使用变量 `table` | main.js:506 | `insertRowInTable` 内赋值后未用 |
| 注册表幻影命令 ×8 | main.js:43-51 | `goToNext/PrevTableCellCommand`、`setAlignCommand`、`deleteSelectedCellsCommand`、`liftListItemCommand`、`sinkListItemCommand`、`updateCodeBlockLanguageCommand` 已注册但 Swift 侧 0 引用；`updateImageCommand`（:47）误导——图片粘贴尚未实现 |
| 无人调用桥 API | main.js:904, 1101, 1103-1113, 1115-1126, 1128-1135 | `getTheme`、`getZoomInfo`、`debugParse`、`debugView`、`debugState`。`debugFocusTable`/`tableInfo` 被 selftest 使用，保留。诊断面整体去留见 [OQ-3](../../plan/open-questions.md) |
| 死消息 `op:'jslog'` | Selftest.swift:216 | 原生侧无任何接收 case，"直接测试"实际无效 |
| 混合类型返回 `findInfo()` | main.js:1013-1026 | `count` 可能是数字或 `'not-ready'` 字符串；统一为数字（-1 表示未就绪）或抛错 |

## 验收标准

- [ ] 上表各位置删除后，`grep -rn` 验证无悬挂引用
- [ ] selftest 全部通过（含命令注册表完整性断言——注意其阈值 `>= 30`
      与本序删除无冲突，删除的幻影命令本就不在 EditorCommands.all 里）
- [ ] `./build.sh` 构建通过，bundle 体积不增大
- [ ] OQ-2 若选"仅 UTF-8"：删除变量并在 README 已知边界补一句；若选 b 则本项出序独立立项

## 依赖与顺序

- 前置：建议 [W1 fix-latent-defects](../2026-10-12-fix-latent-defects/brief.md) 收口后开工
  （同文件 main.js / DocumentWindowController.swift，避免交叉改动）。
- 后继：W3 的"重复收敛"以本序删除结果为基准。
