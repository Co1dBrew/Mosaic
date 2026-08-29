# Mosaic Developer Tools — IA · 线框 · 交接规格（Track B）

> 上游 Source of Truth：**Mosaic AI Retrieval Quality Platform PRD v1.0**
> 设计层级：**Track B — Functional Specification > Visual Polish**
> 线框生成器：[`figma-plugin-devtools/`](figma-plugin-devtools/)（与 Production 生成器完全分离）
> 相关：[`DECISION_LOG.md`](DECISION_LOG.md) · [`GOAL1_UI_COVERAGE.md`](GOAL1_UI_COVERAGE.md) · [`DEVTOOLS_SWIFTUI_PLAN.md`](DEVTOOLS_SWIFTUI_PLAN.md)

**目标用户不是 Mosaic 的普通用户，而是 Developer / AI TPM。** 这里术语精确性优先，
[`SEARCH_CONTRACT.md`](SEARCH_CONTRACT.md) §1.1.1 的用户侧禁用词表在本范围内不适用。

**本文件不新增任何 PRD 之外的产品能力。** 明确排除：Ask My Notes · RAG Chat · Citation QA ·
Agent · Tool Calling · Prompt Studio · LLM-as-Judge · Cost Dashboard · Job Dashboard ·
Vector DB Dashboard · Feature Flag Platform。

---

# 1. Developer Mode IA

## 1.1 导航层级

```text
Settings（07 · 生产屏，已存在）
└── 高级 ›                                    [11 · 高级设置 · 生产屏]
    ├── AI 参数 / 语音转写 / 同步与数据 / 隐私     （既有四节，未改动）
    └── 开发者                                 ← 规格见 Track B 的 D0，**未画进生产屏**
        ├── 开发者模式            [Toggle]      默认 OFF
        └── 开发者工具 ›                        Toggle=ON 时才出现
            │
            └── Developer Mode                [D1 · Track B 线框]
                ├── Retrieval Lab ›           [D2]
                │   ├── Compare Modes         [D3]  ← 同页的第四个 Mode 状态，不是独立页
                │   └── Trace ›               [D4]  ← 从任一结果下钻
                ├── Retrieval Eval ›          [D5]
                │   ├── Compare With Baseline [D6]
                │   └── Failed Cases ›        [D9]
                ├── Release Gate ›            [D7 PASS / D8 BLOCKED]
                │   └── Open Failures ›       [D9]
                ├── Retrieval Trace ›         [D4]  ← 也可直接进入（看最近一次检索）
                └── Retrieval Config ›        [辅助入口，SwiftUI-first，无线框]
```

## 1.2 关键规定

| 项 | 规定 |
|---|---|
| **默认状态** | `开发者模式` 默认 **OFF**。首次安装、TestFlight、App Store 构建一律 OFF |
| **可见性** | Toggle=OFF 时，「开发者工具」整行**不出现**（不是置灰）。理由：置灰会让普通用户去猜它是什么 |
| **入口唯一性** | Developer Mode 只有这一个入口。不做 URL scheme、不做连点版本号、不做摇一摇 |
| **Developer Mode 首页** | **纯入口列表。不做 Dashboard Home，不做 KPI overview。** 它的职责是分发，不是汇报 |
| **Back 行为** | 全链路标准 `NavigationStack` push/pop。返回逐级回退，不做「一键回到 Developer Mode」 |
| **状态保持** | 每个工具页的输入（Query、Dataset、Config 选择）在**本次进入 Developer Mode 期间**保留；退出 Developer Mode 后丢弃。不做持久化 |
| **Production / Developer 分离** | 生产界面**永远不感知** Developer Mode 是否开启。没有任何生产页面因为它而改变外观或行为 —— 唯一的接触点是「设置 › 高级」末尾多出一节（规格见 D0），且该节在 Toggle=OFF 时只有一行 |
| **数据隔离** | Developer Tools 只读生产索引与生产笔记；写操作仅限 Golden Set / Regression Set / Retrieval Config 三类**评测侧**数据。不得改动用户笔记 |

## 1.3 页面清单

