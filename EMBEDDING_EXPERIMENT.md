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

### 质量（Mac release · **v3** 数据集，114 正例 / 20 负例 · measured）

五路对照，主指标 **R@1 / MRR**（R@5 已在 v2 饱和，降为 safety-net）：

| Arm | in-scope R@1 | in-scope R@5 | in-scope MRR | cross R@1 | cross R@5 | overall MRR |
|---|---:|---:|---:|---:|---:|---:|
| Keyword | 0.343 | 0.343 | 0.343 | 0.064 | 0.085 | 0.237 |
| Local Vector | 0.104 | 0.194 | 0.146 | 0.043 | 0.064 | 0.112 |
| Local Hybrid | 0.269 | 0.418 | 0.341 | 0.085 | 0.128 | 0.247 |
| Cloud Vector | 0.851 | 1.000 | 0.930 | 0.681 | 0.936 | 0.882 |
| **Cloud Hybrid（bge-m3）** | **0.866** | **1.000** | **0.938** | **0.681** | **0.936** | **0.886** |

负例（`no-result accuracy`）：keyword **100%**，四个向量臂全是 **0%**。
TD-10 未解决之前，keyword 是唯一能表达「确实没有答案」的一路。

**两次独立跑批（不同日期、不同 API key）的质量数字逐位一致** —— 服务端 embedding
是确定性的，所以质量可复现；**延迟不可**（见下）。

> v2（54 正例）的旧表已作废：那一版云端三组全是 `R@5 = 1.000`，是评测集天花板效应。
> v3 把 cross 压到 0.936、overall 压到 0.974，主指标随之改为 R@1 / MRR。

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

> 已于 2026-08-19 全部重测：取样量 20 → **25**（20 样本时「P95」等于 max）、
> 每档之间**等热状态回 `nominal`**。**6 轮跑批，报区间。**

| 层 | 1k | 5k | 10k | 20k |
|---|---:|---:|---:|---:|
| Metric A keyword P50 / P95 | 4.48–4.68 / 8.97–9.45 | 16.84–17.54 / 23.19–24.53 | 33.27–35.93 / 42.66–46.47 | **68.72–73.32 / 89.23–98.51** |
| Metric B-local 端到端 P50 / P95 | 14.88–15.28 / 17.29–17.73 | 30.00–32.10 / 36.42–41.01 | — | **93.81–97.56 / 119.39–128.33** |
| L2b 余弦检索 P50 / P95 | 0.65–0.67 / 0.69–0.74 | 1.64–1.65 / 1.92–1.96 | 2.85–2.89 / 3.15–3.21 | **5.41–5.61 / 5.86–6.15** |

本地 query 嵌入 P50 **11.11–11.19 ms** / P95 15.75–16.24 ms。20k 向量内存 **29.3 MB**。

**方差收下来了**：20k Metric B-local 的 P50 从旧口径的 ±22% 收到 **±4%**，
P95 从 +20% 收到 **+7.5%**，且现在是真百分位而不是 20 个样本里的最差一个。
最坏 P95 **128.33 ms**，仍在 250 ms 预算内。

⚠️ **旧记录的本地 query 嵌入 6.21 / 7.99 ms 复现不了**，新值 6 轮 ±1%。
热状态、取样量、构建配置三种解释都试过且都不成立 —— **机制未查清，不编**。
详见 `RETRIEVAL_ARCHITECTURE.md` §23.6。

**反直觉**：20k 上 keyword P95 89.23–98.51 ms vs 余弦 5.86–6.15 ms —— **差 14.5–16.8 倍**。
第一批结果的延迟瓶颈是**词法路**，不是向量路。

**云端 query embedding（region `cn-shanghai`，从美国访问）— measured**

| | P50 | P95 |
|---|---:|---:|
| 网络往返 | **383.5 ms** | **1192.7 ms** |
| 解析 + 归一化 | 0.76 ms | 0.99 ms |

