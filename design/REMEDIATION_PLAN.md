> **ARCHIVED** —— 早期整改计划，条目已全部落地或被后续决策取代。
>
> 归档清单见 [`docs/ARCHIVED.md`](../docs/ARCHIVED.md)。**不要据本文件判断现状。**

---

# 万象记 / Mosaic — Figma 设计补全与整改计划

> 基线：Figma 文件 `Untitled`（3 页 · 16 组件 · 24 屏 · 7 条原型连线），2026-08-06 经 Dev Mode MCP 实读确认。
> 本计划不引用 PRD 中「应该存在」的内容，只以文件实际状态为准。
> 目标：把概念验证板补全为可 Prototype、可 Design QA、可交付 SwiftUI 开发的生产级设计文件。
> 相关文档：[`UI_REDESIGN.md`](../UI_REDESIGN.md)（交互逻辑）· [`figma-plugin/`](figma-plugin/)（生成器）

---

## 1. Current Baseline

### 1.1 文件结构（实读）

```
📐 Foundations   1 块规范板：16 色变量(Light/Dark) · 38 数值变量 · 15 文字样式 · 2 效果样式
🧩 Components    16 个组件 / 变体集（55 个变体 · 20 个组件属性）
📱 Screens       2 块画板 × 12 屏 = 24 屏 · 276 实例 · 7 条原型连线
```

### 1.2 组件清单与分类

| 组件 | 变体 | 属性 | 状态判定 |
|---|---|---|---|
| `Icon` | 27（`name=`） | — | ✅ 已完成 |
| `Bar / Status` | 1 | — | ✅ 已完成 |
| `Bar / Home Indicator` | 1 | — | ✅ 已完成 |
| `Row / Menu Item` | 2（`type`） | Label · Icon | ✅ 已完成 |
| `Row / Note` | 4（`pinned`×`unread`） | Title · Summary · Time | ⚠️ 部分（缺 6 种内容态） |
| `Row / Folder` | 2（`trailing`） | Name · Count · Icon | ⚠️ 部分（缺 dragging/pressed） |
| `Row / Form` | 5（`type`） | Label · Value | ⚠️ 部分（缺 disabled/destructive/测试三态） |
| `Chip / Folder` | 2（`state`） | Label · Dot | ⚠️ 部分（缺 pressed/超长名） |
| `Chip / Tag` | 2（`state`） | Label | ⚠️ 部分（缺 pressed；且被复用为 Topic Chip） |
| `Bar / Nav` | 2（`title`） | Title · Leading · Trailing · Show Trailing ×2 | ⚠️ 部分（缺 large-title/scrolled） |
| `Bar / Summary Collapsed` | 2（`unread`） | Text | ❌ 严重不足（需 9 态，现有 2） |
| `Panel / Summary Expanded` | 1 | — | ❌ 严重不足（无变体） |
| `Block / Audio` | 1 | — | ❌ 严重不足（缺 4 态） |
| `Block / Image` | 1 | — | ❌ 严重不足（缺 4 态） |
| `Bar / Toolbar` | 1 | — | ⚠️ 需重构（与 Markdown 条互斥关系未表达） |
| `Button / FAB` | 1 | — | 🗑 建议删除（见 D-02） |

**完全缺失的组件（10 个）**：`Block / Text` · `Block / Document` · `Block / Link` · `Topic Chip`（当前挪用 Chip/Tag）· `Empty State` · `Error Row` · `Loading Row` · `Section Header` · `Toolbar Button` · `Dialog`

### 1.3 屏幕清单

| 屏 | 内容 | 判定 |
|---|---|---|
| ① ③ ⑦ | 现状对照（文件夹列表 / 行内摘要 / ＋菜单） | 🗑 **建议删除** —— 已完成对比论证使命，留在生产文件里会与新 IA 冲突 |
| ② | 首页笔记流 | ⚠️ 仅 default 态 |
| ④ ⑤ ⑥ | 笔记页（收起 / 展开 / ⋯菜单） | ⚠️ 仅 success 态 |
| ⑧ | 编辑器输入态 | ⚠️ 仅 focused 一种 |
| ⑨ | 搜索（有结果） | ⚠️ 缺 3 态 |
| ⑩ | 设置第一屏 | ⚠️ 仅 Kimi 默认态 |
| ⑪ | 文件夹管理 | ⚠️ 仅正常态 |
| ⑫ | 首启空状态 | ✅ 已完成 |
| — | **Advanced Settings** | ❌ 有入口无页面 |

### 1.4 横切覆盖

| 维度 | 状态 |
|---|---|
| Dark Mode | ✅ 24 屏全覆盖，变量模式切换正确 |
| Loading 状态 | ❌ 0 个 |
| Error 状态 | ❌ 0 个 |
| Permission 流 | ❌ 0 个 |
| Sheet / Dialog | ❌ 0 个（仅 1 个 ⋯ Menu 覆盖层） |
| Pressed / Focused / Disabled | ❌ 0 个 |
| Dynamic Type | ❌ 未验证 |
| VoiceOver 标注 | ❌ 0 处 |
| 原型 | ⚠️ 7 条，覆盖 10 条 Flow 中的 2.5 条 |

### 1.5 量化审计数据（用于 Token 整改）

```
gap 实际取值      1 2 2.5 4 5 6 8 10 11 12 13 14 18 22 30      （15 种）
padding 实际取值  2 4 6 8 10 11 12 13 14 16 18 20 22 26 30 32  （16 种）
圆角实际取值      2 3 4 5 8 9 10 12 14 16 20 28 47 99          （14 种）
图标尺寸          13 14 15 17 19 22 25 34 52                    （9 种）
触控目标 <44pt    47 种规格
绝对定位节点      19 个（灵动岛/FAB/未读点/遮罩/菜单 —— 全部合理）
文本绑定样式      625 / 625  ✅
颜色绑定变量      753 处      ✅
数值绑定变量      1353 处     ✅
```

---

## 2. Decisions to Freeze

**这些是产品设计决策，不是 bug。必须先定，否则 Phase 1 之后的所有工作都可能返工。**

**状态：已于 2026-08-06 冻结。以下为最终结论，Phase 1 起以此为准。**

| ID | Decision | Current Design | Audit Recommendation | 最终结论 | 变更 |
|---|---|---|---|---|---|
| **D-01** | 首页新建入口形态 | 右下 56pt FAB + 彩色阴影 | 改为 bottom toolbar compose 按钮 | ✅ **采纳** | 删 `Button / FAB` 与 `elevation/fab`。约束：新建仍是首页最明显的 Primary Action；空状态下仍可直接发现 |
| **D-02** | 笔记页文件夹归属入口 | 导航栏中间 `📁 工作 ▾` | 移入 `⋯ → 移动到文件夹…` | ⚠️ **部分采纳，方案修改** | 见下方 D-02 详解 |
| **D-03** | 底部工具条与 Markdown 条关系 | 二者叠加共 96pt | 改为互斥 | ❌ **不采纳互斥，改为单层自适应** | 见下方 D-03 详解 |
| **D-04** | 文件夹 Chip 溢出策略 | 无上限无提示 | >6 个时显示「更多 ▾」 | ⚠️ **采纳溢出，取消固定阈值** | 见下方 D-04 详解 |
| **D-05** | AI「退出自动生成」的反馈 | 无 | 首页增加 generating / failed | ✅ **采纳，附加约束** | 见下方 D-05 详解 |
| **D-06** | Topic Chip → Tag 表现 | 复用 `Chip / Tag` | 独立组件三态 | ✅ **采纳** | `Chip / Topic`：`default \| pressed \| added`；`added` = filled + checkmark + VoiceOver 语义，不只靠颜色 |
| **D-07** | Chip 行是否随列表滚动 | 未定义 | 固定为 `safeAreaInset` | ✅ **采纳行为，剥离实现** | 见下方 D-07 详解 |
| **D-08** | ①③⑦ 现状对照屏去留 | 留在 Screens 页 | 删除 | ✅ **采纳** | 先导出 PNG 至 `design/archive/`，再从生产 Screens 页删除 ①③⑦ 及其 Dark 版本。归档文件**不参与** Prototype 与 QA |

### D-02 详解 — Folder 作为笔记 Metadata，不是隐藏功能

**同意**：从 Navigation Bar 的 principal 区域移除 `📁 工作 ▾`，导航栏保持 `‹ [空标题] ⋯`。

**不同意**：把归属能力完全隐藏进 `⋯`。

**最终方案**：在**标题下方的 metadata 区域**增加轻量 Folder Chip `工作 ▾`，与 Tags 属于同一 metadata 层级：

```
标题（可留空）
[工作 ▾]  [#排期] [#分工]     ← Folder Chip 与 Tags 同层
正文块流…
```

- 点击 Folder Chip → `Menu / Folder Picker`
- `⋯` 菜单**保留**「移动到文件夹…」作为 secondary entry point

**理由**：Folder 是笔记本身的重要 metadata，不是低频操作。完全隐藏会明显降低编辑过程中随手归类的效率与 discoverability。「一个功能一条路径」是用来消除**语义重复的入口**，不是禁止 contextual shortcut —— 首页长按菜单与笔记内 metadata chip 分处不同场景，属于合理的双入口。

### D-03 详解 — 单层自适应工具条，不是互斥

**否决理由**：互斥方案会导致「文字聚焦 → 所有媒体插入入口消失」，用户必须先手动失焦或收起键盘才能插图，这直接破坏「写一句 → 插媒体 → 继续写」的连续输入链路 —— 而这恰恰是本次重设计的核心收益。

**最终要求**：

