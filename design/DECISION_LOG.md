# Mosaic — Design Decision Log（Goal 1）

> 只记录**真正影响实现**的决定。不记录像素级取舍。
> 每条格式：决定 · 理由 · 影响面 · 状态。

---

## D-UI-DEV-001 · Developer Tools 用 SwiftUI-native low-fi，不做 production dashboard

**决定** Developer Tools 全部走 Track B：灰度线框 + 原生控件近似，独立插件，
不进 Production 的 generation / calibration pipeline。

**理由** 这类页面的读者是 Developer / AI TPM，判断标准是「信息结构对不对」，不是「好不好看」。
把它们塞进 Production 流水线（五套件 + 86 点 ±1pt 校准）成本远超收益 ——
一个 Retrieval Lab 的 `Form` 用不着像素校准。

**影响面** 新建 `design/figma-plugin-devtools/`（独立 manifest + code.js + 冒烟测试）。
Production 的 `design/figma-plugin/` 一行未动。

**状态** 已落地。冒烟测试 6/6，含两条边界断言：未创建任何 Variable/Style、Production 三页未被触碰。

---

## D-UI-DEV-002 · Retrieval Lab 用竖排 mobile inspector，不用横向表格

**决定** 每条结果一张竖排卡片，排名证据压成一行 `K #3 · V #7 → #2`，附 `similarity 0.842`。

**理由** Final Rank / Title / Source / Matched Text / Keyword Rank / Vector Rank / Similarity
共 7–8 个字段。393pt 横排每列只剩 ~48pt，标题必然截断，数字必然换行 —— 表格在这个宽度下
不是「密集」，是「不可读」。竖排卡片牺牲密度换取**5 秒内可解释**。

`K —` 记号是关键：它标出「这一路没命中」，直接回答「为什么这条会出现在结果里」。

**影响面** D2 / D3 的行渲染是自定义 `VStack`，但内部只有文本，无自定义绘制。

**状态** 已落地。

---

## D-UI-DEV-003 · Eval 用数字对比，不用图表

**决定** Eval Center 与 Compare 全部用数字表格；Delta 列用颜色区分方向，不画任何图。

**理由** 40 个 case 的评测结果画折线没有信息量。真正要回答的问题是
「新 Config 比 baseline 好还是差、代价是什么」，那是一个四列表格的问题。
图表在这里是 dashboard theater。

**影响面** D5 / D6。`.monospacedDigit()` 处理数字对齐，不新增字体样式。

**状态** 已落地。

---

## D-UI-DEV-004 · Trace 走 SwiftUI-first，不做 Figma 生产屏

**决定** Trace 的交付物是字段规格 + 信息层级，线框只是极低保真的 `List` 结构，
存在的唯一理由是把 Flow A 在原型里走通。**禁止 waterfall chart。**

**理由** 它本质是三段 key-value。`List + Section + LabeledContent` 已经能回答全部问题。

**影响面** `DEVTOOLS.md` §4.4 / §7。

**状态** 已落地。

---

## D-UI-DEV-005 · Failure Inspection 走 SwiftUI-first

**决定** 同上。Failure Type 固定 7 类（chunking / embedding / keyword / fusion /
missingData / staleIndex / other），不可自由输入。

**理由** Failure Type 要拿来统计（「这一轮 60% 的失败是 chunking」）。
自由文本没有统计价值。7 类覆盖了 PRD 列出的全部失败模式，`other` 兜底且强制填写说明。

**影响面** `DEVTOOLS.md` §5。数据模型需要一个 `FailureType` 枚举。

**状态** 已落地。

---

## D-UI-DEV-006 · Developer Mode 入口只写规格与 Track B 线框，**不画进生产屏**

**决定** 入口（设置 › 高级 › 开发者：`开发者模式` Toggle + `开发者工具 ›`）的规格写在
`DEVTOOLS.md` §1，并画成 Track B 的 **D0** 线框。**生产屏 `11 · 高级设置` 一行未改。**

**过程**（这条决定被自我审计推翻过一次）
最初我把这一节加进了生产 `11 · 高级设置`，理由是 Package A 要求定义 entry point，
且该屏不在 Hard Constraint 的冻结清单内。加完五套件全绿。

