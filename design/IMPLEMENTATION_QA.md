# Mosaic — SwiftUI 实现阶段验证清单

> 本文件收录**在 Figma 中无法验证、必须在 SwiftUI 实现阶段完成**的检查项。
> 它们不是设计缺陷，也不阻塞设计基线冻结。
> 设计基线：[`DESIGN_BASELINE.md`](DESIGN_BASELINE.md) · 交互规格：[`../UI_REDESIGN.md`](../UI_REDESIGN.md)

---

## IMPLEMENTATION-P0

### I-P0-1 · Adaptive Toolbar 连续输入链路

**来源**：产品决策 D-03 的验收标准。

**验收标准**
> 「写一句 → 插媒体 → 继续写」**不得要求用户先手动失焦或收起键盘**。

**验证环境**：Simulator + 真机（键盘行为在两者上不同）

**步骤**
1. 新建笔记，输入一句文字（键盘弹起）
2. 点工具条 `＋` → 媒体插入菜单
3. 选「从相册选图」→ 选图 → 返回
4. 确认：光标自动落在图片下方的新文字块，**键盘全程未收起**

**若不成立的备选方案**：`＋` 改为不弹 Menu，而是就地把工具条内容切换成媒体图标行（inline 展开），再点一次切回 Markdown 行。

**相关实现约定**
```swift
.safeAreaInset(edge: .bottom) { AdaptiveToolbar(mode: isTextFocused ? .adaptive : .insert) }
// ＋ 用 Menu 承载；不要再叠一层 .toolbar(.keyboard)
// Picker 返回后：.onDisappear + DispatchQueue.main.async 再设 @FocusState
```

---

### I-P0-2 · Dynamic Type 极限档位

**Figma 为什么验证不了**：Figma 没有 Dynamic Type 概念，只能画固定字号。

**已在设计侧保证的**：组件不依赖固定高度实现布局（Gate C2 通过），触控目标 ≥44pt。

**验证环境**：Xcode Previews

```swift
#Preview { HomeView().dynamicTypeSize(.accessibility3) }
```

**逐项检查**

| 界面 | 检查点 |
|---|---|
| Home | Folder Chip 行是否溢出、是否仍可点；笔记行是否截断异常 |
| Note Row | `NOTE_MAIN_W = 275pt` 的固定宽必须改为自适应（`Spacer()` + `layoutPriority`） |
| Folder Filter | 大字号下 chip 变宽，「更多 ▾」的溢出阈值需按实际宽度重算 |
| Bottom Toolbar | 5 个图标在大字号下是否挤压 |
| Settings | Form Row 的 label 与 value 是否重叠 |

**至少验证两档**：`.xLarge`（常见）与 `.accessibility3`（极限）。

---

### I-P0-3 · VoiceOver 语义

**Figma 为什么验证不了**：Figma 无法表达 `accessibilityLabel` / `accessibilityHint` / `accessibilityValue`。

**已在设计侧保证的**：状态有非颜色冗余（Topic added 用 ✓ 图标、AI Badge 用不同图标而非仅颜色），节点命名语义化。

**实现约定**

| 元素 | Label | Hint | Value |
|---|---|---|---|
| 未读红点 | 「有 N 条未读更新」 | — | — |
| 置顶图标 | 「已置顶」 | — | — |
| 文件夹色点 | （装饰，`.accessibilityHidden(true)`） | — | — |
| 拖动手柄 | 「拖动以重新排序」 | 「上下拖动改变顺序」 | — |
| Topic Chip（default） | 「主题 {name}」 | 「轻点两下加为标签」 | — |
| Topic Chip（added） | 「主题 {name}」 | — | 「已加为标签」 |
| AI 摘要条（success） | 「AI 摘要」 | 「轻点两下展开」 | 「{oneLiner}」 |
| AI 摘要条（generating） | 「AI 正在生成摘要」 | — | — |
| AI 摘要条（error-auth） | 「AI 摘要失败：API Key 无效」 | 「轻点两下前往设置」 | — |
| AI Badge（generating） | 「AI 正在生成摘要」 | — | — |
| AI Badge（failed） | 「AI 摘要生成失败」 | 「打开笔记查看原因」 | — |
| Folder Meta Chip | 「所属文件夹」 | 「轻点两下更改」 | 「{folderName}」 |
| 笔记行 | 「{title}」 | — | 「{preview}，{time}」 |

**额外检查**
- 笔记行内部元素应合并为一个可访问元素（`.accessibilityElement(children: .combine)`），避免 VO 逐个念
- `⋯` 菜单展开后的阅读顺序
- Sheet 弹出时焦点是否移入 Sheet

---

## 验证阶段划分

| 阶段 | 项目 |
|---|---|
| **SwiftUI 实现中** | I-P0-1 · I-P0-2 · I-P0-3 |
| **Design Handoff** | MANUAL-P1 的光学对齐 · SF Symbols 替换（见 [`TODO_MANUAL_QA.md`](TODO_MANUAL_QA.md)） |
| **Pre-release** | MANUAL-P1 的动效手感 · 中文断行 · 深色模式实图处理 |

---

## 若实现暴露真实设计问题

设计基线已冻结。只有以下情况才回头改 Figma：

1. SwiftUI 实现证明某个交互不可行（例如 I-P0-1 的备选方案被采用）
2. 产品决策改变
3. Dynamic Type / VoiceOver 验证发现结构性缺陷

改动流程：更新 `design/figma-plugin/code.js` → `node test/all.js` → 重跑插件 → MCP 实读核对 → 更新 `DESIGN_BASELINE.md`。
