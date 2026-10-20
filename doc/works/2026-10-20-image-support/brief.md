---
layer: works
module: global
status: active
updated: 2026-10-20
---

# 工序: 图片支持(显示/编辑/粘贴/拖放)

## 需求

用户反馈 MDPreview 不支持图片显示、编辑与粘贴,样例来自
`~/github/wechat-offline/downloads/`(公众号文章离线导出,图片以
`resource/<文章名>/img_NNN.jpg` 相对路径引用,路径含中文/全角冒号/加号/空格)。

1. **显示**: 相对路径图片要能渲染。已实证: 路径不含空格时 `ImagePathRewriter`
   改写为 `file://` 后正常显示(screenshot 像素分析);路径含空格时 CommonMark
   不认为它是图片(remark 解析为纯文本),连改写正则都匹配不到 → 整行按字面显示。
2. **编辑**: 点击图片切换为编辑框(仿 mermaid 图交互: 点选进入编辑,失焦提交),
   可改地址/描述。
3. **粘贴**: ⌘V 直接粘贴剪贴板中的截图,或剪贴板内容为图片文件路径/拷贝的图片
   文件时,把图片文件放入文档同级的 `resource/<md文件名>/` 目录
   (与 wechat-offline 样例的 `resource/<文章名>/` 行为一致),光标处插入引用。
4. **拖放**: 从 Finder 拖图片文件入编辑器(现状会把图片当 markdown 打开成乱码
   文档,属同域缺陷,一并修)。

## 已核实的现状

- `ImagePathRewriter`(Util.swift): 行级正则 `(<[^>]*>|[^)\s]+)` 不容忍空格;
  加载时改写为绝对 file:// URL,保存时还原相对路径(目录内)。
- WebView 已授予全盘读(`loadFileURL(_, allowingReadAccessTo: "/")`),file://
  图片可渲染(实证于愚夫一得样例)。
- milkdown `image` 节点: inline atom、selectable,`toDOM` 输出 `<img>`;
  自带 `insertImageCommand`/`updateImageCommand`(未接入)。
- mermaid-view.js 已有「点击进编辑框、失焦提交」的 NodeView 模式可复用。
- 粘贴走响应链(NSText.paste)→ WKWebView → web paste 事件,milkdown clipboard
  插件只处理文本/markdown,图片载荷被丢弃。

## 验收标准

1. 打开样例《AI 六轮降价后为何要治理价格》(空格路径),全部图片显示;
   《低延迟C++…》(无空格路径)不回归。
2. 点击图片进入编辑框,修改地址/描述后失焦生效,Esc 还原;getMarkdown 与
   保存往返保持路径不变。
3. ⌘V 粘贴截图 → `resource/<md文件名>/img_NNN.png` 落盘,光标处出现图片,
   保存后为相对路径,重开仍显示。
4. 粘贴图片文件路径 / Finder 拖入图片文件 → 同上(文件导入该目录)。
5. selftest 新增用例全绿;旧用例不回归。

## 领取的开放问题(2026-10-20 定稿)

- OQ-A 目录名: **`resource/`**(与样例一致,用户选定);子目录为 `<md文件名去扩展名>`。
- OQ-B 编辑框字段: **地址+描述+标题** 三字段(用户选定)。
- OQ-C Finder 拖入图片: 与粘贴同行为——**复制进 resource/<md文件名>/**
  (用户对粘贴场景已明确"图片放到该目录",拖放按同一行为族收敛)。
- OQ-D 未保存新文档粘贴: **原生弹提示"请先保存文档"**,不插节点、不落盘。
- OQ-E 格式菜单: **加「插入图片…」**(文件选择器,复用同一导入路径)。

## 边界(本工序不做)

- 图片缩放(width/height)编辑: 需扩展 image schema 与 markdown 往返语法,另立工序。
- 导出 HTML 内联图片(现仅内联 CSS,导出件图片仍为 file:// 引用): 另立工序。
- 手敲 `![a](b c.png)`(带空格)在编辑器内即时成图可由 milkdown input rule 完成,
  但重新加载后依赖 remark 对 `<...>` 包裹的解析——不改 remark 层。
- 引用式图片 `![alt][ref]` 不支持改写(样例未用,remark 语法族另议)。
