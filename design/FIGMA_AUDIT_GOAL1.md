# Mosaic / 万象记 — Figma Design Audit（Goal 1 Retrieval Quality System 视角）

> ⚠️ **本文件是 2026-08-07 的首次审计快照，已被后续工作取代，仅作历史记录保留。**
> 当时的结论「Goal 1 在 Figma 中的覆盖率为 0%」已不再成立。
> 当前覆盖状态请看 [`GOAL1_UI_COVERAGE.md`](GOAL1_UI_COVERAGE.md)（Missing = 0）。
> 本文件中关于 PRD 缺失的判断也已被修正 —— Goal 1 的 Source of Truth 是
> **Mosaic AI Retrieval Quality Platform PRD v1.0**（不在本仓库内）。

> 审计日期：2026-08-07
> 审计对象：Figma 文件 `Untitled`（Dev Mode MCP 实读）+ `prd.md` v0.2 + `Sources/MosaicKit`
> 审计基准：本次任务描述的 **Goal 1 — Mosaic Retrieval Quality System v1**
> 实读节点：`13:24939`（01 · 全部界面 Light，20 屏全量结构）· `0:1` · 变量集（live）
>
> **本报告只依据 Figma / 仓库实际状态。凡 Figma 无法判断的，写 Not Defined in Current Figma。**

---

# 1. Executive Summary

1. **当前 Figma 是一份完成度很高、已冻结的「PRD v0.2 笔记 App」设计文件**，不是 Goal 1 的设计文件。实读确认：📱 Screens 页 2 块画板（Light / Dark）× 20 屏 = 40 屏；🧩 Components 37 个顶层组件、26 个变体集、116 个变体、35 个组件属性、450 个实例；📐 Foundations 16 色变量（双模式）、27 数值变量、15 文字样式、2 效果样式。状态：`DESIGN STATUS: FROZEN — READY FOR IMPLEMENTATION`。

2. **Goal 1 在 Figma 中的覆盖率为 0%。** 20 屏里没有任何一屏涉及 Semantic Search、Retrieval Lab、Eval Center、Release Gate、Trace、Failure Inspection、Regression Set、Developer Mode。`11 · 高级设置` 的四个 Section 是「AI 参数 / 语音转写 / 同步与数据 / 隐私」，**没有 Developer Mode 入口**。

3. **Figma / PRD Conflict — 方向与预期相反。** Figma 与 `prd.md` 高度一致，几乎无冲突；真正的冲突是 **Goal 1 在仓库中没有任何权威来源**。`prd.md` v0.2（2026-06-15）全文 515 行，`retrieval / semantic / embedding / vector / recall / MRR / eval / gate / trace / RRF / chunk` 出现次数为 **0**。全仓库 grep 同样为 0（唯一命中是 Figma 插件测试桩里的 `VECTOR` 节点类型）。**Goal 1 目前只存在于本次任务描述里。这是当前最大的项目风险，且是文档风险，不是设计风险。**

4. **不存在 Developer Tool UI Over-design。** 本次审计原本要防的「画了一堆漂亮 Dashboard」问题在当前文件里**不存在**——因为一个 Developer 页面都没画。风险方向是 under-design，不是 over-design。

5. **真正的 over-invest 在别处：Figma 生成与校验基础设施。** `design/figma-plugin/` 是一个 1928 行的设计生成器 + 5 套自动化测试（checks / gates / calibration / tolerance / selftest）+ 86 点数值校准 + 容差体系。对一个 6 周、故事主线是 retrieval quality 的 portfolio 项目，这套 apparatus 的边际收益已经耗尽。**已投入的是沉没成本，不建议推翻；但绝不应该让 Goal 1 的新屏再走这条流水线。**

6. **Search 是唯一已存在、且必须被大幅改造的 Production 页面。** 已有 3 屏（`06 · 搜索`有结果 / `12 · 未输入` / `13 · 无结果`）。当前形态是纯 keyword 搜索：搜索框 + 标签 chip 行 + 结果行（标题 / 一句话 / 文件夹 / 时间）。**结果行的副标题是 AI `one_liner`，不是 Matched Excerpt** —— 这与 Goal 1 「解释为什么这条笔记与 Query 相关」的核心目标直接相反。

7. **Matched Excerpt 不只是设计缺口，也是数据层缺口。** `Sources/MosaicKit/Search/SearchMatcher.swift` 的签名是 `matches(query:haystack:tags:) -> Bool` —— 对拼接后的 haystack 做全词 AND 子串判定，**返回布尔值，无 offset、无 block 归属、无 score、无排序**。所以「高亮命中片段」在今天的架构下不是画一个 UI 就能实现的，必须先改检索层返回结构。

8. **Search 的组件化程度显著低于文件其余部分。** `Search Field` 在 06/12/13 三屏是**裸 frame 复制三份**（`13:23967` / `13:24357` / `13:24397`），不是组件实例；`Tag Filter` 行同样是裸 frame 复制；`Result / Q3 产品评审会`（`13:23986`）是由裸 text 节点手搭的 frame，**`Row / Search Result` 组件不存在**。而同一文件里 `Row / Note`、`Row / Folder`、`Row / Form` 都已是带变体的组件。这是全文件组件化程度最低的一块，恰好又是 Goal 1 唯一的 Production 战场。

9. **Note Editor 不阻碍 Retrieval，且 AI 衍生数据暴露程度是恰当的。** Block/Text · Image · Audio · Document · Link 五类块全部组件化并带状态变体（`20 · 内容块状态一览` 专门陈列 image-failed / audio-transcribing / audio-failed / document-uploading / link-failed）。Audio 的 transcript 有独立 `Audio / Transcript` 子组件并可展开——符合 PRD §4.3.2「转写稿可展开查看与手动修正」；Document 的 `extractedText` 不展示——符合 PRD §4.3.4「提取文字不展示给用户」。**结论：无 AI 衍生数据过度暴露问题，Note Editor 本轮不需要重新设计。**

10. **Portfolio 叙事目前讲的是另一个故事。** 当前文件能极有力地证明「设计系统纪律 + Token 治理 + 状态完备性 + 自动化设计 QA」，这是一个 **Design Systems / Design Engineering** 的 portfolio。它**无法**证明 semantic vs lexical hybrid retrieval、evaluation、release gating、observability。想讲第 27 节那个故事，还差整整一条主线。

---

# 2. Current Figma Inventory

## 2.1 文件结构（实读）

| Page | 内容 | 实读依据 |
|---|---|---|
| `Page 1`（默认页） | 27 个 `name=*` 图标 symbol（gear / search / pencil / chevronR·D·U / back / pin / dots / sparkle / camera / mic / doc / link / tag / plus / play / folder / photo / wave / trash / share / refresh / book / briefcase / bulb / grip） | `get_metadata(0:1)` |
| `📐 Foundations` | 1 块规范板：色板 · 数值 · 系统几何值 · 按下规则 · 触控规则 · 字阶 | `code.js:1876` + `DESIGN_BASELINE.md` |
| `🧩 Components` | 37 个顶层组件节点 / 26 变体集 / 116 变体 / 35 组件属性 | `code.js:450 buildComponents()` + `DESIGN_BASELINE.md` |
| `📱 Screens` | 2 块画板 × 20 屏；`01 · 全部界面（Light）` = `13:24939`，`02 · 全部界面（Dark）` | `get_metadata(13:24939)` 全量实读 |

