# Mosaic v1 · 项目关闭记录

> **这份文件是终点，不是现状描述。** 它记录 Mosaic v1 在关闭那一刻的真实状态，
> 以及在什么条件下才允许重新打开。
>
> 现状读 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)，
> 重新进入的条件读 [`HANDOFF_NEXT.md`](HANDOFF_NEXT.md)。
>
> 关闭日期：2026-09-01 · 分支 `feature/mosaic-mvp-p0`
>
> **最终提交 = tag `mosaic-device-validated-v1` 指向的那一个**（本地 tag，未 push）。
> 这里刻意不写 SHA：写死一个 SHA 之后，任何一次修正这份文档的提交都会让它变成
> 一句错话，而 tag 本来就是为「指向哪一次」这件事存在的。

---

## Status

```
ENGINEERING COMPLETE
DEVICE VALIDATED
PRODUCT VALIDATION PENDING
PROJECT CLOSED
```

### 最终事实（三份文档逐字相同）

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

「关闭」的意思是**工程侧没有剩余的、可由代码解决的问题**。
它不表示产品已经过真实用户验证 —— 那件事写在 Known Limitations 里，
并且是唯一实质性的上架阻断项。

---

## Production

这三样是 v1 真正交付给用户的东西，**已冻结**：

| | |
|---|---|
| **UI** | **v2** —— 2 级信息架构（笔记流 → 笔记页）。旧的 3 级已删除 |
| **Retrieval** | **Keyword** —— `RetrievalConfig.production` = `retrieval-v2-keyword` |
| **Persistence** | **Local**（SwiftData）。无云同步 |

生产配置的一致性由 `ProductionConfigChecks` 守着，
并由 `tools/verify_device.sh` 从**真机 arm64 Release 二进制**里 `strings` 出版本号
再核对一次 —— 从源码读证明不了编译进去了什么。

---

## Retrieval

```
Keyword        = PRODUCTION      ✅ 冻结
Local Hybrid   = EXPERIMENTAL    🧪 Gate PASS · Promotion NO
Cloud Hybrid   = DEFERRED        ⏸ 产品决策
Abstention     = EXPERIMENTAL    🧪 未接生产
```

**Local Hybrid 是 `PASS` + `DO NOT PROMOTE`，这是一个合法状态**：
Gate 问的是「候选有没有把系统弄坏」（没有），
Promotion 问的是「值不值得替换生产」（不值得）。三条独立理由：

1. 质量增益 ≈ 0（R@1 / R@5 delta 精确为 `+0.000`，CI `[0,0]`；R@3 反而更低）
2. 延迟代价确定（真机 P50 约 +300%）
3. **负例克制率 100% → 0%** —— 每一条本就没有答案的 query 都会拿到一屏结果

第 3 条单独就足以否掉这次 promotion，它也解释了为什么 `Abstention`（TD-10）
必须先能上生产，语义路才谈得上替换 keyword。

**Cloud 是产品决策 DEFERRED，不是「缺凭据所以失败」。**
`SKIPPED — CREDENTIALS NOT CONFIGURED` 是它的正常状态。

---

## Quality

| | |
|---|---|
| 评测集 | `scenario-v5` —— 242 篇语料 / 207 条 query / 九类能力 / 分级相关性 / 硬负例 |
| 划分 | development 144 / holdout 63，按类别分层，**带 sha256 冻结指纹** |
| Holdout | **冻结**。最终 Gate 之后没有在它上面调过任何参数 |
| 回归集 | **7 条棘轮**（只收当前通过的），真机上逐条点名 7/7 rank 1 |
| 数据来源 | `agent_authored_realistic`，写进每一条并有断言守着 |
| 发布判定 | `gate-v1` = 绝对下限 + baseline 相对 + 配对 bootstrap 置信 + 分层延迟 + 回归 |
| Gate 下限 | **`V1_PROVISIONAL`** —— `R@1 ≥ 0.35 · R@5 ≥ 0.40 · MRR ≥ 0.38 · P95 < 250 ms` |

> **Gate 下限是临时值。** 依据是当前这份 agent 编写的评测集，
> 拿到人工编写的评测集之后**必须重新校准**（`GATE_POLICY.md` §3）。

