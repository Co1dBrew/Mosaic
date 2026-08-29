# 万象记 Mosaic — UI v2 设计系统生成器（Figma 插件）

在 Figma 里一键生成一份**可交接的设计系统**。对应设计文档 [`../../UI_REDESIGN.md`](../../UI_REDESIGN.md)。

## 运行步骤

1. 打开 **Figma 桌面版**（网页版不支持导入本地插件），新建或打开一个 Design 文件
2. **Plugins → Development → Import plugin from manifest…** → 选本目录的 `manifest.json`
3. **Plugins → Development → 万象记 UI v2 设计系统生成器** 运行
4. 等 5–15 秒，画布自动定位到 `📱 Screens` 页

> **重复运行是幂等的**：会复用并**清空**它自己创建的这三个页面（`📐 Foundations` / `🧩 Components` / `📱 Screens`）后重建，不会堆积副本。你自己的其他页面不受影响。
> 注意：如果你在生成的页面上手工改过东西，重新运行会丢失这些改动。

## 生成内容

### 📐 Foundations

| 资产 | 数量 | 说明 |
|---|---|---|
| 颜色变量 `Mosaic Color` | 16 | Light / Dark **双模式** |
| 数值变量 `Mosaic Scale` | 38 | `space/*` `radius/*` `size/*`，8pt 网格 |
| 文字样式 `iOS/*` | 15 | LargeTitle → Caption2 Emphasized |
| 效果样式 `elevation/*` | 2 | 菜单阴影 / FAB 阴影 |

### 🧩 Components — 16 个组件 / 变体集

| 组件 | 变体 | 组件属性 |
|---|---|---|
| `Icon` | 27（`name=`） | — |
| `Chip / Folder` | 2（`state`） | Label(文本) · Dot(布尔) |
| `Chip / Tag` | 2（`state`） | Label(文本) |
| `Row / Note` | 4（`pinned` × `unread`） | Title · Summary · Time |
| `Row / Folder` | 2（`trailing`） | Name · Count · Icon(实例替换) |
| `Row / Form` | 5（`type`） | Label · Value |
| `Row / Menu Item` | 2（`type`） | Label · Icon(实例替换) |
| `Bar / Nav` | 2（`title`） | Title · Leading · Trailing · Show Trailing 2 · Trailing 2 |
| `Bar / Summary Collapsed` | 2（`unread`） | Text |
| `Bar / Status`·`Bar / Toolbar`·`Bar / Home Indicator` | — | — |
| `Button / FAB`·`Block / Audio`·`Block / Image`·`Panel / Summary Expanded` | — | — |

### 📱 Screens — 12 个界面 ×2 模式

全部由**实例**拼装。① ③ ⑦ 是现状（待替换），其余是改后方案。

含 **7 条原型连线**：首页→笔记页、FAB→编辑器、摘要收起⇄展开、笔记页→⋯菜单、搜索结果→笔记页。

## 这版与上一版的区别

上一版生成的是静态图层，改一处要改 12 处。这版是真正的组件系统：

| | v1 | v2 |
|---|---|---|
| 组件 | 0 | **16 个（55 个变体）** |
| 实例 | 0 | **292** |
| 组件属性 | 0 | **18** |
| 数值变量绑定 | 0 | **1352** |
| 文字绑定样式 | 8 / 625 | **625 / 625** |
| 分页 | 1 | **3** |
| 原型连线 | 0 | **7** |

改 `Row / Note` 组件一次，12 个界面里所有笔记行同步更新。

## 技术说明

- **尺寸**：iPhone 15 逻辑尺寸 393 × 852pt（54pt 状态栏 / 44pt 导航栏 / 34pt Home 指示条）
- **明暗切换**：选中任意画板 → 右侧面板切换 `Mosaic Color` 的模式
- **字体**：按 `PingFang SC → SF Pro Text → SF Pro → Inter → Roboto` 取第一个可用的。PingFang SC 是 iOS 中文界面的真实系统字体，macOS 自带（SF Pro 不含中文字形）
- **固定色**（有意不做成变量）：文件夹图标底色、状态栏灵动岛、开关滑块——这些是品牌色/物理元素，不应随明暗模式变化

## 常见问题

**「找不到可用字体」** — 装 [Inter](https://fonts.google.com/specimen/Inter)，或在 `code.js` 的 `FONT_CANDIDATES` 里加你有的字体。

**运行后没反应** — 看 Figma 底部是否有红色错误；或 **Plugins → Development → Open console** 看堆栈。

**导入报 manifest 错误** — 确认选的是 `manifest.json`，且 `code.js` 与它同目录。

## 本地校验

```bash
node --check design/figma-plugin/code.js
```

仓库外另有一份 Figma API 桩，可在 Node 里真实执行整个生成流程、校验变体命名/组件属性/变量绑定是否合法，把运行时错误挡在进 Figma 之前。