| ID | 页面 | 交付形态 | 说明 |
|---|---|---|---|
| **D0** | 入口 · 设置 › 高级 | 线框 | 要加进生产 Settings 末尾的那一节。**生产屏未改** |
| **D1** | Developer Mode | 线框 | 入口列表 |
| **D2** | Retrieval Lab | 线框 | Query + Config + Result Inspector |
| **D3** | Retrieval Lab · Compare Modes | 线框 | D2 的第四个 Mode 状态 |
| **D4** | Retrieval Trace | 线框（SwiftUI-first） | Pipeline + Index metadata |
| **D5** | Eval Center | 线框 | Dataset × Config → 指标 |
| **D6** | Eval Center · Compare | 线框 | Current / Baseline / Delta |
| **D7** | Release Gate · PASS | 线框 | |
| **D8** | Release Gate · BLOCKED | 线框 | |
| **D9** | Failure Inspection | 线框（SwiftUI-first） | 线框只为把 Flow B/C 走通 |
| — | Retrieval Config | **仅规格** | 见 §4.6 |
| — | Regression Set 管理 | **仅规格** | 见 §5 |

---

# 2. Track B 边界（Package J）

生成器 [`figma-plugin-devtools/code.js`](figma-plugin-devtools/code.js) 与 Production 生成器
**完全分离**：独立 manifest、独立插件、不共享一行代码、只创建并重建一个页面
`🔧 Dev Tools (Wireframe)`。

| 禁止 | 实测 |
|---|---|
| 进入 Production generation / calibration pipeline | ✅ 独立插件，`test/run.js` 断言 Production 三页未被触碰 |
| 创建 Variable / Text Style / Effect Style | ✅ `track-b` 检查断言三者计数为 0 |
| Dark Mode | ✅ 只生成一块 Light 画板 |
| 像素校准 / ±1pt 校验 | ✅ 不进 calibration |
| 自定义图表 / 插画 | ✅ 无 |
| 大型组件库 | ✅ 零 Figma 组件，全部是本地 frame |
| 新增颜色 / 字体 token | ✅ 字面灰度值，不建 Variable |

允许：灰度 box、文本、原生控件近似（导航栏 / Form 行 / Toggle / Segmented / 主按钮）。

**冒烟测试**（`node test/run.js`）：屏数 · 屏尺寸 · 内容不溢出 852pt · 连线数 · Track B 边界 · Production 页未受影响，共 6 项。

---

# 3. Prototype Flows（Package I）

线框内 **11 条连线**，覆盖三条 Flow，死链 0。

## Flow A — Retrieval Investigation

```
D0 设置 › 高级 › 开发者工具
  → D1 Developer Mode
  → D2 Retrieval Lab        （输入 Query「延期毕业」，Mode=Hybrid，Run）
  → D3 Compare Modes        （Keyword / Vector / Hybrid 的 unique hit）
  → D4 Trace                （从任一结果下钻：为什么是这个排名 / 有没有用到过期 embedding）
```

## Flow B — Evaluation

```
D1 Developer Mode
  → D5 Eval Center          （Golden Set × retrieval-v5 → Run）
  → D6 Compare With Baseline（Current / Baseline / Delta，同时看到质量提升与延迟回退）
  → D9 Failure Inspection   （打开某条失败用例）
  → Add to Regression Set
```

## Flow C — Release

```
D1 Developer Mode
  → D7 Release Gate · PASS      → Promote to Production
       D8 Release Gate · BLOCKED → Open Failures → D9 Failure Inspection
```

---

# 4. 逐页交接规格（Package K2）

> 每页固定七段：Purpose / Primary Task / Inputs / Outputs / Navigation / State / Data Dependency / SwiftUI。

---

## D0 · 入口 · 设置 › 高级

**Purpose** 规定要加进生产「设置 › 高级」末尾的那一节长什么样。
**Primary Task** 「开发者模式在哪开？开了以后从哪进？」
**Inputs** `开发者模式` Toggle（默认 OFF）。
**Outputs** Toggle=ON 时出现 `开发者工具 ›`，push 到 D1。
**Navigation** 进：设置 → 高级。出：返回设置。
**State** `off`（只有 Toggle 一行）· `on`（两行）。
**Data Dependency** 一个 `@AppStorage("developerModeEnabled")` 布尔值。
**SwiftUI** 在既有 `AdvancedSettingsView` 末尾加一个 `Section`：
`Toggle` + `if enabled { NavigationLink }`。

> **为什么不画进生产 `11 · 高级设置`**：该屏四节内容原本 683pt，加一节后 857.5pt，
> 而可视区只有 720pt —— 新增的一节会被裁掉，在设计稿上根本看不见。
> 真机上它是可滚动 Form，加一节没问题；问题只在静态设计稿的表现力。
> 见 [`DECISION_LOG.md`](DECISION_LOG.md) D-UI-DEV-006。

---

## D1 · Developer Mode

