# Mosaic 设计基线

# DESIGN STATUS: **RE-FROZEN — Production Semantic Search 已交付**

原冻结时间：**2026-08-07**
解冻时间：**2026-08-07**，依据冻结约束第 2 条「产品决策改变」——
Goal 1（Mosaic AI Retrieval Quality Platform PRD v1.0）把 Search 从 keyword 升级为隐式 Hybrid，
契约见 [`SEARCH_CONTRACT.md`](SEARCH_CONTRACT.md)。
重新冻结：**2026-08-07**，经 5 轮 Figma 实跑 + MCP 实读，7 项缺陷全部修复并逐项验证。

**本次解冻的范围严格限定为 Search。** 其余 17 屏与既有 37 个组件在设计上不动 ——
唯一的例外是 F-5：`19 · AI 摘要 9 态一览` 与首页 `Note / Preview` 的文案修复。
那是新检查器在 Search 之外抓到的**既有缺陷**，属于「实现暴露真实设计问题」，按冻结约束第 1 条处理。

## Figma Status

| 范围 | 状态 | 载体 |
|---|---|---|
| **Production UI** | **RE-FROZEN** | `design/figma-plugin/` → 📐 Foundations · 🧩 Components · 📱 Screens |
| **Developer Tools** | **LOW-FI / IMPLEMENTATION READY** | `design/figma-plugin-devtools/` → 🔧 Dev Tools (Wireframe)（Track B，独立插件） |

两条流水线**完全分离**：Track B 不创建任何 Variable / Style，不进 calibration，
不触碰 Production 三页（其冒烟测试对这两条有断言）。

Developer Tools 的 IA、逐页交接规格、Failure Inspection / Trace / Regression 的
SwiftUI-first 规格见 [`DEVTOOLS.md`](DEVTOOLS.md)。

---

## 当前施工状态

| 项 | 值 |
|---|---|
| 已完成 | Search Field · Row / Search Result · Bar / Search Status 三组件；`06` 改为 Matched Excerpt 形态；`12` 补为自然语言示例形态；`13` 文案更新；新增 `21`–`26` 六屏 |
| 组件数 | 37 → **40**（变体集 26 → 29，变体 116 → **125**，组件属性 35 → **41**，实例 450 → **575**） |
| 屏数 | 20 → **26** ×2 模式 = **52** |
| 原型连线 | 22 → **25**（Flow 7 补三条：示例→相关结果 · 重试→恢复 Hybrid · 返回→状态恢复；结果落点改为 `25` 高亮态而非普通笔记页） |
| 自动化 | `node test/all.js` **5 套件全绿**（checks 9 → **11** 项，selftest 13 → **15** 个变异） |
| 第 1 轮实读 | 发现 F-1 / F-2，已修复 |
| 第 2 轮实读 | F-1 / F-2 确认修复；`06` 五条结果实测 393×110.5，与桩逐项相同 |
| 第 3 轮实读 | 发现 **F-3 / F-4**，以及 Search 之外的既有缺陷 **F-5**，均已修复 |
| 第 4 轮实读 | **F-3 / F-4 / F-5 全部确认修复**；🧩 Components 页首次直读，40 / 29 / 11 / 125 四项吻合。同轮新发现既有缺陷 **F-6 / F-7**，已修复 |
| 第 5 轮实读 | **F-6 / F-7 确认修复。F-1…F-7 七项缺陷全部实读验证通过，无已知缺陷。** |
| Developer Tools 轮次 | 2026-08-07。**生产 Figma 净改动为零** —— Developer Mode 入口曾加进 `11 · 高级设置`，因超出可视区被裁而回退，改由 Track B 的 D0 承载（见 `DECISION_LOG.md` D-UI-DEV-006） |

### 第 1 轮实读发现的缺陷（已于第 2 轮确认修复）

| # | 缺陷 | 根因 | 修复 |
|---|---|---|---|
| **F-1** | Search Result 的 excerpt 渲染成**一条被裁掉的单行**，不换行 | `lines: 2` 配 `grow: 1`，指望 auto-layout 约束宽度。Figma 实际不换行。**桩也估成一行，两边一致地错，calibration 全绿** | 改为显式定宽（329）。新增 `checks.multiline-width` 检查器 + 变异用例锁死 |
| **F-2** | 标题命中高亮**完全不可见** | 标题本身是 `text/primary`，对比式高亮提到 `text/primary` 是零效果 | 取消标题高亮（见 `SEARCH_CONTRACT.md` §2.4） |

同轮确认 **有效**：excerpt 的分段前景高亮在 Figma 中正常渲染，且在 TEXT 组件属性覆盖之后依然保留。

### 第 3 轮实读发现的缺陷（已于第 4 轮确认修复）

