# Mosaic — Production Semantic Search · Design Contract

> 状态：**DONE / RE-FROZEN** —— 不再是 upcoming design work。
> Approved（含 10 条 PRD corrections），Figma 实施完成并经 5 轮实跑 + MCP 实读验证，7 项缺陷全部修复确认。
> 后续任何改动需重新走冻结约束流程（见 [`DESIGN_BASELINE.md`](DESIGN_BASELINE.md)）。
> 修订：2026-08-07 应用 PRD corrections #1–#10；实施第 1–7 步全部完成，经 5 轮 Figma 实跑 + MCP 实读逐项验证，7 项缺陷（F-1…F-7）已全部修复确认。
> 日期：2026-08-07
> 上游 Source of Truth：**Mosaic AI Retrieval Quality Platform — PRD v1.0**（Goal 1 / Goal 2 的唯一权威来源）
> 下游：`design/figma-plugin/code.js` → 📱 Screens · 🧩 Components
> 相关：[`FIGMA_AUDIT_GOAL1.md`](FIGMA_AUDIT_GOAL1.md) · [`DESIGN_BASELINE.md`](DESIGN_BASELINE.md) · [`UI_REDESIGN.md`](../UI_REDESIGN.md)
>
> ⚠️ `prd.md` 是 **Mosaic Notes App 旧产品 PRD**，不是本文件的上游。仅在引用既有笔记产品行为（block 类型、transcript 可见性、摘要参与搜索）时作为现状依据。
>
> ⚠️ **PRD v1.0 不在本仓库内。** 本文件基于其条目清单编写。所有依赖 PRD 具体取值的判断已全部隔离到 §9，未在正文中臆造需求。

**本文件不新增任何产品需求，不扩大 Scope。范围严格限定为 Production Semantic Search 的用户侧契约。**

---

## 已应用的 PRD Corrections（2026-08-07）

| # | Correction | 本文件的处置 |
|---|---|---|
| 1 | **Image OCR 是 Goal 1 检索源**，Golden Dataset 需覆盖 OCR case | §2.8 加入 image 命中行（`photo` 图标）；Q1 关闭。**当前代码无 OCR pipeline → 记为 Implementation Gap IG-1** |
| 2 | Document extracted text **可以**作为 Matched Excerpt 展示 | §2.8 Document 行的 ⚠️ 去除；Q2 关闭 |
| 3 | **不要 progress 百分比**，用 indeterminate 文案 | §4.4 改为 `正在准备智能搜索…`；Q6 关闭 |
| 4 | **AI Summary 不是 Goal 1 检索语料** | §2.8 删除 summary 命中行与 `sparkle` 图标；§3.2 删除 summary anchor；Q10 关闭；12 屏空态文案同步修正 |
| 5 | **不加用户侧 Semantic Toggle**（`semanticEnabled` 属内部 retrieval config） | Q5 关闭；高级设置不新增开关 |
| 6 | **Folder-scoped search 不进 Goal 1** | §6.1 的半冲突降级为 Goal 2；Q7 关闭 |
| 7 | 结果字段**固定为** Title / Matched Excerpt / Folder / Time | Q11 关闭（不加 Tag）；本已排除 badge / score / mode |
| 8 | 保留 QueryPhase × RetrievalCapability 二维模型 | §4.1 不变，确认为 SearchViewModel 推荐架构 |
| 9 | 所有时长 / 阈值 / 字符预算**不锁死为 Product Requirement** | 全文相关数值统一降级为 **Initial Tuning Value**，最终由 benchmark / UX test / SLO 决定 |
| 10 | **Local Retrieval SLO：P50 < 100ms · P95 < 250ms**（不含 UI 动画） | §1.2 §1.3 §4.3 依此重写；交互调参不得人为破坏这一优势 |

### Implementation Gap

| ID | 内容 | 影响 |
|---|---|---|
| **IG-1** | **当前代码无 Image OCR pipeline。** `Sources/MosaicKit` 中不存在 Vision / VNRecognizeTextRequest 相关实现，`prd.md` §4.3.3 走的是「图片作为视觉输入交给多模态模型」，产出 summary 而非可检索文本 | Goal 1 检索语料缺一路；Golden Dataset 的 OCR case 无法通过。**属实现缺口，不是设计缺口** —— 设计侧已按 OCR 存在来定义（§2.8 image 行） |

---

# 1. Search Product Contract

## 1.1 Search Mode — 确认成立

| 问题 | 结论 |
|---|---|
| 普通用户是否看到 Keyword / Vector / Hybrid？ | **否。三个词一个都不出现。** |
| 是否有 mode 切换器（segmented / picker / 长按菜单）？ | **否。不存在任何用户可操作的 mode 控件。** |
| Production Search 默认？ | **Hybrid Retrieval，隐式，永远开启。** |
| Semantic 不可用时？ | **自动 fallback 到 Keyword，不打断、不弹窗、不清空结果。** |

**交互模型成立。** 用户心智模型只有一句话：

> 「你随便说，我尽量帮你找到。」

用户永远只面对**一个输入框**和**一列结果**。系统内部的 keyword / vector / RRF 三层结构，对用户的唯一可见投影是 **Matched Excerpt 的质量**，不是任何控件。

### 1.1.1 用户侧禁用词表（Figma 与实现共同遵守）

以下词**不得出现在任何用户可见文案、placeholder、空态、错误提示、设置项、VoiceOver label 中**：

`embedding` · `向量` / `vector` · `余弦` / `cosine` / `similarity` · `RRF` / `fusion` / `融合` · `chunk` / `分块` · `Recall@K` / `MRR` · `index`（英文原词）· `rerank` · `top-k` · `语义检索` / `semantic`（作为技术名词时）· `config version` · `contentHash` · `stale`

**允许的用户侧说法**：「智能搜索」·「相关内容」·「正在准备」·「按关键词搜索」·「重建搜索数据」。

> `Developer Mode` 内部不受此表约束 —— 那里的用户就是 Developer / AI TPM，术语精确性优先。

### 1.1.2 是否给单条结果标注「这是语义命中」？

**否。不加 badge、不加图标、不分组。**

