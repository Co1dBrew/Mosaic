# Mosaic / 万象记 —— 交接说明（给下一个对话窗口）

> 写于 2026-08-19。分支 `feature/mosaic-mvp-p0`，**已 push，与 origin 同步，工作区干净**。
>
> **先读这一份，再读 `HANDOFF.md`。** 本文件只讲「现在在哪、下一步做什么」；
> 历史与工程决策在 `RETRIEVAL_ARCHITECTURE.md`。

---

## 0. 三十秒版本

Goal 1（AI 检索质量平台）的 **Week 1–6 工程实现已全部完成**，评测/发布闭环可用。
本轮之后项目的重心已经从「把功能做出来」转到「**用数据判断该不该上线**」。

当前最大的三件事：

1. **Golden Set 是 synthetic 的**，不是真实用户标注 → 所有质量数字都不能当用户侧结论
2. **Release Gate 现在会拦住自己**：perf-v2 要求真机 release 数字，Mac/模拟器判 STALE
3. **云端优先已生效，但同意闸门默认关闭** → 实际行为仍是本地语义

---

## 1. 权威文档顺序（冲突时按这个优先级）

| 优先级 | 文件 | 作用 |
|---|---|---|
| 1 | **PRD v1.0**（用户持有，不在仓库） | 最高权威。缺精确数值时**不要编** |
| 2 | `design/SEARCH_CONTRACT.md` | 生产搜索契约，**已冻结** |
| 3 | `RETRIEVAL_ARCHITECTURE.md` | 工程决策记录。**§17–§22 是最近的** |
| 4 | `design/DECISION_LOG.md` | 产品决策，含 **D-AI-003** |
| 5 | `EMBEDDING_EXPERIMENT.md` | 正式实验报告，标注 measured / estimated |
| 6 | `HUMANLIKE_GOLDEN_SET.md` | 评测集说明与限制 |
| 7 | `design/GOAL1_BACKLOG.md` | 任务与 DoD，末尾有逐项核对表 |
| 8 | `prd.md` | **旧版** Notes App PRD，只能用于确认既有行为 |

⚠️ **`design/` 被 `.gitignore` 整体忽略** —— 那里的文档在磁盘上但不在 git 里。
不要以为它们丢了，也不要擅自 `git add -f`。

---

## 2. 怎么跑测试（每次改动后都要跑）

```bash
swift run mosaic-checks
```
```bash
swift run -c release mosaic-checks
```
```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=00008150-000064912E87801C' -allowProvisioningUpdates
```
```bash
cd design/figma-plugin && node test/all.js
```

**最近一次全绿的数字**（以实际运行为准，会小幅浮动）：

| 套件 | 结果 | 条件 |
|---|---|---|
| 内核 debug | ✅ 1467 断言 | 约 3.5 分钟 |
| 内核 release + 云端 | ✅ 1492 断言 | 约 9 分钟（云端臂 + fusion 扫描占大头） |
| App XCTest（模拟器） | ✅ 81 tests | — |
| MosaicBench（iPhone Air 真机） | ✅ 7 tests | 带凭据 140s / 无凭据 30s（test5 skip） |
| Figma Production / DevTools | ✅ 11·9·96·7·15 / 6 | — |

⚠️ **「全绿」必须带上「在什么条件下」。** 上一轮记的 1258 / 1268 是**没有云端凭据**
跑出来的；key 一插上立刻 3 FAILED —— 云端那一段整段包在 `if let cloud…` 里，
缺 key 就不执行，也就**没在保护任何东西**。三条失败断言已修（`RETRIEVAL_ARCHITECTURE.md` §23.1）。
报结果时请写明云端臂跑没跑。

### 五个容易踩的坑

1. **新增 App 文件后必须 `cd App && xcodegen generate`**，否则 Xcode 工程里没有它。
2. **`MosaicBench` 必须走自己的 scheme**。`MosaicTests` 用 `@testable`，Release 下不可用；
   不要为了让它编译去打开 `ENABLE_TESTABILITY`（会污染性能数字）。
3. **别在真机测试跑的同时跑 `build-for-testing`** —— 会抢 DerivedData，
   报 `Result bundle saving failed / mkstemp`，看起来像测试失败但不是。
