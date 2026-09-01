# Mosaic v1 —— NEXT ENTRY CONDITIONS

> **这个项目已经关闭。这份文件不是 backlog，是一道门。**
>
> 它回答的唯一问题是：**什么情况下才允许重新进来。**
>
> 关闭记录读 [`PROJECT_CLOSURE.md`](PROJECT_CLOSURE.md)，
> 现状读 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)，
> 发布标准读 [`GATE_POLICY.md`](GATE_POLICY.md)。

---

```
Do not resume feature development by default.
```

```
PRODUCTION_RETRIEVAL  = KEYWORD
LOCAL_HYBRID          = EXPERIMENTAL   (Gate PASS · Promotion NO)
CLOUD_SEMANTIC        = DEFERRED
ABSTENTION            = EXPERIMENTAL
UI_V2                 = PRODUCTION
ICLOUD                = DISABLED_UNTIL_REAL_CLOUDKIT_AVAILABLE
GATE_POLICY_VERSION   = V1_PROVISIONAL
HUMAN_AUTHORED_EVAL   = FUTURE_PRODUCT_VALIDATION
DEVICE_VALIDATION     = COMPLETE
ENGINEERING           = COMPLETE
PROJECT               = CLOSED
```

Mosaic v1 的工程侧**没有剩余的、可由代码解决的问题**。
不存在「下一个 Sprint」，也不存在「接着做 X 然后做 Y」。

如果你正准备写一行代码，先确认它属于下面五个入口之一。**不属于就不要写。**

---

## 五个入口

### 1 · Real User Bug

真实用户报告的缺陷。

进来之后：先复现，再修，然后**在真机上验证** ——
这个项目的最后两个 P0 都是「模拟器全绿但用起来不对」。
修完补一条回归用例，跑完整验证矩阵（见下）。

### 2 · Real User Feedback

真实用户反馈产生的产品需求。

**反馈不等于需求。** 先把它变成一句可证伪的产品主张，再决定要不要做。

### 3 · Human Evaluation

人工编写的评测数据到位。

**这是 App Store 唯一的实质阻断项。** 基础设施已经就绪，不需要改代码：

- `provenance` 接受 `human_authored`（提问者，没看笔记）
  与 `human_annotated`（标注者，看得到笔记）——
  两者分开是因为**偏差方向相反**：看着笔记写 query 会不自觉地抄词面
- `notesVisibleWhileAuthoring` 字段留好了，**必须记准** —— 它就是那条偏差的开关
- `ScenarioDatasetChecks` 有一条用例证明这样的 JSON 导得进来

数据到位之后要做的第一件事是**重新校准 Gate 下限**：
现在的 `R@1 0.35 / R@5 0.40 / MRR 0.38` 是 `V1_PROVISIONAL`，
依据是 agent 编写的评测集（`GATE_POLICY.md` §3）。
改它要 bump 版本号（`gate-v1` → `gate-v2`）、写新依据、重跑 baseline。

### 4 · App Store Release

发布工作开始。

需要付费 Apple Developer Program（TestFlight / App Store Connect / CloudKit 容器）。
代码侧已就绪，`verify_release.sh` 与 `verify_device.sh` 都是绿的。
上架前可以替换 App 图标 —— 现在那个是脚本生成的临时品牌资产。

免费个人 Team 的两条硬限制会先撞上：**一台设备最多 3 个 App**
（XCUITest 的 Runner 是独立 App）；真机 UI 自动化要在设备上打开
「启用 UI 自动化」（设置 ▸ 隐私与安全性 ▸ 开发者模式）。

### 5 · Approved New Scope

新的产品范围被明确批准。

「明确」= 产品负责人说了要做什么。**技术上可行不构成理由。**

---

## 不构成入口的事

以下都已分类归档，**它们不是待办**：

| 分类 | 内容 | 在哪儿 |
|---|---|---|
| **FUTURE PRODUCT VALIDATION** | 人工 query · 真实反馈 · Gate 重新校准 · Gate v2 | 入口 3 |
| **FUTURE RETRIEVAL RESEARCH** | 云端语义检索 · Local Hybrid 改进 · Abstention 生产化（TD-10）· `lexical_trap` 0.095 · 新排序方法 | `GATE_POLICY.md` §8 · `PROJECT_STATUS.md` §8 |
| **FUTURE SCALE** | 50k / 100k 语料 · 大库优化 · 内存优化 | `RETRIEVAL_ARCHITECTURE.md` §26.6（含重新打开的条件） |
| **APP STORE RELEASE** | Developer Program · TestFlight · App Store Connect · 商店素材 · CloudKit（如获批） | 入口 4 |
| **OPTIONAL POLISH** | App 图标替换 · PDF 导出 · 媒体文件同步 · TD-1 / TD-4 · 额外测试 | `PROJECT_STATUS.md` §8 |