**Purpose** 把四个检索工具分发出去，不做任何汇总。
**Primary Task** 「我要去 Lab / Eval / Gate / Trace。」
**Inputs** 无。
**Outputs** 导航。
**Navigation** 进：设置 → 高级 → 开发者工具。出：返回高级设置。
**State** 只有 default 一种。**没有 loading，没有空态** —— 入口列表永远是那五行。
**Data Dependency** 当前 `RetrievalConfig.version`（显示在 Retrieval Config 行的 value 位）。
**SwiftUI** `List` + 两个 `Section` + `NavigationLink`。整页不超过 40 行代码。

---

## D2 · Retrieval Lab

**Purpose** 解释同一个 Query 为什么得到当前排序。
**Primary Task** 「这条为什么排第 2？是 keyword 把它顶上来的，还是 vector？」
**Primary Action** Run。

**Inputs**

| 字段 | 控件 | 取值 | 默认 |
|---|---|---|---|
| Query | TextField | 自由文本 | 空 |
| Retrieval Mode | Picker | Keyword / Vector / Hybrid | **Hybrid** |
| Embedding Provider | Picker | Local · bge-small-zh / Cloud | Local |
| Chunk Strategy | Picker | Block / Block+240字 / Sentence | Block · 240 字 |
| Top K | Picker | 5 / 10 / 20 / 50 | 20 |
| Fusion Method | Picker | RRF(k=60) / Weighted | **RRF(k=60)** |

> Goal 1 **Hybrid 默认 RRF**。不做复杂 Config Editor —— 六个 Picker 即全部可调项。

**Outputs** 结果列表，每条含：Final Rank · Note Title · Source/Block Type · Matched Text ·
Keyword Rank · Vector Rank · Vector Similarity。

**结果卡片版式（D-UI-DEV-002）**

```
#2  和 advisor 的邮件往来
    Text Block · chunk 1/2
    …我问了能不能延期一个学期毕业，他说要先跟系里确认…
    K #3 · V #7 → #2        similarity 0.842
```

393pt 放不下八列横表。`K #3 · V #7 → #2` 一行把三个排名压在一起，
**5 秒内可读**：keyword 第 3、vector 第 7，融合后升到第 2 —— 说明两路都投了票。
`K —` 表示该路未命中，是解释「为什么这条会出现」最关键的记号。

**Navigation** 进：D1。出：返回 D1。下钻：`Compare Modes` → D3；点任一结果 → D4 Trace。
**State** `idle`（未 Run）· `running` · `results` · `empty`（0 命中）· `error`（provider 不可用）。
`error` 时保留上一次结果并在顶部一行说明 —— 与生产搜索同一条原则：**失败不清屏**。
**Data Dependency** `RetrievalConfig` · 索引 · 笔记正文 / 转写 / OCR / 文档提取文本 / 链接元数据。
**SwiftUI** `Form`（Section: Query / Configuration）+ `List`（结果）。结果行是自定义
`VStack`，但只有文本，无自定义绘制。

---

## D3 · Retrieval Lab · Compare Modes

**Purpose** 让 Keyword / Vector / Hybrid 的差异一眼可见。
**Primary Task** 「Hybrid 到底比单路好在哪？多捞回了什么？」

**关键决定**：**不是三个独立页面**，而是 D2 的 Mode Picker 的**第四个状态**。
理由：三个页面会让人以为要分别 Run 三次；实际上一次检索就能同时给出三路排名。

**Outputs**

```
HYBRID FINAL RANKING
#1  Graduate Handbook.pdf        K #1  V #4  → #1
#2  和 advisor 的邮件往来          K #3  V #7  → #2
#3  NEU Extended Study Option    K —   V #1  → #3   vector only
#4  周会录音 · 10/22              K #2  V —   → #4   keyword only

UNIQUE HITS
Keyword only · 2   周会录音 · 10/22   ·   延期毕业申请材料清单
Vector only  · 1   NEU Extended Study Option
两路都命中 · 6
```

`unique hit` 是这一屏的重点：它直接回答「砍掉 vector 会丢什么」。
**不做横向大表** —— 三列并排在 393pt 下每列只剩 110pt，标题必然截断。

**Navigation** 进：D2 的 `Compare Modes`。出：返回 D2。
**State** 与 D2 共享一次检索结果，无独立 loading。
**SwiftUI** 同一个 `RetrievalLabViewModel`，`mode == .compare` 时切换 `List` 的行渲染。

---

## D4 · Retrieval Trace