4. **要跑云端臂就得给四个环境变量**（另可给 `MOSAIC_LIVE_EMBEDDING_REGION`）。
   凭据在 `~/.mosaic-cloud.env`（仓库外，`chmod 600`），`source` 它即可。
   真机那两条（`test5` / `test6` 云端臂）走 `App/MosaicBench/CloudCredentials.json`
   —— 设备上读不到 Mac 的环境变量（`TEST_RUNNER_` 前缀对 app-hosted 单测无效，已实测）。
5. **分档索引成本默认不跑**（一次 7 分钟）：`MOSAIC_SCALE_COST=1 swift run -c release mosaic-checks`。
   结果已回填 §26.3，不靠每次重跑维持。

---

## 3. 项目现在的状态

### 已完成（有断言守着）

- **Week 1–4**：运行时底座 · 五类语料 chunk/OCR/索引生命周期 · 三路检索 + RRF ·
  Retrieval Lab / Compare / Trace · Golden Set 结构 / EvalRunner / 口径 / Regression / D5·D6·D9
- **Week 5**：配置版本化（生产配置只能经 Promote 换，结构性保证）· Release Gate 四项 ·
  Promote · 生产搜索接入隐式 Hybrid · 两级防抖 · I1–I5 降级 · Result→Note 落点
- **Week 6**：Chunk 策略对比 · Staleness · Regression 长跑（Gate 拦截完整记录）· 无障碍朗读顺序
- **上一轮**：真机延迟基准 · abstention policy 内核 · 分层 SLO + 测量环境闸门 ·
  云端多语言 provider 决策（D-AI-003）· Golden Set v3 加固
- **本轮（2026-08-19，新 key 到位）**：v3 云端质量复跑并确认逐位一致 ·
  修掉三条被缺凭据藏起来的过期 Gate 断言 · **成本一项落地**（服务端回报 token，
  不再用字符外推）· 云端建索引耗时确认为网络量、报区间（§23）·
  **真机云端基准 `MosaicBench.test5` 已落地并实测**（3 轮 × 25 样本，§23.5）·
  发现 `percentiles` 在取样量 ≤ 20 时把 P95 退化成 max ·
  **真机基准全部重测**（25 样本 + 等热状态，6 轮报区间，P1 #7/#13 关闭，§23.6）·
  **Golden Set eval 搬上真机**（`test6`，两个 Gate 判定都出自真机同一次跑批，
  P1 #12 关闭，§23.7）· **R@1 进 Gate**（与 R@5 合成一行，P1 #15，§24.1）·
  **keyword 提速 2.36×**（瓶颈是归一化重算不是缺索引，P1 #9 第一步，§24.2–24.3）·
  **fusion 参数实验**（cross 调不动；意外发现 RRF 在本地臂主动有害，P1 #6 关闭，§25）

### 关键架构约束（**不要在没有证据时改动**）

1. **`MosaicKit` 平台无关** —— 不引 SwiftData / UIKit。`RunEnvironment` 用 Foundation 拿系统版本就是这个原因。
2. **正确性靠写入路径的 `contentHash` 校验，不靠任务取消**（取消是协作式的）。
3. **一个索引只有一个向量空间** —— 整库一条 embedding 路线，不按块切换。
4. **Release Gate 判定 = `allSatisfy`，不加权不算总分**。
5. **生产配置只能经 `promote(id:decision:)` 更换**，且要求 PASS 判定 + 版本号匹配。
6. **derived store 可随时清空**；Golden Set / 配置注册表**不放**那里（不可重建）。

---

## 4. 最近的实测数字（都是真的，别重新编）

### 真机（iPhone Air `iPhone18,4` · iOS 27.0 · **Release** · nominal · 低电量关闭）

**25 样本 · 每档等回 nominal · 6 轮区间**（2026-08-19 重测，旧点值已作废）

| 层 | 1k | 5k | 10k | 20k |
|---|---:|---:|---:|---:|
| Metric A **热** P50/P95（生产路径） | 1.54–1.57 / 2.59–2.60 | 7.18–7.37 / 12.21–12.51 | 14.77–14.93 / 24.83–27.38 | **30.66–31.20 / 52.52–52.56** |
| Metric A **冷** P50/P95（语料刚变） | 4.61–4.63 / 9.77–12.96 | 16.98–17.31 / 24.31–24.35 | 34.18–34.34 / 44.13–44.33 | **70.64–71.37 / 94.92–101.06** |
| Metric B-local 端到端 P50/P95 | 6.32 / 9.16 | 13.72 / 19.26 | — | **45.69 / 66.07** |
| 余弦检索 P50/P95 | 0.65–0.67 / 0.69–0.74 | 1.64–1.65 / 1.92–1.96 | 2.85–2.89 / 3.15–3.21 | **5.41–5.61 / 5.86–6.15** |