| 约束 | 值 |
|---|---|
| 键盘上方 Toolbar 层数 | **最多 1 层** |
| Toolbar 总高度 | **44–50pt** |
| 未聚焦时 | 显示主要插入动作 `📷 🎙 📄 🔗 ｜ #` |
| 文字聚焦时 | 单层 **adaptive mode**：**同时**可进入 Markdown 格式化 **且** 可访问媒体插入 |

**具体图标编排在 Phase 2 组件设计阶段决定**，可选方案例如 `＋ ｜ B I • ｜ # ｜ …`（`＋` 收纳媒体插入菜单，次级 Markdown 格式放入 overflow），或保留 1–2 个最高频媒体入口 + 其余进 overflow。

**最终评价标准不是图标数量，而是**：
> 「写一句 → 插媒体 → 继续写」**不得要求用户先手动失焦或收起键盘**。

### D-04 详解 — 基于宽度的溢出，不用固定阈值

**取消** `folderCount > 6` 这类硬编码规则。

**改为 width-based overflow**，按以下顺序布局：

```
全部 → 未归类 → 当前宽度能完整容纳的 Folder Chips → 更多 ▾
```

可展示数量由**运行时**决定，输入变量：设备宽度 · Chip intrinsic width · Dynamic Type 档位 · 文件夹名称长度。

**附加硬规则 — Selected Folder Must Remain Visible**：
当前被选中的 Folder Chip **必须始终出现在主 Filter Row 中**。若它按自然顺序落在 overflow 内，需调整可见项使其进入主行。

`更多 ▾` 打开完整 `Menu / Folder Picker`。

### D-05 详解 — Failed 不得永久占据主摘要区

**采纳**首页三态：`normal` · `generating` · `failed`。用户退出 Note 后必须能看到 AI 任务正在发生。

**附加约束**：`failed` **不应永久占据首页的主摘要区域**。

- 首页失败表现：摘要行**回退为正文预览**（`text-preview`），仅在时间列位置显示一个轻量 ⚠️ 指示
- 完整错误信息与 recovery CTA 位于**笔记内的 Summary Bar**（见 §7.1 的 4 种 error 态）

**理由**：首页是浏览场景，一条笔记的 AI 失败不应把整行变成错误提示、也不应让用户失去内容预览。错误详情属于该笔记的上下文。

### D-07 详解 — 定义行为，不定义实现

**Design Spec 只定义**：
> Folder Filter Row 在 Note Feed 滚动时保持可访问，作为列表的 pinned filter control。

**不在产品决策中规定具体 SwiftUI API**。候选实现（`safeAreaInset(edge: .top)` · pinned section header · 其它系统方案）移入 **Handoff Notes**，由最终 scroll behavior 决定。

---

> 未列入本表的所有条目（缺失状态、触控目标、Token 收敛、无障碍）属于 Bug / HIG 修复，**不需要产品决策**，直接进 Backlog。

---

## 3. Master Remediation Backlog

优先级：**P0** = 阻塞开发 · **P1** = 发布前必修 · **P2** = 可延后
规模：**S** = 单个变体/单条规则 · **M** = 一个组件集或一屏 · **L** = 一组组件或一整页多态 · **XL** = 跨阶段

### 3.1 结构与决策（IA）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| IA-001 | P0 | 结构 | 8 条产品决策未定 | 完成 §2 决策冻结表签字 | — | S | 8 条全部有最终结论并记入本文档 |
| IA-002 | P1 | 结构 | ①③⑦ 现状屏与新 IA 冲突 | 导出 PNG 至 `design/archive/`，从 Screens 页删除 6 屏 | IA-001(D-08) | S | Screens 页只剩改后方案 |
| IA-003 | P0 | 结构 | FAB 为非原生模式 | 删除 `Button / FAB` 与 `elevation/fab` 效果样式；② ⑫ 改为底部 toolbar + 右侧 compose 按钮 | IA-001(D-01) | M | ② ⑫ 底部为 49pt toolbar，按钮 44×44 hit area |
| IA-004 | P0 | 结构 | 导航栏中间文件夹选择器 | `Bar / Nav` 删除 `title=folder` 变体；④⑤⑥⑧ 导航栏留空标题；**新建 `Chip / Folder Meta` 放在标题下方 metadata 区**（与 Tags 同层）；`⋯` 保留「移动到文件夹…」作为次入口 | IA-001(D-02) | M | 4 屏导航栏仅 `‹ · (空) · ⋯`；标题下方有 `工作 ▾` 可点 chip；两个入口落到**同一个** Folder Picker |

### 3.2 Design Tokens（TOKEN）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| TOKEN-001 | P0 | Spacing | 15 种 gap / 16 种 padding，无 scale | 收敛为 `4/8/12/16/20/24/32`，按 §11 映射表重绑 | IA-001 | M | `Mosaic Scale` 中 `space/*` 仅剩 7 个值 |
| TOKEN-002 | P0 | Radius | 14 种圆角 | 收敛为 `8/12/16/999` + 设备特例 `47` | TOKEN-001 | S | `radius/*` 仅剩 5 个值 |
| TOKEN-003 | P1 | Icon | 9 种图标尺寸 | 收敛为 `16/20/24` + 特例（播放 32、空状态 48） | TOKEN-001 | S | `size/icon-*` 仅剩 3 个通用值 |
| TOKEN-004 | P1 | Row | 7 种行高 | 定义 `row/standard=44` · `row/two-line=56`，其余由内容撑开 | TOKEN-001 | S | 新增 2 个 Token 并在 Row 组件使用 |
| TOKEN-005 | P2 | Motion | 无动画 Token | 新增 `duration/fast=0.2` · `duration/normal=0.3` | — | S | 2 个 FLOAT 变量存在并记入交付说明 |
| TOKEN-006 | P0 | 触控 | 无 hit area 规则 | 新增 `size/tap=44` 的**使用规范**（非新变量，已存在），并在所有可点组件上标注 | TOKEN-001 | S | 每个可点组件的 Description 写明 hit area |
| TOKEN-007 | P2 | Typography | 空标题占位用 `iOS/Title1` 过重 | 改用 `iOS/Title3` | — | S | ⑧ 占位文字为 20pt |
| TOKEN-008 | P0 | 交互 | `pressed` 若做成变体会引发笛卡尔积 | 在 Foundations 定义**全局按下规则**（背景叠加 8% 或 opacity 0.7），组件不建 pressed 变体 | TOKEN-001 | S | 规范板中有该规则；全库 0 个 `pressed=` 变体（结构性差异的除外） |

### 3.3 AI 摘要（AI）— **最高复杂度，独立工作流**

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| AI-001 | P0 | Summary Bar | 仅 2 变体，缺 7 态 | 重建为 `state=` 9 变体（见 §7.1） | TOKEN-001 | L | 9 个变体齐全，命名 `state=xxx` |
| AI-002 | P0 | Summary Bar | 错误态无差异化 CTA | `error-auth`→「去设置」；`error-network`/`error-rate-limit`→「重试」；`error-content` 无 CTA | AI-001 | M | 4 种错误 CTA 各不相同 |
| AI-003 | P0 | Summary Bar | 生成中无反馈 | `generating` 变体：`ProgressView` + 「AI 正在总结…」 | AI-001 | S | 含系统 spinner |
| AI-004 | P1 | Summary Expanded | 无变体、信息层级偏技术 | 加 `logCount=0\|1\|many` 三变体；模型/时间降为 `iOS/Caption2` 次要元数据右对齐 | AI-001 | M | 用户第一眼看到的是 oneLiner 和要点，不是模型名 |
| AI-005 | P0 | Topic Chip | 复用 Tag Chip，可发现性近零 | 新建 `Chip / Topic`，`state=default\|pressed\|added`；`added` = 实心 + `checkmark` | D-06 | M | 三态视觉可区分，且不只靠填充 |
| AI-006 | P1 | Update Logs | 折叠规则未在设计中表达 | `Panel / Summary Expanded` 中体现：1 条直接展示；≥2 条展开最新、其余折叠 | AI-004 | S | 三种数量各有一屏或一变体 |
| AI-007 | P1 | Update Logs | 未读→已读时机未定义 | 在交付说明中写明：**摘要面板展开且 Update Logs 区域进入可视范围**时标记已读 | AI-004 | S | 交付说明含明确触发条件 |
| AI-008 | P0 | Home | 首页无生成中/失败态 | 新建嵌套子集 `Note / AI Badge`，`state=none\|generating\|failed`，由 `Row / Note` 以 Instance Swap 引用 | D-05, HOME-001 | M | 三态可表达；**`failed` 时摘要行回退为正文预览**，仅时间列旁显示轻量 ⚠️，不占满整行 |

