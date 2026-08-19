# Mosaic / 万象记 — 项目交接说明

> 复制这份内容到新对话，即可让新窗口快速接手。
> 最后更新：2026-08-13 · **Goal 1 Week 1–6 的可自动完成部分已全部完成**
> （Week 5 全部 · Week 6 实验与收口；剩余为真机 / 人工 / PRD 依赖项）
> TD-9：**本机 App 已确认**没有中文句向量模型，语义检索不可用，关键词不受影响。

---

## 0. 一句话

**Mosaic / 万象记** 是一个 iOS AI-native 笔记 App，正在被升级成一套
**AI Retrieval Quality Platform**：把传统 keyword 搜索升级为
semantic + lexical hybrid retrieval，并且**可评测、可发布、可追踪、可防回归**。

仓库：`/Volumes/Github/Mosaic` · 分支：`feature/mosaic-mvp-p0`

---

## 1. Source of Truth（重要）

| 文件 | 地位 |
|---|---|
| **Mosaic AI Retrieval Quality Platform PRD v1.0** | **Goal 1 / Goal 2 的唯一权威来源。不在仓库里，在用户手上。** 需要具体取值时要问，不要臆造 |
| `prd.md` | **旧的** Notes App PRD（v0.2）。只作为既有笔记产品行为的现状依据，**不是 Goal 1 的上游** |

**Goal 1（6 周）核心故事**：Build → Evaluate → Ship → Observe → Improve

必须围绕：Keyword / Vector / Hybrid Retrieval · RRF · Chunking · Embedding lifecycle ·
contentHash / stale protection · Retrieval Lab · Golden Dataset · Recall@K / MRR ·
Eval Center · Regression · Release Gate · Trace · Production Semantic Search

**明确不做**：Ask My Notes · RAG Chat · Citation QA · Agent · Tool Calling ·
Prompt Studio · LLM-as-Judge · Cost / Job / Vector DB / Feature Flag Dashboard

---

## 2. 技术栈与工程结构

- **SwiftUI + SwiftData，iOS 17+**
- **`Sources/MosaicKit/`** —— 平台无关内核，**刻意不依赖 SwiftData / UIKit**，
  所以能用 CLT 工具链编译测试。App 在边界处把 `@Model` 适配成值类型
  （`Block.toContent() -> CardBlockContent`）。
- **`App/`** —— Xcode 工程，由 **XcodeGen** 从 `App/project.yml` 生成。
  源码按目录纳入，**新增文件后要 `xcodegen generate`**。
- 测试分两套（CLT 工具链没有 XCTest，所以内核用自制断言 harness）。

### 常用命令

```bash
# MosaicKit 内核测试（1048 断言）
swift run mosaic-checks
# release 模式（1058 断言，含 SLO 与规模断言 —— 性能数字只有 release 才有意义）
swift run -c release mosaic-checks

# App 测试（80 个 XCTest，跑在真实模拟器上）
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 新增 App 源文件后
cd App && xcodegen generate

# Figma 生成器测试
cd design/figma-plugin && node test/all.js          # 5 套件
cd design/figma-plugin-devtools && node test/run.js # Track B 冒烟
```

---

## 3. 设计阶段 —— 已完成并冻结

### Production UI：**RE-FROZEN**

Figma 由 `design/figma-plugin/code.js`（生成器）产出，**不是手工画的**。

- **26 屏 × Light/Dark** · 40 组件 · 29 变体集 · 125 变体 · 575 实例 · 25 条原型连线
- 5 套自动化：`checks 11` · `gates 9` · `calibration 96` · `tolerance 7` · `selftest 15`
- 经 **5 轮 Figma 实跑 + MCP 实读**，抓到并修复 **7 个缺陷（F-1…F-7）**，
  其中 **5 个是既有缺陷**（不是本次引入）

> ⚠️ 改 Figma 的唯一方式是改 `code.js` 然后在 Figma 里重跑插件。
> 我无法自己跑插件，必须请用户跑，然后用 MCP 实读核对。
> **「桩和 Figma 一致地错」是这个项目栽过三次的坑** —— 结论必须来自实读，不是桩。