理由：
1. 它是 engine 内部结构的直接泄漏，违反 1.1.1。
2. Hybrid 下一条结果同时被 keyword 和 vector 命中是常态，badge 无法二值化表达。
3. **Excerpt 本身就是解释。** 用户读到「…发邮件给 advisor 申请延期一学期，需要系里签字…」时，不需要被告知这是语义匹配。

**唯一例外**（见 §2.6）：当**全部**结果都没有 exact keyword 命中时，在列表顶部显示**一行** section 级说明，而不是给每行加 chrome。

## 1.2 何时触发 Semantic

**不是每次按键都触发。** 两级触发（**结构是契约，数值是 Initial Tuning Value**）：

| 通道 | 触发条件 | 防抖（初值） | 数据源 |
|---|---|---|---|
| **Keyword（快通道）** | 每次输入变化 | 150ms | 本地，无网络 |
| **Semantic（慢通道）** | query 达到长度阈值 且 输入停顿 | 400ms | 索引 / provider |

**长度阈值（初值，低于此值不触发 semantic，只走 keyword）：** CJK ≥2 字 / 拉丁 ≥3 字符 / 混合按主语言判定。

理由（**这部分是契约**）：极短 query 的语义邻域是噪声，且会为每次按键付出 embedding 成本；低于阈值时 keyword 前缀匹配的表现明显更好。

> ⚠️ **Correction 9 + 10。** 上述数值全部是 initial tuning value，由 benchmark 与 UX test 收敛，不作为 Product Requirement。
>
> ⚠️ **PRD 已定义 Local Retrieval SLO：P50 < 100 ms · P95 < 250 ms（不含 UI 动画）。**
> 这意味着本地检索本身比人的输入停顿还快。**防抖的存在理由是省 embedding 成本与避免抖动，不是掩盖延迟** ——
> 因此调参的方向应当是**尽量小**，任何把感知延迟推到 SLO 之上的防抖值都是在人为破坏这一优势。
> 特别地：keyword 通道是纯本地的，它的防抖可以趋近 0。

## 1.3 渐进式结果呈现（Progressive Result Upgrade）

这是 Progressive Enhancement 在**正常路径**上的体现，不只是失败路径：

```
t=0        用户停止输入
t≈150ms    Keyword 结果渲染 ── 用户已经可以阅读、滚动、点击
t≈400ms    Semantic 请求发出
t≈?ms      Hybrid 结果返回 ── 列表就地升级为 RRF 融合顺序
```

> **在 SLO（P50<100ms / P95<250ms）之下，这个"升级"窗口往往短到用户察觉不到。**
> 这不削弱本节的价值：R1–R5 的意义是保证**当窗口真的可见时**（冷启动、索引重建、大库）
> 行为仍然正确且不误触。**不要因为通常很快就省掉这套规则。**

**列表重排规则（防误触，P0 级交互契约）：**

| 规则 | 内容 |
|---|---|
| R1 | 结果的身份是 `noteId`，不是 index。重排不改变任何一行的点击目标 |
| R2 | Hybrid 结果在 keyword 渲染后 **≤400ms** 内到达 → **无动画**直接替换（用户尚未开始阅读） |
| R3 | **>400ms** 到达 → 无动画替换，且**不改变 scroll offset** |
| R4 | 用户手指正在触摸列表（滚动中 / 按下中）时，**推迟替换**到触摸结束 |
| R5 | 任何情况下**不做 reorder 动画**。行的位移动画在搜索结果里只会造成误触 |

> R4 的实现细节属于 SwiftUI 层（见 §8）。若实现成本过高，降级方案：结果已渲染 >1.5s 后不再替换顺序，只补充新增行到列表末尾。

---

# 2. Search Result Specification

## 2.1 字段契约

| 槽位 | 现状 | 目标 |
|---|---|---|
| 1 | Title | Title |
| 2 | **AI `one_liner`** | **Matched Excerpt** |
| 3 | Folder · Time | Folder · Time |

**Matched Excerpt 的唯一职责：回答「为什么这条 Note 与当前 Query 有关系」。**
它**不是**笔记摘要。AI `one_liner` 从主槽位降级为 fallback 链的第 3 级（§2.7）。

## 2.2 Excerpt 最大行数

**2 行。**

| 依据 | 说明 |
|---|---|
| 版式 | `iOS/Subheadline` 15/20 × 2 行 = 40pt。**实测行高 110.5pt**（详见 §2.9） |
| 密度 | 852pt 屏、720pt Body，在 110.5pt 行高下可见约 6 条结果。3 行会降到 ~5 条，且行高逼近 130pt，列表明显笨重 |
| 信息量 | 329pt 宽 15pt PingFang SC ≈ 22 CJK 字/行 → 2 行 ≈ **44 字**，足以承载一个完整语义单元 |

> ⚠️ 本节初稿写的是「行高 90.5pt，与既有 `Row / Note` 两行态完全一致」——**那是错的**，
> `Row / Note` 没有 folder 行。实测 110.5。保留这句更正是为了记住：
> 那个「完全一致」当时看起来成立，只是因为 excerpt 根本没换行（F-1）。

**字符预算**：CJK 40–56 字 / 拉丁 80–110 字符。
**Dynamic Type**：行数上限恒为 2，字号放大时行高随之增长，**不因放大而增加行数**（否则列表节奏在无障碍档位下崩坏）。

## 2.3 前后截断（Excerpt Window）

```
[…] ←左上下文── ★命中 ──右上下文→ […]
      ≈1/3 预算           ≈2/3 预算
```

| 规则 | 内容 |
|---|---|
| W1 | 窗口以**第一个命中位置**为锚点 |
| W2 | 左侧预留 ≈1/3 预算，右侧 ≈2/3。**向后读比向前读更重要** |
| W3 | 窗口边界优先吸附到最近的句读（`。！？；\n . ! ? ;`），吸附半径 **±8 字**；超出半径则硬截 |
| W4 | **绝不在高亮词内部截断**。若边界落在高亮 range 内，向外扩展到 range 边界 |
| W5 | 窗口起点 > block 起点 → 前置 `…`；窗口终点 < block 终点 → 后置 `…`。省略号计入字符预算 |
| W6 | block 全文短于预算 → 全文显示，无省略号 |
| W7 | 折叠连续空白与换行为单个空格。**Excerpt 内不保留换行**（换行会破坏 2 行上限） |