| # | 缺陷 | 根因 | 修复 |
|---|---|---|---|
| **F-3** | `23 · 智能搜索不可用` 显示的是 `building` 的文案「正在准备智能搜索…」 | **Figma 的 TEXT 组件属性全变体共用一个默认值**，切换变体不换文案。四个变体里三个在说谎 | 删掉 `Bar / Search Status` 的 Message / CTA Label 两个 TEXT 属性 —— 这四句文案是状态定义的一部分，不是可填内容 |
| **F-4** | `25` / `26` 落在通用样例笔记「Q3 产品评审会」上，与引它们过来的搜索结果毫无关系 | 复用了笔记页模板，没换内容 | `noteHeader` 加 title 参数；两屏改为落在 `和 advisor 的邮件往来` / `周会录音 · 10/22`，正文与转写改成真正被命中的那段话 |
| **F-5** | **既有缺陷，非本次引入。** `19 · AI 摘要 9 态一览` 八行全部显示「AI 一句话概述」；首页 audio/image/empty 三种 Preview 同样显示「AI 一句话概述」 | 与 F-3 同一根因。`Bar / Summary`（9 种文案）与 `Note / Preview`（5 种文案）各自共用一个 TEXT 默认值，而实例没有显式赋值 | `iSummaryBar` / `iNoteRow` 兜底到各变体本体文案；`scAIStates` 改走 `iSummaryBar` 而非自己 `createInstance` |

> **F-5 值得单独说一句。** 它藏在一份标着 `FROZEN — READY FOR IMPLEMENTATION`、
> 且 9/9 + 9/9 + 86/86 全绿的设计里。`19 · AI 摘要 9 态一览` 这一屏的**全部意义**
> 就是把九个状态的差异讲清楚，而它有八行在显示同一句话 ——
> 工程师照着实现，四个错误态的文案就全错了。
>
> 这不是被"更仔细地看图"发现的，是被一条新检查器发现的：`checks.text-prop`。

### 第 4 轮实读发现的缺陷（已于第 5 轮确认修复）

| # | 缺陷 | 根因 | 修复 |
|---|---|---|---|
| **F-6** | **既有缺陷。** 首页两条 `ai-summary` 笔记行显示属性默认值「AI 一句话概述」，而不是各自的摘要 | `Note / Preview` 是**嵌套实例**，文本被自身 TEXT 属性绑定驱动，直接写 `characters` 会被默认值盖回去。只在 ai-summary 行暴露 —— 它的 INSTANCE_SWAP 目标恰好等于属性默认值，Figma 视作没换，绑定始终有效；其它预览因发生真实 swap 反而写得进去 | 删掉 `Note / Preview` 的 TEXT 属性。去掉属性 = 去掉绑定，直接写 `characters` 在所有情况下都成立 |
| **F-7** | `26 · 转写命中` 的转写文案没换成命中内容，仍是通用样例 | `Audio / Transcript` 把**组件本身和内部文本节点都叫 `Transcript`**，`findOne` 先命中外层实例；往非文本节点写 `characters` 既不报错也不生效 | `setInstText` 限定 `type === 'TEXT'`，且**找不到就抛错** —— 生成器宁可当场炸掉，也不要安静地渲染错误文案 |

> **F-6 / F-7 也都是既有缺陷**，不是这次改出来的：F-6 从 `Note / Preview` 建成起就在，
> F-7 是我在 26 屏第一次用 `setInstText` 打转写时才触发的同名陷阱。
> 两者的共同点仍然是**桩不复现**：桩里 `pv.setProperties` 根本不存在（嵌套实例被克隆成普通 FRAME），
> 于是走了回退分支、输出看起来完全正确，测试全绿。这已经是同一个陷阱的第三种形态。

### 新增的两条检查器

| 检查器 | 守什么 | 变异用例 |
|---|---|---|
| `multiline-width` | `maxLines >= 2` 必须显式定宽 —— 靠 `grow` / `stretch` 在 Figma 里**不会换行**，文本会拉成一条长行被裁掉（F-1） | 把 Search Result 的 excerpt 退回 `grow: 1` |
| `text-prop` | 变体间文案不同的 TEXT 属性，**每个实例都必须显式赋值**，否则只会拿到那一个默认值（F-3 / F-5） | 给 `Bar / Search Status` 加回 Message TEXT 属性 |

两者都判定**编写方式**而非排版结果，因此不依赖桩的排版保真度。
`text-prop` 需要桩记住「被默认值盖掉之前的文案」（`_authoredChars`）—— 覆盖之后各变体看起来都一样，事后无法分辨「本来就该一样」和「本来不同、被抹平了」。

### 校准基准状态

