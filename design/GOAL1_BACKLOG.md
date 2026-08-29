# Goal 1 — Engineering Backlog（6 Week）

> 上游：**Mosaic AI Retrieval Quality Platform PRD v1.0**
> 设计侧依赖：[`SEARCH_CONTRACT.md`](SEARCH_CONTRACT.md)（Production，RE-FROZEN）·
> [`DEVTOOLS.md`](DEVTOOLS.md)（Developer Tools）· [`DEVTOOLS_SWIFTUI_PLAN.md`](DEVTOOLS_SWIFTUI_PLAN.md)
>
> **本文件不含任何编造的实测数据。** 所有指标位置写的是「待测」，不是假数字。
> 设计稿里出现的 `0.875` / `181ms` 等是**线框占位样例**，不得当作基线。

标记：`P0` = 该周必须完成，否则后续周阻塞 · `P1` = 该周应完成，可顺延一周

---

# Week 1 — Runtime Foundation

**主题**：把 AI 任务的执行、去重、取消、重试、过期保护这条底座立起来。检索还没开始。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 1.1 | `EmbeddingProvider` 协议（`embed([String]) async throws -> [[Float]]`，带 `modelId` / `dimension`） | P0 | — | 协议定稿；`FakeEmbeddingProvider` 可用于单测 |
| 1.2 | Local / Cloud 两个实现的抽象与切换 | P0 | 1.1 | 可在配置里切换；Cloud 不可用时抛明确错误类型（不是通用 Error） |
| 1.3 | `AIJobCoordinator`：串行队列 + 并发上限 | P0 | — | 同一时刻嵌入任务不超过配置上限；单测覆盖 |
| 1.4 | **去重**：同一 `(blockId, contentHash)` 的在途任务合并 | P0 | 1.3 | 连续提交 100 个相同任务，实际只执行 1 次 |
| 1.5 | **取消**：笔记被删 / App 退后台 / 新任务取代旧任务 | P0 | 1.3 | 取消后不再写入任何结果；单测覆盖竞态 |
| 1.6 | **重试**：指数退避，区分可重试（网络 / 429）与不可重试（401 / 400） | P0 | 1.3 | 401 不重试；网络错误按退避重试至上限 |
| 1.7 | `AIContentHash`：block 内容 → 稳定 hash | P0 | — | 同内容同 hash；改一个字符 hash 变化；对 text / transcript / OCR / 文档提取 / 链接元数据均适用 |
| 1.8 | **Stale protection**：写回结果前校验 `contentHash` 未变 | P0 | 1.7 | 在嵌入进行中修改内容 → 旧结果被丢弃，不污染索引。**单测必须覆盖这条竞态** |
| 1.9 | `RetrievalTrace` 数据结构 + `RetrievalTraceRecorder` 骨架 | P1 | — | 结构定稿；采集开销 < 1ms（用 `XCTMeasure` 验证） |
| 1.10 | **IG-3 核实**：`NoteView` 的 block 是否已有稳定唯一 `.id()` | P0 | — | 给出结论；若无，补上稳定 id（这是 Result→Note 的硬前置） |

**Week 1 出口**：能对任意一批文本稳定地产出向量，且任务被打断 / 内容被改时不会留下脏数据。

---

# Week 2 — Chunking & Embedding Lifecycle