## 2.4 Query Highlight

**修订（2026-08-07，实施中发现的硬约束）：改为对比式前景高亮，不用背景色块。**

| 属性 | 值 |
|---|---|
| 命中片段前景 | `text/primary`（**已有 token**） |
| 上下文前景 | `text/secondary`（**已有 token**） |
| 背景 | **无** |
| 字重 | **不变**（保持 Regular）。字重切换会引起字距重排与视觉抖动 |
| 渲染上限 | 单条 excerpt 内最多 6 段高亮（**tuning value**）；超出的命中不着色 |
| 未命中态 | excerpt 内无任何 query term 时，全文保持 `text/secondary`，不做任何替代标记（见 §2.6） |

**为什么从「`accent/blue-bg` 背景」改成「对比式前景」：**

| 理由 | 说明 |
|---|---|
| **Figma 无法表达分段背景** | Figma 文本节点不支持 per-range background —— 只支持 per-range fill。原方案会导致**设计稿与实现永久不一致**，而这份文件的全部价值就在于消除这种不一致 |
| **两边都原生支持前景** | Figma `setRangeFills` ↔ SwiftUI `AttributedString.foregroundColor`，一比一对上，零翻译损耗 |
| **语义更准** | 「把上下文调暗、让命中保持正常色」比「给命中刷一层蓝」更贴近 excerpt 的职责：**命中是主体，上下文才是辅助** |
| **不会误读为链接** | `accent/blue` 在整行可点的结果行里会暗示"这几个字单独可点" |
| **零布局影响** | 无内边距、无圆角、无行高变化，Dynamic Type 下不会撑行 |
| **Dark Mode 免费** | 两个 token 都已是双模式变量 |

> `accent/blue-bg` 仍然用于 §3.3 的 **block 级落地高亮** —— 那里是一个真实的矩形，Figma 完全可表达。

### 标题不做命中高亮（2026-08-07 实读后修订）

对比式高亮的代价：**它对标题无效。** 标题本身就是 `text/primary`，把命中区间也提为 `text/primary` 是零效果 —— 首次实跑的截图里，`延期毕业申请材料清单` 的高亮完全看不出来。

三个选项与取舍：

| 方案 | 判断 |
|---|---|
| 标题命中用 `accent/blue` | ❌ 在整行可点的结果行里，蓝色字会暗示"这几个字单独可点" |
| 反过来把标题的**非命中**部分调暗 | ❌ 标题被切成深浅两截，破坏标题的整体性 |
| **标题不高亮** | ✅ **采用** |

理由：标题只有一行且很短，用户刚刚输入的 query 就明晃晃地写在标题里（`延期毕业` → `延期毕业申请材料清单`），高亮不提供任何新信息。高亮的价值是**在一片文字里引导视线**，一行标题不存在这个问题。

标题命中由两件事表达：标题肉眼可见地含有 query + 导航时 **Open Note at Top**（§3.2）。

**高亮的匹配单位**：与 keyword 检索使用的分词单位一致。**highlight 必须由检索层返回的 range 驱动，不得在 UI 层重新做字符串搜索** —— 否则高亮与实际命中会不一致（这正是「解释相关性」的可信度所在）。生成器里的 `hits()` 助手**仅用于造 mock 数据**，已在 `code.js` 中就地注明。

**高亮的匹配单位**：与 keyword 检索使用的分词单位一致。**highlight 必须由检索层返回的 range 驱动，不得在 UI 层重新做字符串搜索** —— 否则高亮与实际命中会不一致（这正是「解释相关性」的可信度所在）。

## 2.5 多 chunk 命中时选哪一个

**每行只显示 1 段 excerpt。** 选择顺序：

| 优先级 | 判据 |
|---|---|
| 1 | 融合后得分最高的 chunk |
| 2 | 得分相同 → 覆盖**不同 query term 数量**最多的 chunk |
| 3 | 仍相同 → block order 最靠前的 chunk |
| 4 | 仍相同 → chunk 在 block 内 offset 最小者 |

**v1 不显示「另有 2 处匹配」。** 理由：增加 chrome，且 Goal 1 阶段无证据表明用户需要它。
**但导航必须携带被选中的 chunk 的 blockId + range**（见 §3）。

## 2.6 Semantic 命中但无 exact keyword 时如何表达

**单条结果：什么都不加。** 显示未高亮的 excerpt，无 badge、无图标、无标签。

**列表级例外（唯一）**：当**本次结果中零条含 exact keyword 命中**时（典型场景：纯自然语言 query），在结果列表**顶部**显示一行说明：

```
没有完全匹配的关键词，以下是相关内容
```

- 样式：`iOS/Footnote` · `text/tertiary` · 左内边距 20 · 上下内边距 8
- **不是** Status Bar，不带图标，不带 CTA，不可点击
- 部分结果有高亮、部分没有时 **不显示**此行（混合是正常状态，无需解释）

理由：这条文案只在会让用户困惑的场景出现（整页无高亮），用一行解决，而不是给每一行加 chrome。

## 2.7 Excerpt Unavailable 的 Fallback 链

| 级 | 来源 | 高亮 |
|---|---|---|
| 1 | 命中 chunk 的窗口文本 | 有 |
| 2 | 笔记第一个文字 block 的前 2 行 | 无 |
| 3 | AI `one_liner` | 无 |
| 4 | `无预览内容`（`text/tertiary`） | 无 |

**逐级降级，不跳级。** 第 4 级仍保留完整行高（不塌缩），保持列表节奏。

## 2.8 各命中类型的展示规则

**通用机制：excerpt 行首可选一个 16pt 来源图标（`text/tertiary`），用于标示「这段文字来自哪里」。**

这不是 AI 术语暴露 —— 它是**内容出处**。用户知道自己录过音、导过 PDF；这个图标告诉他们进入笔记后该往哪看。

