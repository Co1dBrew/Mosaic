# Mosaic — Embedding Provider Experiment

> **本文件只含实测数字。** 每个数字后面标了来源：`measured` / `extrapolated` / `待验证`。
> 复现命令在每一节末尾。所有性能数字来自 **Mac release 构建**，不是 iPhone 真机。
>
> 上游决策：[`design/DECISION_LOG.md`](design/DECISION_LOG.md) **D-AI-003**

---

## Problem

生产语义检索用的是 Apple `NLEmbedding`（本机、离线、中文 640 维）。它在**跨语言检索上失败**：
目标 persona（在美国的中国学生）的笔记库天生双语 —— 自己写的笔记是中文，收到的租约 /
保单 / I-20 / Offer 是英文。用户用中文问，答案在英文文档里。

`synthetic-human-v2` 实测：cross-language Recall@5 = **0.211**，in-scope = 0.600。

## Hypothesis

多语言 cloud embedding 把中英映射到**同一个向量空间**，从而让跨语言检索成立。

## Baseline / Treatment

| | Provider | 维度 | 部署 |
|---|---|---:|---|
| Baseline | Apple `NLEmbedding` zh-Hans (`nl-zh-Hans-r1`) | 640 | 本机离线 |
| Treatment | `BAAI/bge-m3`（经硅基流动，OpenAI 兼容 `/v1/embeddings`） | 1024 | 云端 |

两者都跑在**同一条生产管线**上（`ChunkPipeline` → `RetrievalService` → `RRFFusion`），
不是两套实现 —— 否则比出来的可能是实现差异。

## Dataset — `synthetic-human-v3`

| | v2 | **v3** |
|---|---:|---:|
| Notes | 60 | **150** |
| 每类语料 | 12（6 中 / 6 英） | **30（15 中 / 15 英）** |
| 正向 query | 54 | **114** |
| in-scope / cross-language | 35 / 19 | **67 / 47** |
| 负例（`.noRelevantResult`） | 10 | **20** |
| 干扰项（从不作为 expected） | 34 | **77** |
| 长文（> 600 字符） | 6 | 6（五类语料全覆盖） |

v3 新增的**硬用例类型**（这是加固的重点，不是数量）：

- **近似干扰簇** —— 六份条款各不相同的租约（通知期 / 宠物 / 解约 / 车位 / 押金 / 已过期）、
  四份都写 `deductible` 的保险（车险 / 租客险 / 健康险 / 牙科）
- **同主题不同答案** —— 五封都在讲毕业的学校邮件（学位授予 / OPT / 休学 / SEVIS / 典礼）
- **误导性词法重合** —— 手机与健身房合约都写着「提前解约」、共享单车写着「押金」，
  但真答案在租约里；这是 Hybrid / RRF 价值的直接测试材料
- **精确代码 / 型号 / 缩写** —— `CS5330` · `Mask R-CNN RoIAlign` · `VNB3K21099` · `CF259A`
- **模糊表达** —— 「之前问延期毕业那个事」「那个抗生素好转了能不能停」
- **跨语言四个方向** —— 中→英 · 英→中 · 混合→英 · 混合→中

> **设计原则（不做 benchmark theater）**：hard negative 必须是真实用户可能真的拥有的东西。
> 四份不同条款的租约合理；把同一句话复制 30 遍以干扰 embedding 不合理。

**它仍然是 synthetic fixture，不是真实用户 ground truth。** 不能用来声称「真实用户 Recall 提升 x%」。

## Metrics

主指标 **R@1 / MRR**；R@3 / R@5 为 secondary。R@5 从主判定指标**降级为 safety-net** ——
理由见下方 Interpretation。另测：relevance effect / length effect / no-result accuracy / 延迟。

## Results（Mac release · measured）

### 五路对照 · 150 notes / 114 queries