### 3.4 内容块（BLOCK）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| BLOCK-001 | P0 | Text | 组件不存在 | 新建 `Block / Text`，`state=rendered\|editing` | TOKEN-001 | M | 两态 `font`/`lineSpacing` 完全一致，切换不跳变 |
| BLOCK-002 | P0 | Image | 缺 loading/failed/missing | 扩为 `state=loaded\|loading\|failed\|missing` | TOKEN-001 | M | `failed` 显示占位图标 + 「重试」+「移除」，不得为空白矩形 |
| BLOCK-003 | P0 | Image | 极端宽高比未验证 | 补 `ratio=portrait\|landscape\|square\|tall` 四种示例（不做变体，做验证屏） | BLOCK-002 | S | 极高/极宽图不撑破布局 |
| BLOCK-004 | P0 | Audio | 缺转写中/失败 | 扩为 `state=idle\|playing\|transcribing\|failed`（仅播放条维度） | TOKEN-001 | M | `failed` 只有一个「重试」按钮（消除现有重复） |
| BLOCK-005 | P1 | Audio | 转写超 3 行折叠未表达 | **拆为嵌套子集** `Audio / Transcript`，`state=none\|short\|collapsed\|expanded`，避免 4×4 笛卡尔积 | BLOCK-004 | M | 4 种转写态可见；`Block / Audio` 变体数保持 4 而非 16 |
| BLOCK-006 | P0 | Document | 组件不存在 | 新建 `Block / Document`，`state=normal\|unsupported\|missing` | TOKEN-001 | M | `unsupported` 标明「暂不支持提取文字」；`missing` 提供「移除」 |
| BLOCK-007 | P0 | Link | 组件不存在 | 新建 `Block / Link`，`state=preview\|url-only\|loading\|failed` | TOKEN-001 | L | **`failed` 仍显示可点 URL**，四态共用同一 Auto Layout 与 padding |
| BLOCK-008 | P1 | Link | 边界 URL 未验证 | 验证屏覆盖：无 metadata / 非法 / 超长 / 中文域名 / localhost | BLOCK-007 | S | 5 种 URL 均不破坏布局 |
| BLOCK-009 | P1 | 全部块 | 无 focused 表现 | **仅 `Block / Text` 建 `state=rendered\|editing`**（聚焦有结构性差异）；其余块的按下/聚焦走 TOKEN-008 全局规则，不建变体 | BLOCK-001~007, TOKEN-008 | S | 无 `focused=` 变体；文字块两态可切换 |
| BLOCK-010 | P1 | 全部块 | 排序边界未表达 | 首块「上移」禁用、末块「下移」禁用 —— 在块 Context Menu 中体现 | BLOCK-009 | S | 两种禁用态可见 |
| BLOCK-011 | P1 | 空块 | 末尾空文字块规则无视觉验证 | 补一屏：删除最后一块后自动补空文字块的状态 | BLOCK-001 | S | 不出现空白 Card / 幽灵分隔线 |

### 3.5 首页（HOME）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| HOME-001 | P0 | Note Row | 缺 5 种内容 fallback | **拆为嵌套子集** `Note / Preview`，`type=ai-summary\|text\|audio\|image\|empty`；`Row / Note` 主件以 Instance Swap 引用 + 布尔属性 `Show Pin` / `Show Unread`（见 §6.2） | TOKEN-001 | L | 5 种内容态齐全；`text` 不泄漏 Markdown 符号；`Row / Note` 变体数 ≤8 |
| HOME-002 | ~~P1~~ | Note Row | ~~无 pressed 态~~ | **取消**。List 行按下高亮由 iOS 自动提供，无需设计 | TOKEN-008 | — | — |
| HOME-003 | P1 | Note Row | 未读红点视觉归属歧义 | 红点移至与时间同基线右对齐 | HOME-001 | S | 红点与时间水平对齐 |
| HOME-004 | P1 | Folder Chip | 超长名未处理 | 设最大宽 `120pt` + 尾部截断（pressed 走 TOKEN-008） | TOKEN-001, TOKEN-008 | S | 20 字文件夹名不撑破 chip 行 |
| HOME-005 | P0 | Folder Chip | 无溢出策略 | 加 `state=more` 变体（`更多 ▾`）+ `Menu / Folder Picker`。**按可用宽度动态决定可见数量，不用固定阈值** | D-04, DIALOG-007 | M | 顺序为 `全部 → 未归类 → 可容纳的 chips → 更多 ▾`；随设备宽度与 Dynamic Type 变化 |
| HOME-008 | P0 | Folder Chip | 选中项可能落在 overflow 里 | 实现规则：**当前选中的 Folder Chip 必须始终出现在主 Filter Row**；若自然顺序落入 overflow，需调整可见项使其进入主行 | HOME-005 | M | 选中第 12 个文件夹时它仍显示在主行 |
| HOME-006 | P1 | Chip 行 | 0 个用户文件夹时隐藏未验证 | 补一屏：仅「全部」「未归类」时的状态 | HOME-004 | S | 与 ⑫ 空状态区分清楚 |
| HOME-007 | P1 | 手势 | Chip 行与 Swipe 竞争 | **Design Spec 只定义行为**：Chip 行在 Feed 滚动时保持可访问，作为 pinned filter control；与列表间加分隔线。具体 API 候选（`safeAreaInset` / pinned section header / 其它）写入 Handoff Notes | D-07 | S | 设计稿标注「滚动时保持可访问」；**计划正文不出现具体 SwiftUI API** |

### 3.6 笔记页（NOTE）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| NOTE-001 | P0 | Toolbar | 双工具条共 96pt | `Bar / Toolbar` 改为**单层自适应**：`mode=insert\|adaptive`。`adaptive` 下**同时**提供 Markdown 格式化与媒体插入（`＋` 收纳，或保留 1–2 个高频入口 + overflow）；配套新建 `Menu / Media Insert` | D-03 | L | 键盘上方**恒为 1 层、44–50pt**；**文字聚焦时媒体插入仍可达**；验收标准是「写一句→插媒体→继续写」不需先失焦或收键盘 |
| NOTE-002 | P1 | Title | 空标题占位过重 | 改 `iOS/Title3`；补 `empty\|focused\|filled\|very-long` 四态验证 | TOKEN-007 | S | 空标题不产生大块留白 |
| NOTE-003 | P1 | Tags | 无可点提示 | Tag 行加 `pressed`；无标签时底部 `#` 图标显示角标数字 | AI-005 | M | 两个入口（Tag 行 / `#`）进入**同一个** Tag 编辑态 |
| NOTE-004 | P1 | ⋯ Menu | 图标语义重复 | `清除 AI 摘要` 改用 `sparkles.slash`，与 `删除笔记` 区分 | — | S | 两项图标不同 |
| NOTE-005 | P1 | ⋯ Menu | 缺「移动到文件夹…」 | 在 Pin 之后加一组 | IA-004 | S | 菜单含该项且与首页长按菜单同构 |
| NOTE-006 | P0 | 编辑器 | 仅 1 种输入态 | 补三屏：未聚焦（`mode=insert`）· 聚焦（`mode=adaptive`）· **聚焦状态下点 `＋` 展开媒体菜单** · 插入后自动新建文字块并重新聚焦 | NOTE-001, BLOCK-001 | L | 原型中可在**不收起键盘**的前提下完成「写→插图→继续写」 |
| NOTE-007 | P0 | Metadata | 笔记内无文件夹归属入口 | 新建 `Chip / Folder Meta`（`state=assigned\|unassigned`），置于标题下方与 Tags 同层；点击打开 `Menu / Folder Picker` | IA-004, DIALOG-007 | M | 未归类时显示为弱化样式；与 `⋯` 的「移动到文件夹…」落到同一 Picker |

### 3.7 搜索（SEARCH）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| SEARCH-001 | P1 | 搜索 | 仅有结果态 | 补 `empty-query` · `no-result` · `typing` 三屏 | HOME-001 | M | 三态文案各不相同 |
| SEARCH-002 | P1 | Tag Chip | 无选中态 | 复用 `Chip / Tag` 的 `state=selected` | — | S | 点击后有明确选中反馈 |
| SEARCH-003 | P2 | 结果行 | 与首页 Row 一致性 | 结果行复用 `Row / Note` + 追加文件夹标注插槽 | HOME-001 | M | 不新建独立组件 |

### 3.8 文件夹管理（FOLDER）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| FOLDER-001 | P0 | 删除 | 无确认对话框 | 新建 `Dialog / Delete Folder`，`count=zero\|some` 两变体 | DIALOG-001 | M | `some` 显示「将同时删除其中 N 张笔记」；`zero` 显示「此操作不可撤销」 |
| FOLDER-002 | P0 | 新建 | 无 Sheet | 新建 `Sheet / Folder Editor`，`mode=create\|rename` | TOKEN-001 | M | 含名称输入 · 颜色选择 · 图标选择 |
| FOLDER-003 | P1 | 排序 | 无拖拽态 | `Row / Folder` 加**布尔属性** `Dragging`（不建变体维度） | TOKEN-001 | S | 拖拽时有抬起阴影与占位；变体数保持 2 |
| FOLDER-004 | P1 | 空状态 | 无 | 补一屏：0 文件夹，文案说明「文件夹是可选的」 | EMPTY-001 | S | 不诱导用户必须建文件夹 |
| FOLDER-005 | P2 | 边界 | 超长名 / 重名未验证 | 验证屏覆盖 | FOLDER-002 | S | 20 字名称不破坏行布局 |

### 3.9 设置（SETTINGS）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| SETTINGS-001 | P0 | Advanced | 页面不存在 | 新建 Advanced Settings 屏，**分 4 节**：AI 参数 / 语音转写 / 同步 / 隐私 | TOKEN-001 | L | 不是一个长列表 |
| SETTINGS-002 | P0 | Provider | 无 Custom 态 | 补一屏：`Provider=Custom` 时 Base URL 与 Model 提升到第一屏 | SETTINGS-001 | M | 切换 Provider 时布局不错乱 |
| SETTINGS-003 | P1 | 测试连接 | 无三态 | **拆为嵌套子集** `Form / Action Status`，`state=idle\|testing\|success\|failure`，由 `Row / Form` 的 `type=action` 引用 | TOKEN-001 | M | 三态分别为 spinner / 绿勾 / 红叉+错误文案；`Row / Form` 变体数保持 4 |
| SETTINGS-004 | P1 | Form Row | 缺 disabled / destructive | 用**布尔属性** `Disabled` / `Destructive`，不建变体 | TOKEN-001, TOKEN-008 | S | 「重置隐私同意」为 destructive；变体数不增加 |
| SETTINGS-005 | P2 | API Key | 未配置引导缺失 | 补 `API Key` 为空时的行内提示 | SETTINGS-003 | S | 引导用户先填 Key |

