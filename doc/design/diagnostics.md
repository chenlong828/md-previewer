---
layer: design
module: global
status: current
updated: 2026-10-24
---

# 诊断面（OQ-3 结论：保留为官方诊断面并文档化）

诊断代码随 release 构建发布是**有意保留**：单机工具无线上灰度能力，官方
诊断面是问题排查的唯一手段。三个入口统一风格如下：

| 入口 | 语法 | 输出前缀 | 退出码 |
|---|---|---|---|
| 无头自检 | `MDPreview --selftest` | `PASS/FAIL  名称` 每行一项，末行 `SELFTEST PASSED/FAILED` | 0=全过 / 1=有失败 |
| 进程内截图 | `MDPreview --screenshot out.png [input.md]` | `SCREENSHOT …` | 0=成功；2/3/4/5/6/7=各阶段失败（见 Screenshot.swift） |
| 多窗口诊断 | `MDPreview --multiwindow-test --fileA=/path/a.md --fileB=/path/b.md` | `[MULTIWINDOW] PASS/FAIL 检查项` + info 行 | 0=全过 / 1=有失败 |

- 截图模式环境钩子 `MDP_IMPORT_IMAGE=<图片路径>` / `MDP_EDIT_IMAGE=1`:
  加载文档后执行一次「导入→落盘→插入」全链路 / 打开第一张图片的源码编辑块
  再截图(图片导入与编辑框几何的 e2e 验证口)。
- web 侧诊断留痕：`window.__exportedHTML`（自检轮询用，页面级临时变量）、
  `mdbridge.testImagePayload(data)`(剪贴板载荷识别,自检断言用)。
- WebLocator（`#filePath` 唯一用点）仅服务于诊断/开发定位，W3 已限定在
  Util.swift 单点。

> 2026-10-24 自 [architecture.md](architecture.md) 原 §3 下沉，正文未改语义；
> 桥协议相应由 §4 顺延为 §3（冻结件中的旧编号不回改）。