| 项 | 状态 |
|---|---|
| EXACT 计数与变体名 | 已按确定性语义更新，实读一致 |
| `Search Field` 三态 `361×36` | ✅ 实读确认（06/12/13 三屏实例） |
| `Row / Search Result` 两态 `393×110.5` | ✅ 实读确认（06 屏五条实例，与桩精确相同） |
| `Bar / Search Status` 两态 `393×44` | ✅ 第 3 轮实读确认（22 / 23 两屏实例）。`NUMERIC_PENDING` 已清空 |

> 🧩 Components 页已于第 4 轮直读（page guid `1:76`）：顶层组件节点 **40** · 变体集 **29** ·
> 单组件 **11** · 变体总数 **125**，与基线四项全部吻合。Search 三组件的几何也在**组件本体**上
> 复核过一次（此前只在屏幕实例上验过）：`Search Field` 361×36 ×3 · `Row / Search Result`
> 393×110.5 ×2 · `Bar / Search Status` 393×44 ×4。至此无未实读项。

> **未填任何猜测值。** 桩与 Figma 的数字都由同一份 `code.js` 推导，互相比对没有意义 ——
> 只有真实 Figma 的排版输出才构成基准。F-1 正是这条原则的反面教材。

---

## 版本标识

| 项 | 值 |
|---|---|
| 生成器 | `design/figma-plugin/code.js` |
| 生成器 SHA-256（前 16 位） | `61d232b9df162ef4`（仅比 Search 交付版 `e4cb2c25c9fac4a1` 多一段注释，**生成结果逐项一致**；原冻结版 `7d09fbb8264f1260`） |
| 生成器行数 | 2373（冻结版 1928） |
| 仓库 HEAD | `602591a`（设计产物尚未提交，位于工作区） |
| 最后一次真实生成 | 2026-08-07，Figma 文件 `Untitled` |
| 最后一次 MCP 实读 | 2026-08-07，Dev Mode MCP |
| 字体 | PingFang SC（iOS 中文系统字体） |

---

## 设计资产规模

### 页面

| 页 | 内容 |
|---|---|
| 📐 Foundations | 1 块规范板（色板 · 数值 · 系统几何值 · 按下规则 · 触控规则 · 字阶） |
| 🧩 Components | **40** 个顶层组件节点 |
| 📱 Screens | **26** 屏 × 2 模式（Light / Dark） |

### 组件

| 指标 | 数量 |
|---|---|
| 顶层组件节点 | **40** |
| 变体集 | **29** |
| 单组件 | **11** |
| 变体总数 | **125** |
| 组件属性 | **41** |
| 实例 | **575** |

**嵌套架构**（避免笛卡尔积）

| 父组件 | 理论组合 | 实际维护变体 | 减少 |
|---|---|---|---|
| `Row / Note` | 60 | 9 | 85% |
| `Block / Audio` | 16 | 8 | 50% |
| `Row / Form` | 16 | 8 | 50% |

### Token

| 类别 | 数量 | 值 |
|---|---|---|
| 颜色变量 | **16** | Light / Dark 双模式 |
| 数值变量 | **27** | spacing 7 · radius 5 · icon 3 · row 2 · motion 2 · system 8 |
| 文字样式 | **15** | `iOS/LargeTitle` … `iOS/Caption2 Emphasized` |
| 效果样式 | **2** | `elevation/menu` · `elevation/drag` |

spacing 收敛为 `4 / 8 / 12 / 16 / 20 / 24 / 32`；radius 收敛为 `4 / 8 / 12 / 16 / 999`；icon 收敛为 `16 / 20 / 24`。
系统几何值（44 / 49 / 54 / 34 / 47 / 393 / 852）单独分组，不参与收敛。

### 原型

**25 条连线，覆盖 10 条核心 Flow，死链 0。** 关键中间态（generating · confirmation · permission denied · added · failed · retry）全部可达。

---

## 自动化验证结果

连续两轮 clean run 通过（未修改任何代码）。

| 套件 | 结果 |
|---|---|
| `checks.js` — 结构检查 | **11 / 11 PASS** |
| `gates.js` — Batch Gate | **9 / 9 PASS**（A1-A3 · B1-B4 · C1-C2） |
| `calibration.js` — 桩 vs 真实 Figma | **96 / 96 在容差内** |
| `tolerance.js` — 容差边界 | **7 / 7 PASS** |
| `selftest.js` — 变异自检 | **15 / 15 被抓到** |

### 检查项明细

`runtime` · `overflow` · `clipping` · `instances` · `variant-arch` · `naming` · `token-binding` · `touch-target` · **`multiline-width`** · **`text-prop`** · `start-page`

`A1 幂等性`（两轮生成结构完全一致）· `A2 嵌套架构` · `A3 Token 语义`（SUSPICIOUS_MAGIC_NUMBER = 0）
`B1 状态覆盖`（65 个必需状态）· `B2 入口可达`（19 项关键操作）· `B3 错误可恢复` · `B4 架构稳定`
`C1 原型完整` · `C2 无障碍`

