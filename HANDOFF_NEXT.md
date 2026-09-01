# Mosaic —— 交接说明（给下一个对话窗口）

> 写于 2026-09-01。分支 `feature/mosaic-mvp-p0`。
>
> **先读 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)**（现在是什么状态），
> 再读这一份（下一步做什么）。工程决策在 `RETRIEVAL_ARCHITECTURE.md`，
> 发布标准在 `GATE_POLICY.md`。

---

## 0. 三十秒版本

上一轮把项目推到「模拟器上全绿」。这一轮做的是**真机验证**，
而真机第一轮就抓到四件模拟器上发现不了的事：

1. **文档说 keyword，代码默认 hybrid** —— 线上跑的一直是 hybrid
2. **归一化缓存从来没有到达过用户** —— 每次按键都新建一个空的
3. **一个开了也没用的开关** —— 纯词法生产下「智能搜索」那一段没有任何作用
4. **删除笔记会让 App 崩掉** —— SwiftData 的对象被删后 body 还在读它

另外 14 条单测「只在模拟器上成立」（写死 `.simulator` / 依赖本机有没有中文模型），
其中包括**全项目最重要的那条隐私断言** ——「没同意就不构造云端 provider」——
它的 skip 条件恰好在 iPhone 上永远成立，也就是说它在用户真正会用的机器上
从来没有验证过。

四件事都已修，细节见 `PROJECT_STATUS.md` §9。

**当前状态**：

```
ENGINEERING COMPLETE · DEVICE VALIDATED
生产检索 = KEYWORD（代码 / 配置 / UI / Gate / 文档一致，有断言守着）
```

---

## 1. 剩下的工作 —— 只有五类，没有「someday」

所有剩余项都落在下面五类里的一类。**不存在第六类。**
如果某件事属于「当前正确性 / 当前发布工程 / 当前 UI 缺陷 / 当前测试失败」，
它就不该在这份清单上 —— 那种事这一轮已经做完了。

### A · FUTURE PRODUCT VALIDATION（产品验证，只有用户能做）

| # | 事项 | 为什么只有你能做 |
|---|---|---|
| **A1** | **人工编写的评测 query** | 当前 207 条全是 `agent_authored_realistic`。Gate PASS 只说明判定链路闭合，不说明真实用户体验达标。**这是 App Store 唯一的实质阻断项** |
| **A2** | **重新校准 Gate 下限** | `R@1 0.35 / R@5 0.40 / MRR 0.38` 是 `V1_PROVISIONAL`，依据是 agent 编写的评测集。拿到 A1 之后必须重跑并重定 |

**基础设施已经就绪，A1 不需要改代码。** schema 接受 `provenance: "human_authored"`
与 `notesVisibleWhileAuthoring`，`ScenarioDatasetChecks` 有一条用例证明它导得进来。
写 query 的时候把 `notesVisibleWhileAuthoring` 记准 ——
看着笔记写出来的 query 会不自觉地抄词面，那种数据能证明的东西比它看起来少得多。

### B · FUTURE RETRIEVAL RESEARCH（检索研究，不阻塞发布）

| # | 事项 | 说明 |
|---|---|---|
| **B1** | **`lexical_trap` 只有 0.095** | 21 条里只对了 2 条。这一类正是 hybrid 存在的理由，而本机 hybrid 一条都没多解决 |
| **B2** | **TD-10 相关性下限** | 它是 local-hybrid 不能上生产的**直接原因**：负例克制率 100% → 0%。abstention 能上生产之后，语义路才谈得上替换 keyword |
| **B3** | **backlog 里的 5 条** | 两个缺陷的证人里至今仍失败的：`HG041` `LT01` `CR01` `NQ04` `NQ11`。**明确不放进回归集**（回归集是棘轮不是愿望清单） |
| **B4** | **`ambiguous` 需要产品决定** | 「押金多久退」有两个都对的答案。要不要一次返回两条、要不要提示「有两处相关」，是设计问题不是检索问题 |
| **B5** | **切分参数还能更松** | development 上 `r=0.25 f=1` 到 R@1 0.336、`r=0.15 f=2 +latin` 到 0.398，代价是负例克制率降到 80% / 70%。**等 B2 解决再回来取** |
| **B6** | **8 个簇仍是 3–5 篇** | 那些簇上的 R@5 没有区分度。要么扩到 6 篇，要么在报告里不用它们支持 R@5 的结论 |

### C · DEFERRED BY PRODUCT DECISION（产品已决定跳过）

| # | 事项 | 状态 |
|---|---|---|
| **C1** | **云端语义检索** | `DEFERRED`。代码在、路由在、`SKIPPED — CREDENTIALS NOT CONFIGURED` 是它的正常状态，**不构成项目 FAIL**。不要为它请求 API Key，不要用 mock 冒充它 |
| **C2** | **iCloud 同步** | `DISABLED_UNTIL_REAL_CLOUDKIT_AVAILABLE`。打开它要同时做三件事（付费账号 + 容器 + `MOSAIC_CLOUDKIT_ENABLED=YES`），缺一不可 |

### D · EXTERNAL ACCOUNT SETUP（要 Apple 账号）