| arm | group | R@1 | R@3 | R@5 | MRR | P50 | P95 |
|---|---|---:|---:|---:|---:|---:|---:|
| keyword | in-scope | 0.343 | 0.343 | 0.343 | 0.343 | 1.33 ms | 2.00 ms |
| keyword | cross | 0.064 | 0.085 | 0.085 | 0.085 | 1.33 ms | 1.77 ms |
| keyword | overall | 0.228 | 0.237 | 0.237 | 0.237 | 1.33 ms | 1.91 ms |
| local-vector | in-scope | 0.104 | 0.149 | 0.194 | 0.146 | 6.58 ms | 14.30 ms |
| local-vector | cross | 0.043 | 0.064 | 0.064 | 0.062 | 7.33 ms | 16.23 ms |
| local-vector | overall | 0.079 | 0.114 | 0.140 | 0.112 | 7.05 ms | 16.23 ms |
| local-hybrid | in-scope | 0.269 | 0.373 | 0.418 | 0.341 | 8.31 ms | 18.37 ms |
| local-hybrid | cross | 0.085 | 0.128 | 0.128 | 0.113 | 8.80 ms | 16.93 ms |
| local-hybrid | overall | 0.193 | 0.272 | 0.298 | 0.247 | 8.65 ms | 18.37 ms |
| cloud-vector | in-scope | 0.851 | 1.000 | 1.000 | 0.930 | 710 ms | 903 ms |
| cloud-vector | cross | 0.681 | 0.872 | 0.936 | 0.813 | 713 ms | 956 ms |
| cloud-vector | overall | 0.781 | 0.947 | 0.974 | 0.882 | 711 ms | 913 ms |
| **cloud-hybrid** | **in-scope** | **0.866** | **1.000** | **1.000** | **0.938** | 709 ms | 894 ms |
| **cloud-hybrid** | **cross** | **0.681** | **0.872** | **0.936** | **0.813** | 711 ms | 835 ms |
| **cloud-hybrid** | **overall** | **0.789** | **0.947** | **0.974** | **0.886** | 710 ms | 894 ms |

### 负例（20 条 `.noRelevantResult`）

| arm | no-result accuracy | false-positive rate |
|---|---:|---:|
| keyword | **100.0%** | 0.0% |
| local-vector | 0.0% | 100.0% |
| local-hybrid | 0.0% | 100.0% |
| cloud-vector | 0.0% | 100.0% |
| cloud-hybrid | 0.0% | 100.0% |

### Relevance effect vs length effect

| | 长度效应 | 相关性效应 | 谁占主导 |
|---|---:|---:|---|
| Local `nl-zh-Hans-r1` | 0.0496 | 0.0115 | **长度赢 4.3 倍** |
| Cloud `bge-m3` | 0.0886 | 0.4142 | **相关性赢 4.7 倍** |

### RRF 是否仍有价值（Cloud Vector vs Cloud Hybrid，逐条 114 条）

```
Hybrid 胜 1 · Vector 胜 0 · 持平 113
唯一的胜例：HG025「lease termination 30 calendar days」 V#2 → H#1
exact 类 R@1：vector 20/21 → hybrid 21/21
```

**§12 的假设被部分证伪**：`bge-m3` **自己就把精确代码全部排到第 1**（`CS5330` · `Mask R-CNN
RoIAlign` · `VNB3K21099` · `CF259A` 全部 rank 1）。RRF 不是靠保护 exact code 产生价值的。

但 RRF **保留**，三条理由都是实测的：

1. **从不变差**（1 胜 0 负 113 平），成本只有 1.33 ms；
2. **对本地 fallback 是决定性的**：local-vector R@1 0.079 → local-hybrid 0.193（+144%）；
3. **keyword 是唯一有 no-result 能力的一路**（100% vs 0%）。RRF 是它进入结果的通道。

## Interpretation — R@5 = 1.000 **不是**「检索完美」