> ⚠️ **待确认（30 秒即可核实）**：`get_metadata(0:1)` 显示 27 个图标 symbol 直接挂在默认页 `Page 1` 下，但 `code.js:433` 是在 `buildComponents(PG.components)` 内创建 `C.icon`。请在 Figma 里确认 Icon 变体集实际所在页；若确在 `Page 1`，应移入 `🧩 Components` 并删除空的默认页，否则组件库的页面归属是脏的。

## 2.2 Screens 清单（20 屏 × Light/Dark，全部实读自 `13:24939`）

| # | Screen | Node ID (Light) | Current Status | Main Purpose | User / Developer |
|---|---|---|---|---|---|
| 01 | 首页 · 全部笔记 | `13:23492` | Complete（default 态） | 全部笔记流 + Folder chip 筛选 | User |
| 02 | 笔记页 · 摘要收起 | `13:23613` | Complete | 阅读 / 编辑笔记，摘要折叠 | User |
| 03 | 笔记页 · 摘要展开 | `13:23714` | Complete | 展开 AI 摘要面板（Topic chip） | User |
| 04 | 笔记页 · ⋯ 菜单 | `13:23782` | Complete（8 项） | 低频动作收口 | User |
| 05 | 编辑器 · 聚焦 | `13:23946` | Complete（含键盘 + 自适应工具条） | 输入态 | User |
| 06 | **搜索（有结果）** | `13:23990` | **Partial** | 关键词搜索 | **User — Goal 1 战场** |
| 07 | 设置 | `13:24073` | Complete | AI 服务商 / 摘要 / 转写 / 高级 / 关于 | User |
| 08 | 文件夹管理 | `13:24146` | Complete | 文件夹 CRUD | User |
| 09 | 首启空状态 | `13:24183` | Complete | 冷启动引导 | User |
| 10 | 设置 · 自定义服务商 | `13:24247` | Complete | Base URL + 模型 + Key | User |
| 11 | **高级设置** | `13:24336` | Complete（但**无 Developer Mode 入口**） | AI 参数 / STT / iCloud / 隐私 | User |
| 12 | **搜索 · 未输入** | `13:24376` | Partial | 空 query 引导 + tag chip | **User — Goal 1 战场** |
| 13 | **搜索 · 无结果** | `13:24409` | Partial | 零结果 | **User — Goal 1 战场** |
| 14 | 文件夹管理 · 空 | `13:24439` | Complete | 空态 | User |
| 15 | 首页 · 文件夹为空 | `13:24493` | Complete | 筛选后空态 | User |
| 16 | 覆盖层 · 删除确认 | `13:24518` | Complete | destructive dialog | User |
| 17 | 录音 Sheet · 录制中 | `13:24552` | Complete（5 态之一） | 录音 | User |
| 18 | 权限被拒 · 麦克风 | `13:24597` | Complete（含「去设置」） | 权限恢复 | User |
| 19 | AI 摘要 9 态一览 | `13:24722` | Complete（规格板） | hidden/pending/generating/success/success-unread/error-auth/error-network/error-rate-limit/error-content | Spec board |
| 20 | 内容块状态一览 | `13:24858` | Complete（规格板） | image-failed / audio-transcribing / audio-failed / document-uploading / link-failed | Spec board |

**Goal 1 相关屏数：0。** 无 Retrieval Lab / Eval Center / Release Gate / Trace / Failure Inspection / Regression Set / Developer Mode / Index Status。

## 2.3 Components 清单（37，源 `code.js:450–1200`）

| 分组 | 组件 |
|---|---|
| 基础 | `Icon`(27 变体) · `Bar / Status` · `Bar / Nav` · `Bar / Bottom` · `Bar / Toolbar`(mode) · `Bar / Home Indicator` |
| 行 | `Row / Note` · `Row / Folder`(trailing) · `Row / Form`(type) · `Row / Menu Item`(type) · `Error Row`(ctaCount) · `Loading Row`(style) |
| Chip | `Chip / Folder`(state) · `Chip / Folder Meta`(state) · `Chip / Tag`(state) · `Chip / Topic`(state) |
| AI | `Bar / Summary`(state ×9) · `Panel / Summary`(logCount) · `Note / AI Badge`(state) · `Note / Preview`(type) |
| Block | `Block / Text`(state) · `Block / Image`(state ×4) · `Block / Audio`(state ×4) · `Block / Document`(state) · `Block / Link`(state) · `Audio / Transcript`(state) |
| 覆盖层 | `Dialog / Confirmation`(tone) · `Sheet / Recorder`(state ×5) · `Sheet / Tag Editor` · `Sheet / Folder Editor`(mode) · `Sheet / Image Viewer` · `Sheet / URL Input` · `Sheet / Permission`(type) · `Menu / Folder Picker` · `Menu / Media Insert` |
| 其它 | `Empty State` · `Form / Action Status`(state) |

**缺失且 Goal 1 需要的组件：`Row / Search Result` · `Search Field` · `Badge / Status` · `Row / Metric` · `Row / Gate Result` · `Row / Developer Setting` · `Chip / Search Mode`。**

## 2.4 Design Tokens（live 实读 `get_variable_defs(13:24939)`）

- **颜色 16**：`text/primary·secondary·tertiary·on-accent` · `bg/primary·card·fill·fill-strong` · `accent/blue·blue-bg·red·red-bg·orange·green` · `separator` · `scrim`（Light/Dark 双模式）
- **Spacing 7**：`4 / 8 / 12 / 16 / 20 / 24 / 32`
- **Radius 5**：`xs 4 / sm 8 / md 12 / lg 16 / full 999`
- **系统几何 8**：`tap-min 44` · `nav-height 44` · `toolbar-height 49` · `status-height 54` · `home-indicator 34` · `device-radius 47` · `screen-w 393` · `screen-h 852` · `row/standard 44`
- **文字样式 15**：`iOS/Title1·2·3` · `Headline` · `Body` · `Callout` · `Subheadline(+Emphasized)` · `Footnote` · `Caption1(+Emphasized)` · `Caption2` …（PingFang SC）
- **效果 2**：`elevation/menu` · `elevation/drag`

**评价：Token 层已经是 production 级，Goal 1 的所有新屏可以零成本复用，不需要新建任何 Foundation。** 唯一可能需要补的是 metric 的等宽数字（见 §8）。

---

# 3. Current Information Architecture

