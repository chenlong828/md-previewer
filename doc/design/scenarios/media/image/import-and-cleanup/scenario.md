---
layer: design
module: media
status: designed
updated: 2026-11-04
flow: FLOW-MEDIA-001
scenario: SCN-0012
domain: 媒体
valueStream: 图片
title: 导入图片并清理资源
entries:
  - CMP-image/Sources/MDPreview/ImageStore.swift#import
  - CMP-image/Sources/MDPreview/ImageStore.swift#cleanUnreferenced
  - CMP-kernel-media/web/src/kernel/components/media/image-paste.js#setupImagePaste
  - CMP-app-shell/Sources/MDPreview/DocumentWindowController.swift#importImage
docs:
  - path: doc/design/architecture.md
    heading: 2.1a 图片显示/编辑/导入
  - path: doc/requirements/REQ-0003-image.md
    heading: 5. 影响场景
tests:
  - role: R1
    id: TC-IMG-005
  - role: R2
    id: TC-IMG-006
  - role: R3
    id: TC-IMG-007
  - role: N1
    id: TC-IMG-008
---

# 导入图片并清理资源

## 1. 场景与价值

用户粘贴截图/图片文件、拖入图片或走「格式 → 插入图片」：图片复制到 `resource/<md文件名>/`，光标处插入引用；关闭文档时清掉不再被引用的图片，非图片与仍被引用的文件保留。

结果：图片资源与文档同生命周期，不散落、不误删。

## 2. 入口

- `CMP-image#import`：`ImageStore.import`。
- `CMP-image#cleanup`：`ImageStore.cleanUnreferenced`。
- `CMP-editor#init`：`setupImagePaste` 事件。
- `CMP-app-shell#open-document`：导入前保存提示。

## 3. 运行序

流程定义：`FLOW-MEDIA-001`（导入/清理分支）。

1. 触发：⌘V 位图/文件、拖放、菜单导入。
2. 校验：只取第一张；文档已保存；目录可列举；非图片拒绝。
3. 落盘：`resource/<md>/`，保留原名或 `img_NNN` 递增；冲突加后缀。
4. 插入：光标处插入引用，渲染。
5. 关闭：解析当前 Markdown 引用，删除未引用图片；非图片保留；空目录移除。

失败路径：

- 未保存文档：先提示保存，不落盘到错误目录。
- 不可列举目录：拒绝导入，避免覆盖。
- 非图片文件：拒绝并提示。
- 撤销导入：文件保留到关闭时再清理，保证重做可用。

## 4. 不可变引用

- resource 布局：`resource/<md文件名>/`，与 wechat-offline 导出布局一致。
- 单文档单写入口；不支持多文档共享 resource 子目录。
- 清理只动本组件管理的图片；非图片不动。

## 5. 测试

| ID | 角色 | 类型 | 执行 | 断言 | 证据 |
|---|---|---|---|---|---|
| TC-IMG-005 | R1 | 自动 | `--selftest` | `PASS 图片落盘-剪贴板位图(img_001.png)` | present |
| TC-IMG-006 | R2 | 自动 | `--selftest` | `PASS 图片落盘-文件导入保留原名,冲突加后缀` | present |
| TC-IMG-007 | R3 | 自动 | `--selftest` | `PASS 资源清理-孤儿删除且被引用/非图片保留` | present |
| TC-IMG-008 | N1 | 自动 | `--selftest` | `PASS 图片落盘-非图片拒绝` | present |

3 正 1 反均有自动入口；promotion candidate，复跑后可升 `verified`。

## 6. 验证债

- 真实 ⌘V/拖放事件链只有人工手感记录；`MDP_IMPORT_IMAGE` 覆盖控制器侧。
- 撤销后重做再关闭的清理时序需要单独断言。

## 7. 变更记录

- 2026-11-04 五态补录，来源：image-support/image-cleanup result、selftest 图片组。