| 命中类型 | 来源图标 | Excerpt 内容 | 高亮 | 备注 |
|---|---|---|---|---|
| **Text Block** | 无 | 命中 chunk 窗口 | 有 | 默认形态 |
| **Title** | 无 | excerpt 槽位显示笔记开头内容作为上下文 | **均无** | 见下方「标题不高亮」 |
| **Audio Transcript** | `wave`（16pt） | 转写稿命中窗口 | 有 | 口语化文本，`…` 出现频率更高属正常 |
| **Image OCR** | `photo`（16pt） | OCR 文本命中窗口 | 有 | Correction 1 确认为 Goal 1 检索源 |
| **Document** | `doc`（16pt） | **提取正文**命中窗口 | 有 | Correction 2 确认可展示 |
| **Link** | `link`（16pt） | 命中在 title/description → 显示该段；命中在 URL → 显示 URL | 有 | URL 不做句读吸附（W3 跳过） |
| ~~AI Summary~~ | — | — | — | **Correction 4：不在 Goal 1 语料内，已删除** |

**Goal 1 检索语料（Correction 4 锁定）**：Text · Audio Transcript · Image OCR Text · Document extracted text · Link title/description/extracted text；Title 与 Tag 作为 lexical signals。**AI Summary 不参与。**

> **Document（Q2 已关闭）**：「Note Editor 不直接展示 extracted text」与「Search Result 为解释命中展示局部 excerpt」不冲突 —— 前者是**浏览语境**，后者是**解释语境**。无需降级方案。
>
> **Image OCR（Q1 已关闭）**：设计侧按 OCR 存在定义。⚠️ 当前代码无 OCR pipeline → **Implementation Gap IG-1**（见文首）。设计不因实现缺口而回退。

## 2.9 `Row / Search Result` Component Specification

**实测几何（2026-08-07 MCP 实读后修订）：`393 × 110.5`。**

> ⚠️ 先前本节写的 `90.5`（"与 `Row / Note` 两行态一致"）是错的。`Row / Note` 没有 folder 行；
> Search Result 有 title + 两行 excerpt + meta 行，实测 110.5。5 条结果 552.5pt，
> 在 720pt 的 Body 里可见约 6 条 —— 密度仍然合理。

```
Row / Search Result                                   393 × 110.5
├─ padding: leading 20 · trailing 20 · top 12 · bottom 12
├─ Row (vertical, gap 4)
│  ├─ Title        iOS/Headline      text/primary    353 wide · 1 line · truncate tail
│  ├─ Excerpt (horizontal, gap 4, align top)          353 wide
│  │  ├─ Source (20×20 常驻槽位)
│  │  │  └─ Source Icon  16pt  text/tertiary          ← 只有图标随 BOOLEAN 显隐
│  │  └─ Excerpt Text  iOS/Subheadline text/secondary 329 wide · max 2 lines
│  │        highlight: 命中区间提为 text/primary（前景对比，无背景）
│  └─ Meta (horizontal, SPACE_BETWEEN)                353 wide
│     ├─ Folder (horizontal, gap 4)
│     │  ├─ Icon   16pt               text/tertiary
│     │  └─ Folder Name  iOS/Caption1 text/tertiary
│     └─ Time      iOS/Caption1       text/tertiary
└─ Separator       leading inset 20 · 0.5pt · separator
```

**两条实施中被实读推翻的做法，已成硬规则：**

| # | 规则 | 事故 |
|---|---|---|
| **G1** | **`maxLines >= 2` 的文本必须显式定宽，不能靠 `grow` / `stretch`** | 首次实跑时 excerpt 写成 `lines: 2 + grow: 1`，Figma **不换行**，文本拉成一条长行被屏幕裁掉，用户看到半句话。桩当时也估成一行，两边"一致地错"，calibration 全绿。现已加 `checks.multiline-width` + 对应变异用例守住 |
| **G2** | **出处图标放常驻 20pt 槽位，只有图标本身显隐** | 图标直接参与 auto-layout 时，隐藏会退出布局流，导致有无出处的行之间 excerpt 左边缘来回跳。槽位常驻换来所有 excerpt 严格左对齐 |

**Time 从右上角移到 meta 行**：title 与 excerpt 因此各多出 66pt 行宽（约 4 个中文字/行），对以 excerpt 为主角的搜索结果是直接收益。

**变体轴（遵守文件既有「嵌套架构避免笛卡尔积」规则）：**

| 轴 | 值 | 数量 |
|---|---|---|
| `state` | `default` · `pressed` | **2** |

**组件属性（7）：**

| 属性 | 类型 | 默认 |
|---|---|---|
| `Title` | TEXT | `Q3 产品评审会` |
| `Excerpt` | TEXT | — |
| `Folder` | TEXT | `工作` |
| `Time` | TEXT | `3小时前` |
| `Show Source Icon` | BOOLEAN | `false` |
| `Source Icon` | INSTANCE_SWAP → `Icon` | `wave` |

> **实施修订**：原列的 `Show Excerpt` 已删除 —— §2.7 的四级 fallback 链保证 excerpt 槽位**永远**有内容（最差是 `无预览内容`），因此这个开关没有对应的产品状态。属性数 7 → **6**。
>
> 2 变体 × 6 属性，理论组合 ~32，实际维护 **2**。与 `Row / Note`（60→9）同一策略。

**节点命名（实施后，供 handoff 对照）**：`Title` · `Excerpt`(frame) · `Source Icon` · `Excerpt Text` · `Folder`(frame) · `Folder Name` · `Time` · `Row` · `Content`。
`Folder` 与 `Folder Name` 必须分开 —— 否则 `findOne(name==='Folder')` 会命中 frame 而不是文本节点，属性绑定会静默接到错误节点上。

**`pressed` 态**：背景 `bg/fill`，无位移、无缩放。与 `Row / Note` 一致。

**高亮在 Figma 中的表达**：Figma 无法做动态 range。在屏幕实例中对 excerpt 文本节点**手动施加分段 fill**（Figma 原生支持 per-range fill）。
→ **高亮是规范，不是组件属性。** 组件本身不含高亮结构，实现侧由 `AttributedString` 驱动。

---

# 3. Result → Note Interaction Specification（P0）

## 3.1 导航载荷

```
SearchDestination
  noteId:  UUID
  anchor:  .top
         | .block(blockId)                 // text / document / link / image
         | .transcript(blockId)            // audio，需先展开
```

> Correction 4：`.summary` anchor 已删除。`.block` 覆盖 text / image(OCR) / document / link 四类。

