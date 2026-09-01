# 已归档的文档

> 这些文件**留在仓库里是为了保存来龙去脉**，不是为了描述现状。
> 判断「现在是什么样」请读 `PROJECT_STATUS.md`，不要读它们。

| 文件 | 状态 | 被谁取代 | 为什么留着 |
|---|---|---|---|
| `HANDOFF.md` | **ARCHIVED** | `HANDOFF_NEXT.md` | Week 1–6 的完整交接，含大量当时的实测过程 |
| `prd.md` | **SUPERSEDED** | 用户持有的 PRD v1.0 | 旧版 Notes App PRD。**只能用来确认既有行为**，不能当需求依据 |
| `HUMANLIKE_GOLDEN_SET.md` | **SUPERSEDED** | `EVAL_SPEC.md` | 描述的是 v3 评测集。当前是 `scenario-v5` |
| `XCODE_VERIFICATION.md` | **ARCHIVED** | `tools/verify_release.sh` + `tools/verify_device.sh` | 当时手工核对 Xcode 工程的清单，现在核对是自动的（模拟器切片与真机 arm64 切片各一份） |
| `EMBEDDING_EXPERIMENT.md` | **ACTIVE（实验报告）** | — | 仍然有效。它是一份**实验记录**，不是现状描述；数字都标了 measured / estimated 与测量条件 |
| `design/REMEDIATION_PLAN.md` | **ARCHIVED** | — | 早期的整改计划，条目已全部落地或被后续决策取代 |
| `design/FIGMA_AUDIT_GOAL1.md` | **ARCHIVED** | — | Figma 与实现的一次性对照，产出已并入 `SEARCH_CONTRACT` / `DEVTOOLS` |
| `design/DEVTOOLS_SWIFTUI_PLAN.md` | **ARCHIVED** | `design/DEVTOOLS.md` | 实现计划，已实现 |
| `design/IMPLEMENTATION_QA.md` | **ARCHIVED** | `App/MosaicUITests` | 手工 QA 清单，核心流程已自动化 |
| `design/TODO_MANUAL_QA.md` | **ACTIVE（人工清单）** | — | 范围是 **Figma 设计阶段**的人工检查。实现阶段的项已迁出到 `IMPLEMENTATION_QA.md` |
| `design/IMPLEMENTATION_QA.md` 里的 I-P0-2 / I-P0-3 | **部分自动化** | `App/MosaicUITests` | **真机装机**与 **Dynamic Type + 深色**已自动化（Core Flow 7 在真机上跑最大无障碍字号 + Dark，断言核心控件仍点得着）。**VoiceOver 朗读顺序**有内核断言（`RetrievalWeek6Checks` §6.6），但**真人听一遍仍未做**；**云端同意流程**在纯词法生产下已不存在（见 `PROJECT_STATUS.md` §9.3） |
| `design/GOAL1_UI_COVERAGE.md` | **ARCHIVED** | — | 旧 UI 的覆盖对照。UI v2 已替换旧 UI |

## v1 关闭之后的文档角色

| 文件 | 角色 |
|---|---|
| `PROJECT_CLOSURE.md` | **终点记录** —— 冻结了什么、还缺什么、什么条件下重开 |
| `PROJECT_STATUS.md` | 现状 |
| `HANDOFF_NEXT.md` | **重新进入的五个条件**（v1 关闭后它不再是 backlog） |

## 规则

新增文档前先确认它不是在重复上表里的某一份。
一份文档如果**同时**描述「打算怎么做」和「现在怎么样」，它一定会过期 ——
拆成两份：计划进 `design/`，现状进 `PROJECT_STATUS.md`。