**主题**：把五类语料变成可检索的 chunk，并建立索引的生命周期。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 2.1 | `ChunkPipeline`：block → chunks（策略：Block / Block+字数上限 / Sentence） | P0 | 1.7 | 三种策略可切换；chunk 携带 `blockId` + 字符 offset |
| 2.2 | **Text block** 抽取 | P0 | 2.1 | 富文本标记不进入 chunk 文本 |
| 2.3 | **Audio transcript** 抽取 | P0 | 2.1 | 复用既有转写结果，不重新转写 |
| 2.4 | **Document extracted text** 抽取 | P0 | 2.1 | PDF 走 PDFKit；超长按策略截断并标记 |
| 2.5 | **Link** title / description / extracted text 抽取 | P0 | 2.1 | 无描述时退化为 title + URL |
| 2.6 | **Image OCR**（**IG-1，当前代码完全没有**） | P0 | 2.1 | Vision `VNRecognizeTextRequest` 中英文；产出文本进入 chunk。**Golden Set 必须有 OCR case** |
| 2.7 | Embedding lifecycle：新增 / 修改 / 删除 block 时的索引增量维护 | P0 | 1.8, 2.1 | 删除 block → 其 chunk 与向量一并清除；无孤儿 |
| 2.8 | 本地向量存储 | P0 | 2.7 | 持久化；App 重启后索引仍可用 |
| 2.9 | 暴力余弦检索 | P0 | 2.8 | 正确性优先；先不做 ANN |
| 2.10 | 索引状态机：`ready / building / rebuilding / stale / failed` | P0 | 2.7 | 状态可被 UI 订阅（`Bar / Search Status` 的四态直接映射） |
| 2.11 | Benchmark：1k / 5k / 20k chunk 下的检索耗时 | P1 | 2.9 | 产出真实 P50 / P95 数字，**用于确定 ANN 是否必要** |

**Week 2 出口**：全部五类语料可被索引；索引能增量维护且不产生孤儿；有真实的规模-延迟曲线。

> **2.6 是本周风险最高的一项** —— 它是从零开始，且 PRD 要求 Golden Set 覆盖 OCR case。
> 若进度紧张，OCR 可以只支持中英文印刷体，手写体明确不支持。

---

# Week 3 — Retrieval & Lab

**主题**：三路检索 + 融合跑通，并立刻做出调试它的工具。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 3.1 | **改造 `SearchMatcher`**（IG-2）：`Bool` → 带 range / blockId / score 的结果 | P0 | — | 返回 `SearchHit`；既有 `SearchChecks` 全绿 |
| 3.2 | Keyword retrieval：分词 + 打分 + 排名 | P0 | 3.1 | 返回 `keywordRank`；中英文分词口径写进注释 |
| 3.3 | Vector retrieval：query embedding + 余弦 Top K | P0 | 2.9 | 返回 `vectorRank` + `similarity` |
| 3.4 | **RRF 融合**（k=60 默认） | P0 | 3.2, 3.3 | 返回 `fusedRank`；单测覆盖「单路缺失」的情形 |
| 3.5 | `RetrievalService` 统一入口，**同时返回三路排名** | P0 | 3.4 | 这是 Compare Modes 的硬前置（D-UI-DEV-007） |
| 3.6 | `RetrievalConfig` 结构 + 六个可调项 | P0 | 3.5 | 与 `DEVTOOLS.md` §4.2 的 Picker 一一对应 |
| 3.7 | **Retrieval Lab**（D2） | P0 | 3.5, 3.6 | 能跑 query、切配置、看三路排名证据 |
| 3.8 | **Compare Modes**（D3） | P0 | 3.7 | unique hit 分组正确 |
| 3.9 | Trace 接入真实管线（D4） | P0 | 1.9, 3.5 | 七段耗时 + 四项 index metadata 真实；`contentHash` 一致性判定可用 |
| 3.10 | `ExcerptBuilder` 纯函数 + 单测 | P0 | 3.1 | `SEARCH_CONTRACT.md` W1–W7 每条一个用例 |

**Week 3 出口**：能对任意 query 解释「为什么是这个排名」，并看到耗时落在哪一层。

---

# Week 4 — Evaluation

**主题**：从「感觉更好」变成「量化更好」。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 4.1 | Golden Set 数据结构 + 种子数据 | P0 | — | 覆盖五类语料（含 **OCR case**）与两类 query（精确 / 自然语言）。规模待定，**不预设 40** |
| 4.2 | `EvalRunner`：逐 case 执行 + 进度回报 + 可取消 | P0 | 3.5, 4.1 | 中途取消不留半份结果 |
| 4.3 | Recall@1 / @3 / @5 | P0 | 4.2 | 口径写进注释：全部 expected 落在 Top K 即命中 |
| 4.4 | MRR | P0 | 4.2 | 单测覆盖「无命中」= 0 |
| 4.5 | P50 / P95 延迟统计 | P0 | 4.2 | **不含 UI 动画**，只统计检索本身 |
| 4.6 | **Eval Center**（D5） | P0 | 4.3–4.5 | 六个数字 + 失败入口 |
| 4.7 | **Config Comparison**（D6） | P0 | 4.6 | Current / Baseline / Delta；质量与延迟同屏 |
| 4.8 | `EvalFailure` 收集 + **Failure Inspection**（D9） | P0 | 4.2 | 七类 `FailureType`；两个入口同一个 View |
| 4.9 | `RegressionSet` + `Add to Regression Set` | P0 | 4.8 | 与 Golden Set 同构；幂等 |
| 4.10 | Eval 自动同时跑 Golden + Regression | P0 | 4.9 | Pass Rate 与 Recall@5 同口径 |

