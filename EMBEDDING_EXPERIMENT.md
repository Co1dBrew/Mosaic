# Mosaic — Embedding Provider Experiment

> **本文件只写实测数字。** 每个数字都标了来源（Mac release / iPhone 真机 / 云端 +
> region）与它是 measured 还是 estimated。凡是外推值一律标 *estimated*。
>
> 复现命令在每一节末尾。最后更新：2026-08-19

---

## Problem

目标 persona（在美国的中国学生）的笔记库**天生双语**：自己写的笔记是中文，
收到的租约 / 保单 / I-20 / Offer 是英文。

本地 `NLEmbedding` 对整个库只能用**一个**向量空间，因此中文 query 搜不到英文文档。

## Hypothesis

多语言云端 embedding 把中英映射到**同一个语义空间**，能消除跨语言差距。

## Baseline / Treatment

| | |
|---|---|
| Baseline | Apple `NLEmbedding`（`nl-zh-Hans-r1`，640 维，离线） |
| Treatment | `BAAI/bge-m3`（1024 维，OpenAI 兼容 `/v1/embeddings`，托管于 SiliconFlow） |

## Dataset

`synthetic-human-v3`（`Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json`）

| 维度 | 数量 |
|---|---:|
| 笔记 | **150**（73 target / 77 distractor） |
| 五类语料 | 各 30 篇，每类**中文 15 / 英文 15**（有断言防共线） |
| 长文（>600 字） | 6 篇，覆盖全部五类，答案埋在 40%–60% + 80% 之后 |
| 正例 query | **114** = 80 in-scope + 34 cross-language |
| 负例（应无结果） | **20** |
| 近似干扰簇 | 六份条款各异的租约 · 五封同主题不同答案的学校邮件 · 四份写着 deductible 的保险 |

> **这不是真实用户 ground truth。** 它能验证覆盖结构与算法差异，
> **不能**用来声称「真实用户 Recall 提升 x%」。

---

## Results

### 质量（Mac release · v2 数据集，54 正例）

| Mode | in-scope R@5 | cross-language R@5 | overall R@5 |
|---|---:|---:|---:|
| Keyword | 0.457 | 0.105 | 0.333 |
| Local Vector | 0.343 | 0.158 | 0.278 |
| Local Hybrid | 0.600 | 0.211 | 0.463 |
| **Cloud Hybrid（bge-m3）** | **1.000** | **1.000** | **1.000** |

**Cloud R@1 = 0.829 (in-scope) / 0.737 (cross)** —— 见下方 Interpretation，
`R@5 = 1.000` **不等于**检索完美。

### 被否决的方案：中英双索引（measured）

| 臂 | cross-language R@5 |
|---|---:|
| A 现状（单一 zh 空间 + keyword） | 0.211 |
| **B 双索引 + 双嵌入 query** | **0.158** ← 比 baseline 更差 |
| C 双索引 + 作弊路由（永远猜对） | 0.421 |
| D 语种匹配上界（同批笔记换同语种 query） | 0.619 |

机制是确定的：**中文 query 用英文模型嵌入 19/19 全部"成功"、0 条报错**，
但产出噪声向量，进 RRF 只会稀释信号。

### 相关性效应 vs 长度效应（measured）

| provider | 长度效应 | 相关性效应 | 谁主导 |
|---|---:|---:|---|
| 本地 `nl-zh-Hans-r1` | 0.0496 | 0.0115 | **长度赢 4.3 倍** |
| 云端 `bge-m3` | 0.0886 | 0.4142 | **相关性赢 4.7 倍** |

### 延迟

**iPhone 真机（iPhone18,4 · iOS 27.0 · Release · nominal · 低电量关闭）— measured**

| 层 | 1k | 5k | 10k | 20k |
|---|---:|---:|---:|---:|
| Metric A keyword P50 / P95 | 3.67 / 4.75 | 18.07 / 24.95 | 35.46 / 45.97 | **73.88 / 97.87** |
| Metric B-local 端到端 P50 / P95 | 8.20 / 9.62 | 24.96 / 31.17 | — | **92.53 / 119.30** |
| L2b 余弦检索 P50 / P95 | 0.64 / 0.70 | 1.64 / 1.93 | 2.85 / 3.16 | **5.45 / 5.86** |

本地 query 嵌入 P50 **6.21 ms** / P95 7.99 ms。20k 向量内存 **29.3 MB**。

**反直觉**：20k 上 keyword 97.87 ms vs 余弦 5.86 ms —— **差 17 倍**。
第一批结果的延迟瓶颈是**词法路**，不是向量路。

**云端 query embedding（region `cn-shanghai`，从美国访问）— measured**

| | P50 | P95 |
|---|---:|---:|
| 网络往返 | **383.5 ms** | **1192.7 ms** |
| 解析 + 归一化 | 0.76 ms | 0.99 ms |