本地 query 嵌入 P50 **4.29–4.40** / P95 10.22–12.51 ms（⚠️ 见 P1 #14，不可独立引用）。

**Metric A 必须冷热分开看**：缓存按 chunk 缓存，语料一变第一次查询就付全价。
余量：热 P50 **3.2×**、冷 P95 2.5×、Metric B-local P95 **3.8×**。

⚠️ **P95 的取样量下限是 25** —— `percentiles` 在 count ≤ 20 时下标落在最后一位，
「P95」退化成 max。旧记录的 119.30/143.23 就是那样来的。
⚠️ **放凉会让 P95 变差**（冷启动）：L2a 不等热状态时 P95 是 11.6–12.3，等了变 15.8–16.2，
而 P50 一动不动。降方差换的是尾部，报 P95 必须说明取法。
⚠️ **旧的本地嵌入 6.21 ms 复现不了**（新值 11.1，6 轮 ±1%），机制未查清（§23.6）。

**反直觉但已确认**：20k 上 keyword P95 89.23–98.51 ms vs 余弦 5.86–6.15 ms —— **差 14.5–16.8 倍**。
第一批结果的瓶颈是**词法路**，不是向量路。要优化就优化倒排索引，别碰 ANN。

### 真机 Golden Set eval（同一次跑批出质量+延迟 · 150 notes / 186 chunks / 114 正例）

| arm | R@1 | R@5 | MRR | P50 | P95 | no-result |
|---|---:|---:|---:|---:|---:|---:|
| keyword | 0.343 | 0.343 | 0.343 | 0.99 ms | 2.28 ms | **100%** |
| local-hybrid | 0.269 | 0.418 | 0.341 | 13.56 ms | 15.98 ms | 0% |
| cloud-hybrid | **0.866** | 1.000 | **0.938** | 511.15 ms | 614.43 ms | 0% |

两个 Gate 判定（local-hybrid 对 keyword · cloud-hybrid 对 local-hybrid）**都 PASS**，
四项齐全，环境合格。**质量数字与 Mac 侧逐位相同** —— 真机与 Mac 的差别只在延迟。

⚠️ **PASS 不等于可以上线**：评测集是 synthetic，这只证明判定链路闭合了。
⚠️ **R@1 没进 Gate**：local-hybrid 的 R@1 比 keyword 低 21.6%，Gate 仍判 PASS。见 P1 #15。

### 真机云端语义（iPhone18,4 · iOS 27.0.0 · Release · nominal · `cn-shanghai` · 3 轮 × 25 样本）

| 层 | P50 | P95 | max |
|---|---:|---:|---:|
| L3 网络往返 | 420.5 – 442.9 ms | 629.2 – **1075.3** ms | — |
| L3 解析 + 归一化 | 0.48 – 0.53 ms | 0.51 – 1.21 ms | — |
| L4 端到端（20k chunks） | 575.6 – 637.0 ms | 681.7 – **1480.7** ms | 868 – **7623** ms |

网络占 **99.87–99.89%**。20k × 1024 维 = **78.1 MB**。25 次 query 嵌入 = 149 tokens（三轮一致）。

⚠️ **P50 可复现（±5%），尾部不可复现（max 差 8.8 倍）。** 引 P50 + 区间，别引单轮 P95。
**偶发的 7.6 秒是真的** —— keyword 先出结果不是锦上添花。

### 云端 embedding（`BAAI/bge-m3` · region `cn-shanghai`，从美国访问）

| | P50 | P95 |
|---|---:|---:|
| 网络往返 | 383.5 ms | 1192.7 ms |
| 解析 + 归一化 | 0.76 ms | 0.99 ms |

**网络占 99.80%。** 用户会换就近服务商，届时只需重测网络这一层。

### 质量（**v3** 数据集 · 114 正例 / 20 负例 · Mac release · 主指标 R@1 / MRR）