**Purpose** 回答「为什么这个 Query 搜错了」，而不是「花了多少毫秒」。
**Primary Task** 「是 embedding 过期了，还是候选集根本没捞到？」

**信息层级（三段，顺序固定）**

| 段 | 字段 | 作用 |
|---|---|---|
| **1 · 身份** | Query · Config Version · Embedding Version · Index Version | 先确定「这是哪一次、哪套配置」。排查的第一步永远是版本对不对 |
| **2 · Pipeline** | Query Processing · Query Embedding · Keyword Retrieval · Vector Retrieval · Fusion · Ranking · **Total** | 定位耗时落在哪一层 |
| **3 · Index** | chunkCount · candidateCount · resultCount · **contentHash** | 定位数据问题 |

**contentHash 是这一屏最重要的一行。** 它与索引记录一致 → 本次结果没有用到过期 embedding；
不一致 → 标 `stale` 并给出重建入口。**「结果不对」和「索引过期」是两类完全不同的问题，
不能靠猜。**

`candidateCount → resultCount` 的落差同样关键：候选 60、结果 12，说明融合与截断正常；
候选 0 则问题在检索层而不是排序层。

**禁止 waterfall chart。** 七行 `LabeledContent` 已经能回答全部问题，火焰图只增加实现成本。

**Navigation** 进：D2 任一结果 / D1 直接进入（看最近一次检索）。出：返回。
**State** `hasTrace` / `noTrace`（尚未执行过检索）。
**Data Dependency** `RetrievalTrace`（每次检索留存最近 N=20 条，内存即可，不入库）。
**SwiftUI** `List` + `Section` + `LabeledContent`。**无需 Figma 生产屏。**

---

## D5 · Eval Center

**Purpose** 用固定数据集量化一套配置的检索质量与延迟。
**Primary Task** 「retrieval-v5 到底多好？」
**Primary Action** Run Evaluation。

**Inputs** Dataset · Configuration（retrieval-v5）。Cases 数只读显示。每条 case 可带
`queryLanguage / expectedLanguage / scope`；无答案用 `.noRelevantResult`，不是空 expected 的坏标注。
**Outputs**

```
QUALITY       Recall@1 0.700 · Recall@3 0.825 · Recall@5 0.875 · MRR 0.781
BOUNDARY      Cross-language Recall@5 0.211 · MRR 0.171（如有，只作诊断）
NO RESULT     Accuracy 0.000 · False-positive Rate 1.000（如有，暂不进 Gate）
PERFORMANCE   P50 96 ms · P95 181 ms
FAILURES      5 cases ›
```

主质量与性能只取 **in-scope 正例**；overall 仅作参考。**不做图表。** 少量数字 + 一个失败入口
即全部内容，几十个 case 的评测画折线没有信息量。

**Navigation** 进：D1。下钻：`Failed Cases` → D9；`Compare With Baseline` → D6。
**State** `idle` · `running`（带 `n / 40` 进度）· `done` · `failed`（评测本身出错）。
**Data Dependency** Golden Set · RetrievalConfig · 索引。
**SwiftUI** `Form` + `Section` + `LabeledContent`。进度用 `ProgressView(value:total:)`。

---

## D6 · Eval Center · Compare

**Purpose** 回答「新 Config 比 Production Baseline 好还是差」。
**Primary Task** 「值不值得上线？代价是什么？」

**Outputs** 四列：Metric · Current · Baseline · Delta。

| Metric | Current | Baseline | Delta |
|---|---|---|---|
| Recall@1 | 0.700 | 0.650 | **+0.050** |
| Recall@3 | 0.825 | 0.800 | **+0.025** |
| Recall@5 | 0.875 | 0.825 | **+0.050** |
| MRR | 0.781 | 0.742 | **+0.039** |
| P50 | 96 ms | 88 ms | **+8 ms** |
| P95 | 181 ms | 154 ms | **+27 ms** |

**质量与延迟必须在同一屏、同一张表里。** 分开放会让人只看 Recall 就下结论。
Compare 与 Release Gate 都只比较 in-scope 正例；cross-language 与 no-result 不混进主 delta。
Delta 用颜色区分方向（质量↑绿 / 延迟↑红），但**不给 PASS/FAIL** ——

> **Eval 的任务是理解 trade-off，判定是 Release Gate 的事。**

底部一句话总结这次的 trade-off（「质量提升，延迟回退：Recall@5 +0.050，代价 P95 +27ms，仍在 250ms 预算内」）。

