---
layer: design
module: media
status: designed
updated: 2026-11-04
flow: FLOW-MEDIA-001
scenario: SCN-0011
domain: 媒体
valueStream: 图片
title: 显示图片并编辑图片源码
entries:
  - CMP-image/Sources/MDPreview/Util.swift#ImagePathRewriter
  - CMP-image/web/src/image-view.js#getImageView
  - CMP-editor/web/src/bridge.js#window.mdbridge
docs:
  - path: doc/design/architecture.md
    heading: 2.1 ImagePathRewriter 宽松解析与改写边界
  - path: doc/design/architecture.md
    heading: 2.1a 图片显示/编辑/导入
  - path: doc/requirements/REQ-0003-image.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-IMG-001
  - role: R2
    id: TC-IMG-002
  - role: R3
    id: TC-IMG-003
  - role: N1
    id: TC-IMG-004
---

# 显示图片并编辑图片源码

## 1. 场景与价值

本地相对路径图片（含空格/括号/标题）在渲染视图正常显示；点击图片切换为源码编辑块，修改/提交后生效，Esc/非法语法还原，清空地址即删图。

结果：图片路径无需手工转义，图片语法可在原位编辑。

## 2. 入口

- `CMP-image#for-load`：`ImagePathRewriter.forLoad`。
- `CMP-image#node-view`：`getImageView`。
- `CMP-editor#init`：NodeView 挂载到编辑器。

## 3. 运行序

流程定义：`FLOW-MEDIA-001`（显示/编辑分支）。

1. 加载 Markdown：图片相对路径改 `file://`，代码围栏/远程图不改。
2. 渲染：图片节点显示；`naturalWidth/complete` 可观测。
3. 点击图片：整块切源码编辑，baseDir 相对化展示。
4. 提交/失焦：解析并更新文档；非法语法还原；Esc 还原。
5. 清空目的地：删除图片节点。
6. 保存：`forSave` 还原相对路径，含空格加 `<>`。

失败路径：

- 路径不存在：保持原样，不写成坏路径。
- 非法源码：还原到编辑前，不丢节点。
- 窄窗长路径：编辑块内换行，不溢出正文栏。

## 4. 不可变引用

- 代码围栏/行内代码/远程 URL 不被路径改写。
- 保存后再次加载得到同一路径（往返一致）。
- 图片源码编辑块与文件写法同构：`![alt](path "title")`。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-IMG-001 | R1 | 自动 | `--selftest` | `PASS 图片 NodeView 渲染` | present |
| TC-IMG-002 | R2 | 自动 | `--selftest` | `PASS 图片点击进源码编辑块` | present |
| TC-IMG-003 | R3 | 自动 | `--selftest` | `PASS 图片源码编辑提交生效` | present |
| TC-IMG-004 | N1 | 自动 | `--selftest` | `PASS 非法源码提交还原` | present |

3 正 1 反均有自动入口；本卡是 promotion candidate，按 4 条复跑记录确认后可升 `verified`，REQ-0003 再评估。

## 6. 验证债

- 真实剪贴板/拖放的人工手感不在本卡 3+1 内；由 SCN-0012 覆盖导入路径。
- 路径含 Unicode 全角标点的样本未固化。

## 7. 变更记录

- 2026-11-04 五态补录，来源：image-support result、`architecture.md` §2.1/§2.1a、selftest 图片组。