`human_authored` / `human_annotated` 已是合法 provenance，
`notesVisibleWhileAuthoring` 字段也留好了 ——
**拿到人工数据不需要改代码**，有一条用例证明它导得进来。
本轮**没有制造任何假的人工数据**。

---

## Validation

四种环境各自独立记录，**不混表**：

| 环境 | 内容 | 结果 |
|---|---|---|
| **Mac / CLI** | `swift run mosaic-checks` | ✅ 3714 断言 · 无云端凭据 |
| **Simulator** | 单测 107 · UI 12 · Release 构建 · 0 编译警告 | ✅ |
| **Real iPhone** | 单测 107（0 skip）· UI 12 · `MosaicBench` 8（7 过 1 skip） | ✅ |
| **Release** | `verify_release.sh` · `verify_device.sh --with-bench` | ✅ |

设备：`iPhone Air (iPhone18,4)` · iOS `27.0.0` · arm64 · Release ·
thermal `nominal` · 低电量模式关闭。

**关闭时的 Metric A（keyword 生产路径 · 真机 Release）：**

| chunks | 冷 P50 | 冷 P95 | 热 P50 | 热 P95 |
|---:|---:|---:|---:|---:|
| 1 000 | 5.02 ms | 12.30 ms | 3.17 ms | 6.45 ms |
| 5 000 | 20.11 ms | 31.15 ms | 16.93 ms | 26.31 ms |
| 10 000 | 40.83 ms | 59.75 ms | 33.73 ms | 49.59 ms |
| 20 000 | **80.47 ms** | **128.69 ms** | 72.80 ms | 116.07 ms |

预算冷热两侧都是 P50 < 100 ms / P95 < 250 ms —— **全部通过**。

⚠️ **余量要说准**：最大档冷 P50 三次跑批读数是 78.08 / 80.47 / 90.99 ms，
预算 100 ms，**余量只有 10–22%，而跑批之间自身就摆动约 13 ms**。
P95 那一侧余量 1.9×，是舒服的；P50 这一侧不是。
20k 是 PRD 的上限档 —— 1k 上冷 P50 只有 5 ms。
**下一次动词法路时必须重测这一格。**

`MosaicBench` 唯一的 skip 是云端臂（`CLOUD_CREDENTIAL_REQUIRED`），
理由由脚本逐条打印并核对 —— **skip 是真的 skip，pass 是真的 pass。**

---

## Late Closure Fixes

两个在关闭前发现并修复的 P0。**它们都不需要真机才能发现** ——
只需要有人真的把 App 当 App 用一遍。

### 1 · Settings keyboard dismissal

> **Finding: settings keyboard focus was not dismissed after text entry.**

11 个输入控件在输入完成后键盘都不消失，而表单下面还有 Toggle 和按钮。

**修法**：可复用的 `settingsKeyboardDismissal(focus:)`，基于 `@FocusState` 枚举绑定。
**不用** `UIApplication.endEditing` —— 它绕过 SwiftUI 焦点系统且不可组合。
三条退出路径：键盘「完成」工具条（覆盖 `numberPad` 这种没有 Return 键的）·
`submitLabel(.done)` + `onSubmit` · `scrollDismissesKeyboard(.interactively)`。

**键盘收起 ≠ 取消输入**：设置项仍是即时保存，修饰符不碰数据。

```
FIXED · DEVICE VERIFIED · REGRESSION TESTED（Core Flow 8）
```

### 2 · Empty new-note draft prevention

> **Finding: new-note creation persisted empty drafts as untitled notes.**

点「新建」立刻 `insert` + `save`，用户什么都不写就返回 → 留下一行「未命名笔记」。

**修法**：判定收敛到内核 `NoteDraftPolicy`（纯函数，只有一处实现）。
有效内容 = 标题 ∪ 标签 ∪ 任意非空内容块 ∪ OCR/转写文本；空白字符 trim 后判空。
清理走**删除笔记那条既有路径**（媒体 → Card → derived），不新写一遍。

三个限定条件：`isNewDraft`（已有笔记被清空**不删**）·
`onDisappear` ≠「这一屏走了」（往上推「设置」也会触发）·
启动清扫 `EmptyDraftSweep`（App 被划掉时的幽灵）。

