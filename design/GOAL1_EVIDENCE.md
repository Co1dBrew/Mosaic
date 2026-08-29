# Goal 1 — Portfolio Evidence（backlog 6.8）

> 三条 Flow 的完整记录：**User Search · Developer Investigation · Failure → Blocked**。
>
> **本文件不含任何编造数据。** 每个数字后面都标了它的来源（自动断言 / 模拟器实拍 /
> 待验证）。凡是需要真机、需要人工标注、需要外部凭据的，一律写「待验证」而不是估计值。
>
> 复现命令见每一节的「怎么复现」。最后更新：2026-08-10

---

## 0. 一页结论

| 主张 | 证据来源 | 状态 |
|---|---|---|
| 用户能用上隐式 Hybrid 搜索，AI 层失效时搜索仍可用 | `ProductionSearchTests`（I1–I5）+ 模拟器实拍 | ✅ 已验证 |
| 结果能解释「为什么相关」（Matched Excerpt + 对比式高亮） | `SearchPresentationChecks` + 模拟器实拍 | ✅ 已验证 |
| 点结果能落到命中的那一段（scroll + 2.4s 临时高亮） | `SearchLandingTests` + `RetrievalWeek5Checks` + 模拟器实拍（高亮） | ⚠️ 滚动部分待人工验证（需长笔记 / 音频笔记） |
| 坏配置上不了线（Gate 四项，任一 FAIL 即阻断） | `RetrievalWeek5Checks` + `RetrievalWeek6Checks` + 模拟器实拍 | ✅ 已验证 |
| 生产配置只能经 Promote 更换 | `RetrievalConfigRegistry` 无其他入口 + 断言 | ✅ 已验证（结构性） |
| 20k chunks 仍在 SLO 内 → 不需要 ANN | release checks 实测（Mac） | ⚠️ **iPhone 真机待复测** |
| 语义检索在中文笔记上有效 | Golden Set 7 条 / 8 篇（Mac 上真实 `NLEmbedding`） | ⚠️ 样本量不足以支撑阈值；iOS 上无 zh 模型（TD-9） |

---

## Flow A — User Search（用户视角）

**故事**：用户想找「之前问 advisor 能不能晚点毕业」那条笔记，
但记不住原话，也不确定当时写在哪。

### 已验证的行为

| 步骤 | 契约 | 证据 |
|---|---|---|
| 打开搜索，空 query | 三条示例可点，说明可搜哪些内容（§10） | 模拟器实拍 |
| 状态条 | 本机没有句向量模型 → 「智能搜索暂不可用，已按关键词搜索」+ 重试 | 模拟器实拍（iPhone Air · iOS 26 模拟器） |
| 输入 query | keyword 150ms / semantic 400ms 两级触发 + 长度门控 | `SearchPresentationChecks` · `ProductionSearchTests` |
| 结果行 | Title · **Matched Excerpt** · Folder · Time 三槽位 | 模拟器实拍 |
| 高亮 | 命中提为 primary、上下文压暗；**区间由检索层给出** | 实测：query `Advisor` → ranges `[4,11)` = `advisor`（大小写不敏感），excerpt 高亮一致 |
| 点结果 | 进入笔记 + block 级临时高亮（8pt 外扩 · 圆角 12 · 2.0s + 0.4s） | **模拟器录屏逐帧确认**：点击后约 0.25s 出现，持续约 2.5s 后淡出 |

### 不变量 I1–I5（Progressive Enhancement）

没有模型 / 索引没建 / 索引建立中 —— **keyword 结果一律照常**。
逐条用例在 `App/MosaicTests/ProductionSearchTests.swift`。

模拟器上的现状本身就是 I1 的实景：`Embedding Provider 不可用` ·
`Index State failed(本机没有可用的本地句向量模型)` · `Indexed Chunks 0`，
而搜索照常返回结果。

### 怎么复现

```bash
swift run mosaic-checks
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 仍待人工验证

- **scroll-to-block**：模拟器上现有笔记只有一屏，滚动不可观察。需要一条内容超过一屏的
  笔记（≥ 6 个文本块）才能确认 `.center` / `.top(88pt)` 两种落点。
- **转写命中的展开 + 落点**：需要一条带录音转写的笔记。
- **VoiceOver 实际朗读**：断言证明的是内容与顺序，不是体验。

---

## Flow B — Developer Investigation（开发者视角）

**故事**：某条 query 应该找到 A 笔记，实际没找到。问题在哪一层？

### 链路

```
Retrieval Lab（D2）      跑 query，看三路排名证据 K #3 · V #7 → #2
   ↓
Compare Modes（D3）      keyword-only / vector-only / 两路都有，分组正确
   ↓
Retrieval Trace（D4）    七段耗时 + 四项 index metadata；候选为 0 → 问题在检索层
   ↓
Eval Center（D5）        Golden + Regression 一起跑，六个数字
   ↓
Failure Inspection（D9） 七类归因（固定，不可自由输入）→ Add to Regression Set（幂等）
   ↓