**anchor 由检索层给出，不由 UI 猜测。** 若 anchor 无法确定 → 退化为 `.top`。

## 3.2 五类命中的落点行为

| 命中类型 | 行为链 |
|---|---|
| **Text Block** | Open Note → Scroll to Block → Temporary Highlight |
| **Audio Transcript** | Open Note → **Expand Transcript** → 等一次 layout → Scroll to Block → Temporary Highlight |
| **Document** | Open Note → Scroll to Document Block → Temporary Highlight（**不自动打开 QuickLook**） |
| **Link** | Open Note → Scroll to Link Block → Temporary Highlight（**不自动打开浏览器**） |
| **Image OCR** | Open Note → Scroll to Image Block → Temporary Highlight（**不自动全屏打开图片**） |
| **Title** | Open Note at Top → **无 scroll、无 highlight** |
| ~~AI Summary~~ | **Correction 4：已删除 summary anchor** |

> Document / Link **不自动打开外部内容**：用户的意图是「找到这条笔记」，不是「立刻打开这个 PDF」。自动打开会劫持导航栈。

## 3.3 Highlight 契约

| 项 | 值 |
|---|---|
| **视觉** | block 外接矩形 + 8pt 外扩，填充 `accent/blue-bg`，圆角 `radius/md`(12)。**无描边、无阴影、无缩放** |
| **Duration** | 出现即全不透明 → 保持 **2.0s** → **0.4s** ease-out 淡出。总计 **2.4s** |
| **时序** | push 转场**完成后 +0.15s** 才开始。转场中闪高亮会被动画吃掉 |
| **可中断** | 用户滚动 / 点击 / 开始编辑 → **立即取消**（0.2s 淡出）。高亮是提示，不是障碍 |
| **Dark Mode** | `accent/blue-bg` 已是双模式变量，自动生效 |

### 3.3.1 是否在笔记正文内保留 term 级高亮？

**否。只做 block 级临时高亮，正文内不注入 term 高亮。**

理由：笔记正文是**可编辑**表面。向可编辑文本注入高亮 range 会与编辑器的 attributed text 状态、光标、撤销栈冲突，实现成本远高于收益。

> 取舍已知：用户在长 block 内仍需自己找那一句。Block 级高亮 + excerpt 已提供足够定位信息。若后续证明不足，再作为 P2 增强。

## 3.4 Scroll 契约

| 项 | 值 |
|---|---|
| **锚点** | 目标 block 高度 ≤ 50% 可视区 → `.center`；> 50% → `.top`，顶部留 88pt 内边距 |
| **动画** | **无。** 在 push 转场**之前 / 之中**完成定位，笔记页出现时**已经**停在目标位置 |
| **为什么不动画** | push 转场 + scroll 动画叠加会产生明显 jank，且用户会看到内容"飞过"，反而丢失定位感 |
| **transcript 展开** | 展开改变布局高度 → 必须 `expand → 等一次 layout pass → scroll`，不可同帧执行 |
| **anchor 不存在** | blockId 已被删除 / 索引 stale → 退化为 `.top`，**不报错、不提示** |

## 3.5 返回 Search 后的状态恢复

| 项 | 契约 |
|---|---|
| Query 文本 | **完整保留** |
| 结果列表 | **完整保留，不重新检索** |
| 列表 scroll position | **精确恢复** |
| Retrieval capability | 返回时**重新读取**（离开期间索引可能已就绪 → Status Bar 相应更新） |
| 键盘 | **不自动弹出** |

Search 是 push 出去的独立屏，其 ViewModel 由该屏持有 → 上述恢复是 NavigationStack 的自然行为，**不需要额外的状态保存机制**。

## 3.6 再次进入同一条结果

**重复 highlight，行为完全一致。**

理由：用户再次点击就是期望同样的定位反馈。抑制第二次会让人以为点击失效。
**不做 "已读" 标记，不做首次限定。**

---

# 4. Search State Machine

## 4.1 核心建模决定：**两个正交维度，不是 8 个扁平状态**

把 8 个状态铺平会立刻产生无法回答的组合（"index building 时又正在 searching" 是哪个状态？）。正确模型：

```
SearchScreenState = (QueryPhase) × (RetrievalCapability)

QueryPhase              ── 驱动【结果区】
  .idle                    query 为空
  .searching               query 非空，快通道尚未返回
  .ready(results)          有结果
  .noResults               有 query，零结果

RetrievalCapability     ── 驱动【Status Bar】
  .full                    hybrid 可用
  .indexBuilding(progress) 首次建立
  .indexRebuilding         重建中
  .semanticUnavailable     embedding/provider 失败
  .offline                 网络不可达且 provider 依赖云端
```

**两者相互独立演进。** 结果区不关心 capability，Status Bar 不关心 query phase。

这直接映射到 SwiftUI：两个独立的 `@Published`，两个独立的视图分支，**不是 8 个 if-else**。

## 4.2 五条不可违反的不变量

| # | 不变量 |
|---|---|
| **I1** | **输入永远可用。** 没有任何状态会禁用 Search Field |
| **I2** | **已有结果永远可点。** 包括 error / offline 状态下 |
| **I3** | **Keyword 结果与 capability 无关。** 只要 query 非空且本地库可读，keyword 结果就照常显示 |
| **I4** | **Status Bar 永不阻塞。** 最高 44pt，非模态，绝不占满屏，绝不覆盖结果 |
| **I5** | **不使用覆盖结果的 spinner。** loading 只出现在 Search Field 尾部（≤20pt） |

> I1–I5 就是 "Semantic failure ≠ Search failure" 的可执行形式。

## 4.3 QueryPhase × 结果区

| QueryPhase | Search Field | 结果区 | 可继续输入 | 可打开结果 |
|---|---|---|---|---|
| `.idle` | 有光标，placeholder | Tag chips + **自然语言示例区** | ✅ | — |
| `.searching` | 有文本 + **尾部 ProgressView 20pt** | **保留上一次结果**（若有），否则空白 | ✅ | ✅ |
| `.ready` | 有文本 + 清除按钮 | 结果列表（+ §2.6 可选说明行） | ✅ | ✅ |
| `.noResults` | 有文本 + 清除按钮 | `Empty State`，文案按 capability 分叉 | ✅ | — |

