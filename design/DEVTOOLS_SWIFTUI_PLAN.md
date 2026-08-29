# Developer Tools — SwiftUI Implementation Plan

> 只做**职责拆分**与控件建议。不写完整代码，不重构 App architecture。
> 上游：[`DEVTOOLS.md`](DEVTOOLS.md)（IA + 逐页规格）· [`DECISION_LOG.md`](DECISION_LOG.md)

---

# 1. 总原则

| 原则 | 说明 |
|---|---|
| **原生优先** | 每一页都必须能映射到 `NavigationStack / Form / List / Section / Picker / Toggle / LabeledContent / DisclosureGroup`。**任何需要自定义绘制的地方都是设计做错了** |
| **唯一自定义视图** | 只有两处：Retrieval Lab 的结果卡片、Eval Compare 的四列行。两者内部都只有文本 |
| **不碰生产代码** | Developer Tools 是 `MosaicKit` 之上的一层只读消费者。除 `RetrievalTraceRecorder` 外，不进检索热路径 |
| **不做持久化** | 除 Golden Set / Regression Set / RetrievalConfig 三类评测侧数据外，Developer Tools 不写库 |
| **构建隔离** | 整个 Developer Tools 目录用 `#if DEBUG || INTERNAL_BUILD` 包起来。App Store 构建不含这些代码 |

---

# 2. 页面 → View / ViewModel

| 页面 | View | ViewModel | 主要控件 |
|---|---|---|---|
| 开发者节（设置内） | `AdvancedSettingsView`（既有，加一节） | 既有 | `Toggle` + `NavigationLink` |
| D1 Developer Mode | `DeveloperModeView` | **无需** | `List` + `Section` + `NavigationLink` |
| D2 Retrieval Lab | `RetrievalLabView` | `RetrievalLabViewModel` | `Form` + `Picker` ×6 + `List` |
| D3 Compare Modes | `RetrievalLabView`（同一个） | 同一个 ViewModel | `Picker` 第四态切换行渲染 |
| D4 Trace | `RetrievalTraceView` | **无需**（读 `RetrievalTraceStore`） | `List` + `Section` + `LabeledContent` |
| D5 Eval Center | `RetrievalEvalView` | `RetrievalEvalViewModel` | `Form` + `LabeledContent` + `ProgressView` |
| D6 Eval Compare | `EvalComparisonView` | 同 `RetrievalEvalViewModel` | `List` + 自定义 4 列 `HStack` |
| D7 / D8 Release Gate | `ReleaseGateView` | `ReleaseGateViewModel` | `List` + 判定 header + `.disabled()` |
| D9 Failure Inspection | `FailureInspectionView` | **无需**（传入 `EvalFailure`） | `List` + `Section` + `LabeledContent` + `Picker` |
| Retrieval Config | `RetrievalConfigView` | `RetrievalConfigViewModel` | `Form` + `Picker` ×6 |
| Regression Set 管理 | `RegressionSetView` | **无需** | `List` + `.swipeActions` |

> **五个页面不需要 ViewModel** —— 它们是纯展示，数据由上游传入或从 store 直读。
> 不要为了对称给每页配一个 ViewModel。

---

# 3. ViewModel 职责

## `RetrievalLabViewModel`

```
输入   query: String
       config: RetrievalConfig（六个可调项）
       mode: .keyword | .vector | .hybrid | .compare

输出   phase: .idle | .running | .results | .empty | .error(String)
       results: [LabResult]
       uniqueHits: (keywordOnly: [LabResult], vectorOnly: [LabResult], both: Int)
       lastTraceId: UUID?

职责   1. 调用 RetrievalService 执行一次检索
       2. 保留**三路排名**（keywordRank / vectorRank / fusedRank）而不只是最终顺序
       3. 计算 unique hit 分组
       4. 取消上一次未完成的检索
```

> **第 2 条是对检索层的要求，不只是 UI 需求**（`DECISION_LOG.md` D-UI-DEV-007）。
> `RetrievalService` 必须返回带各路排名的结构，否则 Compare Modes 无法实现。

## `RetrievalEvalViewModel`

```
输入   dataset: .golden | .regression | .both
       config: RetrievalConfig
       baseline: RetrievalConfig?

输出   phase: .idle | .running(done: Int, total: Int) | .done | .failed(String)
       metrics: EvalMetrics      // recall@1/3/5, mrr, p50, p95
       baselineMetrics: EvalMetrics?
       deltas: [MetricDelta]
       failures: [EvalFailure]

职责   1. 驱动 EvalRunner 逐 case 执行，回报进度
       2. 计算 Recall@K / MRR / P50 / P95
       3. 与 baseline 求 delta（不做判定 —— 判定是 Gate 的事）
       4. 收集失败 case
```

## `ReleaseGateViewModel`

```
输入   candidate: RetrievalConfig
       baseline: RetrievalConfig
       evalRun: EvalRun
       regressionRun: EvalRun
       thresholds: GateThresholds

输出   checks: [GateCheck]        // label, expression, actual, passed
       verdict: .pass | .blocked | .stale
       canPromote: Bool

职责   verdict = checks.allSatisfy(\.passed) ? .pass : .blocked
       —— 没有别的算法。不加权、不算总分（D-UI-DEV-008）
```