```text
App
├── 首页 · 全部笔记                       [01]  ← 根屏，非 TabView
│   ├── Nav Bar: 🔍 搜索(push) · ⚙︎ 设置(push)
│   ├── Folder Filter Row (horizontal chips, 溢出→「更多」)
│   ├── Feed: Row / Note × N
│   │   ├── tap        → 笔记页 [02]
│   │   ├── long press → Context Menu            ── Not Defined in Current Figma（无该屏）
│   │   └── swipe      → 行手势                   ── Not Defined in Current Figma（无该屏）
│   ├── Bottom Bar: compose 按钮（D-01，FAB 已废除）
│   └── 空态: [09] 首启 · [15] 文件夹为空
│
├── 搜索                                  [06/12/13]  ← push，独立屏（非 .searchable inline）
│   ├── Search Field (裸 frame，未组件化，×3 复制)
│   ├── Tag Filter Row (裸 frame，点击→填入搜索框)
│   ├── Result Row (裸 frame，未组件化)  → 笔记页 [02]
│   │   └── 定位到具体 block?             ── **Not Defined in Current Figma**
│   └── 状态: 未输入 [12] · 无结果 [13] · 有结果 [06]
│       └── loading / error / offline     ── **Not Defined in Current Figma**
│
├── 笔记页                                [02/03/04/05]
│   ├── Summary Bar (collapsed, 9 态) ⇄ Summary Panel (expanded) [03]
│   │   └── Topic Chip → tap → 转为 Tag（D-06）
│   ├── Head: 标题 + Metadata(Folder Meta chip + Tag chips)  ← D-02
│   ├── Blocks: Text / Audio / Image / Document / Link
│   ├── Toolbar (单层自适应，D-03) → Menu / Media Insert
│   ├── Nav Bar ⋯ Menu [04]（8 项：置顶 / 移动到文件夹 / 立即更新总结 /
│   │                        重新生成完整总结 / 清除 AI 摘要 /
│   │                        导出 Markdown / 导出纯文本 / 删除）
│   └── 编辑聚焦态 [05]（含键盘）
│
├── 文件夹管理                            [08/14]  ← 二级页（原首页降级）
│
└── 设置                                  [07]
    ├── AI 服务商（服务商 / API Key / 测试连接）
    │   └── 自定义服务商                   [10]（Base URL / 模型名 / Key / 测试连接）
    ├── 摘要（自动追加更新总结）
    ├── 语音转写（转写方式 / 识别语言）
    ├── 高级 ›                             [11]
    │   ├── AI 参数（Base URL / 模型 / 发图给 AI / JSON 模式）
    │   ├── 语音转写（STT 模型 / Base URL / Key）
    │   ├── 同步与数据（iCloud）
    │   ├── 隐私（重置隐私同意 / 重置音频上传同意）
    │   └── ❌ Developer Mode              ── **不存在**
    └── 关于 ›                             ── 有入口无页面

覆盖层（跨屏）
├── Dialog / Confirmation                 [16]
├── Sheet / Recorder (5 态)               [17]
├── Sheet / Permission                    [18]
├── Sheet / Tag Editor · Folder Editor · Image Viewer · URL Input   ── 有组件，无独立屏
└── Menu / Folder Picker · Media Insert   ── 有组件，无独立屏
```

**Navigation 判定**
- **Tab / NavigationStack**：无 TabView，纯 NavigationStack 栈式（首页为根）。与 PRD §3「导航以栈式进入 + 返回为主」一致。
- **Push**：搜索 · 设置 · 高级设置 · 自定义服务商 · 文件夹管理 · 笔记页。
- **Sheet**：Recorder · Permission · Tag Editor · Folder Editor · Image Viewer · URL Input。
- **Menu（scrim + 浮层）**：笔记页 ⋯ 菜单 [04] · Folder Picker · Media Insert。
- **ConfirmationDialog**：删除确认 [16]。
- **Toolbar entry**：底部 compose [01] · 笔记页自适应工具条 [05]。
- **Context menu / Long press / Swipe action / Drag reorder**：`REMEDIATION_PLAN.md` §9 Flow 3、Flow 8 有文字规格，**但 Figma 中无对应屏**。→ **Not Defined in Current Figma**（P1，非 Goal 1 阻塞）。

---

# 4. Current User Flows

`DESIGN_BASELINE.md` 记录 22 条原型连线 / 10 条 Flow / 死链 0。对应 `REMEDIATION_PLAN.md` §9：

| # | Flow | Goal 1 相关性 |
|---|---|---|
| 1 | 新建 → 输入 → 返回 → AI generating → success | 间接（索引触发时机） |
| 2 | 插图继续写（键盘不收起，D-03 验收） | 无 |
| 3 | 长按 → 移动文件夹 | 无 |
| 4 | 笔记内 ⋯ → 移动文件夹 | 无 |
| 5 | Topic → Tag | 间接（tag 是 lexical 信号） |
| 6 | 重新生成完整总结 | **间接但重要**（会使索引 stale） |
| 7 | **Home → Search → Tag Chip → Result → Note** | **直接 —— Goal 1 唯一相关 Flow** |
| 8 | 文件夹管理（建 / 改名 / 排序 / 删） | 无 |
| 9 | Provider 配置 + 测试连接 | 类比（Developer Mode 的 Form 范式可复用） |
| 10 | 自定义 Provider | 类比 |

**Goal 1 三条关键 Flow（任务书 §26）的现状：**

| Flow | 现状 |
|---|---|
| **User Flow**（自然语言 Query → Hybrid → Matched Excerpt → Open Note） | ❌ 不存在。Flow 7 只到「Tag chip 填入搜索框 → 点结果 → 打开笔记」，无自然语言、无 hybrid、无 excerpt、无定位 |
| **Developer Flow**（Lab → 三路对比 → Golden Dataset → Eval → Gate → Promote） | ❌ 完全不存在 |
| **Failure Flow**（New Config → Eval → Regression Failure → Inspect → BLOCKED） | ❌ 完全不存在 |

---

# 5. Screen-by-Screen Audit

> 只审计与 Goal 1 有关、或可能阻碍 Goal 1 的页面。其余 14 屏经实读确认为 Complete 且与 Goal 1 无冲突，**不为了给建议而强行建议修改**。

---

## Screen: 06 · 搜索（有结果）`13:23990`

### Purpose
用关键词在全部笔记中找到某一条。

### Primary User Task
「我记得我写过某件事，把它找出来。」

### Primary Action
在搜索框输入 → 点击某条结果 → 打开笔记。

### Secondary Actions
点 Tag chip 把 `#标签` 填入搜索框；返回。

### Information Hierarchy
当前层级：**结果标题（Headline）> 一句话（Subheadline / secondary）> 文件夹 + 时间（Caption）**。
问题：这个层级是**为「浏览笔记列表」设计的**，与首页 `Row / Note` 同构（UI_REDESIGN §4 明确写「结果行与首页笔记行同构」）。而搜索场景要回答的是「**为什么这条与我的 Query 有关**」，需要的层级是 **标题 > 命中片段（含高亮）> 归属 + 时间**。当前设计把最该占据视觉焦点的信息（命中证据）替换成了与 Query 无关的 AI `one_liner`。

### Navigation
进入：首页 Nav Bar 🔍（push）。退出：`<` 返回。下一步：结果 → 笔记页 [02]。

### Interaction
Tap（搜索框 / tag chip / 结果行 / 返回）· Text Input（250ms 防抖，UI_REDESIGN §4）。
无 swipe / long press / menu / picker / toggle。

### States
| 状态 | Figma |
|---|---|
| Default（有结果） | ✅ [06]，但只画了 **1 条**结果 |
| Empty（未输入） | ✅ [12] |
| Empty（无结果） | ✅ [13] |
| Loading / Searching | ❌ |
| Error | ❌ |
| Offline | ❌ |
| Index Building / Rebuilding | ❌（概念不存在） |
| Semantic Unavailable → fallback | ❌（概念不存在） |

### Data Dependency
Card.title · AI `one_liner` · Folder(icon+name) · updatedAt · Tag。
**缺**：matched excerpt、match offsets、per-block 归属、relevance score、retrieval mode。

### Problems