### 3.10 Sheet / Dialog（DIALOG）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| DIALOG-001 | P0 | 基础 | 无任何 Dialog 组件 | 新建 `Dialog / Confirmation`，`tone=default\|destructive` | TOKEN-001 | M | 复用于全部确认场景 |
| DIALOG-002 | P0 | 删除笔记 | 无确认 | 用 `Dialog / Confirmation` 实例化 | DIALOG-001 | S | destructive 按钮为红色且非默认焦点 |
| DIALOG-003 | P0 | AI 重生成 | 无确认 | 同上，文案「将清空初始总结与全部更新记录」 | DIALOG-001 | S | — |
| DIALOG-004 | P0 | AI 清除 | 无确认 | 同上，文案「不影响卡片内容」 | DIALOG-001 | S | — |
| DIALOG-005 | P0 | 录音 | Sheet 不存在 | 新建 `Sheet / Recorder`，`state=idle\|recording\|paused\|done\|failed` | TOKEN-001 | L | 含波形 · 计时 · 开始/暂停/停止 |
| DIALOG-006 | P0 | 标签编辑 | 态不存在 | 新建 `Sheet / Tag Editor` | AI-005 | M | 与 Tag 行、`#` 按钮共用同一状态 |
| DIALOG-007 | P0 | 移动文件夹 | Menu 展开态不存在 | 新建 `Menu / Folder Picker`，含「未归类」+ 列表 + 「新建文件夹…」 | FOLDER-002 | M | 文件夹多时可滚动 |
| DIALOG-008 | P1 | 图片全屏 | 不存在 | 新建 `Sheet / Image Viewer` | BLOCK-002 | M | 含关闭 · 缩放提示 |
| DIALOG-009 | P1 | URL 输入 | 不存在 | 新建 `Sheet / URL Input` + 剪贴板命中时的「已粘贴 · 撤销」提示条 | BLOCK-007 | M | 两条路径都有设计 |
| DIALOG-010 | P0 | AI 隐私 | 不存在 | 新建 `Dialog / AI Privacy Consent` | DIALOG-001 | S | 首次生成前出现 |
| DIALOG-011 | P0 | 音频上传 | 不存在 | 新建 `Dialog / Audio Upload Consent` | DIALOG-001 | S | 仅云端转写模式出现 |

### 3.11 权限（PERMISSION）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| PERMISSION-001 | P0 | 通用 | 无被拒引导 | 新建 `Sheet / Permission Denied`，`type=camera\|photo\|microphone` | DIALOG-001 | M | 均含「去设置」按钮，不留死路 |
| PERMISSION-002 | P1 | 相机 | 不可用态未设计 | 相机不可用时 📷 直接进相册（无二级菜单）—— 补该状态 | PERMISSION-001 | S | 模拟器 / 无相机设备可用 |

### 3.12 空 / 加载 / 错误（EMPTY / LOADING / ERROR）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| EMPTY-001 | P1 | 组件 | 无 Empty State 组件 | 新建 `Empty State`，属性：Icon · Title · Message · 可选 CTA | TOKEN-001 | M | 复用于 5 处 |
| LOADING-001 | P1 | 组件 | 无 Loading Row | 新建 `Loading Row`（骨架或 spinner + 文案） | TOKEN-001 | S | 复用于搜索 · 链接 · 图片 |
| ERROR-001 | P1 | 组件 | 无 Error Row | 新建 `Error Row`，属性：Message · CTA 数量 `0\|1\|2` | TOKEN-001 | M | 行内错误统一表现，不弹 Alert |
| ERROR-002 | P1 | 导出 | 失败态缺失 | 用 `Error Row` 覆盖导出失败 | ERROR-001 | S | — |
| ERROR-003 | P2 | iCloud | 同步失败态缺失 | 在 Advanced Settings 中用 `Error Row` | ERROR-001, SETTINGS-001 | S | — |

### 3.13 无障碍（ACCESS）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| ACCESS-001 | P0 | 触控 | 47 种规格 <44pt | 为每个可点组件标注 hit area（Figma 中用透明 44pt 底板表达） | TOKEN-006 | L | 所有可点元素 hit area ≥44×44 |
| ACCESS-002 | P0 | 颜色依赖 | Pin/未读/选中/已添加仅靠颜色 | Pin 用 `pin.fill` 实心图标；未读补数字或形状；Topic added 补 `checkmark` | AI-005, HOME-001 | M | 关闭颜色区分后信息不丢失 |
| ACCESS-003 | P0 | Dynamic Type | 未验证 | 补两组验证屏：XL 与 AX3，覆盖首页 · 笔记页 · 设置 | Phase 5 完成 | L | 无文字覆盖、无行截断、Chip 仍可点 |
| ACCESS-004 | P0 | 固定尺寸 | `Row/Note` 用 275pt 固定宽 | 改为自适应（Spacer + layoutPriority），仅在 Figma 保留定宽用于渲染 | HOME-001 | M | 交付说明写明不得硬编码 275 |
| ACCESS-005 | P1 | VoiceOver | 0 处标注 | 为红点 · Pin · 色点 · grip · Topic Chip 补 label / hint | ACCESS-002 | M | 每个非文字元素有语义标注 |
| ACCESS-006 | P1 | 对比度 | `text/tertiary` 11pt 不达 AA | 11pt 场景禁用 tertiary，改用 secondary | TOKEN-001 | S | 全文件无 11pt + tertiary 组合 |
| ACCESS-007 | P2 | Reduce Motion | 未定义 | 交付说明：摘要展开动画在 Reduce Motion 下降级为无动画 | TOKEN-005 | S | — |

### 3.14 原型（PROTO）

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| PROTO-001 | P1 | Flow 1 | 缺生成中/更新后 | 补 AI Generating 与 Home Updated 两屏并连线 | AI-003, AI-008 | M | 完整可走 |
| PROTO-002 | P1 | Flow 2 | 缺插图后继续输入 | 连线：编辑器→图片选择→插入后聚焦 | NOTE-006 | M | — |
| PROTO-003 | P1 | Flow 3–4 | 移动文件夹缺 | 连线长按菜单 → Folder Picker | DIALOG-007 | M | — |
| PROTO-004 | P1 | Flow 5 | Topic→Tag 缺反馈 | 连线：展开→点 Topic→已添加态 | AI-005 | S | — |
| PROTO-005 | P1 | Flow 6 | 缺确认 | 连线：⋯→重新生成→确认→生成中 | DIALOG-003 | S | — |
| PROTO-006 | P1 | Flow 8 | 文件夹增删改排全缺 | 连线四步 | FOLDER-002 | M | — |
| PROTO-007 | P1 | Flow 9–10 | 设置流缺 | 连线：Provider→Key→测试三态；Custom→Base URL→Model | SETTINGS-002 | M | — |
| PROTO-008 | P2 | 清理 | 可能存在死链 | 全量检查连线目标有效性 | 全部 | S | 0 条死链 |

### 3.15 最终 QA

| ID | P | Area | Issue | Action | Depends On | Size | Acceptance Criteria |
|---|---|---|---|---|---|---|---|
| QA-001 | P1 | 组件 | 可能存在 detached 实例 | 全量扫描，detached 实例归零 | Phase 5 | S | 0 个 |
| QA-002 | P1 | Token | 可能存在裸数值 | 扫描未绑定变量的 padding/gap/radius | TOKEN-001~004 | M | 绑定率 ≥95% |
| QA-003 | P1 | 命名 | 变体命名一致性 | 全部符合 `属性=值`，无 `Variant 1` | Phase 3 | S | 0 处违规 |
| QA-004 | P1 | 布局 | 文本溢出 / 裁切 | 复用已有的溢出与裁切检查脚本 | Phase 5 | S | 0 处 |
| QA-005 | P2 | 冗余 | 孤儿屏 / 重复组件 | 清理 | Phase 5 | S | — |

**Backlog 合计：约 90 项（P0 38 · P1 41 · P2 11）**

---

## 4. Dependency Graph

```
IA-001 决策冻结（8 条）
   │
   ├─→ IA-002/003/004 结构调整
   │
   ▼
TOKEN-001~007 基础层
   │
   ├──────────────┬──────────────┬─────────────┐
   ▼              ▼              ▼             ▼
基础组件        Block 组件      反馈组件      Dialog 基座
Row/Chip/Nav   Text/Image/    Empty/Error/  Confirmation
               Audio/Doc/Link  Loading
   │              │              │             │
   └──────┬───────┴──────────────┴─────────────┘
          ▼
   组件状态补全（Phase 3）
   AI-001~008 · HOME-001~007 · BLOCK-009~011 · SETTINGS-003~004
          │
          ▼
   Sheet / Dialog / Menu（Phase 4）
   DIALOG-001~011 · PERMISSION-001~002
          │
          ▼
   屏幕组装（Phase 5）
   Home · Note · Search · Folder · Settings · Advanced
          │
          ├─────────────┐
          ▼             ▼
   原型连线        无障碍验证
   PROTO-001~008  ACCESS-003~007
          │             │
          └──────┬──────┘
                 ▼
          最终 QA（Phase 8）
```

**关键路径**：`IA-001 → TOKEN-001 → AI-001 → AI-008 → HOME-001 → Phase 5 → PROTO-001`
**最长依赖链上的瓶颈**：`AI-001`（9 变体）与 `HOME-001`（5 内容态）—— 二者都是 L 规模且被大量下游依赖，应最先启动。

