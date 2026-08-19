# Mosaic Human-like Golden Set · synthetic-human-v2

> **这是仿真人场景的工程候选集，不是真实用户标注数据。**
> 它能暴露实验设计与检索管线问题，不能用于声称“真实用户 Recall 提升 x%”。

机器可读源：
[`Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json`](Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json)

## v2 为什么重做

v1 的采集态度是对的：诚实标注、低词法泄漏、失败不回改。但 20 篇语料把三个变量绑在
一起：Text / Transcript 几乎全中文，OCR / Document 几乎全英文，而且正文都很短。
所以 v1 的 overall Hybrid Recall@5 `0.571` 无法归因：看不出差异来自 source、language
还是 length。

v2 的目标只有一个：**让来源、语种、长度和检索范围可以分别观察。**

## 数据组成

| 项目 | v2 |
|---|---:|
| Synthetic notes | 60 |
| Positive queries | 54 |
| In-scope positive | 35 |
| Cross-language positive | 19 |
| No-result queries | 10 |
| 长文（正文 > 600 字符） | 6 |
| Distractors | 34 |

五类来源各 12 篇，每一类都是中文 6 / 英文 6：

| Source | 中文 | 英文 | 长文 |
|---|---:|---:|---:|
| Text | 6 | 6 | 2 |
| Image OCR | 6 | 6 | 1 |
| Audio transcript | 6 | 6 | 1 |
| Document extracted text | 6 | 6 | 1 |
| Link metadata | 6 | 6 | 1 |

6 篇长文都提供两条专项 query：一条答案在正文 40%–60%，另一条在 80% 之后。
默认 `fixed(240/40)` 因此会产出多个 chunk，不再出现“三种策略其实切出同一批文本”的假实验。

34 篇干扰项从不作为 expected，其中明确包含：三篇其他搬家记录、第二份 60 天通知租约、
第二张停车牌、三篇其他产品会议。它们让 Recall@1 真正考验排序，而不只是“库里有没有”。

## 标签与 Gate 口径

每条正例都有：

- `queryLanguage`: `zh | en | mixed`；
- `expectedLanguage`: 由 expected note 推导并写死；
- `scope`: `in-scope | cross-language`；
- `style`: `exact | natural | mixed`；
- 长文专项另有 `longRegion: middle | end`。

核心 `EvalCase`、`EvalRunner` 与 Developer Tools 已支持同一套 language / scope 字段。
Runner 同时产出 overall、in-scope 与 cross-language 指标；**Release Gate 和 Eval Compare
只读取 in-scope 正例**。Cross-language 继续展示，但在产品选择多语言云模型、双索引或明确
不支持之前，不拿已知边界惩罚每次配置实验。

旧设备数据没有这些字段时会迁移为 `.inScope`，维持升级前行为；新建 Golden Case 时编辑器
要求选择 query / expected language，并据此确定 scope。

## 无结果期望

10 条负例已通过正式模型进入同一个 Runner：

```swift
enum EvalExpectation {
    case relevant(noteIDs: [String])
    case noRelevantResult
}
```

负例只有 `results.isEmpty` 才通过；它们不进入 Recall / MRR 分母。新增指标：

- `noResultAccuracy`：正确返回空列表的负例数 / 负例总数；
- `falsePositiveRate`：`1 - noResultAccuracy`。

这两项会显示在 Eval Center，但**暂不进入 Release Gate**。在 TD-10 的相关性下限落地前，
不把任意相似度阈值伪装成“无结果”判断。

## Mac release 实测（2026-08-18）

真实 Apple `NLEmbedding`，默认 `fixed(240/40)`，60 篇 synthetic notes。延迟是 Mac
release 数字，不是 iPhone 真机结论。

| Mode | Group | Recall@1 | Recall@3 | Recall@5 | MRR | P95 |
|---|---|---:|---:|---:|---:|---:|
| Keyword | in-scope | 0.457 | 0.457 | 0.457 | 0.457 | 0.83 ms |
| Keyword | cross-language | 0.053 | 0.105 | 0.105 | 0.105 | 0.89 ms |
| Keyword | overall | 0.315 | 0.333 | 0.333 | 0.333 | 0.87 ms |
| Vector | in-scope | 0.143 | 0.200 | 0.343 | 0.226 | 9.44 ms |
| Vector | cross-language | 0.105 | 0.105 | 0.158 | 0.145 | 9.69 ms |
| Vector | overall | 0.130 | 0.167 | 0.278 | 0.197 | 9.44 ms |
| Hybrid | in-scope | **0.429** | **0.486** | **0.600** | **0.494** | 9.21 ms |
| Hybrid | cross-language | 0.105 | 0.158 | 0.211 | 0.171 | 9.80 ms |
| Hybrid | overall | 0.315 | 0.370 | 0.463 | 0.381 | 9.21 ms |

负例结果：

| Mode | No-result Accuracy | False-positive Rate |
|---|---:|---:|
| Keyword | 100% | 0% |
| Vector | 0% | 100% |
| Hybrid | 0% | 100% |

这批数据支持三个工程结论：

1. 分组后，Hybrid in-scope Recall@5 `0.600`，cross-language 只有 `0.211`；整库单一
   向量空间不能把这个差异解释成普通调参问题。
2. 干扰项与长文加入后，overall Hybrid Recall@5 从 v1 的 `0.571` 降到 `0.463`；
   v1 的小库和均匀短文本确实偏乐观。
3. Vector / Hybrid 对负例 10/10 全部误召回，TD-10 已从推测变成可重复证据。

这些仍然只是 synthetic fixture 的结论，不等同于真人质量结果。

## 自动保护

`HumanLikeGoldenChecks` 会阻止以下回退：

- 每类 source 的中英数量差必须 ≤ 1；
- 至少 6 篇正文 > 600 字符，且每类 source 至少一篇长文；
- 长文中段锚点必须位于 40%–60%，末段锚点必须位于 80% 之后；
- 每篇长文必须各有一条 middle / end query；
- scope 必须与 query / expected language 推导一致；
- 每条 exact query 的空格分词必须真的存在于 expected note；
- 干扰项不能出现在任何 expected 中；
- 负例必须是 `.noRelevantResult`；
- 旧 `expectedNoteIDs` JSON 可迁移读取；
- Gate 必须只用 in-scope 正例，不能被 cross-language 或负例拖动。

复现：

```bash
swift run mosaic-checks
swift run -c release mosaic-checks
```

## 变成正式 Golden Set

1. 在真机准备真实或脱敏笔记，覆盖五类来源、两种语言、短文与长文；
2. 在 Developer Mode → Retrieval Eval → Golden Set 中添加 query，先判断相关性再跑排名；
3. 选择 query / expected language；无答案时开启“这条 query 不该有结果”；
4. 不根据当前系统返回结果修改 expected；
5. 由第二个人盲审一部分标签，保留分歧记录；
6. 真实集和 synthetic fixture 分开报告，绝不合并成一个“用户 Recall”。

正式规模和 Gate 阈值仍以用户持有的 PRD v1.0 为准；仓库没有精确值时不推测。