但自审时量了一下：**该屏四节内容原本 683pt，加一节后 857.5pt，而可视区只有 720pt** ——
新增的「开发者」节被裁掉，在设计稿上根本看不见。
`overflow` 检查器没报，因为它比的是节点宽度与裁切容器，不是纵向内容累加。

**一个看不见的入口比没有入口更糟**：它既不能指导实现，又制造了「已经画了」的错觉。
真机上这是可滚动 `Form`，加一节完全没问题 —— 问题只在静态设计稿的表现力。

**最终做法** 生产屏保持原样（并留一条注释说明为什么不画）；入口规格进 Track B 的 D0，
工程师照此在生产 Settings 里实现。**本轮对生产 Figma 的净改动为零。**

**影响面** 生产 `code.js` 只多了一段注释，生成结果与 RE-FROZEN 状态**逐项一致**
（40 组件 · 29 变体集 · 125 变体 · 41 属性 · 575 实例 · 26 屏 · 25 连线）。

**教训** 「不在冻结清单里」不等于「加进去没有代价」。改动生产屏之前应当先量可视区余量。

---

## D-UI-DEV-007 · Compare Modes 是 Lab 的第四个状态，不是独立页面

**决定** Keyword / Vector / Hybrid / **Compare** 四个 Mode 共用一个页面与一个 ViewModel。

**理由** 做成三个独立页面会暗示「要分别 Run 三次」；实际上一次检索就能同时拿到三路排名。
共用一次结果既省算力，也让 unique hit 的对比天然成立。

**影响面** `RetrievalLabViewModel` 需要同时保留 keywordRanks / vectorRanks / fusedRanks，
而不是只留最终顺序。**这是对检索层返回结构的要求，不只是 UI 决定。**

**状态** 已落地。

---

## D-UI-DEV-008 · Release Gate 任一项 FAIL 即阻断，不做加权总分

**决定** 四项检查（Recall@5 / MRR / P95 / Regression）任意一项 FAIL → `PROMOTION BLOCKED`，
`Promote` 按钮禁用。不计算加权分数，不显示「3/4 通过」这类安慰性汇总。

**理由** 加权总分会制造「大部分指标都很好」的错觉，而 Gate 存在的意义就是拦住这种错觉。
一个可以被平均掉的 Gate 等于没有 Gate。

**影响面** `ReleaseGateViewModel.verdict` 是 `checks.allSatisfy(\.passed)`，没有别的算法。

**状态** 已落地。

---

## D-UI-DEV-009 · Regression Set 与 Golden Set 同构，复用同一个 Eval Runner

**决定** `RegressionCase` 与 `GoldenCase` 结构相同；每次 Eval 自动跑两部分；
Regression Pass Rate 与 Recall@5 同口径（全部 expected 落在 Top 5 即通过）。

**理由** 两套结构 = 两套 Runner = 两套口径，之后一定会出现「Golden 说过了、Regression 说没过」
的解释成本。同构是最省的选择。管理入口只是 Dataset 选择器里多一项，
**不建 Dataset Management Platform**。

**影响面** `EvalRunner` 接受 `[EvalCase]`，不区分来源；`EvalRun` 结果里带 `source` 标记。

**状态** 已落地（规格层面）。

---

## D-UI-DEV-010 · Developer Mode 首页不做 Dashboard / KPI overview

**决定** D1 只有五行入口 + 一句说明。没有指标卡、没有最近运行、没有健康度。

**理由** Package A 明确禁止。更实际的理由：任何 overview 都需要一套「最近一次评测/最近一次发布」
的状态维护，而它对四个工具的实际使用毫无帮助 —— 用的人知道自己要去哪。

**影响面** `DeveloperModeView` 是一个 40 行的 `List`。

**状态** 已落地。

---

## D-UI-DEV-011 · Developer Mode=OFF 时「开发者工具」整行不出现，而非置灰

**决定** Toggle 关闭时隐藏整行。

**理由** 置灰会让普通用户去猜「这是什么、怎么解锁」，反而制造好奇。直接不出现最干净。

**影响面** `if devModeEnabled { NavigationLink(...) }`。

**状态** 已落地（规格层面；线框按 ON 状态绘制以便展示路径）。

---

## D-UI-DEV-012 · Trace 在 Developer Mode=OFF 时仍然采集