### Developer Tools：**Track B 低保真线框**

`design/figma-plugin-devtools/`（**独立插件**，与生产流水线完全分离）
10 屏 + 11 条连线。不创建任何 Variable / Style，不做 Dark Mode，不进 calibration。

### 设计文档（`design/`）

| 文件 | 内容 |
|---|---|
| `SEARCH_CONTRACT.md` | **生产搜索契约，DONE / RE-FROZEN。** 隐式 Hybrid · Matched Excerpt 开窗规则 W1–W7 · 对比式高亮 · QueryPhase × RetrievalCapability 二维状态模型 · Result→Note 落点行为 |
| `DEVTOOLS.md` | Developer Mode IA · 10 屏逐页交接规格 · Failure Inspection / Trace / Regression 的 SwiftUI-first 规格 |
| `DECISION_LOG.md` | D-UI-DEV-001…012（设计决策） |
| `GOAL1_UI_COVERAGE.md` | UI 覆盖矩阵，**Missing = 0** |
| `DEVTOOLS_SWIFTUI_PLAN.md` | View / ViewModel 职责拆分 |
| `GOAL1_BACKLOG.md` | 6 周实现 backlog（Week 1–6 逐条任务 + DoD） |
| `DESIGN_BASELINE.md` | 设计基线、指标、F-1…F-7 缺陷记录 |
| `FIGMA_AUDIT_GOAL1.md` | 首次审计快照（**已过时，仅历史记录**） |

### 遗留

**Track B 线框的视觉验证一直没做完** —— 需要在 Figma 里选中
`🔧 Dev Tools (Wireframe)` 页，我才能 MCP 读到。这是设计阶段唯一未闭环的事。

---

## 4. 工程阶段 —— 已完成

架构文档：**`RETRIEVAL_ARCHITECTURE.md`（根目录）** —— 含 D-RT-001…015 工程决策。

### Week 1 · Runtime Foundation ✅

`Sources/MosaicKit/Retrieval/`：
`AIContentHash` · `EmbeddingProvider` · `EmbeddingJobKey` · `AIJobCoordinator` ·
`StaleGuard` · `DerivedWorkScanner` · `RetrievalTrace` · `DerivedData`

`App/Mosaic/Retrieval/`：`DerivedDataStore` · `DerivedModels`

**最重要的两条**：

1. **Stale protection 在 persistence boundary，不靠 cancellation。**
   `Task.cancel()` 是优化不是保证 —— provider 可能忽略取消、可能先完成后才观察到取消、
   重试可能活过那次编辑、进程重启什么都不取消。所以校验基于**数据**（contentHash），
   放在**无法绕过的地方**（写入路径）。有一个"故意忽略取消的 provider"测试守着。
2. **Derived data 独立 SwiftData container + 独立 store 文件，不进 CloudKit。**
   "删掉全部 derived data 不能丢任何一条笔记" 是**结构性保证**，不是纪律。
   `Card` / `Block` / `Folder` schema **一个字没改**。

**SwiftData 并发结论**：校验后的 derived 写入放在**同步 `@MainActor` 临界区**
（读 hash → 判定 → 写，中间没有 `await`）。不用 `@ModelActor`，因为权威内容在主上下文里，
镜像一份 hash 到后台 actor 会滞后于编辑，而滞后的镜像就意味着接受过期结果。

### Week 2 · Chunking · Corpus · Vector Index ✅

`ChunkPipeline`（3 策略：`.block` / `.fixed(maxChars,overlap)` / `.sentence`）·
`VectorStore`（暴力余弦，精确）· `IndexState` + `IndexStateMachine` ·
`ImageTextExtractor` 协议 · `VisionImageTextExtractor`（真实 OCR，App 侧）

- **IG-1 关闭**：Vision `VNRecognizeTextRequest`，印刷体中英文，**手写不做**
  （手写中文识别质量差到会往索引里注入噪声，而噪声比缺失更糟 —— 它产生自信的错误匹配）