**`.searching` 保留上一次结果而非清空** —— 清空会造成每次按键的白屏闪烁。

## 4.4 RetrievalCapability × Status Bar

| Capability | Status Bar | 文案 | CTA | Keyword 结果 |
|---|---|---|---|---|
| `.full` | **不出现** | — | — | ✅（且已被 hybrid 融合） |
| `.indexBuilding` | 出现 | `正在准备智能搜索…`（**indeterminate，不显示百分比**） | 无 | ✅ **照常** |
| `.indexRebuilding` | 出现 | `正在更新搜索数据…` | 无 | ✅ **照常** |
| `.semanticUnavailable` | 出现 | `智能搜索暂不可用，已按关键词搜索` | `重试` | ✅ **照常** |
| `.offline` | 出现 | `离线中，已按关键词搜索` | 无 | ✅ **照常** |

**四种非 full 状态的共同结构：一行说明 + 可选 CTA，结果照常。这就是 Progressive Enhancement 的全部。**

## 4.5 `.noResults` 的文案分叉

| Capability | 标题 | 说明 |
|---|---|---|
| `.full` | `没有找到匹配的笔记` | `换个说法试试` |
| `.indexBuilding` / `.indexRebuilding` | `暂时没有找到` | `智能搜索还在准备中，稍后可能会有更多结果` |
| `.semanticUnavailable` / `.offline` | `没有找到匹配的笔记` | `当前只能按关键词搜索，换个关键词试试` |

**必须分叉** —— 否则用户无法区分「真的没有」和「系统还没准备好」。这是搜索类产品最常见的信任流失点。

## 4.6 状态迁移

```
QueryPhase:
  idle ──输入──▶ searching ──有结果──▶ ready
                     │                    │
                     └──零结果──▶ noResults│
                                      │    │
  idle ◀────────清空 query────────────┴────┘
  ready ──继续输入──▶ searching（保留旧结果）

RetrievalCapability:  由索引服务单向推送，与用户输入完全无关
  indexBuilding ──完成──▶ full
  full ──内容大量变更──▶ indexRebuilding ──完成──▶ full
  full ──provider 失败──▶ semanticUnavailable ──重试成功──▶ full
  任意 ──断网──▶ offline ──恢复──▶ 之前的状态
```

---

# 5. Current Figma → Target Figma Gap

## 5.1 现有三屏的处置

| 屏 | Node (Light) | 处置 | 说明 |
|---|---|---|---|
| `06 · 搜索` | `13:23990` | **修改** | → `ready · full`。结果行换成 `Row / Search Result` 组件；**从 1 条扩到 5 条**（覆盖 text / transcript / document / link / title 五种命中）；excerpt 替换 one_liner；加高亮 |
| `12 · 搜索 · 未输入` | `13:24376` | **修改** | → `idle`。Search Field 换组件；保留 Tag chips；**新增自然语言示例区** |
| `13 · 搜索 · 无结果` | `13:24409` | **修改** | → `noResults · full`。Search Field 换组件；文案按 §4.5 更新 |

### Tag Filter 行的归属规则（实施中定案，解决 Audit 的 S-12）

**Tag chip 行只属于 `.idle` 态。一旦 query 非空，它让位给结果。**

理由：tag chip 是**无 query 时的建议入口**，不是持久筛选器（点击行为是"把 `#标签` 填进搜索框"，本身就是在制造 query）。有 query 后继续占 44pt 只是噪声。

这条规则同时说明：`13 · 无结果` 现状**没有** Tag 行是对的（它有 query），反而是 `06` 之前带着 Tag 行属于不一致 —— 已在实施中移除。

**三屏全部保留，无一删除。** 现有版式与 token 绑定正确，只换组件与内容。

## 5.2 需要新增的屏（6 屏 × Light/Dark）

| 新屏 | 状态 | 演示重点 |
|---|---|---|
| `21 · 搜索 · 检索中` | `searching · full` | Field 尾部 ProgressView；**上一次结果仍在显示**（I5 的证明） |
| `22 · 搜索 · 索引建立中` | `ready · indexBuilding` | Status Bar + 进度；**keyword 结果照常** —— Progressive Enhancement 的核心证据屏 |
| `23 · 搜索 · 智能搜索不可用` | `ready · semanticUnavailable` | Status Bar + `重试` CTA；**结果照常** |
| `24 · 搜索 · 全部为相关结果` | `ready · full` | §2.6 的顶部说明行；**全部 excerpt 无高亮** —— 自然语言 query 的招牌屏 |
| `25 · 笔记页 · 来自搜索（正文命中）` | — | Block 级临时高亮，已滚动到位 |
| `26 · 笔记页 · 来自搜索（转写命中）` | — | Transcript 已展开 + 高亮 |

> `offline` 与 `indexRebuilding` **不单独出屏** —— 它们与 `22`/`23` 的结构完全相同，仅文案不同，由 `Bar / Search Status` 的变体覆盖。**避免为文案差异画屏。**

**Screens 总数：20 → 26（× Light/Dark = 52）。**

---

# 6. Required Components

**新增 3 个，全部落在你指定的优先级内。不新增任何无关 Design System。**

## 6.1 `Search Field`（新）

| 项 | 内容 |
|---|---|
| 尺寸 | 361 × 36，`radius/sm`(8)，`bg/fill` |
| 变体轴 | `state = idle \| typing \| searching`（**3**） |
| 属性 | `Placeholder`(TEXT) · `Value`(TEXT) |
| 结构 | `Icon/search` 20pt + 文本 + 尾部槽（`typing`→清除按钮 / `searching`→ProgressView 20pt） |
| 解决 | 消除 `13:23967` / `13:24357` / `13:24397` 三份裸 frame 复制 |

## 6.2 `Row / Search Result`（新）

见 §2.9。**2 变体 + 7 属性。**

## 6.3 `Bar / Search Status`（新）

| 项 | 内容 |
|---|---|
| 尺寸 | 393 × 36，紧贴 Search Field 下方 |
| 变体轴 | `state = building \| rebuilding \| degraded \| offline`（**4**） |
| 属性 | `Message`(TEXT) · `Show CTA`(BOOLEAN) · `CTA Label`(TEXT) |
| 结构 | 16pt 图标（`text/tertiary`）+ `iOS/Footnote` 文本 + 可选尾部 CTA（`accent/blue`） |
| 复用 | 排版直接沿用现有 `Error Row` |
| 注意 | **无 `full` 变体** —— `full` 时组件不存在于层级中，不是"隐藏变体"。避免 SwiftUI 侧出现零高度幽灵视图 |

