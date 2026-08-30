# Mosaic —— 交接说明（给下一个对话窗口）

> 写于 2026-08-29。分支 `feature/mosaic-mvp-p0`。
>
> **先读 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)**（现在是什么状态），
> 再读这一份（下一步做什么）。工程决策在 `RETRIEVAL_ARCHITECTURE.md`。

---

## 0. 三十秒版本

上一轮把项目从「Goal 1 工程完成、UI 还是旧的」推到了：

- **UI v2 全部落地**，旧的三级导航已删除
- **评测集换成 `scenario-v5`**：207 条场景化 query，九类能力，分级标注，dev/holdout
- **Gate v1**：baseline 相对 + 统计置信 + 绝对下限
- **修掉三个真缺陷**：删文件夹的 derived 泄漏 · iCloud 状态说谎 · **中文 query 在词法路全灭**

**当前判定：BLOCKED。** 不是链路没跑通，是质量真的没到线。

---

## 1. 现在最要紧的三件事

### P0 · 只有你能做

| # | 事项 | 为什么阻塞 |
|---|---|---|
| **1** | **云端 embedding 凭据** | 本机语义路对 R@1 的贡献实测是 **+0.000**。质量要从云端来，而云端臂现在是 `NOT RUN — MISSING CREDENTIALS`。凭据放 `~/.mosaic-cloud.env`（仓库外，`chmod 600`），`source` 后重跑 |
| **2** | **真机复测延迟** | CJK 切分改动让 keyword P95 从 2.9 ms 涨到 ~29 ms（Mac debug）。**这个数字必须在真机 release 上重测**，Mac 的不算 |
| **3** | **PRD 的 Gate 定值** | 现在的绝对下限 `R@1 0.35 / R@5 0.40 / MRR 0.38` 是**产品判断**，依据写在 `GATE_POLICY.md` §3。拿到 PRD 定值后改一个结构体 |

### P1 · 我能做，等你点头

| # | 事项 | 说明 |
|---|---|---|
| 4 | **回归集还是空的** | Gate 的第四行恒过。从 `scenario-v5` 的失败用例里挑一批进回归集，这一行才开始保护东西 |
| 5 | **`lexical_trap` 只有 0.048** | 21 条里只对了 1 条。这一类是 hybrid 存在的理由，现在它几乎没有被解决。云端臂跑起来之后先看这一类 |
| 6 | **`noisy_query` / `ambiguous` 全 0** | 错别字与歧义两类完全没有覆盖能力。前者可能靠编辑距离，后者需要产品决定「要不要一次返回两条」 |
| 7 | **8 个簇仍是 3–5 篇** | 那些簇上的 R@5 没有区分度。要么扩到 6 篇，要么在报告里不用它们支持 R@5 的结论 |
| 8 | **CJK 切分参数还能更松** | development 上 `r=0.25 f=1` 能到 R@1 0.317、`r=0.15 f=1` 到 0.358，代价是负例克制率降到 80% / 70%。**等 abstention 能上生产再回来取**（`GATE_POLICY.md` §6） |

### P2 · 明确不做

ANN · 向量数据库 · 自托管 bge-m3 · GPU · RAG Chat · reranker · Agent · Prompt Studio。
理由不变：先把 Provider 决策 + 评测 + Gate 收干净。

---

## 2. 怎么跑