| ID | P | 问题 | 证据 |
|---|---|---|---|
| S-1 | **P0** | 结果副标题用 AI `one_liner` 而非 Matched Excerpt，无法解释相关性 | `13:23976` 文本「确定了排期与三位负责人，…」= 首页 Row/Note 的 preview |
| S-2 | **P0** | 无 highlight —— 命中词在结果中不可见 | 结果行内无任何高亮样式节点 |
| S-3 | **P0** | 点击结果后是否 scroll-to-block / highlight block **未定义** | 原型 Flow 7 只到 `→ ④`；Figma 无中间态屏 → **Missing Interaction Definition** |
| S-4 | **P0** | 无 Search Mode 表达（keyword / semantic / hybrid 对用户不可见也不可感知） | 无相关节点 |
| S-5 | **P0** | 无 loading 态。Semantic 检索有网络/计算延迟，keyword 子串匹配没有——**这是从同步搜索转向异步搜索的架构变化，必须先在设计上定义** | 无 |
| S-6 | **P0** | 无 index building / semantic unavailable / offline 的 fallback 表达。当前设计等价于「AI Failure = Product Failure」 | 无 |
| S-7 | P1 | 只画了 1 条结果，多结果的列表节奏、分组、分隔、滚动未验证 | `13:23986` 单实例 |
| S-8 | P1 | 无结果计数 / 无排序或 scope 切换 | 无 |
| S-9 | P1 | placeholder「搜索全部笔记」只暗示 keyword，不邀请自然语言 Query | `13:23966` |
| S-10 | P1 | `Search Field` 是裸 frame，在 06/12/13 三屏复制三份 | `13:23967` / `13:24357` / `13:24397` 均为 FRAME 非 INSTANCE |
| S-11 | P1 | `Result` 行是裸 frame，无 `Row / Search Result` 组件 | `13:23986` 由裸 text 节点手搭 |
| S-12 | P1 | `Tag Filter` 在 [13] 无结果态消失，规则未说明（是刻意隐藏还是遗漏？） | [06]/[12] 有，[13] 无 |
| S-13 | P2 | 结果行不显示 Tag | — |

### Recommendation

1. **把 `Result` 提升为 `Row / Search Result` 组件**，字段：`Title` / `Excerpt`(支持 highlight range) / `Folder` / `Time` / 可选 `Tag`。变体：`state = default | pressed`（`highlighted`/`selected` 在 iOS List 中由系统提供，不要自造，见 §20）。
2. **副标题槽位改为 Matched Excerpt，one_liner 仅作为 excerpt 缺失时的 fallback。** 影响 User Flow：这是「搜索结果可解释」的唯一载体。
3. **把 `Search Field` 组件化**，变体 `state = idle | typing | searching`（searching 时尾部 ProgressView）。
4. **新增 4 个状态屏**：searching / index-building（顶部一行非阻塞提示 + keyword 结果照常出）/ semantic-unavailable（fallback 提示条）/ error。
5. **定义 Result → Note 的落点行为**（见 §6.4），这是 P0 且**在写 SwiftUI 之前必须有答案**。
6. placeholder 改为暗示双模式，例如「搜索关键词，或描述你记得的内容」。**不要出现 embedding / 向量 / 语义相似度 等字样。**

---

## Screen: 12 · 搜索 · 未输入 `13:24376` / 13 · 搜索 · 无结果 `13:24409`

### Purpose / Task
[12] 给出无 query 时的可操作入口；[13] 告诉用户没找到并给下一步。

### Problems

| ID | P | 问题 |
|---|---|---|
| S-14 | P1 | [12] 只有 tag chip 作为引导。Goal 1 需要在这里放 **自然语言 query 示例**（如「我之前问学校能不能晚一点毕业的事情」），这是教会用户「这个搜索框不止能搜关键词」的**唯一时机**，也是 portfolio demo 的最佳舞台 |
| S-15 | P1 | [13] 无结果时无「换个说法试试 / 该内容可能还未建立索引」等归因，用户无法区分「真没有」和「系统没准备好」 |
| S-16 | P2 | [13] 丢失 Tag Filter 行（见 S-12） |

### Recommendation
[12] 加一个「试试这样搜」示例区（3 条自然语言 query，可点击直接填入）；[13] 的文案按 index 状态分叉两版。

---

## Screen: 11 · 高级设置 `13:24336`

### Purpose
承接第一屏放不下的低频配置。

### Problems

| ID | P | 问题 |
|---|---|---|
| S-17 | **P0** | **无 Developer Mode 入口。** Goal 1 的全部 Developer Tool 没有任何可达路径 |
| S-18 | P1 | 无「搜索与索引」Section（重建索引 / 索引状态 / 语义搜索开关）。这是**普通用户**也需要的（当 semantic 出问题时的自救入口），不属于 Developer Mode |

### Recommendation
1. 在 [11] 末尾加 `Section / 开发者`，一行 `Developer Mode  [Toggle]`；开启后在其下方出现一行 `开发者工具 ›`（push 到 Developer Mode 主页）。**用 `Row / Form` 现有组件，零新组件成本。**
2. 加 `Section / 搜索与索引`：`语义搜索 [Toggle]` · `索引状态（已就绪 / 建立中 12%）` · `重建索引`（destructive-ish action row，复用 `Form / Action Status` 三态）。

---

## Screen: 01 · 首页 `13:23492`

### Problems
| ID | P | 问题 |
|---|---|---|
| S-19 | P2 | 搜索入口在 Nav Bar 🔍（push 独立屏）。iOS 原生心理模型更偏向 `.searchable` 下拉。**但**：Goal 1 的搜索是异步 + 多态 + 有 mode 切换，独立屏更好控制。**当前设计正确，不建议改。** |

**其余无 Goal 1 相关问题。**

---

## Screen: 02/03/05 · 笔记页与编辑器

按任务书 §11 检查「是否阻碍 Retrieval / 是否过度暴露 AI 衍生数据」：

| 检查项 | 结论 |
|---|---|
| Text Block 内容来源 | ✅ 直接内容 |
| Audio Block → transcript | ✅ 有 `Audio / Transcript` 子组件，可展开。PRD §4.3.2 要求「可展开查看与手动修正」→ **暴露是对的** |
| Image Block → OCR | ⚠️ **PRD 里根本没有 OCR**。PRD §4.3.3 走的是「图片作为视觉输入发给多模态模型」，产出的是 summary，不是可检索的 OCR 文本。**这是 Goal 1 的一个隐含前提缺口，不是 Figma 缺陷**（见 §9 与 §11） |
| Document Block → extractedText | ✅ 只显示图标 + 文件名 + 类型，不展示提取文字 —— 符合 PRD §4.3.4 |
| Link Block → title/description | ✅ 显示 title + url，提取文本不展示 |

**结论：Note Editor 无 AI derived data 过度暴露问题，不阻碍 Retrieval，本轮不需要任何改动。**

| ID | P | 问题 |
|---|---|---|
| S-20 | P1 | 从搜索结果进入笔记后，没有任何「你是从搜索来的」的视觉延续（无高亮、无锚点）。这是 S-3 的下半段 |

---

# 6. Semantic Search Audit（Goal 1 最重要的 Production UI）

## 6.1 Search Entry

| 检查 | 结论 |
|---|---|
| 从哪里进入 | 首页 Nav Bar 🔍，push 到独立 Search 屏 |
| 首页是否有稳定入口 | ✅ 常驻，符合心理模型 |
| 是否需要单独 Search Screen | ✅ **需要，且当前决策正确**。Goal 1 的搜索是异步的、有多种系统状态、可能需要 mode 提示，`.searchable` 的 inline 下拉难以承载这些 |
| 是否与 Folder / Tag filter 冲突 | ⚠️ **半冲突**。Folder 筛选在首页（Chip row），Tag 筛选被搬到搜索页（UI_REDESIGN §4）。用户想「在『工作』文件夹里搜」时无路径 —— **Search 内无 scope 概念**。P1（Goal 1 不阻塞，但会在 demo 中被问到） |

## 6.2 Query Input

