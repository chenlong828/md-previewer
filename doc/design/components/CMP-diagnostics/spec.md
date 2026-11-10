---
layer: design
module: diagnostics
component: CMP-diagnostics
status: active
updated: 2026-11-10
---

# 诊断面组件规格

## 组件卡

- 状态：active
- 单元：组件
- 层 / 类型：L0 基础能力；技术边界
- 业务价值：为排障者提供不依赖 GUI 的自检、进程内截图与多窗口回归入口；没有它，release 包在用户机器上的问题无法复现与取证。
- 负责 / 不负责：负责四个 CLI 入口的语法、输出前缀、退出码与环境钩子；不负责业务功能，不负责编辑器交互逻辑。
- 内部逻辑：自检检查项（`SelftestRunner`）、截图阶段机（`ScreenshotRunner`）、多窗口断言（`main.swift` 的 `--multiwindow-test` 分支）、右键定位断言（`main.swift` 的 `--context-menu-test` 分支：合成右键事件 → 捕获菜单 → 执行菜单项）。
- 拥有的数据：无持久数据；截图写指定输出文件，诊断日志走 stdout/stderr。
- 变化轴：诊断入口的 flag、输出格式与检查项；随 release 构建发布。
- 公开契约（含能力 ID）：
  - `CMP-diagnostics#selftest`
  - `CMP-diagnostics#screenshot`
  - `CMP-diagnostics#multiwindow`
  - `CMP-diagnostics#context-menu`
- 入口：
  - `CMP-diagnostics/Sources/MDPreview/main.swift#args`（四个 flag 的分发）
  - `CMP-diagnostics/Sources/MDPreview/Selftest.swift#SelftestRunner.run`
  - `CMP-diagnostics/Sources/MDPreview/Screenshot.swift#ScreenshotRunner.run`
- 依赖：AppKit / WebKit；被测对象 EditorWebView、DirectoryTree、ImageStore。
- 冷热属性：冷路径；不进编辑热路径。
- 尺寸预算：目标 ≤120k token；当前源码约 2.9k 行（Selftest 2047 + Screenshot 156 + main 661），实测值待脚本生成。
- 单独运行：
  - `./.build/debug/MDPreview --selftest`
  - `./.build/debug/MDPreview --screenshot out.png doc.md`
  - `./.build/debug/MDPreview --multiwindow-test --fileA=/path/a.md --fileB=/path/b.md`
  - `./.build/debug/MDPreview --context-menu-test`
- 验证计划：四个入口各跑一次；覆盖退出码 0/1 与截图阶段失败码 2–7；环境钩子与 web 诊断留痕各验一次。
- 删除测试：删掉后 release 排障只能依赖用户现场描述，复杂度集中而非消失 → 真边界。

## 四个入口

诊断代码随 release 构建发布是**有意保留**：单机工具无线上灰度能力，官方
诊断面是问题排查的唯一手段。四个入口统一风格如下：

| 入口 | 语法 | 输出前缀 | 退出码 |
|---|---|---|---|
| 无头自检 | `MDPreview --selftest` | `PASS/FAIL  名称` 每行一项，末行 `SELFTEST PASSED/FAILED` | 0=全过 / 1=有失败 |
| 进程内截图 | `MDPreview --screenshot out.png [input.md]` | `SCREENSHOT …` | 0=成功；2/3/4/5/6/7=各阶段失败（见 Screenshot.swift） |
| 多窗口诊断 | `MDPreview --multiwindow-test --fileA=/path/a.md --fileB=/path/b.md` | `[MULTIWINDOW] PASS/FAIL 检查项` + info 行 | 0=全过 / 1=有失败 |
| 右键定位诊断 | `MDPreview --context-menu-test` | `[CONTEXTMENU] PASS/FAIL 检查项` | 0=全过 / 1=有失败 |

`--context-menu-test` 生成临时受控文档，向真实窗口投递合成右键事件（走
`EditorWebView` 的真实监视器与坐标换算），经注入的 `presentContextMenu` 捕获菜单
而不阻塞在菜单跟踪里，再执行菜单项并按单元格文本断言“作用在点击行”。

## 环境钩子与 web 侧留痕

- 截图模式环境钩子 `MDP_IMPORT_IMAGE=<图片路径>` / `MDP_EDIT_IMAGE=1`:
  加载文档后执行一次「导入→落盘→插入」全链路 / 打开第一张图片的源码编辑块
  再截图(图片导入与编辑框几何的 e2e 验证口)。
- web 侧诊断留痕：`window.__exportedHTML`（自检轮询用，页面级临时变量）、
  `mdbridge.testImagePayload(data)`(剪贴板载荷识别,自检断言用)。
- WebLocator（`#filePath` 唯一用点）仅服务于诊断/开发定位，W3 已限定在
  Util.swift 单点。

## 历史

> 2026-10-24 自 [architecture.md](../../architecture.md) 原 §3 下沉，正文未改语义；
> 桥协议相应由 §4 顺延为 §3（冻结件中的旧编号不回改）。
> 2026-11-04 五态迁移：由 `design/diagnostics.md` 迁入本路径，补组件卡与能力 ID。