## `RetrievalConfigViewModel`

```
职责   列出版本、派生新版本、设为 candidate。
       **不允许直接编辑生产配置** —— 生产配置只能经 Release Gate 的 Promote 更换。
```

---

# 4. 需要的数据类型（新增，评测侧）

```
RetrievalConfig      version, mode, embeddingProvider, embeddingModel,
                     chunkStrategy, chunkSize, topK, fusionMethod, rrfK,
                     createdAt, promotedAt?

LabResult            noteId, blockId, sourceKind, matchedText,
                     keywordRank?, vectorRank?, fusedRank, similarity?

EvalCase             id, query, expectedNoteIds[], source(.golden/.regression),
                     addedAt, sourceFailureType?

EvalMetrics          recallAt1/3/5, mrr, p50Ms, p95Ms, caseCount

EvalFailure          case, returnedNotes[], keywordResult, vectorResult,
                     hybridResult, failureType?, diagnosisNote?

FailureType          chunking | embedding | keyword | fusion
                     | missingData | staleIndex | other

GateThresholds       recallAt5MinDelta, mrrTolerance, p95BudgetMs,
                     regressionPassRateMin

RetrievalTrace       queryText, configVersion, embeddingVersion, indexVersion,
                     stageDurations[7], chunkCount, candidateCount,
                     resultCount, contentHash, isStale
```

**全部是新增类型，不修改任何既有模型。** `Card` / `Block` / `Folder` / `AISummary` 不动 ——
Goal 1 不需要对现有数据模型做破坏性修改。

> 唯一的既有类型扩展：`Block` 需要一个稳定的 `id` 供 scroll-to-block 使用（见 IG-3）。
> 若 `Block.id` 已存在且稳定，则**零改动**。

---

# 5. 控件对照表

| 需求 | 控件 | 备注 |
|---|---|---|
| 页面容器 | `NavigationStack` | Developer Mode 起一个独立栈 |
| 入口列表 | `List` + `Section` + `NavigationLink` | D1 |
| 参数表单 | `Form` + `Picker(.menu)` | D2 / Retrieval Config |
| 指标展示 | `LabeledContent` | D4 / D5 |
| 进度 | `ProgressView(value:total:)` | D5 running |
| 四列对比 | `HStack` 固定列宽 105/74/74/74 + `.monospacedDigit()` | D6，**唯一需要对齐处理的地方** |
| Gate 判定区 | `Section` header 或 `VStack` + 背景色 | D7 / D8 |
| 禁用主按钮 | `Button(...).disabled(!canPromote)` | D8 |
| 失败类型选择 | `Picker` 绑定 `FailureType` 枚举 | D9 |
| Regression 删除 | `.swipeActions` | 管理列表 |
| 可折叠段落 | `DisclosureGroup` | Trace 的 pipeline 段（可选） |

**没有一处需要 `Canvas` / `Path` / `GeometryReader` 做绘制。**

---

# 6. 目录建议

```
Sources/MosaicKit/
├── Retrieval/                 ← 生产检索层（Week 1–3）
│   ├── RetrievalService.swift
│   ├── RetrievalConfig.swift
│   ├── ChunkPipeline.swift
│   ├── EmbeddingProvider.swift
│   ├── VectorStore.swift
│   ├── RRFFusion.swift
│   └── RetrievalTraceRecorder.swift      ← 无条件采集，<1ms
├── Eval/                      ← 评测侧（Week 4–5）
│   ├── EvalRunner.swift
│   ├── EvalMetrics.swift
│   ├── GoldenSet.swift
│   ├── RegressionSet.swift
│   └── ReleaseGate.swift
└── Search/
    └── SearchMatcher.swift    ← 需改造返回结构（IG-2）

App/DeveloperTools/            ← #if DEBUG || INTERNAL_BUILD
├── DeveloperModeView.swift
├── RetrievalLabView.swift  + RetrievalLabViewModel.swift
├── RetrievalTraceView.swift
├── RetrievalEvalView.swift + RetrievalEvalViewModel.swift
├── EvalComparisonView.swift
├── ReleaseGateView.swift   + ReleaseGateViewModel.swift
├── FailureInspectionView.swift
├── RegressionSetView.swift
└── RetrievalConfigView.swift + RetrievalConfigViewModel.swift
```

**`Retrieval/` 与 `Eval/` 属于产品本体，不包在 DEBUG 里** —— 生产搜索要用前者，
Release Gate 的阈值判定要用后者。只有 `App/DeveloperTools/` 这一层 UI 是内部构建专属。

---

# 7. 实现顺序建议

与 [`GOAL1_BACKLOG.md`](GOAL1_BACKLOG.md) 一致：

1. **Week 3** 检索三路 + RRF 跑通后，立刻做 `RetrievalLabView` —— 它是调试后续一切的工具
2. **Week 4** `EvalRunner` 跑通后做 `RetrievalEvalView` + `FailureInspectionView`
3. **Week 5** `ReleaseGateView` 最后做，它只是把已有数字摆出来

**不要先做 UI 再做检索层。** Lab 的价值完全依赖于检索层能返回三路排名；
没有那个结构，Lab 就只是一个搜索框。