- **OCR 是 derived data**，存在独立 store，不放 `Block`
- **benchmark（release）**：dim 384，20k chunks → **P50 9.83 ms / P95 10.38 ms**，
  远在 SLO（P50<100ms / P95<250ms）内 → **Goal 1 不需要 ANN**
- ⚠️ 同样代码 debug 模式是 **1200 ms（122×）**。差点据此得出"暴力检索不达标"的错误结论。
  benchmark 现在只在 release 断言 SLO。

### Week 3 · 三路检索 · RRF · Excerpt · Lab ✅

`SearchHit` / `TextMatcher`（**IG-2 关闭**）· `KeywordRetriever` · `RRFFusion` ·
`RetrievalConfig` · `RetrievalService` · `ExcerptBuilder`

`App/Mosaic/DeveloperTools/`：`DeveloperModeView`(D1) · `RetrievalLabView`(D2/D3) ·
`RetrievalLabViewModel` · `RetrievalTraceView`(D4)，设置页已接入开发者入口（默认 OFF）

**关键决定**：

- **分词按空白切分 + 子串定位，不做 CJK 二元组。** 二元组会让一句自然语言 query
  蒙对几条，而按契约它**应该** keyword 零命中、全交给语义路 —— 那正是 24 屏
  「整页零高亮」要展示的产品状态。
- **RRF 而不是加权分数相加**：两路分数不可比（TF 归一分 vs 余弦），加权就是拿两把
  不同刻度的尺子拼长度。RRF 只用名次。**单路缺失 = 不贡献分数，不是罚分** ——
  所以纯语义结果能进榜。
- **不做 BM25**：IDF 需要稳定语料统计，个人笔记库小且一直变，IDF 会抖动，评测不可复现。
- 三种 mode 走**同一条管线**，只是跳过某一路 —— 三份实现会让 Compare 比出实现差异。
- **Progressive Enhancement 在检索层生效**，不依赖 UI 记得处理。

### TD-5 · 真实 embedding ✅（Week 3 之后单独做的）

`NLEmbeddingProvider`（Apple `NaturalLanguage`，zh-Hans **640 维**，完全离线，零下载）
+ `CloudEmbeddingProvider`（OpenAI 兼容 `/v1/embeddings`，供 Week 6 对照实验）

**实测**（query 与目标笔记字面几乎不重合的语料）：

```
真实 provider   Recall@1 = 0.80   Recall@3 = 1.00   MRR = 0.900
mock  provider  Recall@1 = 0.20
```

**一个被数据否掉的直觉**：`NLEmbedding` 空间高度各向异性（相关句 cos 0.944 /
无关句 0.917，只差 0.027）。按常识该做 centering，实测 **centering 反而把
Recall@1 从 1.00 降到 0.75** —— 排序只需相对次序。**没有加这一层。**
副产品约束：**余弦绝对值没有解释力**，不能当"相关度百分比"展示。

**边界**：语言编进 `version`（zh-Hans 640 维 vs en 512 维，不同空间），
**不支持跨语种检索**。拿不到本地模型时**不退回 mock**（静默退回会让 Recall
看起来正常但毫无意义）。

### Week 4 · 评测内核 ✅（UI 未做）

`Sources/MosaicKit/Eval/`：`EvalTypes`（`EvalCase` / `FailureType` 7 类 /
`EvalFailure` / `EvalMetrics` / `EvalRun` / `MetricDelta` / `EvalComparison`）·
`EvalRunner` + `RegressionSet`

**口径决定**（写死在注释里，避免以后有第二种说法）：

- **以笔记为单位计命中，不是 chunk** —— 否则长笔记凭 chunk 多而虚高
- **多个 expected 时必须全部命中** —— 宽松口径会让"找到一半"和"全找到"一样好
- **Regression Pass Rate 与 Recall@5 同口径** —— 避免两套"通过"定义
- **Eval 不下 PASS/FAIL**，只给 trade-off 一句话；判定是 Release Gate 的事
- **取消不留半份结果**（抛 `CancellationError`）—— 半份指标比没有指标危险
- P50/P95 **只统计检索本身**，不含框架、不含 UI