v2（60 篇）上云端三组 R@5 全部 1.000。v3 加固后：**in-scope 仍是 1.000，但 cross 降到 0.936、
overall 降到 0.974** —— 说明 v2 的满分是**评测集天花板**，不是检索能力。

正确结论：**正确目标通常能被召回进 Top-5，但排序尚未解决**（overall R@1 只有 0.789）。
错误结论：Retrieval accuracy is 100%。

因此主判定指标改为 **R@1 / MRR**，R@5 降级为 safety-net。in-scope R@5 至今仍饱和，
下一轮若要继续区分模型，in-scope 还需要更强的干扰。

## Cost

| 项 | 数值 | 来源 |
|---|---:|---|
| 云端建索引（v3 全量） | 186 chunks / 25,310 字符 / **6,211 ms** = **33.4 ms per chunk** | **measured** |
| 20k chunks 建索引 | ≈ 11 分钟 | **linear extrapolation，不是 measured** |
| v3 全量 token | ≈ 6.8k token（按冒烟测得 3.7 字符/token 折算） | **estimated** |
| 20k chunks token | ≈ 81 万 token | **extrapolated** |

> 正式规模 benchmark 仍需按 PRD 在 1k / 5k / 10k / 20k 上分别测
> indexing time · storage · memory · query latency。**外推值不得冒充实测值。**

## Privacy

云端语义意味着**整库笔记正文**通过 HTTPS 发给第三方 embedding provider，
而且发生在启动后的后台索引里 —— 比「用户主动点一次、生成一篇摘要」重得多。

产品条件（已实现，见 `RETRIEVAL_ARCHITECTURE.md` §19.2）：

1. 用户显式配置 provider（Base URL / 模型 / 维度）
2. 有效 API Key（Keychain）
3. **独立的云端语义同意开关**，默认 OFF，可撤销 —— **不复用摘要的 AI 隐私同意**
4. 闸门在唯一构造点 `makeCloudEmbeddingProvider()`，未授权时**连 provider 都不构造**
5. 未授权 + 本地顶得上 → 静默用本地，不打扰；只有本地顶不上才请求授权

**与 Summary 的隐私边界差异（gap，已登记）**：摘要是单篇、用户触发、前台；
语义索引是全库、系统触发、后台。所以用了独立同意项而非复用。

## Decision

见 `design/DECISION_LOG.md` **D-AI-003**：Cloud preferred（已授权时）+ Local fallback +
Keyword final fallback。**不删除 Local。不简单替换默认模型。**

**Release Gate 当前判定：`PROMOTION BLOCKED`**

```
✅ Recall@5   1.000    要求 ≥ 0.418
✅ MRR        0.938    要求 ≥ 0.331（baseline 0.341 − 容差 0.010）
❌ P95        787 ms   要求 ≤ 250 ms
✅ Regression 100%     要求 ≥ 98%（回归集为空）
```

质量三项全过，**P95 一项否决**。这正是 D-UI-DEV-008 的意义：不做加权总分，
「大部分指标都很好」换不来放行。

## Follow-up

1. **P95 是唯一阻断项** → 需要产品决定分层 SLO 的口径（§21.2）或压低网络延迟
2. **in-scope R@5 仍饱和** → 下一轮需要更强的 in-scope 干扰
3. **TD-10 未解决**：v3 上最佳阈值 0.595 挡掉 19/20 负例，但**丢掉 7/67 正例**
4. **真机全部待验证**：iPhone 上的 provider 可用性、延迟、索引耗时

## 怎么复现

```bash
MOSAIC_LIVE_EMBEDDING_BASE=... MOSAIC_LIVE_EMBEDDING_KEY=... MOSAIC_LIVE_EMBEDDING_MODEL=BAAI/bge-m3 MOSAIC_LIVE_EMBEDDING_DIM=1024 swift run -c release mosaic-checks
```

不带环境变量时本地三路照常跑，云端两路标为「待验证」，checks 不会因此变红。