| Query 类型 | 当前设计是否支持 |
|---|---|
| Exact（`CS5330` / `Mask R-CNN` / `API Key`） | ✅ 子串 AND 匹配天然支持 |
| Semantic（「我之前问学校能不能晚一点毕业的事情」） | ❌ **不支持，且 UI 未做任何邀请**。placeholder「搜索全部笔记」+ tag chip 的组合，强烈暗示「这是个关键词框」 |

**关键设计问题：一个框如何同时服务两种 Query？** Figma 当前未回答。三种可行方向：

| 方案 | 说明 | SwiftUI 成本 | 建议 |
|---|---|---|---|
| A. 全隐式 hybrid | 单框，永远 hybrid，用户无感 | 低 | ✅ **推荐**。符合任务书「不暴露 AI 术语」 |
| B. Segmented mode | 关键词 / 智能 / 全部 三段 | 中 | ❌ 把系统内部结构泄漏给用户 |
| C. 隐式 hybrid + 结果分组 | 单框，结果分「精确匹配 / 相关内容」两组 | 中 | ⚠️ 备选，能解释性最强但增加列表复杂度 |

**建议采用 A，并把「为什么相关」的解释权完全交给 Matched Excerpt。** 这样用户模型只有一句话：「你随便说，我尽量找。」

## 6.3 Search Result

| 应有字段 | 当前 |
|---|---|
| Note Title | ✅ `13:23975` |
| **Matched Excerpt** | ❌ **当前是 AI one_liner** |
| Folder | ✅ `13:23981`（icon + name） |
| Updated Time | ✅ `13:23983`（相对时间「3小时前」） |
| Tag（可选） | ❌ |
| Highlight | ❌ |

**这是本次审计的头号 P0。** 搜索结果的存在意义是回答「为什么这条与我的 Query 有关」。one_liner 回答的是「这条笔记讲什么」—— 与 Query 无关，两条不同笔记的 one_liner 长得一样时用户完全无法判断该点哪条。

## 6.4 Result Interaction

**Missing Interaction Definition（P0）。**

Figma 只定义了「点结果 → 笔记页 [02]」。未定义：
- 命中在某个 Block 时，是否 scroll to block？
- 是否 highlight 该 block？
- highlight 是永久、temporary（2–3s 淡出）、还是直到滚动？
- 命中在 Audio transcript 里怎么办？transcript 默认是折叠的 —— **要不要自动展开？**（这一条尤其重要，`Audio / Transcript` 已有 state 变体，但没有 `auto-expanded-from-search` 的定义）
- 命中在 Summary 里（而非正文）怎么办？要不要自动展开 Summary Panel？

**这五个问题若不在 Figma 里定死，SwiftUI 阶段一定会边写边设计。** 建议方案：scroll to block + 2.5s temporary highlight（`accent/blue-bg` 已有 token，零新增）+ 命中在 transcript/summary 时自动展开对应容器。

---

# 7. Search System State 检查（Progressive Enhancement）

| 状态 | Figma 是否考虑 | 应有行为 |
|---|---|---|
| Index Ready | —（无索引概念） | 正常 hybrid |
| Index Building | ❌ | 顶部非阻塞提示条「正在准备智能搜索…」，**keyword 结果照常返回** |
| Index Rebuilding | ❌ | 同上，文案区分 |
| Embedding Failed | ❌ | 一行「智能搜索暂不可用，已按关键词搜索」+ 重试 |
| Offline | ❌ | 若 provider 依赖云端，同上降级 |
| Semantic Unavailable | ❌ | Hybrid → Keyword 自动降级，**不弹错误、不阻断** |

**判定：当前设计不符合 Progressive Enhancement —— 但不是因为设计错了，而是因为整个 index 生命周期概念在设计中不存在。**

**这是 Goal 1 最重要的一条设计原则，也是 portfolio 里最能体现「AI 产品可靠性思维」的地方：**

> AI 层失效时，产品降级为原来的样子，而不是坏掉。

建议在 Figma 里用**一个组件**统一表达：`Bar / Search Status`，变体 `state = hidden | building | degraded | error`。放在 Search Field 正下方，44pt 高，一行文字 + 可选 CTA。**成本极低（一个变体集，可完全复用 `Error Row` 的排版），收益极高。**

---

# 8. Design System Audit

## 8.1 现状评价

**Foundations 与 Components 层已达 production 级，Goal 1 不需要新建任何 Foundation。**

- Typography：15 个 iOS 文字样式，覆盖 Title1–3 / Headline / Body / Callout / Subheadline / Footnote / Caption1–2 + Emphasized 变体 ✅
- Spacing：收敛为 `4/8/12/16/20/24/32` ✅
- Radius：`4/8/12/16/999` ✅
- Divider / List Row / Card / Chip / Tag / Empty State / AI Status / Button / Toolbar / Sheet / Menu：**全部已组件化** ✅
- Search Result：❌ **唯一的空洞**

## 8.2 Goal 1 需要补的（只列真正复用 ≥2–3 次的）

| 需求 | 是否值得 Componentize | 理由 |
|---|---|---|
| `Row / Search Result` | ✅ 必须 | 搜索页 ×N 实例 + 4 个状态屏复用 |
| `Search Field` | ✅ 必须 | 已在 3 屏被复制 3 次（S-10） |
| `Bar / Search Status` | ✅ 必须 | 4 种系统状态（§7） |
| `Badge / Status` | ✅ 必须 | Eval / Gate / Trace / Lab 四处复用，变体 `success \| warning \| failed \| running` |
| `Row / Metric` | ✅ 值得 | Eval + Gate 两页大量重复（Recall@1/3/5 · MRR · P50 · P95） |
| `Row / Gate Result` | ⚠️ 可选 | 若 Gate 用 `Row / Metric` + `Badge / Status` 拼装则不需要独立组件 —— **推荐不建** |
| `Row / Developer Setting` | ❌ 不建 | 直接复用现有 `Row / Form`（已有 type 变体） |
| `Chip / Search Mode` | ❌ 不建 | 采用隐式 hybrid 方案 A（§6.2），不存在 mode 切换 UI |

**新增组件净增 5 个（37 → 42）。** 这是一个克制且必要的增量。

## 8.3 Token 微缺口

Eval / Trace 页会大量出现数字对齐（`0.847` / `132ms` / `Recall@5`）。当前 15 个文字样式全部是 PingFang SC 比例数字。
**建议：不新增文字样式，SwiftUI 侧用 `.monospacedDigit()` 修饰符解决。** → **Implementation-level requirement — no dedicated Figma design required.**

---

# 9. PRD Coverage Matrix

## 9.1 对 `prd.md` v0.2 的覆盖（现有产品）

| Requirement (PRD §) | Figma Status | Design Needed | Goal |
|---|---|---|---|
| §4.1 文件夹管理 | Complete | — | 已交付 |
| §4.2 卡片管理 | Complete | — | 已交付 |
| §4.3 块编辑器（5 类块） | Complete | — | 已交付 |
| §4.4 折叠态长条 | Complete | — | 已交付 |
| §4.5 AI 摘要 + 增量更新（9 态） | Complete | — | 已交付 |
| §4.7 Provider / Key / 测试连接 | Complete | — | 已交付 |
| §4.9 搜索与标签 | **Partial** | 见 §10 | **Goal 1** |
| §4.10 隐私 / iCloud | Complete | — | 已交付 |
| §6.5 可访问性（VoiceOver / Dynamic Type） | Not Required (Figma) | — | Implementation-level requirement — no dedicated Figma design required（见 `IMPLEMENTATION_QA.md` I-P0-2/3） |
| 长按 / 侧滑 / 拖拽排序屏 | Missing | 3 屏 | P1（非 Goal 1） |
| 「关于」页 | Missing | 1 屏 | P2 |