**Week 4 出口**：能回答「retrieval-vX 比 vY 好还是差、代价是什么」，且失败可归因、可沉淀。

---

# Week 5 — Release Gate & Production Integration

**主题**：把评测结果变成上线判定，并把语义检索接进生产搜索。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 5.1 | `RetrievalConfig` 版本化 + 派生 + candidate 标记 | P0 | 3.6 | 生产配置只能经 Promote 更换 |
| 5.2 | `GateThresholds` + 四项检查 | P0 | 4.7, 4.10 | 阈值可配；判定 = `allSatisfy`，无加权（D-UI-DEV-008） |
| 5.3 | **Release Gate**（D7 / D8） | P0 | 5.2 | 进入 2 秒内可答「能不能上 / 为什么不能」；失败行直达 D9 |
| 5.4 | `Promote to Production` | P0 | 5.1, 5.3 | 仅在全 PASS 时可用；写入 `promotedAt` |
| 5.5 | **生产搜索接入 Hybrid** | P0 | 3.5 | 隐式 Hybrid，用户侧无 mode 控件 |
| 5.6 | **两级防抖 + 取消**（keyword 快通道 / semantic 慢通道） | P0 | 5.5 | 初值见 `SEARCH_CONTRACT.md` §1.2；**最终值由 5.9 的 SLO 实测决定** |
| 5.7 | **Progressive Enhancement 降级**：semantic 不可用 → keyword 照常 | P0 | 5.5, 2.10 | I1–I5 五条不变量逐条单测 |
| 5.8 | `Bar / Search Status` 四态接入真实索引状态 | P0 | 2.10, 5.7 | building / rebuilding / degraded / offline |
| 5.9 | **SLO 验证**：P50 < 100ms · P95 < 250ms（不含 UI 动画） | P0 | 5.5 | 未达标则回到 2.11 决定是否上 ANN |
| 5.10 | Result → Note 落点行为 | P0 | 1.10, 3.10 | 四类命中位置各自正确；2.0s + 0.4s 临时高亮 |

**Week 5 出口**：坏配置上不了线；用户能用上语义搜索，且 AI 层失效时搜索仍然可用。

---

# Week 6 — Experiment, Hardening & Evidence

**主题**：把结论做实，把故事讲清。

| # | 任务 | P | 依赖 | Definition of Done |
|---|---|---|---|---|
| 6.1 | Local vs Cloud embedding 对比实验 | P0 | 4.7 | 同一 Golden Set 下的质量 / 延迟 / 成本三项对比，**产出真实数字** |
| 6.2 | Chunk 策略对比实验 | P0 | 4.7 | 三种策略的 Recall@5 对比 |
| 6.3 | 规模 benchmark 复测 | P1 | 2.11 | 索引规模增长后的 P95 曲线 |
| 6.4 | **Staleness 实验** | P0 | 1.8 | 构造「改内容不重建索引」场景，证明 stale 检测生效且结果不被污染 |
| 6.5 | Regression 长期跑 | P1 | 4.10 | 至少一次「新配置引入 regression → Gate 拦截」的完整记录 |
| 6.6 | VoiceOver / Dynamic Type（生产搜索） | P1 | 5.10 | 结果行朗读顺序：标题 → 来源 → 命中片段 → 文件夹 → 时间 |
| 6.7 | 文档收口 | P0 | — | 把实测数字回填进各文档，替换线框占位样例 |
| 6.8 | **Portfolio evidence** | P0 | 6.1–6.5 | 三条 Flow 的完整记录：User Search / Developer Investigation / Failure→Blocked |

**Week 6 出口**：每个设计决定背后都有一个实测数字，而不是一句「感觉更好」。