---

## 5. Phase Plan

采用 **9 个阶段**（在建议的 8 个基础上，把「反馈组件」从 Phase 2 拆出为 2.5，因为 `Empty/Error/Loading` 被 Sheet、屏幕、块三处依赖，需早于它们完成）。

| Phase | 名称 | 内容 | 出口 |
|---|---|---|---|
| **0** | Decision Freeze | §2 的 8 条决策签字 | 8 条全部有结论 |
| **1** | Foundations Cleanup | TOKEN-001~007 · IA-002/003/004 | Token 收敛完成，结构调整落地 |
| **2** | Core Components | 建/补 16 个基础组件（不含状态） | 组件树按 §6 建立 |
| **2.5** | Shared Feedback | EMPTY-001 · ERROR-001 · LOADING-001 | 三个反馈组件可被复用 |
| **3** | Component State Coverage | AI-001~008 · HOME-001~007 · BLOCK-002~011 · SETTINGS-003~004 | 所有 P0 状态齐全 |
| **4** | Sheets / Dialogs / Menus | DIALOG-001~011 · PERMISSION-001~002 | 13 个覆盖层完成 |
| **5** | Screen Completion | 6 个页面**真实存在且有明显差异**的关键状态 | 见下方「Screen State 判定准则」 |
| **6** | Prototype Completion | PROTO-001~008 | 10 条 Flow 可走通 |
| **7** | Accessibility / Device | ACCESS-001~007 | Dynamic Type 两档验证通过 |
| **8** | Final Design QA | QA-001~005 | 五项检查全绿 |

**为什么拆出 2.5**：`Empty State` 被首页/搜索×2/文件夹/标签 5 处使用，`Error Row` 被 AI/STT/图片/链接/文档/导出/iCloud 7 处使用。若与 Phase 3 并行，会出现「先在各处画了 7 个不同的错误行，再回来统一」的返工。

### Screen State 判定准则（取代「每页至少四态」）

**不要求**每页必须有 `default / empty / loading / error` 四屏。例如 Settings 不存在「空设置页」这种业务状态，人为制造一屏毫无意义。

**判定规则**：只有当某状态**改变整页结构**时才建 Screen State；否则优先作为 Component state / inline feedback / Sheet 处理。

| 页面 | 需要的 Screen State | 不需要的 | 理由 |
|---|---|---|---|
| Home | default · empty(全 App 无笔记) · empty(文件夹为空) | loading · error | AI 状态由 `Note / AI Badge` 组件表达，不改变页面结构 |
| Note | default · 编辑聚焦(adaptive toolbar) · ⋯菜单 · 摘要展开 | empty · error | 空笔记就是「标题占位 + 一个空文字块」，属 default 的自然形态；错误由 Summary Bar / 各 Block 就地表达 |
| Search | empty-query · typing · no-result · has-result | error | 四态页面结构确实不同 |
| Folder Mgmt | default · empty | loading · error | 本地数据，无异步 |
| Settings | default · Custom Provider | empty · loading · error | 测试连接三态由 `Form / Action Status` 组件表达 |
| Advanced Settings | default | 其余全部 | 纯表单页 |

**合计 Screen State 约 16 个**（而非机械的 6×4=24）。

---

## 6. Component Plan

### 6.0 三条组件建模硬规则

**规则 1 — 禁止变体笛卡尔积。**
状态完整 ≠ 穷举所有属性组合。凡是「维度 A × 维度 B」会产生 >8 个变体的，一律拆为**嵌套组件 + Instance Swap / Boolean 属性**。

反例（禁止）：`Row / Note` 用 `content=5 × summaryState=3 × pinned × unread × pressed` → 理论 120 变体。
正例：主组件 1 个 + 两个嵌套子组件集（5 + 3 变体）+ 2 个布尔属性 → **共 9 个变体**，覆盖同样 60 种组合。

**规则 2 — `pressed` / `focused` 按「是否产生真实视觉差异」判断，不做机械禁止。**

禁止的是**把它们当作无意义的笛卡尔积组合轴**。只有当该状态产生**独立、稳定、需要设计交付**的视觉或交互差异时才建 Variant。

| 场景 | 结论 | 理由 |
|---|---|---|
| `Row / Note` pressed | **不建** | iOS List 自带按下反馈 |
| 普通 Button / Chip pressed | **优先不建** | 交给系统交互反馈；除非按下态有结构性变化 |
| `Block / Text` rendered/editing | **必须建** | 两态是完全不同的渲染方式 |
| 输入框 focused / error | **可建** | 若描边、背景、辅助文案发生真实变化 |
| 其它 | 按实际视觉差异逐个判断 | — |

在 `📐 Foundations` 中定义一次通用按下规则（背景叠加 8% 或 opacity 0.7）供系统反馈不足时引用。

**规则 3 — 只为「真实存在 + 视觉/交互有明显差异」的状态建变体。**
不为了让组件面板看起来完整而制造变体。

### 6.1 组件树

```
🧩 Components
├── Foundation
│   └── Icon                     27 变体（name=）
│
├── Navigation
│   ├── Bar / Status             1
│   ├── Bar / Nav                变体：size=large|inline           ← 删除 title=folder（D-02）
│   ├── Bar / Bottom             1  ← 新建（D-01）承载 compose 按钮
│   ├── Bar / Toolbar            变体：mode=insert|adaptive        ← D-03 单层自适应
│   │   └─ 嵌套 Menu / Media Insert（adaptive 模式下 ＋ 的展开内容）
│   └── Bar / Home Indicator     1
│
├── Rows
│   ├── Row / Note               ★ 拆解见 §6.2，共 1 主件 + 2 子集
│   ├── Row / Folder             变体：trailing=chevron|grip
│   │                            布尔属性：Dragging
│   ├── Row / Form               变体：type=value|chevron|toggle|action
│   │                            布尔属性：Toggle On · Disabled · Destructive
│   │                            └─ 嵌套 Form / Action Status（idle|testing|success|failure）
│   └── Row / Menu Item          变体：type=default|destructive
│
├── Chips
│   ├── Chip / Folder            变体：state=default|selected|more   ← D-04（无 pressed 变体）
│   ├── Chip / Folder Meta       变体：state=assigned|unassigned     ← 新建（D-02 笔记内归属）
│   ├── Chip / Tag               变体：state=default|selected
│   └── Chip / Topic             变体：state=default|added           ← D-06（pressed 走全局规则）
│
├── AI
│   ├── Bar / Summary            变体：state=9 种（见 §7.1）— 单一维度，不拆
│   └── Panel / Summary          变体：logCount=0|1|many
│
├── Blocks
│   ├── Block / Text             变体：state=rendered|editing        ← 新建（focused 走全局规则）
│   ├── Block / Image            变体：state=loaded|loading|failed|missing
│   ├── Block / Audio            变体：state=idle|playing|transcribing|failed
│   │   └─ 嵌套 Audio / Transcript（none|short|collapsed|expanded）  ← 拆解，避免 4×4
│   ├── Block / Document         变体：state=normal|unsupported|missing  ← 新建
│   └── Block / Link             变体：state=preview|url-only|loading|failed ← 新建
│
├── Feedback
│   ├── Empty State              属性：Icon · Title · Message · Show CTA
│   ├── Error Row                变体：ctaCount=0|1|2
│   └── Loading Row              变体：style=spinner|skeleton
│
├── Overlays
│   ├── Dialog / Confirmation    变体：tone=default|destructive
│   ├── Sheet / Recorder         变体：state=idle|recording|paused|done|failed
│   ├── Sheet / Tag Editor       1
│   ├── Sheet / Folder Editor    变体：mode=create|rename
│   ├── Sheet / Image Viewer     1
│   ├── Sheet / URL Input        1
│   ├── Sheet / Permission       变体：type=camera|photo|microphone
│   ├── Menu / Folder Picker     1
│   └── Menu / Media Insert      1  ← 新建（D-03 的 ＋ 展开内容）
│
└── Deprecated
    └── Button / FAB             🗑 删除（D-01）
```

### 6.2 `Row / Note` 拆解示例（规则 1 的样板）

```
Row / Note                          ← 主组件，0 个变体
├── [instance swap] Note / Preview      子集：type=ai-summary|text|audio|image|empty   (5)
├── [instance swap] Note / AI Badge     子集：state=none|generating|failed             (3)
├── [boolean]       Show Pin
├── [boolean]       Show Unread
└── Time                                文本属性
```

| 方案 | 变体总数 | 可表达组合 |
|---|---|---|
| 笛卡尔积（禁止） | **120** | 120 |
| 嵌套拆解（采用） | **8**（5+3） | 5 × 3 × 2 × 2 = 60 |

同样处理已应用于：`Block / Audio`（4×4 → 4+4）· `Row / Form`（10 → 4+4+3 布尔）· `Row / Folder`（4 → 2+1 布尔）。

**组件数变化**：16 → 约 33（新建 18，删除 1）。变体总数约 **95**（若用笛卡尔积会超过 400）。
**注意这不是「页面变多」，是「系统变完整且可维护」。**

---

## 7. State Matrices

### 7.1 AI Summary State Matrix

