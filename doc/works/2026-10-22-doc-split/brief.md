---
layer: works
module: global
status: active
updated: 2026-10-24
---

# 工序 brief：design 文档按读者下沉（architecture.md 拆分层）

## 需求

把 `doc/design/architecture.md`（264 行，2026-10-24 基线）里只属于单一模块的实现级契约下沉到模块目录，
让 architecture.md 回归「系统层跨模块真相」。范围经用户 2026-10-22 定为**按需下沉**：

- 下沉：图片（§2.1 + §2.1a）→ `design/image/`；文件抽屉（§2.4）→ `design/drawer/`；
  诊断面（§3）→ `design/diagnostics.md`（module: global）。
- 保留在 architecture.md：拓扑与框图、§1 安全取舍、§2.2/§2.3 保存行为、§4 桥协议。
- 不新建 `product.md`；不动代码；不重写语义。工程量 S。

## 背景（为什么现在拆）

- **增长**：10 天 129 → 247 行（约 1.9×），功能提交每次都往 §2 尾部追加。
- **混层**：§2 占 140 行（57%），其中 image 63 行 + drawer 56 行 = 119 行，占全文 48%，
  全部由单一模块的实现变化驱动，却挤在所有人都要读的全局文档里。
- **结构症状**：`§2.1a` 是补丁式编号（没有位置可放新主题）；intro 声明「细节实现以代码
  注释为准」，正文却写 8pt 热区、160–480 夹取、`percentDecodedPath` 这类常量级细节。
- **违规信号**：§2.1a「替代三字段小表单」、§2.4「曾用 shouldExpand…已废弃」是事后回填，
  与现行真相混排（doc-layout-spec 明列）
- **一处一事已破**：仓库根 README「架构」节的框图与桥 op 列表和 architecture.md 不一致
  （README 的 JS→Swift op 缺 `selinfo`/`importImage`；框图缺 clipboard/trailing/listener，
  另一份却缺 typora.css）。
- **状态失真**：frontmatter `updated: 2026-10-21`，但正文 2026-10-22 已两次改 §2.4。
- **引用面**：现行文档 12 处、冻结件（history/）36 处引用该文件，多处带 `§X.Y` 编号——
  拆分的主要成本就在这里。

## 拆分原则（本工序判据）

1. **按「读者 + 变更同频」拆，不按章节对称拆**：只被单一模块实现驱动、只需要改那个模块的
   人读的段落 → 下沉；需要 ≥2 个模块同时遵守 → 留 global。
2. **全局文档只放横切约束**；模块内部实现契约归 `design/<module>/spec.md`。
3. **决策三件套整体搬**（决策/理由/失效条件不拆散）；常量、像素值、夹取区间不进文档，
   由代码与 selftest 断言守门。
4. **先删后拆**：搬迁前先做去重（README 桥 op 列表与框图）与历史句出清（「已废弃/替代了」
   移入坑档案或 ADR，正文留现行 + 一句否决指针）。
5. **引用按「文件 + 小节标题」**，不再按编号；冻结件不回改，用 result.md 对照表 +
   architecture.md 首部一句迁移说明兜底可追溯。
6. **只搬不写**：本工序不改语义（除标题、链接、去重、历史句迁移），以便逐段守恒核对。

## 目标结构与映射

| 现位置 | 行数 | 去向 |
|---|---|---|
| 1–28 头部/定位/框图 | 28 | architecture.md 保留（框图收敛为唯一一份；README 删重复） |
| §1 安全取舍 | 37 | architecture.md 保留（横切：全盘读授权 / mermaid loose / 桥面收敛） |
| §2.1 + §2.1a 图片 | 63 | `design/image/spec.md`（改写契约 / NodeView 编辑 / 导入落盘 / GC / 边界） |
| §2.2 + §2.3 保存行为 | 19 | architecture.md 保留；触发线：再涨约 10 行或出现第二条文档 IO 决策 → `design/document-io/spec.md` |
| §2.4 抽屉与目录模式 | 56 | `design/drawer/spec.md`（lazy 装载 / 锚定 / 拖拽调宽 / 窗口收敛 / pendingOpen / 目录模式） |
| §2.5 列表序列化 | 17 | architecture.md 保留（横切 markdown 格式契约，≥2 模块遵守） |
| §3 诊断面 | 19 | `design/diagnostics.md`（module: global） |
| §4 桥协议 | 22 | architecture.md 保留（v1 现行 + v2 存档指针） |

预估：architecture.md ≈ 127 行（含 §2.5 的 17 行），image ≈ 65，drawer ≈ 58，diagnostics ≈ 20。

## 基线更新（2026-10-24 执行前复核）

- **总行数 247 → 264**：唯一增量是 2026-10-24 新增的 §2.5（列表序列化 4 空格契约，
  17 行）。各段行数与立项时完全吻合（§2.1+2.1a=63、§2.2+2.3=19、§2.4=56、§3=19、§4=22）。
- **§2.5 保留在 architecture.md**：按本 brief 判据（≥2 个模块遵守的横切契约）它不该下沉，
  已加入上方映射表，预估 architecture.md 终稿 ≈127 行。
- **引用面 36 → 39 处（冻结件）**：增量正是 2026-10-24 归档工序的 brief/result 引用 3 处；
  现行 `doc/works` 下两个抽屉工序 result 各有 3–4 处 §2.4 引用，拆分时一并改。
- **执行切片**：先切 §3 诊断面（19 行、零代码引用冲突）验证「搬运 + 引用改写」流程，
  再动 §2.1 图片、§2.4 抽屉；README 去重与历史句出清在最后收口一遍。

## 验收标准

1. **守恒**：原 264 行每段在目标树中恰好出现一次（新增标题/链接/迁移说明除外），逐段打勾。
2. **链接可达**：现行文档（README、plan/*.md、未归档 works/*/result.md）里指向
   architecture.md 的引用改为「文件 + 小节标题」且可点开；history/ 冻结件不回改，
   由 architecture.md 首部迁移说明 + result.md 对照表兜底。
3. **frontmatter 合规**：layer/module 与路径一致（image/drawer 目录名 = module 值），
   updated 为 2026-10-24，status 按层取合法值。
4. **去重**：仓库根 README 不再复制桥 op 列表与框图，改为指向 design；框图唯一一份。
5. **历史句出清**：现行文档不再出现「已废弃 / 替代了 X」的叙述。
6. **无新增事实**：不写新决策；确需补写的登记 open-questions。

## 领取的开放问题

无（本工序不改代码、不改语义）。遗留待议（本工序不建占位）：是否新建 `product.md`
承接产品画像与组件划分、`document-io/` 是否为 §2.2/§2.3 的终局归属——按触发线在后续
工序再定。