```bash
swift run mosaic-checks
```
```bash
cd App && xcodegen generate
```
```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
```bash
./tools/verify_release.sh
```
```bash
MOSAIC_SEG_SWEEP=1 swift run mosaic-checks
```

真机基准（要连设备）：

```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=00008150-000064912E87801C' -allowProvisioningUpdates
```

### 最近一次的数字

| 套件 | 结果 | 条件 |
|---|---|---|
| 内核 checks | ✅ 3633 断言 | Mac · debug · 约 4 分钟 · **无云端凭据** |
| App 单测 | ✅ 93 tests | iPhone 17 Pro 模拟器 |
| UI 测试 | ✅ 6 flows | 同上 |
| MosaicBench | ⏭ 7 条 skip | 模拟器上按设计跳过 |
| 发布核对 | ✅ 全过 | Release 产物 |

**报结果时请写明云端臂跑没跑。**

---

## 3. 六个容易踩的坑

1. **新增 App 文件后必须 `cd App && xcodegen generate`**，否则 Xcode 工程里没有它。
2. **`MosaicBench` 必须走自己的 scheme**。`MosaicTests` 用 `@testable`，Release 下不可用。
3. **别在真机测试跑的同时跑 `build-for-testing`** —— 会抢 DerivedData。
4. **改评测集后要重跑生成脚本并更新冻结指纹**：
   `python3 tools/eval/build_scenario_set.py`，把 checksum 抄进
   `ScenarioDatasetChecks.frozenChecksum`。不改的话 checks 会红，那正是它该做的。
5. **不要拿 holdout 调参**。参数用 development 定（`QuerySegmentationSweep` 就是干这个的）。
   针对某一条 holdout 用例加特殊逻辑属于 overfit，必须撤销。
6. **`design/` 现在在 git 里了**（`DESIGN_DIRECTORY = VERSION_CONTROLLED`），
   不再是「在磁盘上但不在版本控制里」。

---

## 4. 这个项目的工作方式（**请延续**）

1. **先读代码再动手**，不假设。每轮开始 `git status` / `git log` 看真实状态。
2. **结论必须来自测量。** 这个项目至少 **8 次**直觉是错的，清单在
   `PROJECT_STATUS.md` §8。最近一次：「自然语言中文 query 在词法路零命中是设计前提」——
   它是缺陷，修好之后 R@1 +67%。
3. **不编造数据。** 没测的写「待验证」；外推值标 *estimated*；
   Mac / 模拟器数字**绝不**冒充真机数字。
4. **新数据推翻旧结论时接受新数据**，不维护旧结论。
5. **发现既有缺陷要报告，但不擅自扩大范围**（TD-1 至今没动）。
6. **测试要能证明退出标准，不是刷数量。** 每条断言对应一个明确主张。
   一条断言如果只是把当前行为抄了一遍，它保护不了任何东西 ——
   本轮就修正了四条这样的断言（`GATE_POLICY.md` §6 末尾）。
7. **不擅自 push / 建 PR** —— 用户会明确说。
8. **凭据不进对话记录**：写本地文件、给路径，跑完删除。

---

## 5. 上下文里可能有的错误说法（以本文件与 `PROJECT_STATUS.md` 为准）

- ~~「评测集是 synthetic-human-v4，166 正例 + 30 负例」~~ → 现在是 **`scenario-v5`**，207 条
- ~~「in-scope R@5 恒为 1.000」~~ → 那是 v4 的簇太小（3 篇）。v5 扩到 6–8 篇后不再饱和
- ~~「UI 还是文件夹优先的三级结构」~~ → **UI v2 已落地**，旧的三级已删除
- ~~「Gate 判的是 R@1 / R@5 / MRR / 延迟 / 回归」~~ → 还多一行**绝对下限**（gate-v1）
- ~~「零容差意味着任何退化都阻断」~~ → gate-v1 下**只有统计显著的退化**才阻断
- ~~「keyword 对无答案 query 100% 克制」~~ → 那是分词缺陷的副产品，现在是 90%
- ~~「整句自然语言 query 在 keyword 路零命中是设计前提」~~ → **是缺陷，已修**
- ~~「abstention 已经做完了」~~ → 内核做完了，**没接生产**，且有断言守着不接
- ~~「iCloud 只要用户在设置里打开就能用」~~ → entitlements 里没有容器，**此版本不提供**
- ~~「design/ 被 .gitignore 忽略，不要 git add」~~ → 已入库