---

# 跨周风险登记

| 风险 | 周 | 应对 |
|---|---|---|
| **OCR 从零开始**（IG-1） | W2 | 只支持中英文印刷体；手写体明确不做 |
| **`SearchMatcher` 改造牵动既有搜索**（IG-2） | W3 | 先补齐既有 `SearchChecks`，改造后必须全绿 |
| **block `.id()` 可能不稳定**（IG-3） | W1 | 第一周就核实，不要拖到 W5 |
| **暴力余弦在大库下超 SLO** | W2/W5 | 2.11 的 benchmark 决定是否上 ANN；ANN 属**范围扩张**，需先确认 |
| **Golden Set 规模不足以支撑统计判断** | W4 | 规模由 PRD 决定；不足时优先扩 case 而不是调阈值 |

---

# 与设计文档的对应

| Backlog | 设计依据 |
|---|---|
| 3.10 / 5.5–5.8 / 5.10 | [`SEARCH_CONTRACT.md`](SEARCH_CONTRACT.md)（RE-FROZEN） |
| 3.7 / 3.8 / 3.9 | [`DEVTOOLS.md`](DEVTOOLS.md) §4.2 / §4.3 / §4.4 |
| 4.6 / 4.7 / 4.8 / 4.9 | §4.5 / §4.6 / §5 / §6 |
| 5.2 / 5.3 | §4.7 |
| 全部 View / ViewModel 拆分 | [`DEVTOOLS_SWIFTUI_PLAN.md`](DEVTOOLS_SWIFTUI_PLAN.md) |

---

# 完成状态逐项核对（2026-08-10）

> 口径：**DoD 全部满足且有自动断言守着** = ✅ ·
> **实现完成但某一条 DoD 只能靠真机 / 人工确认** = ⚠️ ·
> **未做** = ❌。数字一律来自实跑，见 `RETRIEVAL_ARCHITECTURE.md` §18 与
> `design/GOAL1_EVIDENCE.md`。

## Week 1–4

| # | 状态 | 备注 |
|---|---|---|
| 1.1–1.10 | ✅ | Week 1 全部关闭；IG-3 已核实（block 有稳定 id，5.10 直接用上了） |
| 2.1–2.10 | ✅ | 五类语料 · 增量维护无孤儿 · 索引状态机 |
| 2.11 | ✅ | 曲线已产出（§18.1）；**iPhone 真机已复测**：1k/5k/10k/20k 四档 · 25 样本 · 6 轮区间（§21.3–21.4） |
| 3.1–3.10 | ✅ | 三路检索 · RRF · Lab / Compare / Trace · Excerpt W1–W7 |
| 4.1 | ⚠️ | 真人集结构 ✅；**真实种子数据刻意不做**（用例引用本机笔记 UUID，跨设备预置必然 dangling）。另有 synthetic-human-v2：60 notes / 54 positive / 10 no-result，用于工程回归，不能替代真人标注 |
| 4.2–4.5 | ✅ | 口径写死在注释里：以笔记计 · 多 expected 全命中 · 取消不留半份 · P50/P95 只算检索 |
| 4.6–4.10 | ✅ | D5 / D6 / D9 · Regression 幂等 · Pass Rate 与 Recall@5 同口径 |

## Week 5