| # | 事项 |
|---|---|
| **D1** | **付费 Apple Developer Program** —— TestFlight / App Store Connect / CloudKit 容器都要它 |
| **D2** | 免费个人 Team 的硬限制：**一台设备最多 3 个 App**。本轮真机 UI 测试撞到过 —— XCUITest 的 Runner 是一个独立 App，装不进去就跑不了 |
| **D3** | 真机 UI 自动化需要设备上打开「**启用 UI 自动化**」（设置 ▸ 隐私与安全性 ▸ 开发者模式）。不开的话报 `Timed out while enabling automation mode`，看起来像构建问题 |

### E · OPTIONAL POLISH（可做可不做，不影响发布判定）

| # | 事项 |
|---|---|
| **E1** | **App 图标是临时品牌资产**（脚本生成）。上架前可替换，**不阻塞任何测试** |
| **E2** | PDF 导出（当前有 Markdown / 纯文本） |
| **E3** | 媒体文件同步（元数据可同步，二进制不同步） |
| **E4** | TD-1（`SummaryService` 无 stale 保护）· TD-4（waiter 泄漏，当前深度无害） |

---

## 2. 怎么跑

### 不需要设备

```bash
swift run mosaic-checks
```
```bash
cd App && xcodegen generate
```
```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skip-testing:MosaicBench
```
```bash
./tools/verify_release.sh
```

### 需要连真机

```bash
./tools/verify_device.sh
```
```bash
./tools/verify_device.sh --with-bench
```
```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -configuration Debug -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates -only-testing:MosaicTests -only-testing:MosaicUITests
```
```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates
```

`verify_device.sh` 自己发现设备，**不硬编码 udid** —— 上一轮的交接文档里写死了一个，
换台手机就变成一句谎话。

### 最近一次的数字

| 套件 | 结果 | 机器 |
|---|---|---|
| 内核 checks | ✅ 3687 断言 | Mac · debug · **无云端凭据** |
| App 单测 | ✅ 99 条 | 模拟器 **与** 真机（真机 0 skip） |
| UI 测试 | ✅ 8 条 | 模拟器 **与** 真机 |
| `MosaicBench` | ✅ 8 条 · 7 过 · 1 skip | **真机 Release**（skip 的是云端臂） |
| 发布核对 | ✅ 全过 | `verify_release` + `verify_device` |

**报结果时请写明跑在哪台机器上，以及云端臂跑没跑。**

---

## 3. 八个容易踩的坑

1. **新增 App 文件后必须 `cd App && xcodegen generate`**，否则 Xcode 工程里没有它。
2. **`MosaicBench` 必须走自己的 scheme**。`MosaicTests` 用 `@testable`，Release 下不可用。
3. **别在真机测试跑的同时跑 `build-for-testing`** —— 会抢 DerivedData。用不同的
   `-derivedDataPath`（本轮就是这么并行跑的）。
4. **改评测集后要重跑生成脚本并更新冻结指纹**：
   `python3 tools/eval/build_scenario_set.py`，把 checksum 抄进
   `ScenarioDatasetChecks.frozenChecksum`。不改的话 checks 会红，那正是它该做的。
5. **不要拿 holdout 调参。** 它已经用于最终 Gate，从现在起是冻结的。
   holdout 上发现问题要先分清「实现缺陷」还是「排序能力不足」——
   前者可以修，后者进 §1.B。
6. **不要在测试里写死 `.simulator` 或 `#if targetEnvironment(simulator)` 之外的机器假设。**
   本轮 14 条失败全是这个。要环境就取 `RunEnvironment.capture()` 的当前值。
7. **不要让测试依赖「本机有没有某个模型」。** 把可用性作为参数传进去
   （`ProductionEmbedding.decide` 现在支持）。否则分支里写错的期望
   在一半的机器上永远执行不到。
8. **不擅自 push / 建 PR** —— 用户会明确说。
9. **凭据不进对话记录**：写本地文件、给路径，跑完删除。

---

## 4. 这个项目的工作方式（**请延续**）

1. **先读代码再动手**，不假设。每轮开始 `git status` / `git log` 看真实状态。
2. **结论必须来自测量。** 这个项目至少 **13 次**直觉是错的，清单在
   `PROJECT_STATUS.md` §10。本轮新增三条，其中两条是「我们以为已经生效的东西
   其实从来没生效」。
3. **不编造数据。** 没测的写「待验证」；外推值标 *estimated*；
   Mac / 模拟器数字**绝不**冒充真机数字。
   本轮起草文档时一度先写了一张 Metric A 的表再去跑基准 —— 那是编造，已撤回重填。
4. **新数据推翻旧结论时接受新数据**，不维护旧结论。
5. **发现既有缺陷要报告，但不擅自扩大范围**（TD-1 至今没动）。
6. **测试要能证明退出标准，不是刷数量。** 一条断言如果只是把当前行为抄了一遍，
   它保护不了任何东西。反过来，**一条永远被 skip 的断言等于不存在** ——
   本轮就有一条隐私断言因此在真机上从未运行。
7. **只在模拟器上绿不算绿。** 本轮的四个缺陷没有一个能在模拟器上发现。