| Arm | in-scope R@1 | in-scope R@5 | in-scope MRR | cross R@5 |
|---|---:|---:|---:|---:|
| Keyword | 0.343 | 0.343 | 0.343 | 0.085 |
| Local Hybrid | 0.269 | 0.418 | 0.341 | 0.128 |
| **Cloud Hybrid** | **0.866** | **1.000** | **0.938** | **0.936** |

负例 no-result accuracy：keyword **100%**，四个向量臂全是 **0%**。

⚠️ **前后 3 把 key、5 次跑批，质量数字一位都没变** —— 服务端 embedding 是确定性的。
**延迟不是**：Mac 上 cloud-hybrid P95 在 569–1485 ms 之间摆。

### 成本（同一份 v3 语料 186 chunks / 25 310 字符 · Mac）

| | Local | Cloud |
|---|---:|---:|
| 建索引 | 3 038 – 3 596 ms | 4 517 – 64 227 ms |
| `prompt_tokens` | — | **9 720**（五次跑批每次都一样，跨 3 把 key） |

**这张表里只有 token 可以引用。** 单 chunk 云端耗时五次差 14 倍（24.3 → 345.3 ms），
它是网络量不是算力量。实测 **0.38 token/字符**，此前外推用的 3.7 偏低。

### 被数据否决的方案（portfolio 最值钱的素材）

| 臂 | cross-language R@5 |
|---|---:|
| 现状（单一 zh 空间 + keyword） | 0.211 |
| **中英双索引 + 双嵌入 query** | **0.158** ← 比 baseline 还差 |
| 双索引 + 作弊路由 | 0.421 |
| 语种匹配上界 | 0.619 |

机制确定：**中文 query 用英文模型嵌入 19/19 全部"成功"、0 条报错**，产出噪声向量。

---

## 5. 技术债现状

| ID | 状态 |
|---|---|
| **TD-1** | `SummaryService` 无 stale 保护（既有缺陷）。**开放**，一直没动 |
| **TD-4** | `AIJobCoordinator` 排队取消会漏 waiter。**开放**，当前深度无害 |
| **TD-6** | 向量索引仅内存，启动从 derived store 重建。**开放**（20k ≈ 29.3 MB，真机可接受） |
| **TD-10** | 相关性下限。**Improved / Calibratable，未解决** —— v3 上三个信号全部重叠，云端 margin 最好（正例零损失挡掉 6/20）但**余量 0.0002 不可发布**。默认 `neverAbstains` |
| **TD-11** | 余弦受长度支配。**provider-specific**：本地长度赢 4.3 倍，云端相关性赢 4.7 倍。**不要写成「系统永久解决」** |
| ~~TD-9~~ | **已关闭（真机推翻）**：iPhone 上 `zh-Hans` ✅ 640 维。之前的 ❌ 来自模拟器（不带模型资源） |
| ~~TD-12~~ | **已关闭（限云端）**：cross-language 0.211 → 1.000。但 R@1 = 0.737，排序仍有空间 |
| ~~TD-2/3/5/7/8~~ | 已关闭 |

**已关闭的既有缺陷**：文本块不换行（`RichMarkdownEditor` 缺 `sizeThatFits`）

---

## 6. 待办（按优先级，含谁能做）

### P0 · 只有用户能做

| # | 事项 | 为什么阻塞 |
|---|---|---|
| 1 | **PRD v1.0 的 Golden Set 规模** | 真正进 Gate 的分母是 **in-scope** 那一组（v3 是 80 条）。要问的是「in-scope 要多少条」，不是「总共多少条」 |
| 2 | **PRD v1.0 的四项 Gate 阈值定值** | 现用初值：Recall@5 零容差 / MRR 容差 0.010 / P95 250ms / Regression 98%。改一个结构体即可 |
| 3 | **真机 Golden Set 标注** | 用例引用**本机笔记 UUID**，代码里预置不了。D5 → Golden Set → `+` |
| ~~4~~ | ~~**新的云端 API key**~~ | ✅ **2026-08-19 已完成**：v3 云端质量已复跑（逐位一致）、成本对照已落地（§23.3）。**这个 key 也贴进了对话记录 → compromised，跑完请撤销。**下一次给 key 请写本地文件给路径 |

### P1 · 我能做，等你点头