**网络占 99.80%。** 这个数字换服务商 / 换区域即作废，因此必须带 region 标签，
并在 `PerformanceGatePolicy` 里配为「记录但不判定」。

**云端语义 —— iPhone 真机（iPhone18,4 · iOS 27.0.0 · Release · nominal · 低电量关闭 ·
region `cn-shanghai`）— measured，3 轮 × 25 样本**

| 层 | P50（3 轮区间） | P95（3 轮区间） | max（3 轮区间） |
|---|---:|---:|---:|
| L3 网络往返 | 420.5 – 442.9 ms | 629.2 – **1075.3** ms | — |
| L3 解析 + 归一化 | 0.48 – 0.53 ms | 0.51 – 1.21 ms | — |
| L4 Hybrid 端到端（20k chunks） | 575.6 – 637.0 ms | 681.7 – **1480.7** ms | 868 – **7623** ms |

**网络占 99.87 – 99.89%**（与 Mac 侧的 99.80% 一致）。20k × 1024 维向量 = **78.1 MB**。
每轮 25 次 query 嵌入 = **149 prompt_tokens**，三轮完全一致。

**三个必须一起读的结论：**

1. **P50 可复现，尾部不可复现。** 端到端 P50 三轮落在 576–637 ms（±5%），
   而 P95 从 682 跳到 1481 ms、max 从 868 跳到 **7623 ms（8.8 倍）**。
   引用这一层请引 **P50 + 区间**，不要引单轮 P95。
2. **偶发的 7.6 秒是真的。** 一次云端语义 query 有可能花七秒多 ——
   这正是 progressive enhancement（keyword 先出结果）不是锦上添花而是必需的原因。
3. **这批数字有资格参与 perf-v2 判定**（`disqualification` 为 nil，有断言守着）。
   Mac 侧那些不行 —— 这就是它必须在真机上跑的理由。

> ⚠️ **P95 的取样量下限是 25。** `percentiles` 取 `s[min(count-1, Int(count*0.95))]`，
> `count ≤ 20` 时下标落在最后一位，「P95」退化成 max。
> 先用 10 样本测过一轮，P95 与 max 逐位相同 —— 那不是百分位，是单次最差请求。

**云端 Hybrid 端到端（Mac release · 同一 region）— measured，报区间**

| | P50 | P95 |
|---|---:|---:|
| cloud-hybrid in-scope | 400 – 721 ms | 569 – 1 485 ms |

三次跑批的**质量**数字逐位一致，**延迟** P95 却在 569–1 485 ms 之间摆。
再次印证：这一层的数字属于当天的网络，不属于这套代码 ——
**跑一次不能当定值**，且它是 Mac 数字，不能冒充真机。

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

backlog 6.1 要求「质量 / 延迟 / **成本**」三项，成本一栏此前是空的。现在补上了 ——
关键是**换了计量单位**：token 由服务端回报（`usage.prompt_tokens`），不再用
「字符数 ÷ 3.7」外推。

**同一份 v3 语料（186 chunks / 25 310 字符），Mac：**

| 项 | Local `nl-zh-Hans-r1` | Cloud `bge-m3` | 来源 |
|---|---:|---:|---|
| 建索引墙上时间 | 3 038 – 3 596 ms | **4 517 – 64 227 ms** | **measured**（5 次跑批） |
| 单 chunk | 16.3 – 19.3 ms | **24.3 – 345.3 ms** | **measured** |
| `prompt_tokens` | — | **9 720** | **measured**（服务端回报） |
| 计费 | 0（设备时间与电） | 按 token | — |

> 区间来自 5 次跑批（4 次 release + 1 次 debug），跨 3 把不同的 API key。**云端那一段与构建配置无关** ——
> 它花的是 HTTP 往返，不是本机 CPU。本地那一段 debug 3 211 ms / release 3 596 ms
> 也**不能**读成「debug 更快」（release 另有一次 3 038 ms）：本地嵌入耗时由 `NLEmbedding` 这个系统框架决定，
> 我们的代码只是在调用它，两个数字的差是噪声。