**没有第六类。** 尤其没有「someday」「以后再说」「有空就做」。

---

## 重新进来之后怎么跑

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
./tools/verify_device.sh --with-bench
```
```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -configuration Debug -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates -only-testing:MosaicTests -only-testing:MosaicUITests
```

`verify_device.sh` 自己发现设备，**不硬编码 udid**。
它用 `devicectl` 而不是 `xctrace` —— 后者只把 USB 直连的列进「== Devices ==」，
网络配对的会落进「Offline」，而那种设备 `xcodebuild` 照样能装能跑。

### 关闭时的基线（拿它对比，不是拿它当目标）

| 套件 | 结果 | 机器 |
|---|---|---|
| 内核 checks | 3714 断言 | Mac · debug · 无云端凭据 |
| App 单测 | 107 条 | 模拟器 **与** 真机（真机 0 skip） |
| UI 测试 | 12 条 | 模拟器 **与** 真机 |
| `MosaicBench` | 8 条 · 7 过 · 1 skip | 真机 Release（skip = 云端臂） |
| 20k 冷 P50 | 78.08 – 90.99 ms（三次） | 真机 Release（预算 100 ms，余量仅 10–22%） |

**报结果时写明跑在哪台机器上，以及云端臂跑没跑。**

---

## 九个容易踩的坑

1. **新增 App 文件后必须 `cd App && xcodegen generate`**，否则 Xcode 工程里没有它。
2. **`MosaicBench` 必须走自己的 scheme**。`MosaicTests` 用 `@testable`，Release 下不可用。
3. **别在真机测试跑的同时跑 `build-for-testing`** —— 会抢 DerivedData。用不同的
   `-derivedDataPath`。
4. **改评测集后要重跑生成脚本并更新冻结指纹**：
   `python3 tools/eval/build_scenario_set.py`，把 checksum 抄进
   `ScenarioDatasetChecks.frozenChecksum`。不改的话 checks 会红，那正是它该做的。
5. **不要拿 holdout 调参。** 它已经用于最终 Gate，是冻结的。
   holdout 上发现问题要先分清「实现缺陷」还是「排序能力不足」。
6. **不要在测试里写死机器假设**（`.simulator` / `"debug"`）。
   要环境就取 `RunEnvironment.capture()` 的当前值 —— 曾经 12 条用例因此只在模拟器上成立。
7. **不要让测试依赖「本机有没有某个模型」。** 把可用性作为参数传进去
   （`ProductionEmbedding.decide` 支持）。否则分支里写错的期望在一半的机器上永远执行不到 ——
   曾经**最重要的那条隐私断言**因此在 iPhone 上从未运行过。
8. **不擅自 push / 建 PR** —— 用户会明确说。
9. **凭据不进对话记录**：写本地文件、给路径，跑完删除。

---

## 这个项目的工作方式（**请延续**）

1. **先读代码再动手**，不假设。每轮开始 `git status` / `git log` 看真实状态。
2. **结论必须来自测量。** 这个项目至少 **13 次**直觉是错的，清单在
   `PROJECT_STATUS.md` §10。
3. **不编造数据。** 没测的写「待验证」；外推值标 *estimated*；
   Mac / 模拟器数字**绝不**冒充真机数字。
4. **新数据推翻旧结论时接受新数据**，不维护旧结论。
5. **发现既有缺陷要报告，但不擅自扩大范围**。
6. **测试要能证明退出标准，不是刷数量。** 一条只是把当前行为抄了一遍的断言
   保护不了任何东西；**一条永远被 skip 的断言等于不存在**。
7. **只在模拟器上绿不算绿。** 真机第一轮抓到的四个缺陷没有一个能在模拟器上发现。
8. **测试全绿也不算做完。** 最后两个 P0 是用户自己用出来的 ——
   **每一轮收口前，自己把 App 当 App 用一遍。**