| # | 事项 | 说明 |
|---|---|---|
| ~~5~~ | ~~**Golden Set 加固到 200+**~~ | ✅ **v4 已落地：210 篇 / 166 正例 / 30 负例 / 19 个同构簇**（§26.1）。⚠️ **一半目标没达成**：R@1 压下来了（cloud 0.866→0.792），但 **in-scope R@5 仍是 1.000**。机制：一簇 3 篇，Top-5 装得下整簇。v5 要的是**更大的簇**（6–8 篇），不是再加散篇 |
| ~~6~~ | ~~**cross-language R@1**~~ | ✅ **已完成，结论是「调不动」（§25）**：7 个 k 值 + 2 个加权点 + 单臂参照，cross R@1 摆动 **0.000**。原因确定：keyword 在 cross 上只有 **4/47** 条 query 有结果，fusion 91.5% 的时候只有一个输入。**这一项到此结束，不是「还没调好」** |
| ~~18~~ | ~~**默认融合换不换**~~ | ✅ **已换成 `.weighted(keyword: 0.7, vector: 0.3)`**（§26.2）。v4 上复现且更强：RRF 比 keyword 单独差 **10 条用例**。选 0.7 云端付 −0.010、本地拿 +0.099，**交换比 10:1**。只影响新建配置，已 promote 的生产配置不受影响。回退 = 改回 `.rrf(k: 60)` 一行 |
| ~~7~~ | ~~**真机基准降低方差**~~ | ✅ **已完成（2026-08-19，你点头后做的）**：取样量 25 + 每档等回 nominal，6 轮报区间。P50 方差 ±22% → ±4%（§23.6） |
| ~~8~~ | ~~**「开启云端能搜到英文文档」提示**~~ | ✅ **已完成（§26.4）**：判断在内核（`shouldOfferCloudUpgrade`，四个抑制条件全有断言），文案在 App（受 §1.1.1 词表约束），**挂在零结果**而非常驻状态条，**不改路由** |
| ~~10~~ | ~~**真机上跑一次云端臂**~~ | ✅ **已完成**：`MosaicBench.test5`，3 轮 × 25 样本，数字见 §4。**但这不等于 cloud-hybrid 能进 Gate** —— 判定要读同一次 EvalRun 的质量+延迟，而质量还在 Mac 侧（§23.5 末） |
| ~~12~~ | ~~**让 golden set eval 整体跑在真机上**~~ | ✅ **已完成**：`MosaicBench.test6`。两个 Gate 判定都 PASS，全部数字出自真机同一次跑批（§23.7）。**PASS ≠ 可上线**，评测集仍是 synthetic |
| ~~15~~ | ~~**R@1 没进 Gate**~~ | ✅ **已完成**：R@1 与 R@5 合成判定区**同一行**（不改四行版式），任一不过即阻断，零容差为**初值**。后果：local-hybrid 由 PASS 变 BLOCKED（§24.1）。⚠️ 真机未复测确认 |
| ~~9~~ | ~~**keyword 路倒排索引**~~ | ✅ **第一步已完成**：分段实测发现 68.5% 花在**与 query 无关的归一化重算**上，不是缺索引。`NormalizedTextCache` 拿 26 MB 换 **2.36×**，语义逐位不变（§24.2–24.3）。⚠️ 真机未复测；n-gram 索引待定 |
| ~~16~~ | ~~**真机复测 #15 与 #9**~~ | ✅ **已完成（§24.5）**：local-hybrid 确认 BLOCKED；keyword 真机提速 2.29–2.30×；顺带发现 `test2` 测的不是产品路径，已改成走 `RetrievalService` 并冷热分报 |
| ~~17~~ | ~~**n-gram 索引**~~ | ✅ **决定不做（§26.6）**。三条理由：没人在 65k chunks 上；它要改匹配单位（中文无分词器）；下一个瓶颈是建索引 3.9 分钟与常驻 74.9 MB，不是查询。**重开条件**：PRD 语料上限 >40k，或真机热 P50 越过 60 ms |
| ~~13~~ | ~~**`test4` 的「P95」其实是 max**~~ | ✅ **已完成**：全部延迟用例统一 25 样本，`samples` 常量带着理由。旧数字已作废并回填 |
| ~~14~~ | ~~**L2a 不可独立引用**~~ | ✅ **已结构性处理（§26.5）**：`test4` 不再单独打印 L2a，改为连同「占同批次端到端的百分比」一起打印，并断言 `L2a < 端到端`。想引绝对值就必须把那张表一起抄走。机制仍未查清，但它不再能被单独抄走 |
| ~~11~~ | ~~**20k 分档索引成本**~~ | ✅ **已完成（§26.3）**：本地四档全测，**完美线性**（漂移 1.00×）。20k 建索引 **235 s**、常驻 **74.9 MB**。云端只在 1k 实测。⚠️ **修正**：token/chunk **不跨语料恒定**（fixture 52.3 vs 合成 39.4），外推必须用该语料自己的换算率 |