## 6.4 直接复用（零新增）

`Icon`(wave/photo/doc/link/search/xmark/refresh/warning/briefcase) · `Chip / Tag` · `Empty State` · `Bar / Nav` · `Bar / Status` · `Bar / Home Indicator` · `Audio / Transcript` · 全部 block 组件

## 6.5 Token 增量

**0。** 所有需要的 token 已存在：
`accent/blue-bg` (高亮) · `radius/xs` (高亮圆角) · `radius/md` (block 高亮圆角) · `text/tertiary` (来源图标) · `bg/fill` (pressed / field) · `iOS/Subheadline` · `iOS/Footnote` · `iOS/Caption1` · `iOS/Headline`

> Eval / Trace 页可能需要的等宽数字 → 与本任务无关，且属 Implementation-level（`.monospacedDigit()`）。

**组件总数：37 → 40。**

---

# 7. Exact Screens to Add / Modify

| # | 动作 | 屏 | 目标状态 | 依赖组件 |
|---|---|---|---|---|
| 1 | 改 | `06 · 搜索` | `ready · full` | Search Field · Row/Search Result ×5 |
| 2 | 改 | `12 · 搜索 · 未输入` | `idle` | Search Field · Chip/Tag · 示例区 |
| 3 | 改 | `13 · 搜索 · 无结果` | `noResults · full` | Search Field · Empty State · Chip/Tag |
| 4 | 增 | `21 · 搜索 · 检索中` | `searching · full` | Search Field(searching) · Row/Search Result |
| 5 | 增 | `22 · 搜索 · 索引建立中` | `ready · indexBuilding` | + Bar/Search Status(building) |
| 6 | 增 | `23 · 搜索 · 智能搜索不可用` | `ready · semanticUnavailable` | + Bar/Search Status(degraded) |
| 7 | 增 | `24 · 搜索 · 全部为相关结果` | `ready · full` | Row/Search Result（无高亮）+ 说明行 |
| 8 | 增 | `25 · 笔记页 · 来自搜索（正文命中）` | — | 既有 block 组件 + 高亮矩形 |
| 9 | 增 | `26 · 笔记页 · 来自搜索（转写命中）` | — | `Audio / Transcript`(expanded) + 高亮矩形 |

**全部 × Light / Dark。原型连线在本阶段不做**（等 Search 屏定稿后统一连）。

---

# 8. SwiftUI Implementation Implications

## 8.1 检索层必须先改（**设计无法绕过的前置条件**）

```swift
// 现状 —— Sources/MosaicKit/Search/SearchMatcher.swift
static func matches(query: String, haystack: String, tags: [String]) -> Bool

// 本契约要求
struct SearchHit {
    let noteId: UUID
    let anchor: SearchAnchor          // .top / .block / .transcript / .summary
    let excerpt: String               // 已开窗、已截断
    let highlights: [Range<String.Index>]   // 相对 excerpt
    let source: HitSource             // text / title / transcript / document / link / summary
    let score: Double
}
```

**返回 `Bool` 的接口无法支撑 Matched Excerpt、无法支撑高亮、无法支撑导航 anchor。** 这是 §2 / §3 全部内容的硬前置。

## 8.2 Excerpt 构造应是纯函数

```swift
func buildExcerpt(chunk: String, matches: [Range<String.Index>], budget: Int) -> (String, [Range<String.Index>])
```

纯函数 → **可单元测试**（W1–W7 每条对应一个用例）→ 且与 Golden Dataset 的评测逻辑天然对齐。建议放在 `MosaicKit/Search/ExcerptBuilder.swift`，配套 `MosaicKitChecks/ExcerptChecks.swift`。

## 8.3 两条独立的状态流

```swift
@Published var queryPhase: QueryPhase           // 由用户输入驱动
@Published var capability: RetrievalCapability  // 由索引服务推送，与输入无关
```

**绝不合并成一个 8 值枚举**（§4.1）。

## 8.4 并发与取消

- 快通道：`.task(id: query)` + 150ms debounce，本地同步执行
- 慢通道：400ms debounce + 长度阈值门控，`Task` 可取消
- **每次 query 变化必须取消上一个 semantic Task** —— 否则旧结果会覆盖新结果
- R4（触摸中推迟重排）：可用 `ScrollView` 的 `.simultaneousGesture` 或 `scrollPhase` 感知；**若成本过高，走 §1.3 的降级方案**

## 8.5 Block `.id()` 稳定性（**需先核实**）

`ScrollViewReader.scrollTo(blockId)` 要求每个 block 在 `NoteView` 中有稳定且唯一的 `.id()`。**当前 `Blocks` 容器是否已满足，需要在动 Figma 之前核实一次** —— 若不满足，§3 的全部导航契约都无法落地。

## 8.6 Transcript / Summary 展开的时序

```
setExpanded(true) → 等一次 layout pass → scrollTo(anchor) → +0.15s → highlight
```
同帧执行 scroll 会滚到展开前的旧坐标。

## 8.7 Highlight 的实现形态

block 级高亮是**覆盖在 block 背后的一个矩形**，不是文本属性。`.background(highlightColor.opacity(isHighlighted ? 1 : 0))` + `.animation`。与编辑器状态完全解耦。

## 8.8 Implementation-level（**无需 Figma 设计**）

- Excerpt 开窗算法（W1–W7）
- 高亮 range 的计算与合并
- 防抖时长与取消语义
- `.monospacedDigit()`
- VoiceOver：结果行应朗读「标题，来自录音，命中片段，文件夹，时间」

---

# 9. Remaining Open Questions

## 9.1 已由 Corrections 关闭（7 项）

