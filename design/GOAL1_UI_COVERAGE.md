# Goal 1 — UI Coverage Matrix

> 生成日期：2026-08-07
> 上游：**Mosaic AI Retrieval Quality Platform PRD v1.0**
> 状态口径只允许四种：`Complete` · `Implementation-ready` · `Implementation-level only` · `Missing`

| 口径 | 含义 |
|---|---|
| **Complete** | Production 级 Figma 已交付并经实读验证，可直接照着实现 |
| **Implementation-ready** | 低保真线框 + 完整交接规格已交付；信息结构确定，工程师无需现场决策 |
| **Implementation-level only** | 不需要任何 Figma；规格已写清字段与层级，直接用原生控件实现 |
| **Missing** | 尚无定义 —— **本轮结束时必须为 0** |

---

## 1. 覆盖矩阵

| Requirement | Production Figma | Dev Wireframe | SwiftUI-first | Status |
|---|---|---|---|---|
| **Semantic Search**（隐式 Hybrid + 自动降级） | ✅ 06 / 21 / 22 / 23 / 24 | — | — | **Complete** |
| **Matched Excerpt**（开窗 · 截断 · 对比式高亮 · fallback 链） | ✅ `Row / Search Result` + §2.2–2.8 | — | — | **Complete** |
| **Search Fallback**（Progressive Enhancement） | ✅ `Bar / Search Status` 4 态 + 22 / 23 | — | — | **Complete** |
| **Result → Note**（scroll / 展开 / 临时高亮 / 状态恢复） | ✅ 25 / 26 + §3 | — | — | **Complete** |
| **Developer Mode**（IA · 入口 · 默认 OFF） | — （刻意不改生产屏，见下） | ✅ D0 + D1 | ✅ `DEVTOOLS.md` §1 | **Implementation-ready** |
| **Retrieval Lab** | — | ✅ D2 | ✅ §4.2 | **Implementation-ready** |
| **Retrieval Comparison**（K / V / H + unique hit） | — | ✅ D3 | ✅ §4.3 | **Implementation-ready** |
| **Eval Center**（Dataset × Config → Recall@K / MRR / P50 / P95） | — | ✅ D5 | ✅ §4.5 | **Implementation-ready** |
| **Eval Config Comparison**（Current / Baseline / Delta） | — | ✅ D6 | ✅ §4.6 | **Implementation-ready** |
| **Failure Inspection**（7 类 Failure Type） | — | ✅ D9（仅为走通原型） | ✅ §5 | **Implementation-level only** |
| **Regression**（闭环 + Pass Rate + 管理入口） | — | — | ✅ §6 | **Implementation-level only** |
| **Release Gate**（PASS / BLOCKED） | — | ✅ D7 / D8 | ✅ §4.7 | **Implementation-ready** |
| **Trace**（Pipeline + Index metadata + contentHash） | — | ✅ D4（仅为走通原型） | ✅ §4.4 / §7 | **Implementation-level only** |
| **Retrieval Config**（版本 · 派生 · 候选） | — | — | ✅ §4.6 | **Implementation-level only** |

### Missing = 0 ✅

**Goal 1 不存在任何 Missing UI Definition。**

---

## 2. 不做的（明确排除，非遗漏）

| 项 | 归属 | 理由 |
|---|---|---|
| Ask My Notes · RAG Chat · Citation QA · Cross-note reasoning | Stage 3 | PRD 明确非 Goal 1 |
| Agent · Tool Calling · Workflow orchestration | 非目标 | PRD 明确排除 |
| Prompt Studio · LLM-as-Judge | 非目标 | 同上 |
| Cost / Job / Model Gateway / Vector DB / Feature Flag Dashboard | 非目标 | 同上 |
| Developer Mode Dashboard Home · KPI overview | 本轮明确排除 | Package A 禁止；见 `DECISION_LOG.md` D-UI-DEV-010 |
| Dataset Management Platform | 本轮明确排除 | Package F 禁止；Regression 管理只是 Dataset 选择器里的一项 |
| Folder-scoped Search | Goal 2 | PRD Correction #6 |
| 用户侧 Semantic Toggle | 不做 | PRD Correction #5；`semanticEnabled` 属内部 retrieval config |

---

## 3. 非 UI 的实现缺口（不影响本矩阵，但会影响 Goal 1 交付）

| ID | 内容 | 影响 |
|---|---|---|
| ~~IG-1~~ | ~~无 Image OCR pipeline~~ | **✅ Week 2 已关闭。** `VisionImageTextExtractor`（`VNRecognizeTextRequest` · `.accurate` · zh-Hans/zh-Hant/en-US）已落地并经真机模拟器验证；OCR 作为 derived data 存在独立 store，不进 `Block` schema。仅支持印刷体，手写体明确不做 |
| **IG-2** | **`SearchMatcher` 仍返回 `Bool`。** `matches(query:haystack:tags:) -> Bool`，无 offset、无 block 归属、无 score | Matched Excerpt 与高亮**无法实现**。是 Production Semantic Search 落地的硬前置 |
| ~~IG-3~~ | ~~Block 级 id 稳定性未核实~~ | **✅ Week 1 已关闭。** `Block.id: UUID` 已持久化且与 `order` 分离；reorder / edit / restart 后 id 不变，已在真实 SwiftData 上验证。无需迁移 |

IG-1 / IG-3 已关闭，**IG-2 仍是 Production Semantic Search 落地的硬前置**，排在 Week 3。
详见 [`../RETRIEVAL_ARCHITECTURE.md`](../RETRIEVAL_ARCHITECTURE.md) §12 技术债清单。

---

## 4. 与上一版审计的对照

[`FIGMA_AUDIT_GOAL1.md`](FIGMA_AUDIT_GOAL1.md)（2026-08-07 首次审计）当时的结论是
**Goal 1 在 Figma 中的覆盖率为 0%**，并列出 P0 五项、P1 九项缺失。现状：

| 审计编号 | 内容 | 现状 |
|---|---|---|
| P0-1 | `Row / Search Result` + Matched Excerpt + 高亮规范 | ✅ Complete |
| P0-2 | Result → Note 落点行为 | ✅ Complete |
| P0-3 | Search 系统状态与降级规范 | ✅ Complete |
| P0-4 | Search 异步交互定义 | ✅ Complete |
| P0-5 | Developer Mode 入口与 IA | ✅ Implementation-ready（入口在 Track B D0，生产屏未改） |
| P1-1 | Retrieval Lab wireframe | ✅ D2 |
| P1-2 | Eval Center wireframe | ✅ D5 / D6 |
| P1-3 | Failure Inspection | ✅ 规格 §5 |
| P1-4 | Release Gate wireframe | ✅ D7 / D8 |
| P1-5 | Trace wireframe | ✅ 规格 §4.4 + D4 |
| P1-6 | `Badge / Status` + `Row / Metric` 组件 | ⛔ **不做** —— Track B 不建组件库，线框里是本地 frame |
| P1-7 | 高级设置「搜索与索引」Section | ⛔ **不做** —— PRD Correction #5 排除了用户侧 semantic toggle |
| P1-8 | Search idle 示例区 / 无结果归因 | ✅ 12 / 13 |
| P1-9 | Search scope | ⛔ Goal 2（Correction #6） |

P1-6 / P1-7 / P1-9 是**审计当时的建议被后续 PRD Correction 推翻**，不是遗漏。