| State | Trigger | UI | CTA | Next State |
|---|---|---|---|---|
| `hidden` | 笔记无任何内容 | 整条不渲染 | — | `pending`（用户输入后） |
| `pending` | 有内容 · 无摘要 · 自动更新开启 | ✨ 退出后将自动生成总结（`text/tertiary`，不可点） | — | `generating`（退出页面时） |
| `generating` | 退出触发 或 ⋯→立即更新 | ✨ AI 正在总结… + `ProgressView` | — | `success` / `error-*` |
| `success` | 生成成功 · 无未读更新 | ✨ {baseOneLiner} 单行截断 + `chevron.down` | 展开 | `expanded` |
| `success-unread` | 有未读 update log | 🔴 + ✨ {baseOneLiner} + `chevron.down` | 展开 | `expanded`（并标记已读，见 AI-007） |
| `error-auth` | `missingAPIKey` · `unauthorized` · `missingModel` · `invalidBaseURL` | ⚠️ API Key 无效或未配置 | **去设置** | Settings 页 |
| `error-network` | 网络失败 · 超时 | ⚠️ 网络连接失败 | **重试** | `generating` |
| `error-rate-limit` | 429 · 额度不足 | ⚠️ 调用频率超限，请稍后重试 | **重试** | `generating` |
| `error-content` | 内容过少 | 内容太少，暂无可总结的内容（非警告样式，`text/secondary`） | — | `pending`（内容增加后） |

**首页 vs 笔记内的错误分工（D-05）**：上表 4 种 error 态**只出现在笔记内的 Summary Bar**。首页 `Row / Note` 遇到失败时，摘要行**回退为正文预览**，仅在时间列旁显示轻量 ⚠️ 指示 —— 失败不得永久占据首页的主摘要区域，用户重新进入笔记才看到完整错误与 recovery CTA。

**关键规则**：
- `error-content` **不是错误**，不用警告图标和警告色 —— 它是正常的业务提示。
- 只有 `error-auth` 的 CTA 是「去设置」。网络类错误给「重试」，配置类错误给「去设置」。**不要所有错误都给重试。**
- `pending` 态不可点击，避免用户以为点了能立即生成。

### 7.2 Content Block State Matrix

| Block | State | UI | Interaction | Recovery |
|---|---|---|---|---|
| **Text** | `rendered` | 渲染后的 Markdown | 点击 → `editing` | — |
| | `editing` | Markdown 源码 + 光标 + Markdown 工具条 | 失焦 → `rendered` | — |
| **Image** | `loading` | 占位块 + spinner | — | — |
| | `loaded` | 缩略图（有说明才显示说明） | 点击 → 全屏；长按 → 菜单 | — |
| | `failed` | 占位图标 + 「加载失败」 | — | **重试** / **移除** |
| | `missing` | 占位图标 + 「文件已丢失」 | — | **移除** |
| **Audio** | `idle` | 播放按钮 + 波形 + 时长 | 点击播放 | — |
| | `playing` | 暂停按钮 + 进度波形 + 当前时间 | 拖动进度 | — |
| | `transcribing` | 播放条 + spinner + 「转写中…」 | — | — |
| | `failed` | 播放条 + ⚠️ 转写失败 | — | **重试**（唯一按钮） |
| | `transcript=collapsed` | 转写前 3 行 + 「展开」 | 点击展开 | — |
| | `transcript=expanded` | 全部转写 + 「收起」 | 长按 → 重新转写 / 编辑 / 删除 | — |
| **Document** | `normal` | 图标 + 文件名 + 类型 | 点击 → QuickLook；长按 → 删除 | — |
| | `unsupported` | 同上 + 「暂不支持提取文字」橙色标记 | 仍可预览 | — |
| | `missing` | 灰化 + 「文件已丢失」 | — | **移除** |
| **Link** | `loading` | URL + spinner | — | — |
| | `preview` | 标题 + 描述 + 图标 + URL | 点击 → 应用内浏览器；长按 → Safari/复制/编辑/删除 | — |
| | `url-only` | 仅 URL（无 metadata） | **同上，完全可用** | — |
| | `failed` | 仅 URL + 灰色「预览获取失败」 | **仍可点击打开** | 可选「重试预览」 |

**Link 的核心约束**：`failed` 与 `url-only` 都**必须保持链接可用**。预览是增强，不是前提。

### 7.3 Permission Flow Matrix

| Permission | Initial Request | Denied | Recovery | System Settings Required |
|---|---|---|---|---|
| Camera | 点击 📷 → 拍照 时系统弹窗 | `Sheet / Permission (camera)` | 「去设置」→ App 设置页 | ✅ |
| Photo Library | 点击 📷 → 从相册选 时系统弹窗 | `Sheet / Permission (photo)` | 「去设置」 | ✅ |
| Microphone | 点击 🎙 时系统弹窗 | `Sheet / Permission (microphone)` | 「去设置」 | ✅ |
| Speech Recognition | 首次本地转写时 | 与 microphone 合并提示 | 「去设置」 | ✅ |
| AI Privacy Consent | 首次生成摘要前 | `Dialog / AI Privacy Consent` 取消 | 设置页「重置隐私同意状态」 | ❌ App 内 |
| Audio Upload Consent | 首次云端转写前 | `Dialog / Audio Upload Consent` 取消 | 设置页「重置音频上传同意」 | ❌ App 内 |
| Document Access | 文档选择器（系统托管） | 无需自定义 | — | ❌ |

**规则**：系统权限被拒 → 必须给「去设置」；App 内同意 → 必须在设置页给重置入口。**任何一条都不能是死路。**

### 7.4 Empty / Loading / Error Matrix

| 类型 | 场景 | 组件 | 文案要点 |
|---|---|---|---|
| **Empty** | 全 App 无笔记 | `Empty State` | 还没有笔记 + 指向底部新建按钮 |
| | 某文件夹为空 | `Empty State` + CTA | 这个文件夹还是空的 + 「查看全部笔记」 |
| | 搜索未输入 | `Empty State` | 搜索全部笔记 + 说明搜索范围 |
| | 搜索无结果 | `Empty State` | 没有找到匹配的卡片 + 换个关键词 |
| | 文件夹管理为空 | `Empty State` | 说明**文件夹是可选的**，不诱导必须创建 |
| | 标签为空 | 不显示任何 Section | 无空 Section |
| **Loading** | AI 摘要 | `Bar / Summary` state=generating | — |
| | 转写 | `Block / Audio` state=transcribing | — |
| | 图片 | `Block / Image` state=loading | — |
| | 链接元数据 | `Block / Link` state=loading | — |
| | 搜索 | `Loading Row` | 防抖期间不显示，>500ms 才显示 |
| | 测试连接 | `Row / Form` type=action-testing | — |
| **Error** | AI | `Bar / Summary` error-×4 | 见 §7.1 |
| | STT | `Block / Audio` state=failed | 单一「重试」 |
| | 图片 / 文档 / 链接 | 各块 failed 态 | 就地恢复，**不弹 Alert** |
| | 导出 | `Error Row` | 就地提示 |
| | iCloud | `Error Row`（Advanced Settings 内） | — |
| | 测试连接 | `Row / Form` type=action-failure | 行下方显示错误详情 |

**原则**：错误优先 **local · contextual · recoverable**。只有会导致数据丢失的操作才用 Alert。

---

## 8. Sheet / Dialog Plan

| 组件 | 类型 | 变体 | 触发点 | 依赖 |
|---|---|---|---|---|
| `Dialog / Confirmation` | confirmationDialog | `tone=default\|destructive` | 通用基座 | — |
| `Dialog / AI Privacy Consent` | alert | 1 | 首次生成摘要 | Confirmation |
| `Dialog / Audio Upload Consent` | alert | 1 | 首次云端转写 | Confirmation |
| `Dialog / Delete Folder` | confirmationDialog | `count=zero\|some` | 文件夹左滑删除 | Confirmation |
| `Sheet / Recorder` | sheet `.medium` | `state=`5 | 🎙 | — |
| `Sheet / Tag Editor` | sheet `.medium` | 1 | Tag 行 / `#` 按钮 | Chip/Tag |
| `Sheet / Folder Editor` | sheet `.medium` | `mode=create\|rename` | ＋ / 左滑重命名 | — |
| `Sheet / Image Viewer` | fullScreenCover | 1 | 点击图片 | Block/Image |
| `Sheet / URL Input` | alert + TextField | 1 | 🔗（剪贴板非 URL 时） | — |
| `Sheet / Permission Denied` | sheet `.medium` | `type=`3 | 权限被拒 | — |
| `Menu / Folder Picker` | Menu | 1 | 长按菜单「移动到文件夹…」 | — |

**层级约束**：**禁止 Sheet 套 Sheet**。`Sheet / Recorder` 完成后直接回到编辑器，不再弹二级确认。`Menu / Folder Picker` 中的「新建文件夹…」是唯一允许的 Menu→Sheet 跳转。

---

## 9. Prototype Plan

