---
layer: works
module: global
status: closed
updated: 2026-10-14
---

# 工序收口：结构治理（main.js 拆分 + Swift 菜单表驱动 + lint）

## 验收结果

| 验收标准 | 结果 | 实证 |
|---|---|---|
| main.js 拆为职责单一模块，单文件不超过 ~300 行；esbuild 构建产物功能等价 | ✅ | 拆为 11 个模块（最大 bridge.js 282 行）；`node build.mjs` 通过，bundle 9,593,546 字节（与拆分前 9,593,206 同量级，差异来自模块头注释） |
| selftest 全部通过（拆分前后各跑一次留档于本工序目录） | ✅ | `selftest-拆分前.txt` / `selftest-拆分后.txt` 均 SELFTEST PASSED、PASS 数一致 |
| ESLint 接入且 0 error；`state` 形状静态声明 | ✅ | flat config（no-unused-vars/no-undef 等 8 条核心规则）；`state.js` 字面量显式声明全部字段；`npx eslint src` 退出码 0 |
| 菜单 identifier 编译期可查（常量/枚举），字符串裸引用清零 | ✅ | `MenuID` 常量枚举；联动查找（findMenu/updateMenuItem/menuNeedsUpdate）全部比较 identifier；裸字符串仅存在于 MenuID 定义点 |
| `./build.sh` 通过 | ✅ | 见批次四收口时的完整构建（build.sh 完整跑通） |

## 模块地图（web/src/）

| 模块 | 职责（一句话） | 依赖 |
|---|---|---|
| `state.js` | 全局状态单例（显式声明）+ 原生消息通道 + 内容真相源访问器 | @milkdown/utils |
| `stats.js` | 词数统计计算与节流上报 | state |
| `theme.js`（并入 editor） | 主题应用（DOM/mermaid） | state, mermaid |
| `mermaid-view.js` | mermaid 自定义 NodeView（渲染/编辑交互） | diagramSchema |
| `editor.js` | 编辑器装配与源码模式切换 | state, stats, find, find-bar, selinfo, mermaid-view |
| `selinfo.js` | 光标表格状态上报插件 | state |
| `find.js` | 查找搜索核心与高亮插件（纯逻辑） | 无项目内依赖 |
| `find-bar.js` | 查找栏 UI wiring | state, find |
| `tables.js` | 表格行列几何操作 + 命令名表 | 无项目内依赖 |
| `commands.js` | Swift↔JS 命令名的 JS 侧权威注册表 | 预设导出 |
| `export.js` | 独立 HTML 导出 | state, editor |
| `bridge.js` | window.mdbridge API 表面 | 上述全部 |
| `main.js` | 入口：样式装配 + wiring + boot | bridge, state, stats, find-bar |

依赖方向无环：main → bridge → {editor, find-bar, tables, commands, export} → state。

## 决策记录

- OQ-5 定案 **a**：esbuild 多模块 + ESLint + JSDoc 注释，不迁 TypeScript（成本收益评估见 open-questions 回写）。
- 拆分期间引入 `getMermaidView()` 惰性装配函数：ESM 导入不可赋值，`mermaidView ??=` 的装配点收进 mermaid-view 模块自身。
- 菜单构建新增 `appendSubmenu` 声明式辅助，buildMenus 由逐级声明改为构建器闭包，行数 130 → 约 100 且嵌套直线可读。

## 结论落点表

| 活结论 | 落点 |
|---|---|
| main.js 拆分粒度（11 模块 + 依赖方向） | `web/src/`（上表）+ [open-questions.md OQ-5](../../plan/open-questions.md) |
| 菜单 identifier 常量与三态联动表 | `Sources/MDPreview/AppDelegate.swift` `MenuID` / `appearanceItems` / `appendSubmenu` |
| ESLint 门禁与仓库约定（catch 绑定豁免、下划线占位形参） | `web/eslint.config.js`、`web/package.json` lint script |

## 遗留

- 无。W5 时序治理与本序文件不相交。
