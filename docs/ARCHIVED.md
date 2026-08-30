# 已归档的文档

> 这些文件**留在仓库里是为了保存来龙去脉**，不是为了描述现状。
> 判断「现在是什么样」请读 `PROJECT_STATUS.md`，不要读它们。

| 文件 | 状态 | 被谁取代 | 为什么留着 |
|---|---|---|---|
| `HANDOFF.md` | **ARCHIVED** | `HANDOFF_NEXT.md` | Week 1–6 的完整交接，含大量当时的实测过程 |
| `prd.md` | **SUPERSEDED** | 用户持有的 PRD v1.0 | 旧版 Notes App PRD。**只能用来确认既有行为**，不能当需求依据 |
| `HUMANLIKE_GOLDEN_SET.md` | **SUPERSEDED** | `EVAL_SPEC.md` | 描述的是 v3 评测集。当前是 `scenario-v5` |
| `XCODE_VERIFICATION.md` | **ARCHIVED** | `tools/verify_release.sh` | 当时手工核对 Xcode 工程的清单，现在核对是自动的 |
| `EMBEDDING_EXPERIMENT.md` | **ACTIVE（实验报告）** | — | 仍然有效。它是一份**实验记录**，不是现状描述；数字都标了 measured / estimated 与测量条件 |
| `design/REMEDIATION_PLAN.md` | **ARCHIVED** | — | 早期的整改计划，条目已全部落地或被后续决策取代 |
| `design/FIGMA_AUDIT_GOAL1.md` | **ARCHIVED** | — | Figma 与实现的一次性对照，产出已并入 `SEARCH_CONTRACT` / `DEVTOOLS` |
| `design/DEVTOOLS_SWIFTUI_PLAN.md` | **ARCHIVED** | `design/DEVTOOLS.md` | 实现计划，已实现 |
| `design/IMPLEMENTATION_QA.md` | **ARCHIVED** | `App/MosaicUITests` | 手工 QA 清单，核心流程已自动化 |
| `design/TODO_MANUAL_QA.md` | **ACTIVE（人工清单）** | — | 仍然需要人做：真机装机、VoiceOver、Dynamic Type、云端同意流程 |
| `design/GOAL1_UI_COVERAGE.md` | **ARCHIVED** | — | 旧 UI 的覆盖对照。UI v2 已替换旧 UI |

## 规则

新增文档前先确认它不是在重复上表里的某一份。
一份文档如果**同时**描述「打算怎么做」和「现在怎么样」，它一定会过期 ——
拆成两份：计划进 `design/`，现状进 `PROJECT_STATUS.md`。