### Week 4 · 评测 UI ✅（D5 / D6 / D9）

`MosaicKit/Eval/EvalDataset`（Golden + Regression 同一个结构，D5 的 Dataset 选择器）

`App/Mosaic/DeveloperTools/`：`EvalDatasetStore` ·
`RetrievalEvalViewModel` · `RetrievalEvalView`(D5) · `EvalDatasetView` + `GoldenCaseEditor` ·
`EvalComparisonView`(D6) · `FailureInspectionView` + `FailureListView`(D9)

> `NoteCorpus`（Lab / Eval / 生产搜索共用的语料读取）后来移到了
> `App/Mosaic/Retrieval/` —— 它是生产层，不是 Developer Tools。

**四条工程判断**（详见 `RETRIEVAL_ARCHITECTURE.md` §14）：

1. **Golden / Regression 落在自己的 JSON 文件里，不进 derived store。**
   derived store 的契约是「可以随时清空」，而人工标注删了就得重标。
2. **没有种子数据，用例必须在设备上标。** 用例引用本机笔记 UUID，跨设备预置只会
   全都 dangling。`danglingCases` 把引用了已删笔记的用例标出来 —— 它们必然失败，
   但原因不是检索质量。
3. **评测自己建一份临时内存索引**（不落盘、不覆盖生产索引）。生产索引是按某一套
   chunk 策略建的，换策略后 chunkID 全变、vector 命中被静默丢弃 —— 那会表现成
   「换策略语义变差」。建索引耗时**不计入 P50/P95**。
4. **baseline 跑 current 那一批用例快照。** 这是在模拟器上实跑 Flow B 抓到的缺陷：
   D9 的 `Add to Regression Set` 会当场把用例数 +1，于是 D6 的 delta 里混进了
   「分母变了」，看起来像配置变差。

顺带：`RetrievalService` 的 provider 改成可选（没有模型时 vector 路整条跳过、
keyword 照常，与 `IndexState` 降级同一个出口）；并修掉 `DeveloperModeView` 在
provider 为 nil 时给 Lab 塞 `MockEmbeddingProvider()` 的既有不一致 —— 与「不退回 mock」相反。

**已在模拟器上实跑完整 Flow B**：标 Golden 用例 → Run → 六个数字 → Failed Cases →
归因 → Add to Regression Set（幂等，按钮变 `In Regression Set`）→ Compare → 四列 delta；
杀掉 App 重开，数据集仍在。

---

## 5. 当前状态

```
MosaicKit  swift run mosaic-checks        ✅ 1048 断言
           swift run -c release            ✅ 1058（多出的是 SLO 与规模断言）
App        xcodebuild test                 ✅ 80/80
Figma      node test/all.js                ✅ 5 套件全绿（本轮未改）
           devtools node test/run.js       ✅ 6/6
```

> ⚠️ **本机没有中文句向量**（2026-08-13 确认，与 iOS 26 模拟器一致）。
> 生产路线见 `EmbeddingRouter`：本机有中文模型 → 离线中文；笔记含中文且本机没有
> → 云端 `/v1/embeddings`（设置里配模型）；纯英文 → 本机英文。未配置云端时，
> 含中文的库语义关闭、关键词照常。见 TD-9。

---

## 6. 已完成与剩余

> **Week 1–6 中所有不依赖真机 / 人工标注 / 外部凭据的工作已完成。**
> 剩余项集中在 §6 末尾与 `design/GOAL1_EVIDENCE.md`。

### TD-8 已关闭 · 生产索引服务 ✅

`App/Mosaic/Retrieval/IndexingService.swift`（详见 `RETRIEVAL_ARCHITECTURE.md` §15）。
在它之前，Week 1–3 的每一块都单独测过，但**没有人把它们接起来** ——
derived store 只有测试在写，真机上索引永远是空的。