### P2 · 明确不做（除非你要求）

ANN · 向量数据库 · 自托管 bge-m3 · GPU · RAG Chat · reranker / cross-encoder ·
Agent · Prompt Studio · 复杂隐私 UI。**理由：先把 Provider 决策 + 评测 + Gate 收干净。**

---

## 6.5 怎么跑真机云端臂（P1 #10，唯一缺的是 key）

设备上的测试进程**读不到 Mac 的环境变量**（`TEST_RUNNER_` 前缀对 app-hosted
单元测试无效，已实测），所以凭据要进 bundle。

**凭据存放位置：`~/.mosaic-cloud.env`**（仓库外，`chmod 600`，含 base / key / model /
dim / region）。Mac 侧 `source` 它即可；真机侧从它生成 bundle 文件：

```bash
source ~/.mosaic-cloud.env && python3 -c "
import json, os
json.dump({'base': os.environ['MOSAIC_LIVE_EMBEDDING_BASE'], 'key': os.environ['MOSAIC_LIVE_EMBEDDING_KEY'], 'model': os.environ['MOSAIC_LIVE_EMBEDDING_MODEL'], 'dim': int(os.environ['MOSAIC_LIVE_EMBEDDING_DIM']), 'region': os.environ['MOSAIC_LIVE_EMBEDDING_REGION']}, open('App/MosaicBench/CloudCredentials.json','w'), indent=2)"
```

```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=00008150-000064912E87801C' -allowProvisioningUpdates -only-testing:MosaicBench/DeviceLatencyBenchmarkTests/test5_metricB_cloudSemantic
```

```bash
rm App/MosaicBench/CloudCredentials.json
```

三点说明：

- 那个 JSON **已在 `.gitignore` 里**，且由构建脚本可选拷贝 ——
  有没有它都能构建成功，**都不需要 `xcodegen generate`**。跑完删掉。
- 跑之前设备要满足：**关低电量 · 热状态 nominal**（刚跑过别的就放凉）。
  不满足的话 `disqualification` 不为 nil，断言会拦下来 —— 那是对的，
  不合格的数字本来就不该被引用。
- 它**不判延迟**（perf-v2 对 Metric B-cloud 是「记录但不判定」），
  只判「这批数字有没有资格被引用」。延迟数字打印出来，人工回填文档。

---

## 7. 仍需人工验证的清单（按操作顺序）

1. 真机装 release 构建，记录机型 / 系统 / 构建号（`MosaicBench.test0` 会打印）
2. 确认路由状态：设置 → 开发者模式 → 开发者工具 → 配置段
3. 真机准备五类真实（或脱敏）笔记，含中英 / 长文 / 近似干扰项
4. Golden Set 编辑器里**先标相关性，再跑检索**（不要看着排名改 expected）
5. 负例开「这条 query 不该有结果」
6. 第二人**盲审**部分 expected（不看检索排名）
7. 分别跑 Keyword baseline 与 Hybrid candidate，记录 in-scope / cross-language / no-result 三组
8. 云端同意流程：**同意 → 拒绝 → 撤销 → 未同意时零请求**
9. 长笔记的 scroll-to-block（`.center` / `.top(88pt)` 两种落点）+ 转写自动展开 + 2.4s 高亮
10. VoiceOver 朗读顺序 + 最大 Dynamic Type
11. Figma 插件里选中 `🔧 Dev Tools (Wireframe)` 页，人工核对 DevTools 线框

---

## 8. 这个项目的工作方式（**请延续**）

1. **先读代码再动手**，不假设。每轮开始前 `git status` / `git log` 看真实状态。
2. **结论必须来自测量。** 本项目至少 **6 次**直觉是错的：
   centering 更好（错）· 暴力检索不达标（debug 的锅）· 行高一致（其实是文本没换行）·
   双索引能救跨语言（实测更差）· margin 不受长度偏置影响（本地模型上完全无效）·
   iOS 没有中文模型（模拟器的锅）。