## 9.2 对 Goal 1 的覆盖

| Requirement | Figma Status | Design Needed | Goal |
|---|---|---|---|
| Semantic Search | **Missing** | 是 | Goal 1 |
| Hybrid Search（用户侧隐式） | **Missing** | 是 | Goal 1 |
| Matched Excerpt | **Missing** | 是 | Goal 1 |
| Search Highlight | **Missing** | 是 | Goal 1 |
| Search Fallback / Progressive Enhancement | **Missing** | 是 | Goal 1 |
| Index Status（用户可见） | **Missing** | 是 | Goal 1 |
| Result → Note 定位行为 | **Missing** | 是（P0） | Goal 1 |
| Developer Mode 入口 | **Missing** | 是（1 行） | Goal 1 |
| Retrieval Lab | **Missing** | wireframe only | Goal 1 |
| Retrieval Comparison（K vs V vs H） | **Missing** | wireframe only | Goal 1 |
| Eval Center | **Missing** | wireframe only | Goal 1 |
| Golden Dataset 管理 | **Missing** | wireframe only | Goal 1 |
| Failure Inspection | **Missing** | wireframe only | Goal 1 |
| Regression Set（Add to…） | **Missing** | wireframe only | Goal 1 |
| Release Gate | **Missing** | wireframe only | Goal 1 |
| Retrieval Trace | **Missing** | wireframe only | Goal 1 |
| Chunking / Embedding lifecycle / contentHash | Not Required | — | Implementation-level requirement — no dedicated Figma design required |
| RRF Fusion / Top-K / 相似度算法 | Not Required | — | 同上（仅在 Lab 的 Picker 里作为选项值出现） |
| Ask My Notes / RAG Chat / Citation QA | **Not Required** | 否 | Stage 3 / 非目标 |
| Cost / Job / Model Gateway Dashboard | **Not Required** | 否 | 非目标 |

**Over-scoped 项：0。当前 Figma 中不存在任何超出 Goal 1 范围的页面。**

---

# 10. Missing Design

## P0 — Development Blocking
> 没有这些，SwiftUI 阶段会被迫临时拍板核心产品逻辑。

| # | 缺失 | 影响的 Flow |
|---|---|---|
| P0-1 | **`Row / Search Result` 组件 + Matched Excerpt + Highlight 规范**（excerpt 取多长、截断规则、多命中取哪段、高亮样式） | User Flow 全部 |
| P0-2 | **Result → Note 的落点行为**：scroll-to-block · temporary highlight · transcript/summary 自动展开 | User Flow 全部；影响 NoteView 的 ScrollViewReader 架构 |
| P0-3 | **Search 系统状态与降级规范**（`Bar / Search Status` 4 态 + 各态下 keyword 是否照常工作） | 决定 SearchViewModel 的整个状态机 |
| P0-4 | **Search 从同步变异步的交互定义**（loading 呈现方式、防抖时长、旧结果保留还是清空、取消语义） | 决定 SearchViewModel 的并发模型 |
| P0-5 | **Developer Mode 入口与 IA**（挂在 [11] 高级设置下、开关 + push） | Developer Flow 全部 |

## P1 — Goal 1 Required
| # | 缺失 |
|---|---|
| P1-1 | Retrieval Lab wireframe（Query → mode 三选 → 参数 → Run → Result Inspector 含 keywordRank / vectorRank / finalRank / similarity 四列对照） |
| P1-2 | Eval Center wireframe（Dataset × Config → Run → Recall@1/3/5 · MRR · P50 · P95；**必须能并排比较两个 Config**） |
| P1-3 | Failure Inspection wireframe（Query / Expected / Returned / 三路结果 / Failure Type / **Add to Regression Set**） |
| P1-4 | Release Gate wireframe（Current vs Baseline vs Threshold 三列 + 大号 **PASS / PROMOTION BLOCKED** + 失败项高亮） |
| P1-5 | Trace wireframe（7 段耗时 + configVersion / embeddingVersion / indexVersion / chunkCount / candidateCount / resultCount / contentHash） |
| P1-6 | `Badge / Status` + `Row / Metric` 组件 |
| P1-7 | 高级设置「搜索与索引」Section（语义搜索开关 / 索引状态 / 重建索引） |
| P1-8 | Search 未输入态的自然语言示例区（S-14）、无结果态归因文案（S-15） |
| P1-9 | Search scope（在当前文件夹内搜）—— 或明确决定不做并记录 |

## P2 — Polish
| # | 缺失 |
|---|---|
| P2-1 | 结果行显示 Tag |
| P2-2 | 搜索历史 / 最近搜索 |
| P2-3 | 多结果列表的分组与节奏验证（≥8 条） |
| P2-4 | Tag Filter 在无结果态的去留规则（S-12） |
| P2-5 | 「关于」页 |

## Goal 2 / Future（**本阶段不做**）
Ask My Notes · RAG Chat · Citation QA · Cross-note reasoning · Agent / Tool Calling · LLM-as-Judge · Prompt Management · Vector DB Dashboard · Feature Flag / Cost / Job / Model Gateway Dashboard。

## Remove / Ignore
**无。** 当前 Figma 20 屏没有一屏超出范围，全部服务于 PRD v0.2 或对 Goal 1 中性。`archive/legacy-screens.js`（旧 IA 对照屏）已按 D-08 归档，处理正确。

---

# 11. Over-designed / Over-scoped Areas

**Figma 屏级：0 处。**（本次审计原本要防的「Developer Dashboard 过度设计」在当前文件里不存在。）

**但存在一处真实的 over-investment，需要一个明确决策：**

## 11.1 Figma 生成与校验流水线

`design/figma-plugin/` = 1928 行生成器 + 5 套自动化测试（`checks` 9 项 / `gates` 9 项 / `calibration` 86 点 / `tolerance` 7 边界 / `selftest` 13 变异）+ 数值容差体系（宽 ±1.0 / 高 ±2.0 / EXACT 0）。

`DESIGN_BASELINE.md` 规定的变更流程是：

```
改 code.js → node test/all.js 五套件全绿 → Figma 重跑插件 → MCP 实读核对 → 刷新 calibration 基准 → 更新 SHA/日期/指标
```

**问题：把 Goal 1 的 Developer Tool wireframe 塞进这条流水线，成本会远超收益。** 一个 Retrieval Lab 的 SwiftUI `Form` 用不着 ±1pt 的像素校准。

**建议（P0 级流程决策，不是设计决策）：明确分成两条轨。**

| 轨 | 内容 | 设计 bar | 载体 |
|---|---|---|---|
| **Track A — Production UI** | Search 全部改造 · 高级设置新 Section | Production：走生成器流水线，复用全部 token 与组件，Light/Dark 双模式 | `code.js` + 📱 Screens |
| **Track B — Developer Tool** | Lab · Eval · Failure · Gate · Trace | Functional：**手绘 wireframe，只用 List/Form/Section/Picker/Toggle 的方框，不上 token、不做 Dark、不做组件化、不进 calibration** | 新建一页 `🔧 Dev Tools (Wireframe)` |

**Track B 的判定标准只有一条：SwiftUI 工程师看了能不能不问问题就写出来。** 不追求好看。

## 11.2 一个可选的更激进方案