Eval Compare（D6）       current vs baseline，质量与延迟同屏；不下 PASS/FAIL
```

### 本轮抓到的一个真实缺陷（追因记录）

> 这一条是 Flow B 最好的样本，因为它的结论**推翻了直觉**。

1. **现象**：6.2 chunk 策略对比里，三种策略的 Recall@5 完全相同（0.500），
   而且长文用例 3/3 全部失败。
2. **第一反应**（错的）：「三种切分一样好」。
3. **第一次追因**：语料太短 —— 8 篇笔记都不到 240 字，三种策略切出的 chunk **完全相同**。
   于是加了 3 篇长笔记（答案埋在中段），chunk 数变成 11 / 26 / 25，MRR 开始有差异。
4. **仍然**：长文用例 3/3 全败。所以问题不在切分。
5. **第二次追因**（直接量余弦）：
   - `query vs 答案句(32字)` = 0.9190
   - `query vs 整篇长文(1339字)` = 0.8748
   - **`query vs 完全无关的短句(13字)` = 0.9366** ← 比答案句还高
6. **对照实验**：把同一段文字重复 n 次拉长，余弦单调下降 0.0496；
   而相关 / 无关文本在同一长度上只差 0.0115。**长度效应是相关性效应的 4.3 倍。**
7. **结论**（TD-11）：`NLEmbedding` 的余弦主要由**文本长度**决定，不是相关性。
   - 直接解释了长文用例为什么全败；
   - 直接决定了 TD-10 的相关性下限**不能只看余弦**（任何阈值都会变成隐蔽的长度过滤器）；
   - 直接把「切到相近长度」从 recall 特性升级为**可比性要求**。
8. **没有做的事**：没有实现长度归一化。那是一次没有 Golden Set 支撑的模型层改动，
   属于范围扩张。改为写一条断言把现象钉住（`checkCosineLengthBias`），
   换模型时它会立刻告诉你变没变。

### 怎么复现

```bash
swift run -c release mosaic-checks
```

输出里的 `6.2 Chunk 策略对比` 与 `TD-11 长度偏置` 两张表。

---

## Flow C — Failure → Blocked（发布视角）

**故事**：一套新配置引入了回归，Gate 必须拦住它。

### 完整闭环（全部由断言守着）

| 步骤 | 结果 |
|---|---|
| 评测出现失败用例 | 收集到 `EvalFailure`，默认**未归因** |
| 人工归因 `missingData` + 说明 | `isTriaged == true` |
| `Add to Regression Set` | 首次成功、**重复被拒**（幂等，否则 Pass Rate 分母虚高） |
| 下一次评测 | **自动**带上回归集（8 条 = 7 golden + 1 regression），两部分分开统计 |
| 候选配置 keyword-only | Recall@5 **0.250** vs baseline hybrid **0.625**；Regression **0/1** |
| Gate 判定 | **PROMOTION BLOCKED** —— Recall@5 / MRR / Regression 三项同时阻断 |
| 阻断行 | Regression 行给 `Open Failures ›` 直达 D9 |
| `Promote to Production` | 按钮置灰；**且注册表直接抛错**，生产配置没有被换成 keyword-only |

数据来源：`RetrievalWeek6Checks.checkRegressionBlocksRelease`（release 实测）。

### 四项检查的边界（`RetrievalWeek5Checks`）

| 场景 | 判定 |
|---|---|
| 四项全过 | `PASS` |
| P95 310ms > 250ms，其余全绿 | `BLOCKED`，只有 P95 那一行红 —— **不加权，「大部分指标都很好」换不来放行** |
| Regression 39/40 = 97.5% | `BLOCKED` |
| MRR 恰好在 baseline − 0.010 上 | `PASS`（浮点边界不能因为 1 ulp 翻面） |
| Recall@5 比 baseline 低 0.001 | `BLOCKED`（默认零容差） |
| 没跑过评测 / 评测跑的是别的配置 | `STALE`，不是 PASS |
| 有 current 没 baseline | `BLOCKED`，且 detail 写明「还没跑 baseline」而不是「质量下降」 |
| 两次跑批用例数不同 | `BLOCKED`，detail 点明分母变了 |
| 回归集为空 | 这一项恒过，但 detail 说明它为什么是绿的 |

### Promote 的三道结构性关卡

`RetrievalConfigRegistry.promote(id:decision:)` 要求：目标是 candidate ·
`decision.isPass` · `decision.configVersion == 记录的 version`。

第三条拦的是**「改完参数没重跑评测就上线」**。
断言 `testBlockedDecisionCannotPromoteEvenIfCalledDirectly` 绕过 ViewModel
直接调 store，确认拦截在更下面一层。

### 模拟器实拍

- Developer Mode → **发布** 段：Release Gate · Retrieval Config · Production Config `retrieval-v1`
- Release Gate：`STALE` + 「还没有评测结果 —— 先在 Eval Center 跑一次。」+
  四项检查区给出补救动作 + `Promote to Production` **置灰**
- Retrieval Config：生产段只读 · `Duplicate as new version` → `DRAFT · retrieval-v2` →
  改 Top K → `Save & Set as candidate` → 版本列表出现 `retrieval-v3 · candidate`
  （**版本号不复用**：被丢弃的 v2 不会被下一条重新占用）

### 怎么复现

设置 → 开发者模式 → 开发者工具 → 发布。

---

## Flow D — Synthetic v2 解耦与产品边界

**故事**：v1 的 overall 指标无法区分 source、language、length。v2 把三个变量拆开，
并把 no-result 与 cross-language 变成正式可观测维度。

| 证据 | 结果 |
|---|---|
| Source × language | 五类来源各 12 篇，每类中文 6 / 英文 6；有自动断言防回退 |
| Length | 6 篇 >600 字符，五类来源均覆盖；中段答案 40%–60%，另有末段 query |
| Distractors | 34 篇从不作为 expected；含搬家、租约、停车牌、产品会近似项 |
| Scope | 54 正例 = 35 in-scope + 19 cross-language；Runner / Compare / Gate 使用同一标签 |
| No-result | 10 条正式 `.noRelevantResult`；Recall/MRR 分母只含正例 |
| Hybrid release | Recall@5：in-scope **0.600** / cross-language **0.211** / overall **0.463** |
| 负例 release | Keyword no-result 100%；Vector / Hybrid 0%（各 10/10 误召回） |
| Gate | 只看 in-scope 正例；cross-language 与负例显示但不参与发布判定 |

它将 TD-10（无相关性下限）从推测变成实证，也新增 TD-12：目标 persona 的双语语料与
“整库一个本地向量空间”冲突。生产路由未擅自更改，待产品选择多语言云模型、双索引或
明确不支持。完整数据与限制见 `HUMANLIKE_GOLDEN_SET.md`、架构记录见 §20。

---

## 附：本轮真实测试结果

| 套件 | 结果 |
|---|---|
| `swift run mosaic-checks`（debug） | ✅ 1048 断言 |
| `swift run -c release mosaic-checks` | ✅ 1058 断言（多出的是 SLO 与规模断言） |
| `xcodebuild test -scheme Mosaic`（iPhone 17 Pro 模拟器） | ✅ 80 tests |
| `design/figma-plugin` `node test/all.js` | ✅ 5 套件（checks 11 · gates 9 · calibration 96 · tolerance 7 · selftest 15） |
| `design/figma-plugin-devtools` `node test/run.js` | ✅ 6 / 6 |

> 断言数会随实验语料变化小幅浮动；以实际运行输出为准。

---

## Flow E — Provider Decision（D-AI-003）

> 这是整份 portfolio 里**决策链最完整**的一条：一个被数据否决的方案 + 一个成功方案的代价。

### 1 · Failure（本地多语言失败）

目标 persona 的笔记库天生双语（自己写中文，收到的租约 / 保单 / I-20 是英文）。
本地 `NLEmbedding` 的 cross-language Recall@5 = **0.211**（v2）/ **0.128**（v3 加固后）。

### 2 · Rejected Approach（中英双索引 —— 实测比 baseline 更差）

| 臂 | R@5 |
|---|---:|
| A 现状（单一 zh 空间 + keyword） | 0.211 |
| **B 双索引 + 双嵌入 query** | **0.158** ← 比现状还差 |
| C 双索引 + **作弊路由**（永远猜对） | 0.421 |
| D 语种匹配上界（同批笔记换同语种 query） | 0.619 |

**为什么否决**：中文 query 用英文模型嵌入 **19/19 全部「成功」、0 条报错** ——
它不会失败，它会安静地给一个无意义的向量。噪声进 RRF 反而稀释信号。
而且即使给它一个永远猜对的路由（C），也只到 0.421，远低于同语种上界 0.619。
**根因不是路由不准，是中文 query 与英文笔记不在同一语义空间。** 换任何本地模型都一样。

### 3 · Successful Treatment（云端多语言）

`BAAI/bge-m3`，v3 实测：cross-language R@5 **0.128 → 0.936**，in-scope R@1 **0.269 → 0.866**。
顺带把 TD-11 完全反转（长度效应主导 → 相关性效应主导 4.7 倍）。

### 4 · Trade-off（代价，未解决）

云端语义 P50 **710 ms** / P95 **894 ms**，vs Local Retrieval SLO 的 250 ms。
**Release Gate 判定 `PROMOTION BLOCKED`** —— 质量三项全过，P95 一项否决。
云端不因为质量好就自动进生产。

### 5 · Architecture Decision（不是替换模型）

```
Cloud Semantic（已配置 + 已授权）→ Local Semantic → Keyword Only
```

六种云端失败形态全部注入过（401 / 429 / 5xx / offline / timeout / malformed /
dimension mismatch / count mismatch），keyword 路每次都照常返回结果。
**Semantic failure ≠ Search failure** 有断言守着。

### 6 · 加固数据推翻自己的旧结论

v3 把 v2 的两个结论推翻了：R@5 满分是天花板效应（不是检索完美）；
TD-10 的「0.54 阈值安全」是小负例集假象（v3 上该阈值要丢掉 10.4% 的正确答案）。
**接受新数据，不维护旧结论** —— 这条比任何一个提升百分比都更值得写进 portfolio。