**Navigation** 进：D5。出：返回 D5。下钻：`Failed Cases` → D9。
**State** `idle`（未选 baseline）· `comparing` · `done`。
**Data Dependency** 两次 EvalRun 结果。
**SwiftUI** `List` + 自定义 4 列 `HStack`（固定列宽 105/74/74/74，`.monospacedDigit()`）。

---

## D7 / D8 · Release Gate

**Purpose** 判定一套配置能不能上线，以及不能的话是哪一项卡住。
**Primary Task** 「能上吗？为什么不能？」
**要求：进入页面 2 秒内答出这两个问题。**

**版式**：顶部一整块判定区（`PASS` 绿底 / `PROMOTION BLOCKED` 红底，34pt 加粗），
下面是四项检查，每项一行给出**具体条件与实测值**。

| Check | 条件 | PASS 示例 | BLOCKED 示例 |
|---|---|---|---|
| Recall@5 | ≥ baseline | 0.875 ≥ 0.825 ✅ | 0.861 ≥ 0.825 ✅ |
| MRR | ≥ baseline − 0.010 容差 | 0.781 ✅ | 0.766 ✅ |
| P95 | ≤ budget 250 ms | 181 ms ✅ | **310 ms ❌** |
| Regression | ≥ threshold 98% | 100% · 40/40 ✅ | **97.5% · 39/40 ❌** |

**判定规则：任一项 FAIL 即阻断。不做加权，不做总分。**
加权总分会制造「大部分指标都很好」的错觉，而 Release Gate 的存在意义就是拦住这种错觉。
四项检查的输入均为 **in-scope 正例**；cross-language 是已知架构边界，no-result 阈值尚未冻结，
两者继续显示在 Eval Center，但暂不参与 Gate。

失败行整行红底，并在行内给 `Open Failures ›` 直达 D9 —— **从「不能上线」到「为什么」只需一次点击**。
`Promote to Production` 在 BLOCKED 时置灰禁用。

**Navigation** 进：D1。下钻：失败行 → D9。
**State** `pass` · `blocked` · `stale`（评测结果早于当前 Config，需重跑）。
**Data Dependency** EvalRun（current + baseline）· RegressionRun · GateThresholds。
**SwiftUI** `List` + 自定义判定 header + `Section`。禁用态用 `.disabled(true)`。

---

## 4.6 Retrieval Config（仅规格，无线框）

**Purpose** 查看与切换检索配置版本。
**理由不做线框**：它就是 D2 那六个 Picker 的持久化版本，没有新的布局决策。

字段：`version`（只读）· `mode` · `embeddingProvider` · `embeddingModel` · `chunkStrategy` ·
`chunkSize` · `topK` · `fusionMethod` · `rrfK` · `createdAt` · `promotedAt?`。

操作：`Duplicate as new version`（从当前版本派生）· `Set as candidate`。
**不做自由编辑生产配置** —— 生产配置只能通过 Release Gate 的 Promote 更换。

**SwiftUI** `Form` + `Picker` ×6 + 只读 `LabeledContent`。

---

# 5. Failure Inspection 规格（Package E — SwiftUI-first）

**交付判定：B（SwiftUI-first specification）。** 它是一张纯 key-value + 三段列表的页面，
没有任何真实布局决策。线框 D9 存在的唯一理由是把 Flow B / C 在原型里走通。

## 5.1 字段

| 段 | 字段 | 说明 |
|---|---|---|
| Query | `query` | 失败的那条 query 原文 |
| Expected | `expectedNoteIds[]` | Golden Set 标注的应召回笔记；每条标 `returned` / `not returned` |
| Returned | `returnedNotes[]` | 实际返回的 Top N，带 rank |
| Per-mode | `keywordResult` · `vectorResult` · `hybridResult` | 每路各自的命中位置或 `not found` |
| Diagnosis | `failureType` | 见下表 |
| Note | `diagnosisNote?` | 可选的一句人工说明 |

## 5.2 Failure Type（固定 7 类，不可扩展）

| 值 | 含义 | 典型证据 |
|---|---|---|
| `chunking` | 切分把语义切断了 | expected 笔记的 chunk 里没有完整的命中语义单元 |
| `embedding` | 向量表示不佳 | vector 排名极低而人读上下文明显相关 |
| `keyword` | 词法层面没命中 | 同义词 / 异形词，keyword `not found` |
| `fusion` | 单路排名好但融合后掉了 | K 或 V 排名高，Hybrid 反而跌出 Top K |
| `missingData` | 语料里根本没有这段文本 | OCR / 转写 / 文档提取缺失 |
| `staleIndex` | 索引过期 | `contentHash` 与当前内容不一致 |
| `other` | 以上都不是 | 必须填 `diagnosisNote` |