Developer Mode 的 5 个页面，如果全部用原生 SwiftUI `Form + List + Section + Picker`，**跳过 Figma 直接写代码**可能更快，且效果不会更差。建议至少对 **Trace** 和 **Failure Inspection** 采取这个策略（它们本质上就是 key-value 列表）。Figma 只保留 Lab / Eval / Gate 三张，因为这三张有真实的**布局决策**（三路对比怎么排、两个 Config 怎么并列、PASS/BLOCKED 怎么一眼看出）。

---

# 12. Development Risk（SwiftUI 视角）

| Screen | Difficulty | Main Technical Risk |
|---|---|---|
| Search（改造后） | **Hard** | ① 异步检索的并发与取消（`.task(id:)` + debounce，旧结果竞态）；② `AttributedString` 高亮 excerpt 的性能（长列表逐行构造）；③ 状态机从「有/无结果」膨胀到 8 态 |
| Result → Note 定位 | **Hard** | `ScrollViewReader` + `.id()` 锚点必须覆盖到 **block 级**；当前 NoteView 的 Blocks 是否已有稳定 id 需核实；transcript/summary 自动展开会与既有折叠状态管理冲突 |
| `Row / Search Result` | Medium | excerpt 截断 + 高亮 + Dynamic Type 下的行数稳定性 |
| `Bar / Search Status` | Easy | 一行文字 + 可选按钮 |
| 高级设置新增 2 个 Section | Easy | 原生 `Form` |
| Retrieval Lab | Medium | 结果 Inspector 的多列对照在 iPhone 窄屏上排版；建议用「每行一个结果 + 三个 rank 的 inline 小标签」而非真表格 |
| Eval Center | Medium | **Config 并排比较**在 393pt 宽度上是真实的布局难题（这是 Figma 必须回答的，不是实现细节） |
| Failure Inspection | Easy | `List` + `Section` |
| Release Gate | Easy–Medium | 逻辑简单；难在「一眼看出为什么不能上线」的视觉编码 |
| Trace | Easy | `List` + `LabeledContent` |
| **索引生命周期（非 UI）** | **Hard** | contentHash → stale 检测 → 增量 embedding → 与 SwiftData/CloudKit 的写入时序。**这是 Goal 1 最大的工程风险，且与 Figma 无关** |

## Unnecessary Complexity 警告
- ❌ 不要为 Eval 画折线图 / 柱状图。6 周项目里，**一张能比较两个 Config 的数字表格 > 任何图表**。
- ❌ 不要为 Trace 画瀑布图 / 火焰图。7 行 `LabeledContent` 就够。
- ❌ 不要给用户侧 Search 做 mode segmented control（§6.2 方案 B）。

---

# 13. Recommended Figma Roadmap

> 排序依据：**开发依赖关系 + 产品风险**，不是页面顺序。

## Phase 0 — 补 PRD（**最高优先级，且不是 Figma 工作**）
Goal 1 目前没有任何书面来源。**先写一份 `prd-retrieval.md`**（2–3 页足矣）定义：检索模式、index 生命周期、失败降级策略、evaluation 指标定义、gate 阈值、Developer Mode 范围。
**为什么先做**：没有它，后面每一张 Figma 都是在猜。这也是 portfolio 里 AI TPM 能力的直接证据。
**风险**：跳过这步，Figma 会画出与最终实现不一致的东西，返工成本高于写文档成本。

## Phase A — Product Flow Lock（Figma，1–2 天）
锁定：Search 的 IA（独立屏 / 隐式 hybrid / 无 mode 切换）· Search 状态机全集 · Result → Note 落点行为 · Developer Mode 在 IA 中的位置。
**产出：一张 IA + 状态机图（可以就画在 Figma 里，不必是高保真屏）。**
DoD：P0-2、P0-3、P0-4、P0-5 全部有书面答案。

## Phase B — Semantic Search Production UI（Figma，3–4 天）★核心
`Search Field` 组件 · `Row / Search Result` 组件 · `Bar / Search Status` 组件 · 8 个状态屏（default 多结果 / searching / index-building / degraded / error / 未输入含示例 / 无结果 / 结果→笔记高亮）· Light + Dark。
**走 Track A 流水线。这是唯一需要 production quality 的部分。**

## Phase C — Developer Tools Wireframe（Figma，2 天）
新页 `🔧 Dev Tools (Wireframe)`，只画 3 张：Retrieval Lab · Eval Center（含 Config 并排比较）· Release Gate。
**Trace 与 Failure Inspection 跳过 Figma，直接 SwiftUI。**
走 Track B，不上 token、不做 Dark、不做 calibration。

## Phase D — Componentization（Figma，0.5 天）
只建 5 个：`Search Field` · `Row / Search Result` · `Bar / Search Status` · `Badge / Status` · `Row / Metric`。
**Developer Setting 行复用 `Row / Form`，不新建。**

## Phase E — Prototype（Figma，0.5 天）
只连 3 条 Flow（任务书 §26）：User Flow（含 index-building 降级分支）· Developer Flow · Failure Flow。
**这三条就是 portfolio 的演示脚本，不要连其它。**

## Phase F — Handoff（0.5 天）
更新 `DESIGN_BASELINE.md` 与 `IMPLEMENTATION_QA.md`：新增组件的 spacing / state / interaction / navigation；明确标注哪些是 Implementation-level（monospacedDigit · excerpt 截断算法 · 高亮 range 计算 · VoiceOver 语义）。

---

# 14. Recommended Next 5 Design Tasks

### 1. 写 `design/prd-retrieval.md` — Goal 1 的产品定义（**不是 Figma 任务，但必须最先做**）
* **Why**：`prd.md` v0.2 全文 0 处提及 retrieval / semantic / eval / gate / trace。Goal 1 目前只存在于对话里。没有它，Figma 每一个决定都是猜测，且 portfolio 缺少「AI TPM 定义问题」这一环。
* **What to design**：检索模式（隐式 hybrid）· index 生命周期状态机（ready / building / rebuilding / stale / failed）· 失败降级矩阵（hybrid → keyword，不阻断）· 评测指标定义与 golden dataset 规模 · gate 阈值（如 Recall@5 不低于 baseline − 2%、P95 < 300ms、regression 100% pass）· Developer Mode 范围边界（明确写出 §3 的非目标清单）。
* **DoD**：3 页以内；每个 Search UI 状态都能在文档里找到对应的系统状态；`prd.md` §4.9 加一行指向它。

### 2. 设计 `Row / Search Result` 组件 + Matched Excerpt 规范
* **Why**：这是 Goal 1 的**产品价值本身**。当前结果行显示 AI one_liner，回答的是「这条笔记讲什么」，而搜索需要回答「为什么它和你的 Query 有关」。影响 User Flow 的每一步，也影响检索层的返回结构（`SearchMatcher` 目前返回 `Bool`，无 offset —— **必须改成返回带 range 的 match 结果**）。
* **What to design**：组件字段 Title / Excerpt(highlight range) / Folder / Time / 可选 Tag；变体 `state = default | pressed`；excerpt 规范（长度上限、前后省略号规则、多命中取第一段还是最佳段、无 excerpt 时 fallback 到 one_liner）；highlight 视觉（建议 `accent/blue-bg` 背景 + `text/primary`，已有 token）；Dynamic Type 下 2 行截断。
* **DoD**：组件建成并在 Search 屏替换现有裸 frame；至少陈列 5 条不同形态的结果（短 excerpt / 长截断 / 多命中 / 无 excerpt fallback / 命中在 transcript）；Light + Dark。