**决定** 采集无条件进行（用于 SLO 自测），但不暴露任何入口。开销必须 < 1ms，只记时间戳与计数。

**理由** PRD 定义了 Local Retrieval SLO（P50<100ms / P95<250ms）。
如果只在 Developer Mode 开启时采集，就永远拿不到真实用户路径上的延迟分布。

**影响面** `RetrievalTraceRecorder` 是检索管线的一部分，不是 Developer Tools 的一部分。

**状态** 已落地（规格层面）。

---

## 附：Goal 1 Week 1 — Runtime Foundation 的工程决策

D-RT-001…D-RT-008 完整记录在 [`../RETRIEVAL_ARCHITECTURE.md`](../RETRIEVAL_ARCHITECTURE.md) §7：

| ID | 决定 |
|---|---|
| D-RT-001 | Derived data 独立 store / 独立 schema / 不进 CloudKit / 不与 Note 建 SwiftData 关系 |
| D-RT-002 | cancellation 不能替代 hash validation —— 前者是优化，后者才是正确性保证 |
| D-RT-003 | job identity 含 contentHash —— 这正是 dedup 得以安全的原因 |
| D-RT-004 | restart 走 rescan + requeue，不做 durable job queue |
| D-RT-005 | Week 1 不实现真实 vector / 检索，Provider 只留可替换的接缝 |
| D-RT-006 | metadata-only 改动（order / tags / folder / 标题）不改变 block hash |
| D-RT-007 | 校验后的 derived 写入放在同步 @MainActor 临界区，而不是 @ModelActor |
| D-RT-008 | Trace 内存环形缓冲、不落库、无条件采集 |

---

## 附：Production Semantic Search 阶段的决定

见 [`SEARCH_CONTRACT.md`](SEARCH_CONTRACT.md)（隐式 Hybrid · 对比式高亮 · 标题不高亮 ·
Tag 行只属 idle 态 · QueryPhase × RetrievalCapability 二维状态模型 · block 级临时高亮）
与 [`DESIGN_BASELINE.md`](DESIGN_BASELINE.md)（F-1…F-7 七项缺陷的根因与修法）。
该阶段已 **RE-FROZEN**，本轮未改动。

---

## D-AI-003 · Cloud multilingual embedding 成为首选语义 provider，但不删除 Local

**Decision.** 云端多语言 embedding（`BAAI/bge-m3`，1024 维）在**已配置且用户已授权**时
成为首选语义检索 provider。**Local embedding 不删除**，降级为 fallback。

最终能力层级：

```
Cloud Semantic     ← 已配置 + 已授权
  ↓ fallback
Local Semantic     ← 本机模型能覆盖当前语料语种
  ↓ fallback
Keyword Only       ← 永远可用，最终保障
```

**Why.** 在 `synthetic-human-v3`（150 篇 / 114 条 query / 20 条负例）上实测：

| | in-scope R@1 | in-scope R@5 | cross R@5 | overall MRR |
|---|---:|---:|---:|---:|
| Local Hybrid | 0.269 | 0.418 | 0.128 | 0.247 |
| **Cloud Hybrid** | **0.866** | **1.000** | **0.936** | **0.886** |

差距不是调参能补的：跨语言那一支本地做不到，因为整库只有一个向量空间，
而中文 query 经英文模型出来的是噪声（上一轮双索引实验已经用数据否决，见下）。

**Why Local 仍然保留：** offline · 未配置 API Key · 用户拒绝云端处理 · provider 故障 ·
rate limit · 隐私敏感场景。这五种情况下语义路不能整条消失。

**Why Keyword 是最终保障：** 负例实测里 keyword 的 no-result accuracy 是 **100%**，
而四个向量臂全是 **0%**。在 TD-10 解决之前，keyword 是唯一能表达「确实没有答案」的一路。

**Rejected alternative — 中英双索引 + 语种路由。** 实测比 baseline 更差：
真实路由 R@5 = 0.158（现状 0.211），即使给它一个**永远猜对的作弊路由**也只到 0.421，
而同语种上界是 0.619。根因不是路由不准，而是中文 query 与英文笔记不在同一语义空间 ——
换任何本地模型都改变不了。**这条不是推理否决的，是实验否决的。**