```
OCR → DerivedWorkScanner.plan → AIJobCoordinator → provider.embed
    → DerivedDataStore.commit(StaleGuard) → InMemoryVectorStore
```

**三条不变量**：

1. **内存索引只装落盘成功的向量。** 被 `StaleGuard` 拒掉的那条不能进内存索引 ——
   否则磁盘上没有的过期向量继续参与线上检索，等于把 stale protection 要防的 bug
   换个地方重演。有「嵌入进行中改内容」的用例守着。
2. **orphan 先删再写**：块被删 / 被清空 / chunk 数变少时，两处同时失效。
3. **不靠取消**：去重靠 `EmbeddingJobKey`（含 contentHash），正确性靠写入路径校验。

**触发点**：启动（先灌回落盘向量**再**扫描，顺序反了会每次冷启动重嵌全库）·
编辑后（保存之后通知，合并 + 防抖 600ms）· 删除笔记 · Developer Mode 的 `Rescan Now`。

顺带：Retrieval Lab 现在会在「选的 chunk 策略 ≠ 索引用的策略」时明确提示 ——
那种情况下 vector 命中变少**不是语义变差，是索引对不上**。

### TD-7 已关闭 · 生产搜索接入 Hybrid ✅（backlog 5.5–5.8）

`App/Mosaic/Features/Search/SearchViewModel.swift` + 重写的 `SearchView`
+ 内核 `Sources/MosaicKit/Search/SearchPresentation.swift`
（详见 `RETRIEVAL_ARCHITECTURE.md` §16，上游是 `design/SEARCH_CONTRACT.md`）。

- **隐式 Hybrid，用户侧零 mode 控件**；结果三槽位 Title · **Matched Excerpt** · Folder/Time
- **对比式前景高亮**：命中提为 primary，上下文压暗。高亮区间由检索层给出，
  UI 侧**不重新做字符串搜索** —— 否则高亮会与真实命中不一致
- **两级触发**：keyword 150ms / semantic 400ms + 长度门控（CJK≥2 / 拉丁≥3，`SemanticGate`）
- **状态条**接真实索引状态；`semanticUnavailable` 带「重试」。**I1–I5 逐条有用例**：
  没有模型、索引没建、索引建立中，keyword 结果一律照常
- **标题 / 标签**不进语料但仍然搜得到（lexical signals，补在内容命中之后）

**两处行为变更，都是契约要求的**：

1. **AI 摘要退出检索语料**（Correction 4）。以前靠摘要措辞能搜到的笔记，
   现在只能靠正文 / 转写 / OCR / 文档 / 链接 / 标题 / 标签搜到。空态文案已同步。
2. `.noResults` 在语义可用时几乎不可达 —— 见 **TD-10**（向量路没有相关性下限）。

### Week 5 已全部完成 ✅（5.1–5.4 · 5.9 · 5.10）

详见 `RETRIEVAL_ARCHITECTURE.md` **§17**。

- **5.1 配置版本化**（内核 `RetrievalConfigRegistry`）：派生只出 draft · candidate 至多一条 ·
  **生产配置没有任何编辑入口**。换掉它的唯一路径是 `promote(id:decision:)`，
  而它要求「目标是 candidate + 判定 PASS + 判定跑的就是这套配置」。
  第三条拦的是**「改完参数没重跑评测就上线」**。
- **5.2 Release Gate 内核**：四项检查，`checks.allSatisfy(\.passed)`，**不加权、不算总分**。
  没有 baseline / 两次跑批用例数不同 → **不放行**，且 detail 写明是「还没跑 baseline」
  而不是「质量下降」（补救动作完全不同）。
- **5.3 / 5.4 D7/D8 + Promote**（`ReleaseGateView` · `RetrievalConfigView` · `ReleaseStore`）：
  判定区 34pt + 四行「条件 vs 实测值」+ 失败行直达 D9 + Promote 置灰。
  Promote 成功后 `IndexingService.applyConfig` 重建索引 —— 否则 Promote 只是改了一行 JSON。