**网络占 99.80%。** 这个数字换服务商 / 换区域即作废，因此必须带 region 标签，
并在 `PerformanceGatePolicy` 里配为「记录但不判定」。

---

## Interpretation

### `R@5 = 1.000` 不是「检索准确率 100%」

证据：

- vector-only 同样 R@5 = 1.000，但 **R@1 只有 0.737 / 0.829**
- Top-5 里 **33.3% 的位置被干扰项占着**
- `HG054` 排在第 **5** 名 —— 再多一个干扰项就掉出去

**正确结论**：*正确目标通常能被召回进 Top-5，但排序没有解决。*
**错误结论**：*检索准确率 100%。*

因此 v3 之后主指标降级：**Primary = R@1 / MRR**，R@5 降为 safety-net。

### TD-10：加固数据集推翻了上一轮的乐观读数

v3（in-scope 正例 67 / 负例 20，正例零损失约束）：

| provider | 信号 | 间隙 | 挡掉负例 | 余量 |
|---|---|---:|---:|---:|
| 本地 | 绝对下限 / **margin** / 比值 | 全部为负 | **0/20 · 0/20 · 0/20** | — |
| 云端 | 绝对下限 | −0.1689 | 2/20 | 0.0088 ⚠️ |
| 云端 | **margin** | −0.0661 | **6/20** | **0.0002** ⚠️ |
| 云端 | 比值 | −0.1517 | 2/20 | 0.0054 ⚠️ |

- v2 上「阈值 0.54 挡掉 9/10」的结论**作废**（v3 负例 10→20、语料 60→150，
  正例最低相似度 0.541→0.4413）
- 「margin 不受长度偏置影响所以更可靠」这个假设**在本地模型上完全错了**
  （正例与负例的 margin 中位数都是 0.0032）
- 云端上 margin 确实是最好的信号（6/20 vs 2/20，3 倍），方向成立，
  但余量 0.0002 **不可发布**

**状态：Improved / Calibratable，not production-resolved。**
`AbstentionPolicy.neverAbstains` 是默认值，产品行为与接入前逐位一致。

---

## Cost

| 项 | 值 | 来源 |
|---|---|---|
| v2 语料索引（96 chunks / 14 459 字符） | 4 534 ms | **measured** |
| 单 chunk 索引 | 47.2 ms | **measured** |
| 20k chunks 全量索引 | ≈ 15.7 min | ***estimated*（线性外推，非实测）** |
| 20k chunks token 量 | ≈ 814k | ***estimated*（3.7 字符/token）** |

正式 benchmark 仍需按 PRD 的 1k / 5k / 10k / 20k 分档实测 indexing time /
storage / memory / query latency。**外推值不得当作实测。**

## Privacy

云端 embedding 会把**整库**笔记正文发到第三方，且发生在启动后的后台索引里 ——
比「用户主动点一次、生成一篇摘要」重得多。

因此**不复用** AI 摘要的隐私同意，而是独立的
`hasAcceptedCloudEmbeddingNotice`（默认 false）。闸门做在**两层**：
`EmbeddingRouter` 返回 `.cloudNeedsConsent`（不是 `.cloud`），
且 `ProductionEmbedding.decide` 在该状态下**连 provider 都不构造**
—— 一个请求都发不出去。断言：`testCloudRouteRequiresExplicitConsentAndNeverBuildsProvider`。

## Decision — D-AI-003

**Cloud Semantic → Local Semantic → Keyword Only**，云端为首选，**本地保留**。

本地必须保留的实测依据：**TD-9 被真机推翻** —— iPhone 上 `zh-Hans` ✅ 640 维，
且本地 hybrid 在 20k chunks 上 P95 119.30 ms，**在 SLO 内**。
此前「iOS 上没有中文模型」来自模拟器（不附带 `linguisticdata` 模型资源），
是一次把**测量环境当成产品事实**的错误。

`EmbeddingRouter` 的默认仍是**本地优先**（「能离线做的事不该上传」）；
改成云端优先属于隐私默认值变更，需单独决定。

## Follow-up

1. **Golden Set 继续加固**：R@5 已饱和，语料要往 200+ 走，并加更强的近似干扰
2. **cross-language R@1 = 0.737** —— 排序仍有空间
3. **abstention 需要更大的 hard-negative 集**才可能校准出可发布的阈值
4. **云端质量需在 v3 上复跑**（本表云端质量数来自 v2）
5. 换到就近区域的服务商后重测网络层

## 怎么复现

```bash
swift run -c release mosaic-checks
```

```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=<device-udid>' -allowProvisioningUpdates
```

云端相关的臂需要 `MOSAIC_LIVE_EMBEDDING_BASE / _KEY / _MODEL / _DIM`。
**本报告不包含任何凭据**；实验用的两个 key 均已出现在对话记录中，视为 compromised 并已撤销。