| # | 问题 | 结论 |
|---|---|---|
| ~~Q1~~ | 图片 OCR 是否参与检索 | **是**，Goal 1 检索源（Correction 1）。代码侧缺口记为 **IG-1** |
| ~~Q2~~ | 结果中可否展示 Document 提取正文 | **可以**（Correction 2） |
| ~~Q5~~ | 是否有用户侧语义搜索开关 | **否**，`semanticEnabled` 属内部 retrieval config（Correction 5） |
| ~~Q6~~ | 索引进度百分比 | **不做**，用 indeterminate 文案（Correction 3） |
| ~~Q7~~ | Folder-scoped search | **不进 Goal 1**（Correction 6） |
| ~~Q10~~ | AI 摘要是否参与检索 | **否**（Correction 4） |
| ~~Q11~~ | 结果行是否显示 Tag | **否**，字段固定 4 项（Correction 7） |

## 9.2 仍然开放（5 项）

> Q8 / Q9 已按 Correction 9 + 10 重新表述：**不再问"PRD 定义了什么数值"，而是问"由什么机制收敛"。**

| # | 问题 | 影响 | 当前处置 |
|---|---|---|---|
| **Q3** | Chunk 粒度是 block 级还是 sub-block 级？ | §2.3 开窗预算、§3.1 anchor 精度 | 暂定 **sub-block**，anchor 落到 blockId。**设计不受影响**（两种粒度下 UI 相同），仅影响 excerpt 质量 |
| **Q4** | chunk id 重新索引后是否稳定？ | 能否把 chunkId 放进导航载荷 | 暂定**不稳定**，故 anchor 只携带 blockId。若稳定则可精确到 chunk，是纯增益 |
| **Q8** | 防抖与最小 query 长度的收敛机制？ | §1.2 | **Initial tuning value**（Correction 9）。需要一个 benchmark 口径：在什么数据集上、以什么指标判定"更好" |
| **Q9** | `searching` 态在 SLO 下的实际可见率？ | 决定该屏是否值得做完整视觉 | SLO 是 P95<250ms → 该态多数时候不可见。**仍要设计**（冷启动 / 重建 / 大库时可见），但**不投入 polish** |
| **Q12** | 结果数量上限 / 分页？ | 列表是否需要「加载更多」 | 暂定 **Top 50，无分页**。Goal 1 不做分页 |

**这 5 项都不阻塞当前 Figma 实施** —— 它们影响的是检索质量与调参，不影响已定稿的 UI 契约。

---

# 10. Recommended Figma Implementation Order

> 严格按依赖顺序。每一步产出可独立 review，不必等全部完成。

| 步 | 内容 | 状态 |
|---|---|---|
| **0** | 确认本契约 + 应用 corrections | ✅ 完成 |
| **1** | 建 `Search Field`（3 变体 + 1 属性） | ✅ 完成 |
| **2** | 建 `Row / Search Result`（2 变体 + 6 属性） | ✅ 完成 |
| **3** | 建 `Bar / Search Status`（4 变体 + 2 属性） | ✅ 完成 |
| **4** | 改 `06` → `ready · full`（5 条结果，覆盖 5 种命中出处） | ✅ 完成 |
| **4.5** | 顺带：`12` `13` 换用 Search Field 组件（消除三份裸 frame 复制）+ Correction 4 的文案修正 | ✅ 完成 |
| — | 第 1 轮 Figma 实跑 + MCP 实读 | ✅ 完成，**抓到 F-1 / F-2 两个缺陷** |
| **5** | Review + 修复 F-1（excerpt 不换行）/ F-2（标题高亮无效） | ✅ 完成 |
| — | 第 2 轮 Figma 实跑 + MCP 实读 | ✅ 完成，两个缺陷确认修复 |
| **6** | 增 `21 searching` `22 indexBuilding` `23 degraded` `24 全部为相关结果`；`12` 补到目标形态 | ✅ 完成 |
| **7** | 增 `25` `26`（Result → Note landing） | ✅ 完成 |
| — | Flow 7 原型补线（22 → **25** 条） | ✅ 完成 |
| — | 第 3 轮实读 | ✅ 抓到 F-3（状态条文案串了）/ F-4（落点笔记不对）/ F-5（既有：19 屏九态同一句话） |
| — | 第 4 轮实读 | ✅ F-3/F-4/F-5 确认；Components 页首次直读；抓到 F-6（既有：首页预览文案）/ F-7（转写没换） |
| — | 第 5 轮实读 | ✅ **F-6 / F-7 确认。七项缺陷全部实读验证通过。** |
| **8** | 更新 `DESIGN_BASELINE.md`（SHA / 日期 / 指标） | ✅ 完成 |

**Production Semantic Search 交付完成。**

### 步骤 6 / 7 的三个设计决定

| # | 决定 | 理由 |
|---|---|---|
| **D-S1** | **22 / 23 屏刻意少一条结果** —— 纯语义命中的 `NEU Extended Study Option` 在降级时消失，四条 keyword 命中照常 | 这是 Progressive Enhancement 唯一能被"看见"的地方。降级不是「搜索坏了」，是「结果少了几条、不那么聪明了」。如果降级屏和正常屏结果完全一样，这一屏就什么也没证明 |
| **D-S2** | **21 屏的 query 比 06 长两个字**（`延期毕业` → `延期毕业申请`），结果仍是旧的 | 若 query 与 06 相同，「为什么它还在转」无法解释。改长后这一屏自洽：用户又敲了两个字，新结果没回来，旧结果照常可读可点 |
| **D-S3** | **25 / 26 屏把每个 block 都套进 8pt 槽位**，只有命中的槽位有底色 | auto-layout 没有负外边距，高亮要比 block 外扩 8pt 就只能靠统一套壳。这样所有 block 左边缘仍落在 x=20（与 02 屏一致），高亮才是「外扩」而不是把命中块「缩进」 |

### 12 屏的最终形态

放弃了通用空状态插画，改为：`Search Field(idle)` → `Tag Filter` → **`试试这样搜` + 3 条可点的自然语言示例** → 语料说明 footer。

空 query 是教会用户「这个框不止能搜关键词」的**唯一时机**；一张插画在这里的信息量不如三句能直接点的例子。三条示例取自任务书 §9.2 的原句。

**第 4 步是分水岭**：它一旦成立，「Matched Excerpt 解释相关性」这件事就从文档变成了可以给人看的东西。

> Developer Mode / Retrieval Lab / Eval Center / Release Gate **本阶段不开始**。