| Flow | Screen Sequence | Required Frames | Required States | Missing Pieces | Expected Interaction |
|---|---|---|---|---|---|
| **1** 新建→AI | Home → Note(new) → 输入 → Back → Home | ②, ⑧, ②(generating), ②(updated) | Row/Note `generating`+`normal` · Summary `pending`→`generating`→`success` | ②的两个变体屏 · AI-003 · AI-008 | 返回后行内显示「总结中…」，随后变为一句话摘要 |
| **2** 插图继续写 | Note(聚焦打字) → 工具条 `＋` → Media Insert Menu → Picker → Note(图片+新文字块聚焦) | ⑧(adaptive), ⑧(menu 展开), Picker(系统), ⑧′ | Toolbar `mode=adaptive` · Menu/Media Insert · Block/Image `loaded` · Block/Text `editing` | ⑧ 三个态 · NOTE-001 · NOTE-006 | **全程键盘不收起**；插图后光标自动落在图片下方新文字块。这条 Flow 是 D-03 的验收用例 |
| **3** 移动文件夹 | Home → 长按 → Context Menu → Folder Picker → Home | ②, ②(menu), Folder Picker | Row/Note `pressed` | 长按菜单屏 · DIALOG-007 | 选择后行从当前筛选中消失（若筛选中） |
| **4** 笔记内改归属 | Note → ⋯ → 移动到文件夹 → Picker | ④, ⑥, Folder Picker | — | IA-004 后 ⋯ 菜单需加项 | 与 Flow 3 落到**同一个** Picker |
| **5** Topic→Tag | Note → Summary Bar → Expanded → 点 Topic | ④, ⑤, ⑤′ | Chip/Topic `default`→`added` | AI-005 · ⑤′ 屏 | 点击后 chip 变实心+✓，标题下 Tag 行同步出现 |
| **6** 重新生成 | Note → ⋯ → 重新生成 → 确认 → generating | ④, ⑥, Dialog, ④(generating) | Summary `generating` | DIALOG-003 · AI-003 | 确认后摘要条立刻变为生成中 |
| **7** 搜索 | Home → Search → Tag Chip → Result → Note | ②, ⑨(empty), ⑨(typing), ⑨(result), ④ | Chip/Tag `selected` | SEARCH-001 三屏 | 点 Tag 后搜索框自动填入 `#标签` |
| **8** 文件夹管理 | Home → Chip⋯ → Folder Mgmt → Create → Rename → Reorder → Delete | ⑪, Folder Editor×2, ⑪(dragging), Dialog | Row/Folder `dragging` | FOLDER-002/003 · FOLDER-001 | 删除时显示「将同时删除其中 N 张笔记」 |
| **9** Provider 配置 | Settings → Provider → Key → Test | ⑩, ⑩(testing), ⑩(success), ⑩(failure) | Row/Form `action-×3` | SETTINGS-003 三态 | 测试成功显示绿勾，失败显示红叉+原因 |
| **10** Custom Provider | Settings → Provider=Custom → Base URL → Model | ⑩, ⑩(custom) | — | SETTINGS-002 | 切换后 Base URL 与 Model 出现在第一屏 |

**现状**：7 条连线覆盖 Flow 1（一半）· Flow 2（无中间态）· Flow 7（无 Tag 筛选）。**需新增约 22 条连线与 14 个中间态屏。**

---

## 10. Accessibility Plan

**原则：无障碍在每个 Phase 内完成，不作为 Phase 7 的补丁。**

| Phase | 无障碍任务 |
|---|---|
| **1 Foundations** | TOKEN-006 确立 44pt hit area 规则；ACCESS-006 禁用「11pt + tertiary」组合 |
| **2 Core Components** | 每个可点组件建立时就带 44pt 透明底板；`Row / Note` 不使用固定 275pt 宽（ACCESS-004） |
| **3 State Coverage** | ACCESS-002：`selected` / `added` / `unread` / `pinned` 四类状态**必须同时有非颜色特征**（图标 · 形状 · 文字） |
| **4 Sheets** | 所有 destructive 按钮标注 `accessibilityLabel` 含「删除」字样 |
| **5 Screens** | 每屏标注 VoiceOver 阅读顺序 |
| **7 Validation** | ACCESS-003：XL 与 AX3 两档 Dynamic Type 验证；ACCESS-005 VoiceOver 标注补全 |

**非颜色冗余的具体做法**：

| 状态 | 当前（仅颜色） | 改为 |
|---|---|---|
| 置顶 | 橙色 pin 描边图标 | `pin.fill` 实心 + VO「已置顶」 |
| 未读 | 红点 | 红点 + VO「有 N 条未读更新」 |
| Chip 选中 | 蓝色填充 | 蓝色填充 + `checkmark` 前缀 |
| Topic 已添加 | （当前无区分） | 实心 + `checkmark` + VO「已添加为标签」 |
| 文件夹色点 | 彩色方块 | 方块 + 文件夹名（已有）；色点仅辅助 |
| 拖动手柄 | 灰色三横线 | 保持 + VO「拖动以重新排序」 |

---

## 11. Token Migration Plan

### 11.1 Spacing

| Current | → Target | 说明 |
|---|---|---|
| 1, 2, 2.5 | **保留** | 波形条间距 / 描边宽度，属视觉细节非布局间距，不纳入 scale |
| 4, 5, 6 | → **4** | |
| 8, 10 | → **8** | |
| 11, 12, 13 | → **12** | |
| 14, 16, 18 | → **16** | |
| 20, 22 | → **20** | |
| 26, 30, 32 | → **32** | |

**最终 scale**：`4 / 8 / 12 / 16 / 20 / 24 / 32`（24 目前未用到，保留供后续）

### 11.2 Radius

| Current | → Target | 说明 |
|---|---|---|
| 2, 3, 4, 5 | **保留为 `radius/xs=4`** | 波形条 / 键帽等微元素 |
| 8, 9, 10 | → **8** | chip · 小卡片 |
| 12, 14 | → **12** | 按钮 · 内容块 |
| 16, 20 | → **16** | 卡片 · 菜单 · Sheet |
| 28 | → **999** | 圆形按钮改用 capsule 语义 |
| 47 | **保留** | **设备物理圆角，系统值，不参与收敛** |
| 99 | → **999** | 统一 capsule 命名 |

### 11.3 Icon Size

| Current | → Target |
|---|---|
| 13, 14, 15 | → **16** |
| 17, 19 | → **20** |
| 22, 25 | → **24** |
| 34 | **保留**（音频播放按钮，视觉锚点） |
| 52 | **保留**（空状态插画尺寸） |

### 11.4 保留的系统值（不参与收敛）

| 值 | 用途 |
|---|---|
| 44 | HIG 最小触控目标 / 导航栏高度 |
| 49 | 底部 toolbar 标准高度（D-01 后引入） |
| 54 | 状态栏高度（Dynamic Island 机型） |
| 34 | Home Indicator 区域 |
| 47 | 设备圆角 |
| 393 / 852 | iPhone 15 逻辑尺寸 |

**执行方式**：不要手工在 Figma 里逐个改。这些值全部由生成器 `code.js` 的 `SCALE` 常量与调用点决定，**改常量 + 改调用点，重跑插件**即可全量迁移。

---

## 12. Execution Order

| # | 步骤 | Why now | Depends on | Unlocks | Size |
|---|---|---|---|---|---|
| 1 | 冻结 8 条产品决策 | 决定组件树形状，先做避免全盘返工 | — | 一切 | S |
| 2 | Token 收敛（Spacing/Radius/Icon/Row） | 所有组件都建立在其上；后做要改 30 个组件 | 1 | Phase 2 | M |
| 3 | 结构调整（删 FAB · 删现状屏 · 导航栏改造） | 属结构性，越早越省 | 1, 2 | Phase 2 | M |
| 4 | **AI Summary 组件（9 态）** | 关键路径最长节点，被首页与笔记页双向依赖 | 2 | AI-008 · Phase 5 | L |
| 5 | **Content Blocks（5 个 × 状态）** | 第二长节点，3 个组件从零建 | 2 | 笔记页全部状态 | XL |
| 6 | Shared Feedback（Empty/Error/Loading） | 被 12 处依赖，晚做必返工 | 2 | Phase 4 · 5 | M |
| 7 | Rows / Chips 状态补全 | 依赖 Token 与 Feedback | 2, 6 | 首页 · 搜索 · 文件夹 | L |
| 8 | Sheets / Dialogs / Menus（13 个） | 依赖 Confirmation 基座与各块组件 | 5, 6 | Phase 5 · 6 | XL |
| 9 | Home 全状态 | 组件齐备后组装 | 4, 7 | Flow 1 · 3 · 7 | M |
| 10 | Note 全状态 | 同上 | 4, 5, 8 | Flow 2 · 4 · 5 · 6 | L |
| 11 | Search 三态 | 依赖 Row/Note 与 Empty State | 7, 6 | Flow 7 | S |
| 12 | Folder Management 全状态 | 依赖 Folder Editor Sheet | 8 | Flow 8 | M |
| 13 | Settings + Advanced Settings | 相对独立，可与 9–12 并行 | 2, 6 | Flow 9 · 10 | L |
| 14 | Prototype 连线（10 Flow） | 需要全部屏与状态就位 | 9–13 | 可交付评审 | L |
| 15 | Accessibility 验证（Dynamic Type / VO） | 需完整屏才能验证极限 | 14 | 可交付开发 | L |
| 16 | Final Design QA | 收口 | 15 | 交付 | M |

**可并行**：步骤 13（Settings）与 9–12 无依赖关系，可与之并行。步骤 4 与 5 也可并行（分属不同人时）。

---

## 13. Definition of Done

### Phase 0
- [ ] §2 全部 8 条决策有最终结论并回写本文档
- [ ] 每条决策记录了 trade-off 理由

### Phase 1
- [ ] `space/*` 仅剩 7 个值，`radius/*` 仅剩 5 个，`size/icon-*` 仅剩 3 个
- [ ] 系统值（44/49/54/34/47/393/852）单独分组且有注释说明为何不收敛
- [ ] `Button / FAB` 与 `elevation/fab` 已删除
- [ ] ①③⑦ 及其 Dark 版本已归档并从 Screens 页删除
- [ ] 重跑生成器后 QA-002 绑定率 ≥95%

### Phase 2
- [ ] §6 组件树中所有节点存在（可以只有 default 变体）
- [ ] 无 detached 实例
- [ ] 所有组件命名符合 `分类 / 名称`

### Phase 2.5
- [ ] `Empty State` · `Error Row` · `Loading Row` 三组件可被实例化并覆盖 §7.4 全部场景