**代价（已知且未解决）：** 云端语义 P50 ≈ 710 ms / P95 ≈ 790–960 ms，
远超 PRD 的 Local Retrieval SLO（P50 < 100 / P95 < 250）。因此 SLO 拆成三层（见
`RETRIEVAL_ARCHITECTURE.md` §21.2），且 **Release Gate 当前判定为 BLOCKED** ——
质量三项全过，P95 一项否决。**云端不因为质量好就自动进生产。**

**不做的事：** 不简单把 `NLEmbedding` 替换成 `bge-m3`。实现是 capability-aware routing
（`EmbeddingRouter.choose`），云端失败必须降级而不是让搜索失败。

---

## D-AI-003 · Cloud multilingual embedding 为首选语义 provider，本地保留为 fallback

**决定**：能力层级为 **Cloud Semantic → Local Semantic → Keyword Only**。
云端可用且获授权时优先走云端；否则退本地语义；本地也不可用时退关键词。
**不删除本地 embedding。**

### 为什么不是「换个默认模型」

跨语言是唯一云端不可替代的场景，而它不是调参问题：

| 方案 | cross-language R@5 | 结论 |
|---|---:|---|
| 本地单一向量空间（现状） | 0.211 (v2) / 0.128 (v3) | baseline |
| **中英双索引 + 双嵌入 query** | **0.158** | ❌ **比 baseline 更差**，实测否决 |
| 双索引 + 作弊路由（永远猜对） | 0.421 | 上界仍不足 |
| 语种匹配上界（同批笔记换同语种 query） | 0.619 | 参照 |
| **云端 bge-m3（同一向量空间）** | **1.000** (v2) | ✅ |

双索引失败的机制是确定的：**中文 query 用英文模型嵌入 19/19 全部"成功"、0 条报错**，
但产出的是噪声向量，进 RRF 只会稀释信号。

### 本地为什么必须留

1. **真机上本地是可用的**（TD-9 推翻）：iPhone Air / iOS 27.0 实测 `zh-Hans` ✅ 640 维。
2. **真机本地 hybrid 在 SLO 内**：20k chunks P50 92.53 ms / P95 119.30 ms。
3. 云端要求用户配 Key + 明确同意上传 + 自付费用 —— 不配的用户不该只剩关键词。
4. 离线 / provider 故障 / 429 / 隐私敏感场景。

### 代价（必须与决定一起记）

云端 query embedding 实测 P50 383.5 ms / P95 1192.7 ms，**其中网络占 99.80%**
（解析+归一化仅 0.76 ms）。这不是优化能消掉的，因此：

- SLO 拆成分层（见 `RETRIEVAL_ARCHITECTURE.md` §22.1）
- 云端那一层由 `PerformanceGatePolicy` 配为「**记录但不判定**」
- 该层数字必须带 `providerRegion` 标签，region 不符时 Gate 判 **STALE 而不是 FAIL**

### 默认值已改为云端优先（2026-08-19）

`EmbeddingRouter` 的默认顺序现在是 **Cloud → Local → Keyword**。
v2 时写的是「本地优先，能离线做的事不该上传」，v3 的实测把它推翻了：
跨语言 0.128 vs 1.000 的差距，大到「省一次上传」换不回来。

**云端优先 ≠ 默认上传。** 三条约束同时成立：

1. `hasAcceptedCloudEmbeddingNotice` **默认仍是 `false`** —— 没有明确同意时，
   `choose` 拿不到 `cloudConsentGranted`，云端那一路根本不会被选中。
2. **未授权时落回本地语义**，而不是降级为「语义不可用」——
   不能因为用户拒绝上传就把他从可用的本地检索上赶下来。
   `.cloudNeedsConsent` 只在**本地也顶不上**时才出现，那时候问用户才有意义。
3. 闸门仍在两层：`EmbeddingRouter` 返回 `.cloudNeedsConsent` 而非 `.cloud`，
   且 `ProductionEmbedding.decide` 在该状态下连 provider 都不构造。

**已知缺口**：本地语义可用、云端已配置但未授权、且库是双语时，
系统会安静地用本地跑（跨语言搜不到），**不会主动告诉用户「开启云端能搜到英文文档」**。
补它需要一个新的用户侧提示，属于 UI 范围，本轮未做。
