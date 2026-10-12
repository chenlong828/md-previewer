---
layer: works
module: global
status: closed
updated: 2026-10-14
---

# 工序收口：死代码与不可达分支清理

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| 上表各位置删除后，`grep -rn` 验证无悬挂引用 | ✅ | `savedEncodingName` / `markdownExtensions` / `debugSummary` / `setSourceModeCached` / `pathPart` / `titlePart` / `jslog` / `editorStateCtx` / `callCommand` / `insertHardbreakCommand` / 幻影命令 / `getTheme` / `getZoomInfo` / `debugParse` / `debugView` / `debugState` / `__mdStage` 全仓 grep 零命中 |
| selftest 全部通过（命令注册表完整性断言无冲突） | ✅ | SELFTEST PASSED；`命令注册表完整(33 条)`——删除的幻影命令本就不在 EditorCommands.all，阈值不受影响 |
| `./build.sh` 构建通过，bundle 体积不增大 | ✅ | web bundle 9,594,242 → 9,593,206 字节（-1,036）；`swift build` 无警告 |
| OQ-2 选"仅 UTF-8"：删除变量并在 README 已知边界补承诺 | ✅ | 结论选 **a**；`savedEncodingName` 已删，README 已知边界新增"保存恒定 UTF-8 输出"（顺带记录 TextFile.write 无条件补尾换行的隐式行为，与 W7-Q5 文档化联动） |

## 删除清单与偏差记录

- Swift 侧 6 项、Selftest 死消息 1 项、JS 侧导入/监听/变量/桥 API 各项：按 brief 原表执行，无偏差。
- **偏差 1（超表删除）**：注册表幻影命令实为 **12 个**而非 8 个——brief 所列 8 个之外，`addRowAfterCommand` / `addRowBeforeCommand` / `addColAfterCommand` / `addColBeforeCommand` 同样已注册但 Swift 全部走 `tableCommand` 自实现，grep 验证零引用，一并删除。
- **偏差 2（同批修正）**：`waitForCollect` 超时静默掉出（`_ = name`）在 W1 扩建自检基建时已先行修复为 `fail(name)`（该缺陷属 W7-Q1，因其阻碍"红"的可信性提前落地；W7 收口时复核）。
- `window.__mdStage` 三个赋值点随 `debugState` 删除一并移除（唯一读取方消失）。

## 结论落点表

| 活结论 | 落点 |
|---|---|
| OQ-2 定案 a：承诺仅 UTF-8 输出，不做原编码保存 | 结论回写 [open-questions.md OQ-2](../../plan/open-questions.md)；承诺落 `README.md` 已知边界 |
| 命令注册表只登记 Swift 实际转发的命令名（表格行列命令不经此表） | `web/src/main.js` `commandRegistry` 注释 |

## 遗留

- 无。W3 的重复收敛以本序删除结果为基准。