- **5.9 SLO**：Mac release 实测 20k chunks 端到端 P50 **75.85 ms** / P95 **79.54 ms**
  → 在 SLO 内，**不上 ANN**。⚠️ 真机待复测。
- **5.10 落点**：几何与时序在内核 `SearchLanding` 里逐条断言；
  `.top` 落点的 88pt 锚点是**反解出来的**，不是拍的。
  **模拟器录屏逐帧确认了 2.4s 临时高亮。**

顺带修掉一个既有缺陷：`RichMarkdownEditor` 缺 `sizeThatFits`，长文本横向铺出屏幕。
它**挡着 5.10 的验收**（块比屏幕宽时，高亮的 8pt 外扩与 12pt 圆角全被挤出屏幕）。

### Week 6 已完成可自动化的部分 ✅

实测数字见 `RETRIEVAL_ARCHITECTURE.md` **§18**，三条 Flow 的完整记录见
`design/GOAL1_EVIDENCE.md`。

**最重要的一条新发现 —— TD-11**：`NLEmbedding` 的余弦**受文本长度支配**。
同一段文字拉长 16 倍，余弦下降 0.0496；而相关 / 无关文本在同一长度上只差 0.0115
（**相差 4.3 倍**），并且存在「无关但更短」压过「相关但更长」的情形。

它一次解释了三件事：长笔记为什么天然吃亏 · TD-10 的阈值为什么不能只看余弦
（任何 `similarity > x` 都会变成隐蔽的长度过滤器）· 为什么「切到相近长度」
是**可比性**要求而不只是 recall 特性。**没有实现长度归一化** —— 那是没有 Golden Set
支撑的模型层改动，属范围扩张；改为写一条断言把现象钉住。

### ⚠️ 仍然是当前最大风险：Golden Set 规模

旧内核 checks 里那份是 **7 条 query / 8 篇笔记**，改一条用例数字就跳 0.14，
**没有统计效力**；而且只有纯文本。

2026-08-18 已重做为 `synthetic-human-v2`：**60 篇仿真人笔记 / 54 条正向 query /
10 条正式 no-result 用例**。五类语料各 12 篇且每类中英 6/6；35 条 in-scope / 19 条
cross-language；6 篇 >600 字符长文覆盖五类来源；34 篇干扰项从不作为 expected。
机器可读源在 `Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json`，方法与 release
实测在 `HUMANLIKE_GOLDEN_SET.md`，架构结论见 `RETRIEVAL_ARCHITECTURE.md` §20。

v2 已把 language / scope / no-result 接进正式 `EvalCase`、`EvalRunner` 和 Developer Tools；
Release Gate 只读 in-scope 正例，cross-language 与负例单独报告。它解决了工程 fixture 的
来源×语言×长度共线，但**仍然不是真实用户标注**，不能用于声称真实用户 Recall 提升。

标注入口已经有（D5 → Golden Set → +），但用例引用**本机笔记的 UUID**，
代码里预置不了，必须在设备上标。**Release Gate 的阈值建立在这种样本上没有意义。**
（具体规模由 PRD v1.0 决定 —— 要问用户。）

### 剩下的事：全部依赖真机 / 人工 / 外部凭据

见 `design/GOAL1_EVIDENCE.md` 的「仍待人工验证」与 `GOAL1_BACKLOG.md` 末尾的核对表。

---

## 7. 未决技术债