| # | 状态 | DoD 核对 |
|---|---|---|
| 5.1 | ✅ | `RetrievalConfigRegistry`：派生只出 draft · candidate 至多一条 · **生产配置没有任何编辑入口**，只能经 `promote`。版本号自增不复用 |
| 5.2 | ✅ | `GateThresholds` 四项可配；判定 = `checks.allSatisfy(\.passed)`，**无加权**。边界用例见 §Flow C |
| 5.3 | ✅ | D7/D8：34pt 判定区 + 四行「条件 vs 实测值」+ 失败行红底 + `Open Failures ›` 直达 D9。模拟器实拍确认「2 秒内答出能不能上 / 为什么不能」 |
| 5.4 | ✅ | `Promote to Production` 仅全 PASS 可用（UI 置灰 **且** 注册表拒绝）；写入 `promotedAt`；顺带 `IndexingService.applyConfig` 重建索引 |
| 5.5 | ✅ | 隐式 Hybrid，用户侧无 mode 控件；禁用词表有断言 |
| 5.6 | ✅ | keyword 150ms / semantic 400ms + `SemanticGate` 长度门控；**最终值仍取初值** —— 5.9 实测远快于人的输入停顿，没有调大的理由 |
| 5.7 | ✅ | I1–I5 逐条单测 |
| 5.8 | ✅ | 四态接真实 `IndexState`，一处映射 `RetrievalCapability.derive` |
| 5.9 | ✅ | **真机 release 实测**：20k 端到端 P50 45.69 / P95 66.07 ms，预算余量 3.8× → 不上 ANN（§21.4、§24.5） |
| 5.10 | ⚠️ | 五类落点分派 · 88pt 锚点反解 · 2.0s+0.4s 高亮 · 可中断 · anchor 失效安静退化，全部有断言；**高亮已在模拟器录屏逐帧确认**。滚动与转写展开需要长笔记 / 音频笔记，**待人工验证** |

## Week 6

| # | 状态 | DoD 核对 |
|---|---|---|
| 6.1 | ✅ | 三项齐了（§23）：质量 = v3 五路实测（cloud-hybrid in-scope R@1 **0.866** vs local **0.269**）；延迟 = 报区间的 Mac 端到端 + 真机 Metric A/B-local；成本 = 服务端回报的 `prompt_tokens` **9 720 / 186 chunks**（measured，非字符外推）。⚠️ 云端墙上时间三次跑批差 10 倍，**只引 token 不引耗时** |
| 6.2 | ✅ | 三种策略实测（§18.2）。**结论是「换切分解决不了这批用例」**，追因产出 TD-11 |
| 6.3 | ✅ | 1k/5k/10k/20k 曲线 ✅ Mac + **真机 6 轮区间**（25 样本，等热状态，§23.6）|
| 6.4 | ✅ | 改内容不重建索引 → 过期结果被丢弃 + 写入路径拒收 + 状态如实降级 |
| 6.5 | ✅ | 「新配置引入 regression → Gate 拦截」完整记录，全部由断言守着 |
| 6.6 | ⚠️ | 朗读**内容与顺序**有断言；**真机 VoiceOver / Dynamic Type 主观验证待做** |
| 6.7 | ✅ | 实测数字已回填 `RETRIEVAL_ARCHITECTURE.md` §18；线框占位样例（0.875 / 181ms）仍只出现在**设计文档**里，且已标注为占位 |
| 6.8 | ✅ | `design/GOAL1_EVIDENCE.md`，三条 Flow |

## 仍然开放的风险（不是「没做完」，是「需要外部输入」）

| 风险 | 说明 |
|---|---|
| **Golden Set 规模** | 工程 fixture 已扩成 synthetic-human-v2（60 notes / 54 positive / 10 no-result，五类来源内中英平衡并含长文、干扰项），但它不是实际用户 ground truth。**Release Gate 的产品阈值仍不能建立在 synthetic 样本上。** 标注入口已有（D5 → Golden Set → +），本机 UUID 必须在设备上标；正式规模由 PRD v1.0 决定 |
| **跨语言架构选择** | synthetic v2 实测 Hybrid Recall@5：in-scope 0.600 / cross-language 0.211。需在云端多语言、双索引、明确不支持三者中做产品选择；选择前 cross-language 单独报告且不进 Gate |
| **TD-9 · iOS 无 zh 句向量模型** | 模拟器实测 `zh-Hans ❌ · zh-Hant ❌ · ja ❌ · en ✅ 512维`；macOS 上 zh-Hans ✅ 640维。**2026-08-13 本机 App 确认不可用**（Provider 文案与降级契约一致）。iOS 上只有 keyword 路可评测，生产配置是 hybrid → 那些设备上 Gate 恒为 STALE（这是对的） |
| **TD-11 · 余弦受长度支配** | 新发现，见 §18.3。它同时决定了 TD-10 的阈值不能只看余弦 |
| **真机性能** | 全部数字来自 Mac |
| **Track B 线框视觉验证** | 需要在 Figma 里选中 `🔧 Dev Tools (Wireframe)` 页才能 MCP 实读 |
