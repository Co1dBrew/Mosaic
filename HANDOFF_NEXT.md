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

| 套件 | 结果 |
|---|---|
| 内核 debug | ✅ 1258 断言 |
| 内核 release | ✅ 1268 断言 |
| App XCTest（模拟器） | ✅ 81 tests |
| MosaicBench（iPhone Air 真机） | ✅ 5 tests |
| Figma Production / DevTools | ✅ 11·9·96·7·15 / 6 |

### 三个容易踩的坑

1. **新增 App 文件后必须 `cd App && xcodegen generate`**，否则 Xcode 工程里没有它。
2. **`MosaicBench` 必须走自己的 scheme**。`MosaicTests` 用 `@testable`，Release 下不可用；
   不要为了让它编译去打开 `ENABLE_TESTABILITY`（会污染性能数字）。
3. **别在真机测试跑的同时跑 `build-for-testing`** —— 会抢 DerivedData，
   报 `Result bundle saving failed / mkstemp`，看起来像测试失败但不是。

---

## 3. 项目现在的状态

### 已完成（有断言守着）

- **Week 1–4**：运行时底座 · 五类语料 chunk/OCR/索引生命周期 · 三路检索 + RRF ·
  Retrieval Lab / Compare / Trace · Golden Set 结构 / EvalRunner / 口径 / Regression / D5·D6·D9
- **Week 5**：配置版本化（生产配置只能经 Promote 换，结构性保证）· Release Gate 四项 ·
  Promote · 生产搜索接入隐式 Hybrid · 两级防抖 · I1–I5 降级 · Result→Note 落点
- **Week 6**：Chunk 策略对比 · Staleness · Regression 长跑（Gate 拦截完整记录）· 无障碍朗读顺序
- **本轮新增**：真机延迟基准 · abstention policy 内核 · 分层 SLO + 测量环境闸门 ·
  云端多语言 provider 决策（D-AI-003）· Golden Set v3 加固

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

| 层 | 1k | 5k | 10k | 20k |
|---|---:|---:|---:|---:|
| Metric A keyword P50/P95 | 3.67/4.75 | 18.07/24.95 | 35.46/45.97 | **73.88/97.87** |
| Metric B-local 端到端 P50/P95 ⚠️区间 | 8.20–16.62 / 9.62–18.59 | 24.96–32.24 / 31.17–41.59 | — | **92.53–113.03 / 119.30–143.23** |
| 余弦检索 P50/P95 | 0.64/0.70 | 1.64/1.93 | 2.85/3.16 | **5.45/5.86** |

⚠️ **Metric B-local 报区间不报点值** —— 同一设备两次跑批 20k P95 从 119 到 143 ms。
`test4` 跑在整套用例之后，设备已发热。**真机延迟跑一次不能当定值。**

**反直觉但已确认**：20k 上 keyword 97.87 ms vs 余弦 5.86 ms —— **差 17 倍**。
第一批结果的瓶颈是**词法路**，不是向量路。要优化就优化倒排索引，别碰 ANN。

### 云端 embedding（`BAAI/bge-m3` · region `cn-shanghai`，从美国访问）

| | P50 | P95 |
|---|---:|---:|
| 网络往返 | 383.5 ms | 1192.7 ms |
| 解析 + 归一化 | 0.76 ms | 0.99 ms |

**网络占 99.80%。** 用户会换就近服务商，届时只需重测网络这一层。

### 质量（v2 数据集，Mac release）

| Mode | in-scope R@5 | cross-language R@5 |
|---|---:|---:|
| Keyword | 0.457 | 0.105 |
| Local Hybrid | 0.600 | 0.211 |
| **Cloud Hybrid** | **1.000** | **1.000**（R@1 0.829 / 0.737） |

⚠️ **`R@5 = 1.000` 不是「检索完美」**：vector-only 同样 1.000 而 R@1 只有 0.737；
Top-5 里 33.3% 是干扰项；有一条正好排第 5 名。**结论是评测集饱和了。**
v3 之后主指标是 **R@1 / MRR**，R@5 降为 safety-net。

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
| 4 | **新的云端 API key** | 旧的两个已撤销。给了之后可以：跑 v3 上的云端质量（现有云端数来自 v2）、补 Local vs Cloud 成本对照 |

### P1 · 我能做，等你点头

| # | 事项 | 说明 |
|---|---|---|
| 5 | **Golden Set 继续加固到 200+** | R@5 已饱和。需要更强的近似干扰。**可以我生成（仍是 synthetic），你写更好** |
| 6 | **cross-language R@1 = 0.737** | 排序还有空间，可做 fusion 参数实验 |
| 7 | **真机基准降低方差** | 每档之间等热状态回 `nominal`，或跑 3 轮报区间。**会改变已记录的基准口径**，所以没擅自动 |
| 8 | **「开启云端能搜到英文文档」提示** | D-AI-003 的已知缺口：本地可用+云端未授权+双语库时，系统安静地用本地跑，不告诉用户。属 UI 范围 |
| 9 | **keyword 路倒排索引** | 20k 上它比向量路慢 17 倍，是 Metric A 的真瓶颈 |

### P2 · 明确不做（除非你要求）

ANN · 向量数据库 · 自托管 bge-m3 · GPU · RAG Chat · reranker / cross-encoder ·
Agent · Prompt Studio · 复杂隐私 UI。**理由：先把 Provider 决策 + 评测 + Gate 收干净。**

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