**为什么固定 7 类**：Failure Type 是要拿来统计的（「这一轮 60% 的失败是 chunking」）。
可自由输入的分类没有统计价值。

## 5.3 操作

**`Add to Regression Set`** —— 唯一的写操作。幂等：已在集合中则按钮变为
`In Regression Set`（禁用）。

## 5.4 Navigation（两个入口，同一页面）

```
D5 Eval Center → Failed Cases    → D9   （评测阶段：批量看失败）
D6 Eval Compare → Failed Cases   → D9
D8 Release Gate → Open Failures  → D9   （发布阶段：只看 regression 失败的那几条）
```

两个入口进入的是**同一个 View**，只是数据源不同（EvalRun.failures vs RegressionRun.failures）。

## 5.5 Implementation

> **SwiftUI List / Section / LabeledContent。No production Figma required.**

---

# 6. Regression Flow（Package F）

## 6.1 最小闭环

```
Eval / Gate 里出现 Failed Query
   ↓  点进去
D9 Failure Inspection            标注 Failure Type
   ↓  Add to Regression Set
RegressionSet（一个 query id 列表 + 期望笔记）
   ↓  下一次 Eval 自动带上
Regression Pass Rate  =  通过条数 / 集合总数
   ↓
Release Gate 的第 4 项检查      ≥ threshold 98%
```

## 6.2 规定

| 项 | 规定 |
|---|---|
| **数据结构** | `RegressionSet` = `[RegressionCase]`，`RegressionCase = { query, expectedNoteIds[], addedAt, sourceFailureType }`。**与 Golden Set 同构** —— 复用同一个 Eval Runner，不写第二套 |
| **参与时机** | 每次 Eval **自动**跑 Golden Set + Regression Set 两部分。Regression 不需要单独触发 |
| **Pass Rate 定义** | 一条 case 通过 = 其全部 `expectedNoteIds` 落在 Top 5 内。这与 `Recall@5` 同口径，避免两套定义 |
| **管理入口** | Developer Mode → Retrieval Eval → Dataset 选择器里多一项 `Regression Set · n cases`，点进去是一个 `List`，支持左滑删除。**不建 Dataset Management Platform** |
| **不做** | 版本化、分支、导入导出、协作、标签体系 |

## 6.3 为什么阈值是 98% 而不是 100%

Regression Set 会随时间增长，其中会混入标注本身有争议的 case。要求 100% 会让 Gate 在
第 50 条之后永远无法通过，然后被人为跳过 —— **一个总是被跳过的 Gate 等于没有 Gate**。
98% 留出约 1/50 的容错，同时任何一次新增失败都会立刻把 40 条集合打到 97.5%（即示例 D8）。

> 具体阈值属 tuning value，最终由 PRD / benchmark 决定，此处给出的是**取值理由**。

---

# 7. Trace 规格（Package H — SwiftUI-first）

见 §4.4 的完整字段与信息层级。补充实现约定：

| 项 | 规定 |
|---|---|
| 留存 | 最近 **20** 条，内存数组，App 退出即丢。不入 SwiftData |
| 采集 | 每次检索无条件采集。**开销必须 < 1ms** —— 只记时间戳与计数，不记内容 |
| 生产影响 | Developer Mode=OFF 时仍然采集（用于 SLO 自测），但**不暴露任何入口** |
| 禁止 | waterfall chart · 火焰图 · 时间轴可视化 · 导出上传 |

---

# 8. 已知问题登记（只记录，不修）

> Hard Constraint 要求：在 RE-FROZEN 的 Production UI 上发现问题只登记不修。
> 本轮在 Track B 工作中未触碰任何生产屏，**未发现新的生产侧缺陷**。

| # | 内容 | 状态 |
|---|---|---|
| — | 无 | — |

**本轮对生产 Figma 的净改动为零。**

Developer Mode 的入口一度被加进 `11 · 高级设置`，但自审时发现该屏四节原本已占 683pt，
加一节后达 857.5pt，超出 720pt 可视区 —— 新增的一节会被裁掉，在设计稿上根本看不见。
已回退，入口规格改由 Track B 的 **D0** 承载。
详见 [`DECISION_LOG.md`](DECISION_LOG.md) D-UI-DEV-006。