### 3. 设计 Search 的 8 个状态屏 + `Bar / Search Status` 组件
* **Why**：Search 正从同步子串匹配变为异步检索，状态从 3 个膨胀到 8 个。这直接决定 `SearchViewModel` 的状态机与并发模型 —— 不定死，SwiftUI 阶段必然边写边设计。同时这是 portfolio 里「AI Failure ≠ Product Failure」的唯一证据。
* **What to design**：`Bar / Search Status` 变体 `hidden | building | degraded | error`（44pt，一行文案 + 可选 CTA，复用 `Error Row` 排版）；8 屏 = default(多结果) / searching / index-building(**keyword 结果照常显示**) / semantic-degraded / error / 未输入(含 3 条自然语言示例) / 无结果(按 index 状态两版文案) / offline。
* **DoD**：每一屏的文案里**不出现** embedding / 向量 / 余弦 / RRF / chunk / Recall 等字样；building 与 degraded 两屏必须同时显示可用的 keyword 结果；Light + Dark。

### 4. 定义 Result → Note 的落点行为（Missing Interaction Definition）
* **Why**：Figma 当前只有「点结果 → 笔记页」一根连线，落点行为完全未定义。这会直接改变 `NoteView` 的架构（ScrollViewReader + block 级 `.id()` 锚点 + 与既有折叠状态的冲突处理），是**最容易在开发中期爆炸**的一项。
* **What to design**：命中在正文 block → scroll to block + 2.5s temporary highlight（`accent/blue-bg`）；命中在 audio transcript → 自动展开 `Audio / Transcript` 再定位；命中在 summary → 自动展开 `Panel / Summary` 再定位；命中在 title → 不滚动；返回搜索后是否保留高亮。用 2 张「笔记页 · 来自搜索（高亮态）」屏表达。
* **DoD**：4 种命中位置各有明确书面答案；高亮时长与消失方式写入 handoff；原型连线 Search Result → 高亮态笔记页跑通。

### 5. Retrieval Lab 与 Eval Center 的 wireframe（Track B，低保真）
* **Why**：这两张是 Developer Flow 的骨架，且有真实的**布局决策**必须先答：三路（keyword / vector / hybrid）结果如何在 393pt 窄屏上对比；两个 Config 的指标如何并排。Trace 与 Failure Inspection 是纯 key-value 列表，**建议跳过 Figma 直接 SwiftUI**。
* **What to design**：**Lab** = Query 输入 → mode Picker（三选）→ 可选参数（Embedding Backend / Chunk Strategy / Top K / Fusion）→ Run → 结果列表，每行含 Note/Block/Matched Text + `K:3 V:7 → 2` 形式的 inline rank 对照 + similarity。**Eval** = Dataset Picker × Config Picker → Run → `Row / Metric` 列表（Recall@1/3/5 · MRR · P50 · P95），**并支持选第二个 Config 并排显示 delta**。
* **DoD**：只用 List / Form / Section / Picker / Toggle 的方框表达，不上 token、不做 Dark、不做组件化、不进 calibration；一个 SwiftUI 工程师看完能直接写出来且不需要提问；明确标注 Trace 与 Failure Inspection「no Figma, SwiftUI-first」。

---

# 15. Goal 1 Figma Definition of Done

> 在进入大规模 SwiftUI 开发前，Figma 至少要到这个程度 —— **不多也不少**。

## 必须完成（Under-design 防线）

| # | 项 | 判定标准 |
|---|---|---|
| 1 | Search 状态机全集 | 8 个状态屏齐全，每屏对应一个明确的系统状态；**building / degraded 两屏必须证明 keyword 仍然工作** |
| 2 | `Row / Search Result` + excerpt 规范 | 组件化，含高亮；excerpt 的长度、截断、多命中、fallback 四条规则有书面答案 |
| 3 | Result → Note 落点行为 | 正文 / transcript / summary / title 四种命中位置各有定义；高亮时长与消失方式确定 |
| 4 | Search 异步语义 | 防抖时长、loading 呈现、旧结果保留还是清空、取消语义 —— 四问有答案 |
| 5 | Developer Mode 入口 | 在 `11 · 高级设置` 有一行可达路径，push 目标明确 |
| 6 | Lab / Eval / Gate 三张 wireframe | 三路对比布局、Config 并排布局、PASS/BLOCKED 视觉编码 —— 三个布局决策有答案 |
| 7 | 3 条原型 Flow | User Flow（含降级分支）· Developer Flow · Failure Flow 全部可点通，死链 0 |
| 8 | 5 个新组件 | `Search Field` · `Row / Search Result` · `Bar / Search Status` · `Badge / Status` · `Row / Metric` |
| 9 | 用户侧术语审查 | 8 个 Search 状态屏 + Note 页的**所有可见文案**，零 AI engineering 术语 |

## 明确不做（Over-design 防线）

| # | 不做 | 理由 |
|---|---|---|
| 1 | Developer Tool 的 Design System | SwiftUI `Form / List / Section` 原生外观就是交付标准 |
| 2 | Developer Tool 的 Dark Mode | 变量已支持，自动生效，不需要画 |
| 3 | Eval 的图表 / Trace 的瀑布图 | 数字表格 + 7 行 LabeledContent 已足够回答所有问题 |
| 4 | Trace / Failure Inspection 的 Figma 屏 | 纯 key-value 列表，SwiftUI-first |
| 5 | Developer Tool 进 calibration 流水线 | ±1pt 校准对 wireframe 无意义 |
| 6 | 用户侧 Search mode 切换器 | 违反「不暴露 AI 术语」，隐式 hybrid 即可 |
| 7 | 任何 Stage 3 页面（Ask My Notes / Chat / Citation） | 明确非目标 |
| 8 | Cost / Job / Feature Flag / Model Gateway / Vector DB Dashboard | 明确非目标 |

## Portfolio Story 判定（任务书 §27）

| 维度 | 达成条件 |
|---|---|
| **User Value** | Search 的 default 屏能让人一眼看出「命中片段解释了相关性」 |
| **System** | Lab wireframe 的一屏里同时出现 keyword rank / vector rank / final rank |
| **Evaluation** | Eval wireframe 能并排比较两个 Config 的 Recall@5 与 MRR |
| **Reliability** | Search 的 index-building / degraded 两屏证明降级不阻断；Trace 里有 contentHash 与 embeddingVersion |
| **Release** | Gate wireframe 一眼看出 **PROMOTION BLOCKED** 及具体是哪一项没过 |
| **Observability** | Failure Inspection 能从一条失败 Query 走到 Failure Type 并 Add to Regression Set |

**六条全部达成，portfolio 的故事就从「我设计了一个 AI 笔记 App」变成了「我把一个 keyword-based notes app 升级成了可评测、可发布、可追踪、可防 regression 的 AI Retrieval Quality System」。**

---

## 附：本次审计的方法与边界

- **实读**：`get_metadata(13:24939)` 返回 20 屏全量层级；`get_metadata(0:1)`；`get_variable_defs(13:24939)` 返回 live token；`get_screenshot(13:23990)` 视觉核对 Search 屏。
- **未实读**：`🧩 Components` 与 `📐 Foundations` 两页的 node 树（MCP 当前选中节点在 Screens 页，无法枚举其它页 guid）。组件清单以 `code.js:450–1200` 的 `buildComponents()` 为准，并与 `DESIGN_BASELINE.md`（37 / 26 / 116 / 35 / 450）交叉核对一致。
- **Dark 画板** `02 · 全部界面（Dark）` 未逐屏实读；依据 `code.js:1904–1906` 与 gates 套件判定为 Light 的模式镜像。
- 本报告未修改任何 Figma 内容。
