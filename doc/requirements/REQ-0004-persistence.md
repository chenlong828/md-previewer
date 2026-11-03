---
layer: requirements
module: persistence
status: accepted
updated: 2026-11-04
---

# REQ-0004：文档打开、保存与规范化

**类型**：quality

## 1. 场景叙述

用户打开一个 Markdown（UTF-8 或 GB18030），在应用里查看/编辑后保存；应用不误报脏、不破坏原内容，保存结果恒为 UTF-8、末尾补一个换行、列表按每级 4 空格规范化；文件被外部程序修改时，应用能自动重载或询问保留。

结果是：打开的文件不坏、保存的文件可读，纯查看不会弹出保存询问，外部变更不会静默覆盖。

## 2. 价值

不做的后果：GB18030 文件保存后乱码；无尾换行文件每次保存都产生无意义 diff；纯查看被误判为修改；外部编辑与本地编辑互相覆盖，丢内容。

## 3. 非目标

- 不保持原编码回写；保存一律 UTF-8。
- 不做自动保存、版本历史、文件锁、冲突合并。
- 不做多文档共享同一文件。
- 不改变 Markdown 语义；规范化只限尾换行与列表缩进。

## 4. 行为约定

- 打开：UTF-8 优先，失败回退 GB18030；识别失败明确报错。
- 保存：恒 UTF-8；末尾恰好一个换行；列表每级 4 空格，首行标记紧凑；图片路径先 `forSave`。
- 脏基线：加载/保存/源码切换后为干净；撤销回原文恢复干净；纯查看不弹保存。
- 外部变更：干净则自动重载；脏则询问“保留我的修改/重新加载”，不自动覆盖。
- 关闭：脏文档先确认；取消则不关闭。

## 5. 影响场景

| 场景 | 状态 | 本次新增/修改的断言 |
|---|---|---|
| [SCN-0002 打开、编辑与保存](../design/scenarios/editing/document-lifecycle/open-edit-save/scenario.md) | designed | 打开即编辑、脏基线、保存、关闭确认；保存失败不破坏原文件 |
| [SCN-0003 保存规范化](../design/scenarios/editing/document-lifecycle/save-normalization/scenario.md) | designed | UTF-8 回写、尾换行、列表 4 空格、2 空格旧文件可开 |
| [SCN-0004 外部变更](../design/scenarios/editing/document-lifecycle/external-change/scenario.md) | draft | 干净自动重载；脏询问保留/重载 |

## 6. 验收归属

验收 = 三个场景全部 `verified` + 第 4 节约束未被违反。当前 SCN-0004 仅 draft，故保持 `accepted`。

## 7. 澄清记录

- 2026-11-04 五态补录：从 `architecture.md` §2.2/§2.3、README 与历史工序结果反推。
- 编码/尾换行/外部变更缺自动化，先记验证债，不假装 verified。

## 8. 状态

`accepted`；待 SCN-0002/0003/0004 verified 后转 `delivered`。