### Phase 3
- [ ] AI Summary 9 态齐全，4 种错误 CTA 各不相同（**9 态是真实业务状态，属合理 Variant，不受数量检查拦截**）
- [ ] 5 种 Block 状态齐全，Link `failed` 仍可点击
- [ ] `Row / Note` 覆盖 5 种内容态 + 3 种 AI 状态，且通过嵌套而非笛卡尔积实现
- [ ] **变体架构检查通过**：无多个独立布尔被乘成完整笛卡尔积 · 无产品中永不出现的组合 · 无「本可用 nested/boolean/instance property 表达却展开成大量 Variant」的情况。**不设机械的统一变体数上限**
- [ ] 所有变体命名为 `属性=值`，无 `Variant N`
- [ ] Light / Dark 双模式全部可切换
- [ ] 无组件依赖固定高度实现布局（Dynamic Type 前提）
- [ ] 每个 error 态都有 recovery path

### Phase 4
- [ ] 13 个覆盖层齐全
- [ ] 无 Sheet 套 Sheet
- [ ] 所有 destructive 操作有确认，且确认按钮非默认焦点
- [ ] 所有权限被拒态含「去设置」

### Phase 5
- [ ] 按「Screen State 判定准则」完成约 16 个页面状态（**不做机械的 6×4**）
- [ ] 每个被省略的状态都能说出「为什么它不需要独立 Screen」
- [ ] Advanced Settings 存在且分 4 节
- [ ] Settings 覆盖 Custom Provider 态
- [ ] QA-004 文本溢出与裁切检查 0 处

### Phase 6
- [ ] 10 条 Flow 全部可从头走通
- [ ] 0 条死链
- [ ] 每条 Flow 的关键中间态（generating / confirming / denied）都在原型中可达

### Phase 7
- [ ] XL 与 AX3 两档 Dynamic Type：无文字覆盖 · 无行截断 · Chip 仍可点
- [ ] 所有可点元素 hit area ≥44×44
- [ ] 关闭颜色区分后，pinned / unread / selected / added 四类状态仍可辨识
- [ ] 每个非文字元素有 VoiceOver label

### Phase 8
- [ ] detached 实例 = 0
- [ ] Token 绑定率 ≥95%
- [ ] 变体命名违规 = 0
- [ ] 死链 = 0
- [ ] 孤儿屏 / 重复组件 = 0

---

## 14. Final Batch A / B / C

### Batch A — Before Any Screen Work

> **在动任何屏幕之前必须完成。这批不产出好看的截图，但决定后面所有工作是否会返工。**

| # | 任务 | 条目 | 规模 | 验收 |
|---|---|---|---|---|
| A-1 | 决策冻结（**已完成 2026-08-06**） | IA-001 | S | ✅ 8 条已定，其中 D-02/03/04 方案已修改 |
| A-2 | 归档并删除现状对照屏 | IA-002 | S | ①③⑦ 及 Dark 版导出至 `design/archive/`，Screens 页只剩改后方案 |
| A-3 | 删除 FAB，改底部 toolbar | IA-003 | M | `Button / FAB` 与 `elevation/fab` 消失；② ⑫ 底部为 toolbar + compose 按钮 |
| A-4 | 导航栏改造 + Folder Meta Chip | IA-004 · NOTE-007 | M | 导航栏 `‹ (空) ⋯`；标题下方有 `工作 ▾` chip |
| A-5 | Spacing Token 收敛 | TOKEN-001 | M | `space/*` 仅剩 7 值 |
| A-6 | Radius Token 收敛 | TOKEN-002 | S | `radius/*` 仅剩 5 值 |
| A-7 | Icon Size Token 收敛 | TOKEN-003 | S | `size/icon-*` 仅剩 3 通用值 |
| A-8 | Row Height Token | TOKEN-004 | S | 新增 `row/standard=44` · `row/two-line=56` |
| A-9 | Motion Token | TOKEN-005 | S | `duration/fast` · `duration/normal` |
| A-10 | **全局 pressed 规则** | TOKEN-008 | S | 规范板中定义一次；全库不建 pressed 变体 |
| A-11 | 44pt hit area 规则 | TOKEN-006 | S | 每个可点组件 Description 写明 |
| A-12 | 空标题占位降级 | TOKEN-007 | S | `iOS/Title3` |
| A-13 | 基础组件树建立（仅 default 变体） | §6.1 全部节点 | L | 33 个组件节点存在，命名符合 `分类 / 名称` |
| A-14 | 嵌套子组件集建立（空壳） | `Note / Preview` · `Note / AI Badge` · `Audio / Transcript` · `Form / Action Status` | M | 4 个子集存在，供 Phase 3 填充 |
| A-15 | 共享反馈组件 | EMPTY-001 · ERROR-001 · LOADING-001 | M | 三件可实例化 |

**Batch A 合计 15 项。完成标志：组件树成形、Token 稳定、拆解结构就位、无返工风险。**

> **A-13/A-14 是本批的关键**：先把嵌套拆解的骨架搭好，Phase 3 才能只填变体而不重构组件。若跳过 A-14 直接进 Phase 3，会退化成笛卡尔积。

### Batch B — Complete Product States

> **本项目工作量的主体。核心是补状态，不是画新屏。**

| 内容 | 条目 | 规模 |
|---|---|---|
| AI 摘要工作流 | AI-001~008 | L |
| 内容块 5 件套 | BLOCK-001~011 | XL |
| 首页状态 | HOME-001~007 | L |
| 笔记页状态 | NOTE-001~006 | M |
| 搜索 | SEARCH-001~003 | S |
| 文件夹 | FOLDER-001~005 | M |
| 设置 + 高级 | SETTINGS-001~005 | L |
| Sheet / Dialog / Menu | DIALOG-001~011 | XL |
| 权限 | PERMISSION-001~002 | M |
| 错误补充 | ERROR-002~003 | S |

**Batch B 合计约 55 项。**

### Batch C — Validation & Handoff

| 内容 | 条目 | 规模 |
|---|---|---|
| 原型 10 条 Flow | PROTO-001~008 | L |
| 无障碍验证 | ACCESS-001~007 | L |
| 最终 QA | QA-001~005 | M |
| 交付说明撰写 | SwiftUI Handoff Notes（见下） | M |

**Batch C 合计约 20 项。**

---

## 附：Design Spec 与 SwiftUI Implementation Spec 的边界

**放进 Figma 的**：组件变体 · 状态 · 尺寸 · 间距 · 44pt hit area 底板 · 原型转场 · VoiceOver 文案

**放进 Handoff Notes 的（不污染视觉组件）**：

| 设计意图 | SwiftUI 实现建议 |
|---|---|
| 44pt hit area | `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` |
| **Chip 行滚动时保持可访问**（D-07 只定义行为，实现由此处决定） | 候选 A：`.safeAreaInset(edge: .top)` —— 完全固定<br>候选 B：`Section` + `.headerProminence` pinned header —— 随 section 吸顶<br>候选 C：`ScrollView` + `.scrollTargetBehavior` 自定义<br>**取舍**：若需要「向下滚动时隐藏、向上滚动时出现」则用 C；若始终可见用 A。最终由 scroll behavior 定 |
| 底部工具条 + 新建按钮 | `ToolbarItem(placement: .bottomBar)` |
| **单层自适应工具条**（D-03） | `.safeAreaInset(edge: .bottom)` 承载单一 toolbar；用 `@FocusState` 切换 `mode`；`＋` 用 `Menu` 承载媒体插入，**避免再叠一层 `.keyboardToolbar`** |
| 左滑置顶 / 右滑删除 | `.swipeActions(edge: .leading)` / `.swipeActions(edge: .trailing)` |
| 长按菜单 + 拖拽排序 | `List` + `.contextMenu` + `.onMove`（二者在 List 内可共存，**不要**自定义 `.draggable`） |
| 插入媒体后聚焦新块 | `@FocusState` + Picker `.onDisappear` 后 `DispatchQueue.main.async` 赋值 + `ScrollViewReader.scrollTo` |
| Markdown 渲染/编辑切换不跳变 | 两态使用相同 `font` 与 `lineSpacing`；切换时 `.animation(nil)` |
| Sheet 高度 | `.presentationDetents([.medium])`，不自定义高度 |
| 确认对话框 | `.confirmationDialog`，destructive 用 `role: .destructive` |
| 「总结中」瞬态 | 不入 SwiftData；用外部 `@Observable` 状态机或 `@Transient` |
| Reduce Motion | `@Environment(\.accessibilityReduceMotion)` 降级动画 |
| Dynamic Type | 全部改 `minHeight`；Chip 行用 `ViewThatFits` |

---

## 附：本计划的执行方式

**重要**：本 Figma 文件由 [`design/figma-plugin/code.js`](figma-plugin/code.js) 程序化生成，**不是手工绘制**。

因此本计划的执行方式是**改生成器再重跑**，而不是在 Figma 里手工改图层。这带来两个约束：

1. **所有整改都应落到 `code.js`**，否则下次重跑会被覆盖。
2. **已有的六项自动检查**（起始页健壮性 · 文本溢出 · 裁切截断 · 行高自适应 · 组件实例计数 · 变体属性完整性）应随每个 Phase 扩充。建议新增：变体命名规范检查 · Token 绑定率检查 · 触控目标检查 · 死链检查。

**每次改完必须做的两步**（本项目已验证过三次「桩放行了真 bug」）：
1. Node 桩跑一遍，挡运行时错误
2. 重跑插件后用 MCP 实读核对，挡视觉缺陷

单靠任何一步都不够。