```
FIXED · DEVICE VERIFIED · REGRESSION TESTED（Core Flow 9/10/11 + EmptyDraftTests）
```

最终行为：

| 情形 | 结果 |
|---|---|
| 空草稿 | **DISCARDED** |
| 纯空白（空格 / 换行 / Tab） | **DISCARDED** |
| 有文字 | **PERSISTED** |
| 只有图片 / 录音 / 文档 / 链接 | **PERSISTED** |
| 已有笔记被用户清空 | **NOT AUTO-DELETED** |

---

## Known Limitations

**只有五条，全部不是「没做完」，而是「明确不在 v1 范围内」：**

1. **人工评测尚未进行** —— 207 条 query 全是 agent 编写的。
   Gate PASS 只说明判定链路闭合，**不说明真实用户体验达标**。
2. **没有生产级云端语义检索** —— 产品决策 DEFERRED。
3. **没有 iCloud 同步** —— `DISABLED_UNTIL_REAL_CLOUDKIT_AVAILABLE`。
   设置页据实显示「此版本不提供」，不给一个必然失败的开关。
4. **没有生产级 abstention** —— TD-10 未解决（余量 0.0002）。
5. **分发需要 Apple 账号** —— TestFlight / App Store Connect 需付费 Developer Program。
   免费个人 Team 还有一条硬限制：一台设备最多 3 个 App。

---

## Reopen Conditions

**默认不恢复功能开发。** 只有以下五种情况允许重新进入主开发：

1. **真实用户报告了 bug**
2. **真实用户反馈产生了产品需求**
3. **人工编写的评测数据到位**
4. **App Store / TestFlight 发布工作开始**
5. **新的产品范围被明确批准**

以上五条之外：

```
DO NOT RESUME FEATURE DEVELOPMENT
```

---

## Final Project Tree

```
MOSAIC v1
│
├── Product
│   ├── UI v2                     ✅ FROZEN
│   ├── Notes                     ✅ FROZEN
│   ├── Empty Draft Lifecycle     ✅ FROZEN
│   ├── Settings Keyboard UX      ✅ FROZEN
│   ├── Search                    ✅ FROZEN
│   └── Persistence (local)       ✅ FROZEN
│
├── Retrieval
│   ├── Keyword Production        ✅ FROZEN
│   ├── Local Hybrid              🧪 EXPERIMENTAL (Gate PASS · Promotion NO)
│   ├── Cloud Hybrid              ⏸ DEFERRED
│   └── Abstention                🧪 EXPERIMENTAL
│
├── Quality
│   ├── Scenario Eval (v5)        ✅ FROZEN (sha256)
│   ├── Regression (7 witnesses)  ✅
│   ├── Gate v1                   ✅ PROVISIONAL
│   └── Human Eval                ⏭ FUTURE (import path ready)
│
├── Validation
│   ├── Mac                       ✅
│   ├── Simulator                 ✅
│   ├── Real Device               ✅
│   └── Release                   ✅
│
└── Lifecycle
    ├── Engineering               ✅ COMPLETE
    ├── Device Validation         ✅ COMPLETE
    ├── Product Validation        ⏭ FUTURE
    └── Project                   🔒 CLOSED
```

---

## 这个项目留下的三条经验

写在最后，因为它们比任何一个具体修复都更可能在下一个项目里再用到。

1. **「全绿」必须带上「在什么条件下」。**
   `MosaicBench` 的 7 条一直在 skip（没有真机），也就是说延迟那一整条
   从来没有产生过结论。真机跑起来之后**第一次就 FAIL**。
   一个从来没跑过的 Gate 与没有 Gate 没有区别。

2. **只在模拟器上绿不算绿。** 真机第一轮抓到四件事，其中两件是
   「我们以为已经生效的东西其实从来没生效」—— 生产配置一直跑的是 hybrid；
   归一化缓存每次按键都新建一个空的。**两条路结果逐位相同，只是慢，
   所以没有任何既有测试会因此变红。**

3. **测试全绿也不算做完。** 最后两个 P0 是用户自己用出来的。
   12 条 UI 流程当时全绿，只是没有人做过「点了新建又什么都不写」
   和「在设置里输入完然后想点下面那个开关」这两个动作 ——
   **因为写测试的人是照着功能写的，不是照着人写的。**