3. **不编造数据。** 没测的写「待验证」；外推值标 *estimated*；
   Mac / 模拟器数字**绝不**冒充 iPhone 真机数字。
4. **新数据推翻旧结论时接受新数据**，不维护旧结论（v3 推翻了 v2 的 TD-10 读数就是例子）。
5. **发现既有缺陷要报告，但不擅自扩大范围**（TD-1 至今没动，因为改摘要行为超出范围）。
6. **测试要能证明退出标准，不是刷数量。** 每条断言对应一个明确主张。
7. **不擅自 push / 建 PR** —— 用户会明确说。
8. **凭据不进对话记录**：写本地文件、给路径，跑完删除。

---

## 9. 上下文里可能有的错误说法（请以本文件为准）

- ~~「iOS 上没有中文句向量模型」~~ → **真机有**（TD-9 已推翻）
- ~~「本地跨语言可以靠双索引解决」~~ → **实测比 baseline 更差**
- ~~「TD-10 用 0.54 阈值挡掉 9/10 负例」~~ → **v3 上作废**，余量 0.0002
- ~~「EmbeddingRouter 默认本地优先」~~ → **已改为云端优先**（同意闸门仍默认关闭）
- ~~「20k 真机 P95 = 119 ms」~~ → **区间 119–143 ms**
- ~~「云端质量数来自 v2，需要在 v3 上复跑」~~ → **v3 已跑**（本文件 §4 就是）
- ~~「云端上不了线是因为 P95 超 250ms」~~ → **perf-v2 下延迟不再是否决项**
  （Metric B-cloud 记录不判定）。现在挡住它的是**测量环境**（Mac 判 STALE）
  与**评测集仍是 synthetic**
- ~~「20k ≈ 814k token」~~ → 按实测换算率应为 **≈ 1.05M**（仍是 *estimated*）
- ~~「内核 release 全绿 1268 断言」~~ → 那是**没有云端凭据**时的数字；
  带凭据是 **1285**，且当时有 3 条过期断言被藏着
- ~~「真机 Metric B-local P95 = 119–143 ms」~~ → 那是 20 个样本里的 max。
  真百分位是 **119.39–128.33 ms**（25 样本 · 6 轮）
- ~~「真机本地 query 嵌入 P50 6.21 ms」~~ → 复现不了，新值 **11.1 ms**（6 轮 ±1%）
- ~~「真机 Metric A 20k = 73.88 / 97.87 ms」~~ → 区间 **68.72–73.32 / 89.23–98.51 ms**
- ~~「Gate 判的是 R@1 / MRR」~~ → 之前确实没进；**现在 R@1 已进 Gate**（与 R@5 合成一行）
- ~~「keyword 慢是因为没有倒排索引」~~ → **68.5% 花在与 query 无关的归一化重算上**。
  已用缓存换到 2.36×，**没上索引**。而且倒排索引保不住子串语义（中文无分词器）
- ~~「改用原生 `String.range(of:options:)` 会更快」~~ → **实测更慢**（91 / 242 ms vs 63 ms）
- ~~「cross-language R@1 可以靠调 fusion 参数改善」~~ → **实测摆动 0.000**，
  因为 cross 上 fusion 大多数时候只有一个输入（§25.2）
- ~~「RRF 至少是中性的」~~ → **本地臂上它主动有害**：把 R@1 从 0.343 压到 0.269。
  等权会让弱臂稀释强臂 —— 与「双索引反而更差」是同一个失效模式（§25.3）
- ~~「weighted 融合因为两路分数不可比所以不能用」~~ → **实现用的是名次倒数不是分数**，
  这条弃用理由描述的不是它自己的实现（§25.5）
- ~~「cloud-hybrid 进不了 Gate」~~ → 真机上**已经 PASS**（§23.7）。但评测集是 synthetic，
  所以这句 PASS 只说明链路闭合，不说明可以上线
- ~~「云端延迟 P95 约 1.2 s」~~ → 真机上 P50 只有 576–637 ms，
  但 **max 见过 7623 ms**。这一层要报 P50 + 区间，单轮 P95 不稳
- ~~「真机跑完云端臂 cloud-hybrid 就能进 Gate」~~ → **不能**。质量还在 Mac 侧，
  判定要读同一次 EvalRun 的质量 + 延迟。见 P1 #12