---

## 校准结果

### 容差规则

| 类别 | 容差 | 依据 |
|---|---|---|
| EXACT（计数 · 变体名 · 属性名 · 变量绑定 · 原型目标 · 样式数） | **0** | 语义类属性，不存在「差一点」 |
| 宽度 | **±1.0 pt** | 由显式尺寸 / Token 决定，只容 auto-layout 取整 |
| 高度 | **±2.0 pt** | 受字体度量影响；桩按字符数估行宽，Figma 按字形推进量 |
| 位置 x/y | **±1.0 pt** | 误差来源同宽度 |
| 浮点哨兵（<1pt 零值） | **±0.01** | `state=hidden` 等零高/零宽节点 |

容差由 `tolerance.js` 的 7 个边界用例证明是代码里真实生效的判定（Δ=2 PASS、Δ=2.1 FAIL、Δ=−2 PASS、Δ=−2.1 FAIL）。

### 结果

```
EXACT             39 / 39 一致（容差 0）
NUMERIC 精确相同   54
NUMERIC 容差内      3
NUMERIC 超出容差    0
────────────────────────────
合计              96 / 96
```

3 项「容差内」而非「精确相同」的是：`Note Row`（Δh 1.0）· `Panel / Summary logCount=1`（Δh 2.0）· `Panel / Summary logCount=many`（Δh 2.0）。均为多行中文文本的行宽估算差异。

---

## 已知人工待办

### 设计侧

| 类别 | 数量 |
|---|---|
| BLOCKER | **0** |
| DESIGN MANUAL-P0 | **0** |
| MANUAL-P1 | **7**（见 [`TODO_MANUAL_QA.md`](TODO_MANUAL_QA.md)） |

MANUAL-P1 按验证阶段分组：Design Handoff 3 项 · SwiftUI 实现中 2 项 · Pre-release 2 项。

### 实现侧

见 [`IMPLEMENTATION_QA.md`](IMPLEMENTATION_QA.md)：**3 项 IMPLEMENTATION-P0**

- **I-P0-1** Adaptive Toolbar 连续输入链路（D-03 验收）
- **I-P0-2** Dynamic Type 极限档位
- **I-P0-3** VoiceOver 语义

这三项在 Figma 中结构上无法验证，不阻塞设计冻结。

---

## 产品决策

8 条决策已冻结并全部落地，执行过程中未产生新的待决项。

| ID | 决策 |
|---|---|
| D-01 | FAB → 底部 toolbar compose 按钮 |
| D-02 | 文件夹归属移至标题下方 metadata chip（`⋯` 保留次入口） |
| D-03 | 单层自适应工具条（非互斥） |
| D-04 | Folder Chip 按宽度溢出 + 选中项必须可见 |
| D-05 | 首页 AI generating / failed 指示（failed 不占主摘要区） |
| D-06 | `Chip / Topic` 独立组件，added = 实心 + ✓ |
| D-07 | Folder Filter Row 滚动时保持可访问（实现方式见 Handoff Notes） |
| D-08 | 删除旧 IA 对照屏（已归档至 `archive/`） |

---

## 冻结约束

**当前 Figma 文件作为设计基线冻结。** 后续不再修改，除非：

1. SwiftUI 实现暴露真实设计问题
2. 产品决策改变
3. 实现证明某个交互不可行
4. 明确要求重新设计

**不为「让桩与 Figma 数字完全一致」而修改视觉设计。** 桩的目标是足够准确地捕获 regression，不是复制 Figma 排版引擎。

### 变更流程

```
改 design/figma-plugin/code.js
   ↓
node test/all.js（5 套件全绿）
   ↓
在 Figma 重跑插件
   ↓
MCP 实读核对，刷新 calibration 基准
   ↓
更新本文件的 SHA / 日期 / 指标
```

---

## 相关文档

| 文件 | 内容 |
|---|---|
| [`../UI_REDESIGN.md`](../UI_REDESIGN.md) | 交互逻辑规格 · 功能保全对照表 |
| [`REMEDIATION_PLAN.md`](REMEDIATION_PLAN.md) | 整改计划 · 决策冻结 · State Matrix |
| [`TODO_MANUAL_QA.md`](TODO_MANUAL_QA.md) | 设计侧人工待办 |
| [`IMPLEMENTATION_QA.md`](IMPLEMENTATION_QA.md) | 实现侧验证清单 |
| [`figma-plugin/README.md`](figma-plugin/README.md) | 插件运行方式 |
| [`archive/README.md`](archive/README.md) | 旧 IA 对照屏归档 |
| [`mockup.html`](mockup.html) | 早期 HTML 高保真稿（现状 vs 改后） |