| ID | 内容 | 状态 |
|---|---|---|
| **TD-1** | `SummaryService` 无 stale 保护（**既有缺陷**）。捕获 `blocks` → `await` → 写回，无 job identity / dedup / 校验。今天不算数据损坏但并发生成是 last-write-wins | 开放。现在有三个可抄的用例 |
| **TD-4** | `AIJobCoordinator.acquireSlot()` 用 `withCheckedContinuation`，排队中被取消会漏一个 waiter | 开放，当前深度下无害 |
| **TD-6** | 向量索引仅在内存，启动时从 derived store 重建（20k chunks ≈ 30MB @ dim 384） | 开放 |
| **TD-10** | **向量检索没有相关性下限**：按余弦取 Top K，再离谱的 query 也会拿回整个语料 → 语义可用时 `.noResults` 几乎不可达。v2 的 10 条负例已正式接入 Runner：Keyword 10/10 空结果，Vector / Hybrid 10/10 误召回。**不能随手拍阈值** —— TD-11 证明余弦被长度混淆 | 开放；负例指标已可观测，阈值待真实 Golden Set + 模型路线 |
| **TD-11** *(new)* | **`NLEmbedding` 余弦受文本长度支配**：拉长 16 倍余弦掉 0.0496，而相关/无关只差 0.0115（4.3 倍）。长笔记天然吃亏；TD-10 的阈值因此不能只看余弦 | 开放。`RetrievalWeek6Checks.checkCosineLengthBias` 钉住现象；换模型时重测 |
| **TD-12** | ~~双语 persona 与整库单向量空间冲突~~ → **Resolved for cloud multilingual provider（D-AI-003）**。v3 实测 cross-language R@5：本地 0.128 → 云端 **0.936**。**但记录 R@1 只有 0.681**，排序仍有空间。中英双索引已被实验否决（真实路由 0.158 < baseline 0.211，作弊上界 0.421 < 同语种上界 0.619） | 云端路线已选定；**本地跨语言仍然不支持**，这是明确的产品边界 |
| **TD-13** *(new)* | **云端语义 P95 远超 Local Retrieval SLO**：实测 P50 710ms / P95 894ms vs 预算 250ms。Release Gate 因此判定 **BLOCKED**（质量三项全过，P95 一项否决） | 开放。SLO 已拆三层（§21.2）；Gate 用哪一层的 P95 需要产品显式决定，不能悄悄换数字 |
| **TD-9** | **iOS 上没有中文句向量模型**。模拟器矩阵：`zh-Hans ❌ · en ✅ 512 维`；macOS zh-Hans ✅。**2026-08-13 本机确认**。现已按语言分流：本机中文 → 离线；有中文无本机中文 → 云端 embedding；纯英文 → 本机英文。**不拿英文模型嵌中文笔记。** 云端未配置时含中文库 Gate 仍为 STALE | **已确认；云端退路已接线。** 用户需在设置填写支持 `/v1/embeddings` 的模型 |
| — | ~~`NLEmbedding` 对**长文本**的稳定性未验证~~ | **已测（§18.2/18.3）**：长文用例在三种 chunk 策略下全败，根因是 TD-11 |
| — | benchmark 是在 Mac 上用确定性向量测的，**iPhone 数字一定不同** | Week 6 真机复测 |

**已关闭**：IG-1（OCR，Week 2）· IG-2（SearchMatcher，Week 3）· IG-3（Block identity，Week 1）·
TD-5（真实 embedding）· TD-7（生产搜索接入 Hybrid + 落点）· TD-8（生产索引服务）·
文本块不换行（既有缺陷，§17.4）

---

## 8. 这个项目的工作方式（希望延续）

1. **先读代码再动手**，不假设。每轮开始前确认现状。
2. **结论必须来自测量或实读，不是直觉。** 这个项目里至少三次直觉是错的：
   centering 会更好（错）· 暴力检索不达标（是 debug 模式的锅）·
   "行高与 Row/Note 一致"（是因为文本根本没换行）。
3. **不编造数据。** 线框里的 `0.875` / `181ms` 是占位样例，文档里明确标注；
   backlog 里指标位置写"待测"而不是假数字。
4. **发现既有缺陷要报告，但不要顺手扩大改动范围。** 7 个 Figma 缺陷里 5 个是既有的，
   TD-1 至今没动 —— 因为改生产摘要行为超出了"打地基"的范围。
5. **测试要能证明退出标准，而不是刷数量。** 每条断言对应一个明确的产品/工程主张。
6. 我**不能**自己跑 Figma 插件，必须请用户跑；可以跑 `xcodebuild` 和模拟器。