**两个必须一起读的结论：**

1. **token 稳定，墙上时间不稳定。** 五次跑批的 token 合计**每次都是 9 720**，
   而单 chunk 耗时从 24.3 跳到 345.3 ms —— 差 **14 倍**。云端建索引是**网络量**，
   不是算力量：本地那一侧 17–19 ms/chunk 稳得住，变的全在网络。
   **要引用成本就引 token；引墙上时间等于引当天的网速。**
   （与 Metric B-local 报区间同一个教训。）
2. **实测换算率 0.38 token/字符**（9 720 / 25 310），即 **≈ 2.6 字符/token**，
   而不是此前外推用的 3.7。旧的 `20k chunks ≈ 814k token` 因此偏低。

| 项 | 值 | 来源 |
|---|---|---|
| 20k chunks token 量 | ≈ **1.05M** | ***estimated*（按实测 52.3 token/chunk 线性外推）** |
| 20k chunks 全量索引耗时 | 不外推 | 底数波动 10 倍，外推没有意义 |

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
且本地 hybrid 在 20k chunks 上 P95 **119.39–128.33 ms（6 轮，真百分位）**，
**在 SLO 内**。
此前「iOS 上没有中文模型」来自模拟器（不附带 `linguisticdata` 模型资源），
是一次把**测量环境当成产品事实**的错误。

> ⚠️ 本节曾写「`EmbeddingRouter` 的默认仍是本地优先」—— **已过期**。
> 该决定已在 `f380c4f` 翻转为**云端优先**（`RETRIEVAL_ARCHITECTURE.md` §21.1）：
> 同一批 114 条 query 上本地 Hybrid 的 in-scope R@1 只有 0.269、cross R@5 只有 0.128，
> 差距不是「省一次上传」换得回来的。
> **但授权仍是硬前置**：`cloudConsentGranted` 默认 false，没同意时优先降级到本地，
> 只有本地也顶不上才返回 `.cloudNeedsConsent`。省下的那次上传由用户决定，不由默认值决定。

## Follow-up

1. **Golden Set 继续加固**：R@5 已饱和，语料要往 200+ 走，并加更强的近似干扰
2. **cross-language R@1 = 0.737** —— 排序仍有空间
3. **abstention 需要更大的 hard-negative 集**才可能校准出可发布的阈值
4. ~~**云端质量需在 v3 上复跑**~~ —— **已完成（2026-08-19）**：上表即 v3 实测，
   与 `DECISION_LOG.md` D-AI-003 里记录的数字逐位一致
5. 换到就近区域的服务商后重测网络层
6. **20k 分档的 indexing 成本仍需实测** —— 现在只有 186 chunks 这一个点

## 怎么复现

```bash
swift run -c release mosaic-checks
```

```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=<device-udid>' -allowProvisioningUpdates
```

云端相关的臂需要 `MOSAIC_LIVE_EMBEDDING_BASE / _KEY / _MODEL / _DIM`，
另可给 `MOSAIC_LIVE_EMBEDDING_REGION`（例：`cn-shanghai`）——
**延迟是地理量**，region 会跟着跑批一起进 `RunEnvironment`，不带它的云端延迟数字不可比。
**本报告不包含任何凭据**；实验用的前两个 key 均已出现在对话记录中，视为 compromised 并已撤销。

⚠️ **第三个 key（2026-08-19 本轮）同样是在对话里直接给的，因此同样 compromised，
用完请撤销。** 已经发生三次了 —— 想避免第四次，就别把 key 贴进对话：
写进一个本地文件（`chmod 600`，放在仓库外），只把**路径**说出来，跑完删掉。
`.gitignore` 已经挡住 `*.local` / `Secrets.xcconfig`，但它挡不住对话记录。
