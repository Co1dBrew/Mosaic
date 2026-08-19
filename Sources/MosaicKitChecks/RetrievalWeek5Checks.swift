import Foundation
import MosaicKit

/// Week 5 —— 配置版本化（5.1）· Release Gate（5.2）· Promote（5.4）· SLO（5.9）。
///
/// 这一套断言守的是**一个产品主张**：坏配置上不了线，而且「上不了线」这件事
/// 不能靠自觉。所以下面大量的用例是在验证「绕过路径不存在」，而不是「正常路径能走通」。
enum RetrievalWeek5Checks {

    typealias F = RetrievalFoundationChecks

    // MARK: 5.1 · 配置版本化 / 派生 / candidate

    static func checkRegistry(_ r: CheckRunner) {
        r.suite("Week5 · 配置版本化 —— 生产配置只能经 Promote 更换")

        var registry = RetrievalConfigRegistry()
        r.expect(registry.records.count == 1, "初始只有一条记录")
        r.expect(registry.production.role == .production, "初始记录即生产配置")
        r.expect(registry.production.promotedAt == nil,
                 "初始生产配置没有 promotedAt —— 它不是被 promote 上去的，是初始值")
        r.expect(registry.candidate == nil, "初始没有候选")

        // 派生。
        guard let draft = try? registry.duplicate(from: registry.production.id, mutate: { $0.topK = 30 }) else {
            r.expect(false, "可以从生产配置派生"); return
        }
        r.expect(draft.role == .draft, "派生出来的一律是 draft —— 派生本身不表达「我要上这个」")
        r.expect(draft.derivedFrom == registry.production.id, "记录派生来源")
        r.expect(draft.config.topK == 30, "派生时可以改参数")
        r.expect(draft.version != registry.production.version,
                 "派生出新版本号（\(registry.production.version) → \(draft.version)）")

        // 版本号不复用：删掉 draft 之后下一个版本号不能撞上已经存在过的。
        var seqRegistry = RetrievalConfigRegistry()
        let a = try! seqRegistry.duplicate(from: seqRegistry.production.id)
        try! seqRegistry.remove(id: a.id)
        let b = try! seqRegistry.duplicate(from: seqRegistry.production.id)
        r.expect(a.version != b.version,
                 "删掉一条 draft 之后版本号不复用（\(a.version) vs \(b.version)）—— Trace / EvalRun 里记的就是这个字符串")

        // candidate 至多一条。
        try? registry.setCandidate(id: draft.id)
        r.expect(registry.candidate?.id == draft.id, "可以指定候选")
        let draft2 = try! registry.duplicate(from: draft.id, mutate: { $0.topK = 40 })
        try? registry.setCandidate(id: draft2.id)
        r.expect(registry.candidate?.id == draft2.id, "新候选生效")
        r.expect(registry.records.filter { $0.role == .candidate }.count == 1,
                 "候选至多一条 —— 两个候选并存时「能不能上」就没有主语了")
        r.expect(registry.record(id: draft.id)?.role == .draft, "旧候选降回 draft，不是并存")

        // 没有任何 API 能改生产记录。
        var didThrow = false
        do { try registry.setCandidate(id: registry.production.id) } catch { didThrow = true }
        r.expect(didThrow, "生产记录不能被设为候选")
        didThrow = false
        do { try registry.remove(id: registry.production.id) } catch { didThrow = true }
        r.expect(didThrow, "生产记录不能被删除 —— 删了之后线上跑的是什么就没有记录了")
        didThrow = false
        do { try registry.remove(id: draft2.id) } catch { didThrow = true }
        r.expect(didThrow, "候选也不能删（先降回 draft）")

        // JSON 往返：App 侧要落盘。
        if let data = try? JSONEncoder().encode(registry),
           let back = try? JSONDecoder().decode(RetrievalConfigRegistry.self, from: data) {
            r.expect(back == registry, "注册表可 JSON 往返 —— 人工决策的产物，不可重建，必须落盘")
        } else {
            r.expect(false, "注册表可 JSON 往返")
        }
    }


    // MARK: 测量环境（分层 policy 之后，判定的前置条件）

    /// 与**当前构建**匹配的合格环境。写死 `release` 会让 debug 下的 checks 全变 STALE，
    /// 而这一节测的是判定逻辑，不是性能。
    static var qualifyingEnvironment: RunEnvironment {
        RunEnvironment(deviceClass: .mac,
                       deviceModel: "test",
                       osVersion: "test",
                       buildConfiguration: buildMode,
                       thermalState: "nominal",
                       lowPowerMode: false,
                       measuredLayer: .firstResult,
                       providerRegion: nil,
                       capturedAt: Date())
    }

    /// 接受当前构建的 policy —— 只为让质量类断言能跑到，不代表生产 policy。
    static var qualifyingThresholds: GateThresholds {
        GateThresholds(performance: PerformanceGatePolicy(
            version: "test-perf", requiredDeviceClass: .mac,
            requiredBuildConfiguration: buildMode))
    }

    // MARK: 5.2 · 四项检查

    /// 构造一次跑批结果。指标直接给定 —— 这一节测的是**判定逻辑**，
    /// 不是检索质量，用真实检索反而会让阈值边界不可控。
    static func run(version: String,
                    recall5: Double, mrr: Double, p95: Double,
                    caseCount: Int = 40,
                    regressionCases: Int = 40, regressionRecall5: Double = 1.0) -> EvalRun {
        EvalRun(configVersion: version, embeddingVersion: "e1",
                metrics: EvalMetrics(caseCount: caseCount, recallAt1: 0.7, recallAt3: 0.8,
                                     recallAt5: recall5, mrr: mrr, p50Ms: p95 / 2, p95Ms: p95),
                goldenMetrics: .zero,
                regressionMetrics: EvalMetrics(caseCount: regressionCases, recallAt1: 0, recallAt3: 0,
                                               recallAt5: regressionRecall5, mrr: 0, p50Ms: 0, p95Ms: 0),
                failures: [])
    }

    static func checkGate(_ r: CheckRunner) {
        r.suite("Week5 · Release Gate —— 任一项 FAIL 即阻断，不做加权")

        let baseline = run(version: "retrieval-v2", recall5: 0.825, mrr: 0.742, p95: 154)

        // 全过。
        let pass = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                        current: run(version: "retrieval-v2", recall5: 0.875, mrr: 0.781, p95: 181),
                                        baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(pass.status == .pass, "四项全过 → PASS")
        r.expect(pass.checks.count == 4, "恰好四项检查 —— 与 DEVTOOLS §4.7 一一对应")
        r.expect(pass.headline == "PASS", "判定区文案")
        r.expect(pass.blockingChecks.isEmpty, "PASS 时没有阻断行")

        // P95 超预算 —— 质量再好也拦。
        let slow = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                        current: run(version: "retrieval-v2", recall5: 0.990, mrr: 0.950, p95: 310),
                                        baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(slow.status == .blocked, "P95 310ms > 250ms → BLOCKED")
        r.expect(slow.blockingChecks.map(\.kind) == [.firstResultLatency], "只有 Metric A 那一行是阻断行")
        r.expect(slow.checks.first { $0.kind == .recallAt5 }?.passed == true,
                 "其余三项照常通过 —— 不做加权，「大部分指标都很好」不能换来放行")
        r.expect(slow.checks.first { $0.kind == .firstResultLatency }?.actualText == "P50 155 ms · P95 310 ms",
                 "P50 与 P95 在同一行里给出（\(slow.checks.first { $0.kind == .firstResultLatency }?.actualText ?? "—")）")
        r.expect(slow.checks.first { $0.kind == .firstResultLatency }?.opensFailures == false,
                 "P95 超预算不对应任何一条 case，不给 Open Failures")

        // Regression 97.5% —— 40 条里错 1 条。
        let regressed = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                             current: run(version: "retrieval-v2", recall5: 0.861, mrr: 0.766,
                                                          p95: 181, regressionCases: 40, regressionRecall5: 0.975),
                                             baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(regressed.status == .blocked, "Regression 97.5% < 98% → BLOCKED")
        let reg = regressed.checks.first { $0.kind == .regression }!
        r.expect(reg.actualText == "97.5% · 39/40", "通过率与条数同时给出（\(reg.actualText)）")
        r.expect(reg.opensFailures, "失败的 Regression 行直达 D9 —— 从「不能上线」到「为什么」一次点击")

        // MRR 容差：baseline 0.742，容差 0.010 → 0.732 仍然通过，0.731 不通过。
        let onTolerance = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                               current: run(version: "retrieval-v2", recall5: 0.875, mrr: 0.732, p95: 100),
                                               baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(onTolerance.checks.first { $0.kind == .mrr }?.passed == true,
                 "MRR 恰在容差边界上通过 —— 边界不能因为一次浮点除法差 1 ulp 就翻面")
        let belowTolerance = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                                  current: run(version: "retrieval-v2", recall5: 0.875, mrr: 0.700, p95: 100),
                                                  baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(belowTolerance.status == .blocked, "MRR 跌破容差 → BLOCKED")

        // Recall@5 默认零容差。
        let recallDown = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                              current: run(version: "retrieval-v2", recall5: 0.824, mrr: 0.800, p95: 100),
                                              baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(recallDown.status == .blocked,
                 "Recall@5 低于 baseline 即阻断 —— 默认零容差，「掉一点点换别的好处」不是 Gate 能表达的事")
        let recallEqual = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                               current: run(version: "retrieval-v2", recall5: 0.825, mrr: 0.800, p95: 100),
                                               baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(recallEqual.checks.first { $0.kind == .recallAt5 }?.passed == true, "与 baseline 相等算通过")

        // 阈值可配。
        let loose = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                         current: run(version: "retrieval-v2", recall5: 0.990, mrr: 0.950, p95: 310),
                                         baseline: baseline,
                                         thresholds: GateThresholds(performance: PerformanceGatePolicy(
                                             version: "test-loose", firstResultP50Ms: 200, firstResultP95Ms: 400,
                                             requiredDeviceClass: .mac,
                                             requiredBuildConfiguration: buildMode)),
                                         environment: qualifyingEnvironment)
        r.expect(loose.status == .pass, "阈值可配 —— 拿到 PRD 定值后只改这一个结构体")

        // 已知不支持的跨语言 case 单独报告，不能拖低主指标或阻断发布。
        let poorOverall = EvalMetrics(caseCount: 59, recallAt1: 0.2, recallAt3: 0.3,
                                      recallAt5: 0.35, mrr: 0.25, p50Ms: 10, p95Ms: 999)
        let supported = EvalMetrics(caseCount: 35, recallAt1: 0.8, recallAt3: 0.9,
                                    recallAt5: 0.95, mrr: 0.85, p50Ms: 9, p95Ms: 20)
        let supportedBaseline = EvalMetrics(caseCount: 35, recallAt1: 0.7, recallAt3: 0.8,
                                            recallAt5: 0.90, mrr: 0.80, p50Ms: 8, p95Ms: 18)
        let scopedCurrent = EvalRun(configVersion: "retrieval-v2", embeddingVersion: "e1",
                                    metrics: poorOverall, goldenMetrics: poorOverall,
                                    regressionMetrics: .zero, failures: [],
                                    inScopeMetrics: supported,
                                    crossLanguageMetrics: EvalMetrics(caseCount: 24, recallAt1: 0,
                                        recallAt3: 0, recallAt5: 0, mrr: 0, p50Ms: 900, p95Ms: 999))
        let scopedBaseline = EvalRun(configVersion: "retrieval-v2", embeddingVersion: "e1",
                                     metrics: poorOverall, goldenMetrics: poorOverall,
                                     regressionMetrics: .zero, failures: [],
                                     inScopeMetrics: supportedBaseline)
        let scopedDecision = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                                  current: scopedCurrent, baseline: scopedBaseline,
                                        thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        r.expect(scopedDecision.status == .pass,
                 "Gate 只看 in-scope 正例；cross-language 与负例只作诊断")
        r.expect(scopedDecision.checks.first { $0.kind == .recallAt5 }?.actualText == "0.950",
                 "Gate 展示的是 in-scope 实测值，不是 overall 0.350")
    }

    static func checkGateEdges(_ r: CheckRunner) {
        r.suite("Week5 · Release Gate —— stale / 无 baseline / 用例集不同")

        let current = run(version: "retrieval-v2", recall5: 0.875, mrr: 0.781, p95: 181)

        // 没跑过评测。
        let noRun = ReleaseGate.evaluate(configVersion: "retrieval-v2", current: nil, baseline: nil,
                                          thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        r.expect(noRun.status == .stale, "还没有评测结果 → STALE，不是 PASS")
        r.expect(noRun.isPass == false, "STALE 不可 promote")
        r.expect(noRun.staleReason?.contains("先在 Eval Center") == true, "给出补救动作")

        // 评测跑的是别的配置。
        let mismatched = ReleaseGate.evaluate(configVersion: "retrieval-v3", current: current, baseline: nil,
                                                thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        r.expect(mismatched.status == .stale,
                 "评测结果早于当前配置 → STALE —— 「改完参数没重跑评测」时判定还是绿的，但它判的是上一套")
        r.expect(mismatched.staleReason?.contains("retrieval-v2") == true, "说明跑的是哪一套")

        // 没有 baseline：质量类检查无法成立，且不能默认放行。
        let noBaseline = ReleaseGate.evaluate(configVersion: "retrieval-v2", current: current, baseline: nil,
                                                thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        r.expect(noBaseline.status == .blocked, "没有 baseline 时不能默认放行")
        r.expect(noBaseline.checks.first { $0.kind == .recallAt5 }?.detail?.contains("baseline") == true,
                 "说明是「还没跑 baseline」而不是「质量下降」—— 补救动作完全不同")
        r.expect(noBaseline.checks.first { $0.kind == .firstResultLatency }?.passed == true,
                 "P95 是绝对预算，没有 baseline 也能判")

        // 用例集不同 —— §14.3 抓到过的那个缺陷，在 Gate 上同样致命。
        let baselineOtherSet = run(version: "retrieval-v2", recall5: 0.825, mrr: 0.742, p95: 154, caseCount: 39)
        let incomparable = ReleaseGate.evaluate(configVersion: "retrieval-v2",
                                                current: current, baseline: baselineOtherSet,
                                                thresholds: qualifyingThresholds,
                                                environment: qualifyingEnvironment)
        r.expect(incomparable.status == .blocked, "两次跑批用例数不同 → 不放行")
        r.expect(incomparable.checks.first { $0.kind == .recallAt5 }?.detail?.contains("用例数不同") == true,
                 "点明分母变了 —— 否则会有人在这里开始调 topK")

        // 回归集为空：恒过，并说明理由。
        let emptyRegression = ReleaseGate.evaluate(
            configVersion: "retrieval-v2",
            current: run(version: "retrieval-v2", recall5: 0.875, mrr: 0.781, p95: 181,
                         regressionCases: 0, regressionRecall5: 0),
            baseline: run(version: "retrieval-v2", recall5: 0.825, mrr: 0.742, p95: 154),
            thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        let empty = emptyRegression.checks.first { $0.kind == .regression }!
        r.expect(empty.passed, "回归集为空时这一项恒过 —— 没有回归用例就没有回归")
        r.expect(empty.detail?.contains("回归集还没有用例") == true, "但要说明它为什么是绿的")
    }

    // MARK: 5.4 · Promote

    static func checkPromote(_ r: CheckRunner) {
        r.suite("Week5 · Promote —— 只有全 PASS 的判定能换掉生产配置")

        var registry = RetrievalConfigRegistry()
        let originalProductionID = registry.production.id
        let candidate = try! registry.duplicate(from: originalProductionID, mutate: { $0.topK = 30 })
        try! registry.setCandidate(id: candidate.id)

        let baseline = run(version: "retrieval-v1", recall5: 0.825, mrr: 0.742, p95: 154)
        let blocked = ReleaseGate.evaluate(configVersion: candidate.version,
                                           current: run(version: candidate.version, recall5: 0.9, mrr: 0.9, p95: 310),
                                           baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)

        var didThrow = false
        do { _ = try registry.promote(id: candidate.id, decision: blocked) } catch { didThrow = true }
        r.expect(didThrow, "BLOCKED 的判定无法 promote —— 这是结构性的，不是「UI 上把按钮置灰」")
        r.expect(registry.production.id == originalProductionID, "生产配置没有被换掉")

        // 判定属于另一套配置。
        let passForOther = ReleaseGate.evaluate(configVersion: "retrieval-v99",
                                                current: run(version: "retrieval-v99", recall5: 0.9, mrr: 0.9, p95: 100),
                                                baseline: run(version: "retrieval-v99", recall5: 0.8, mrr: 0.8, p95: 100),
                                        thresholds: qualifyingThresholds, environment: qualifyingEnvironment)
        r.expect(passForOther.isPass, "构造一个 PASS 判定")
        didThrow = false
        do { _ = try registry.promote(id: candidate.id, decision: passForOther) } catch { didThrow = true }
        r.expect(didThrow,
                 "PASS 但判的是别的配置 → 拒绝 —— 拦的是「改完参数没重跑评测就上线」")

        // 正常路径。
        let good = ReleaseGate.evaluate(configVersion: candidate.version,
                                        current: run(version: candidate.version, recall5: 0.875, mrr: 0.781, p95: 181),
                                        baseline: baseline,
                                        thresholds: qualifyingThresholds,
                                        environment: qualifyingEnvironment)
        r.expect(good.isPass, "同一套配置的 PASS 判定")
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let promoted = try? registry.promote(id: candidate.id, decision: good, at: at)
        r.expect(promoted != nil, "全 PASS 时可以 promote")
        r.expect(registry.production.id == candidate.id, "生产配置换成了候选")
        r.expect(registry.production.promotedAt == at, "写入 promotedAt")
        r.expect(registry.productionConfig.topK == 30, "生产参数随之生效")
        r.expect(registry.candidate == nil, "promote 之后不再有候选")
        r.expect(registry.record(id: originalProductionID)?.role == .draft, "旧生产配置降为 draft，记录保留")
        r.expect(registry.promotionHistory.count == 1, "上线历史可回溯")

        // 非候选不能 promote。
        didThrow = false
        do { _ = try registry.promote(id: originalProductionID, decision: good) } catch { didThrow = true }
        r.expect(didThrow, "非候选不能直接 promote —— 必须先 Set as candidate 并跑评测")
    }

    // MARK: 5.9 · SLO —— 生产检索路径端到端

    /// 与 §9.7 的 benchmark 同一条纪律（D-RT-015）：**只在 release 断言**。
    /// 同一份代码 debug 模式慢两个数量级，在 debug 里断言 SLO 会得出
    /// 「暴力检索不达标」这个已经被证伪过一次的结论。
    static func checkSLO(_ r: CheckRunner) async {
        r.suite("Week5 · SLO —— 生产检索路径 P50 < 100ms · P95 < 250ms")

        let dim = 384
        let chunkCount = 5_000
        var chunks: [NoteChunk] = []
        let store = InMemoryVectorStore()
        chunks.reserveCapacity(chunkCount)

        // 确定性语料与向量：SLO 测的是**检索本身的规模行为**，
        // 引入真实 embedding 会把 provider 的耗时混进来，那是另一条曲线（trace 里单列）。
        for i in 0..<chunkCount {
            let noteID = "n\(i / 20)"
            let text = "第 \(i) 段内容 关于 排期 与 延期毕业 的讨论 record \(i) schedule policy"
            let ref = BlockRef(noteID: noteID, blockID: "b\(i)")
            let chunk = NoteChunk(id: "c\(i)", ref: ref, source: .text,
                                  indexInBlock: 0, text: text, contentHash: "h\(i)")
            chunks.append(chunk)
            await store.upsert(EmbeddingRecord(ref: ref, chunkID: chunk.id, chunkIndex: 0,
                                               contentHash: chunk.contentHash,
                                               embeddingVersion: "det-v1",
                                               dimension: dim,
                                               vector: MockEmbeddingProvider.deterministicVector(for: chunk.id, dimension: dim)))
        }

        let provider = MockEmbeddingProvider(dimension: dim)
        let service = RetrievalService(provider: provider, vectors: store)
        let config = RetrievalConfig(version: "slo", mode: .hybrid,
                                     embeddingProvider: "mock", embeddingVersion: "det-v1",
                                     chunkStrategy: .block, topK: 50)

        let queries = ["延期毕业", "排期", "schedule policy", "第 4200 段内容", "record 999"]
        var samples: [Double] = []
        // 预热一次：第一次调用要付 actor 首次进入与内存分配的钱，那不是稳态。
        _ = await service.retrieve(query: "预热", chunks: chunks, config: config)
        for round in 0..<40 {
            let q = queries[round % queries.count]
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = await service.retrieve(query: q, chunks: chunks, config: config)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
        }

        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        print(String(format: "\n    ── 5.9 SLO（%@ · %d chunks · dim %d · hybrid 端到端）──",
                     buildMode, chunkCount, dim))
        print(String(format: "    P50 = %.2f ms   P95 = %.2f ms\n", p50, p95))

        #if DEBUG
        r.expect(p50 > 0, "debug 构建只测量不断言 —— 同一份代码 debug 比 release 慢两个数量级（D-RT-015）")
        #else
        r.expect(p50 < 100, String(format: "P50 < 100 ms（实测 %.2f ms）", p50))
        r.expect(p95 < 250, String(format: "P95 < 250 ms（实测 %.2f ms）", p95))
        #endif
    }

    static var buildMode: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    // MARK: 5.10 · Result → Note 落点

    static func checkLanding(_ r: CheckRunner) {
        r.suite("Week5 · 落点行为 —— 五类命中各自正确（SEARCH_CONTRACT §3）")

        // 时序：契约写死的三个数字。
        r.expect(SearchLanding.highlightDelay == 0.15, "转场完成后 +0.15s 才开始 —— 转场中闪高亮会被动画吃掉")
        r.expect(SearchLanding.highlightHold == 2.0, "保持 2.0s")
        r.expect(SearchLanding.highlightFade == 0.4, "0.4s ease-out 淡出")
        r.expect(SearchLanding.highlightTotal == 2.4, "总计 2.4s")
        r.expect(SearchLanding.interruptFade < SearchLanding.highlightFade,
                 "被打断时淡出更快 —— 高亮是提示，不是障碍")

        // 行为分派：Title 命中不滚动、不高亮；音频要先展开。
        r.expect(!SearchLanding.requiresScroll(.top), "Title 命中落在顶部，不滚动")
        r.expect(!SearchLanding.requiresHighlight(.top), "Title 命中不高亮")
        r.expect(SearchLanding.requiresScroll(.block("b1")), "text / image / document / link 四类都滚到 block")
        r.expect(SearchLanding.requiresScroll(.transcript("b2")), "audio 也滚到 block")
        r.expect(SearchLanding.requiresTranscriptExpansion(.transcript("b2")),
                 "audio 命中要先展开转写 —— 折叠状态下滚过去只看得到一个播放条")
        r.expect(!SearchLanding.requiresTranscriptExpansion(.block("b1")), "其余四类不展开任何东西")

        // block 被删 / 索引 stale → 退化为 .top，不报错。
        r.expect(SearchLanding.resolve(.block("gone"), existingBlockIDs: ["b1"]) == .top,
                 "anchor 指向的 block 不在了 → 退化为 .top，不报错、不提示")
        r.expect(SearchLanding.resolve(.block("b1"), existingBlockIDs: ["b1"]) == .block("b1"),
                 "block 还在时按原 anchor 落点")
        r.expect(SearchLanding.resolve(.transcript("b2"), existingBlockIDs: ["b1"]) == .top,
                 "转写 anchor 同样会退化")

        // 滚动落点：≤50% 居中，>50% 顶部对齐 + 88pt 内边距。
        r.expect(SearchLanding.scrollTarget(blockHeight: 200, viewportHeight: 800) == .center,
                 "block 高度 ≤ 50% 可视区 → 居中")
        r.expect(SearchLanding.scrollTarget(blockHeight: 400, viewportHeight: 800) == .center,
                 "恰好 50% 仍然居中（边界含在 center 一侧）")
        if case let .top(unitY) = SearchLanding.scrollTarget(blockHeight: 600, viewportHeight: 800) {
            // y·(H_view − H_viewport) = −topInset → y = 88 / (800 − 600) = 0.44
            r.expect(abs(unitY - 0.44) < 1e-9,
                     String(format: "block 高度 > 50% → 顶部对齐，锚点由 88pt 内边距反解（%.3f）", unitY))
        } else {
            r.expect(false, "block 高度 > 50% → 顶部对齐")
        }
        if case let .top(unitY) = SearchLanding.scrollTarget(blockHeight: 900, viewportHeight: 800) {
            r.expect(unitY == 0,
                     "block 比可视区还高时 88pt 内边距无解 —— 顶部对齐是能给出的最好结果，而不是崩掉")
        } else {
            r.expect(false, "超长 block 仍然顶部对齐")
        }
        r.expect(SearchLanding.scrollTarget(blockHeight: 0, viewportHeight: 0) == .center,
                 "量不到几何时退化为居中，而不是不滚")

        // 导航载荷：同一篇笔记的不同落点是不同的目标（§3.6 重复进入要重复高亮）。
        let a = SearchDestination(noteID: "n1", anchor: .block("b1"))
        let b = SearchDestination(noteID: "n1", anchor: .transcript("b1"))
        r.expect(a.id != b.id, "载荷身份包含 anchor，不只是 noteID")
        r.expect(SearchDestination(noteID: "n1", anchor: .top).id == "n1|top", "顶部落点的身份稳定")
    }


    // MARK: 5.9b · 分层性能 policy 与测量环境闸门

    static func checkLayeredPerformanceGate(_ r: CheckRunner) async {
        r.suite("Week5 · 分层性能 policy —— 环境不合格判 STALE，不是 FAIL")

        let quality = run(version: "v", recall5: 0.90, mrr: 0.90, p95: 120)
        let baseline = run(version: "v", recall5: 0.80, mrr: 0.80, p95: 120)

        func env(_ deviceClass: RunEnvironment.DeviceClass,
                 _ build: String,
                 layer: MeasuredLatencyLayer = .firstResult,
                 thermal: String = "nominal",
                 lowPower: Bool = false,
                 region: String? = nil) -> RunEnvironment {
            RunEnvironment(deviceClass: deviceClass, deviceModel: "m", osVersion: "o",
                           buildConfiguration: build, thermalState: thermal,
                           lowPowerMode: lowPower, measuredLayer: layer,
                           providerRegion: region)
        }
        let v2 = GateThresholds(performance: .v2)   // 要求 release + 真机

        // ① 没有环境元数据 → STALE
        let noEnv = ReleaseGate.evaluate(configVersion: "v", current: quality,
                                         baseline: baseline, thresholds: v2, environment: nil)
        r.expect(noEnv.status == .stale, "没记录测量环境 → STALE（不知道跑在什么机器上）")
        r.expect(noEnv.staleReason?.contains("测量环境") == true, "说明原因是环境，不是质量")

        // ② 模拟器数字 → STALE。**这条最重要**：模拟器跑的是 Mac 的 CPU。
        let sim = ReleaseGate.evaluate(configVersion: "v", current: quality, baseline: baseline,
                                       thresholds: v2, environment: env(.simulator, "release"))
        r.expect(sim.status == .stale, "模拟器数字 → STALE，不能用于发布判定")
        r.expect(sim.staleReason?.contains("simulator") == true, "点明是模拟器")

        // ③ debug 构建 → STALE。本项目实测 debug 慢 18 倍。
        r.expect(ReleaseGate.evaluate(configVersion: "v", current: quality, baseline: baseline,
                                      thresholds: v2,
                                      environment: env(.physicalDevice, "debug")).status == .stale,
                 "debug 构建 → STALE（同一份代码实测慢 18 倍）")

        // ④ 低电量 / 发热 → STALE：那时测的是被限频后的性能。
        r.expect(ReleaseGate.evaluate(configVersion: "v", current: quality, baseline: baseline,
                                      thresholds: v2,
                                      environment: env(.physicalDevice, "release", lowPower: true)).status == .stale,
                 "低电量模式 → STALE（CPU 被限频）")
        r.expect(ReleaseGate.evaluate(configVersion: "v", current: quality, baseline: baseline,
                                      thresholds: v2,
                                      environment: env(.physicalDevice, "release", thermal: "serious")).status == .stale,
                 "设备发热 → STALE（已降频）")

        // ⑤ 真机 release → 真正参与判定
        let real = ReleaseGate.evaluate(configVersion: "v", current: quality, baseline: baseline,
                                        thresholds: v2, environment: env(.physicalDevice, "release"))
        r.expect(real.status == .pass, "真机 release + 四项达标 → PASS")
        r.expect(real.checks.count == 4, "仍然是四行 —— P50/P95 合成一行，不改 DEVTOOLS §4.7 的版式")
        let metricA = real.checks.first { $0.kind == .firstResultLatency }!
        r.expect(metricA.actualText.contains("P50") && metricA.actualText.contains("P95"),
                 "Metric A 一行里同时给出两个分位点（\(metricA.actualText)）")

        // ⑥ region 不匹配 → STALE。**这是「延迟是地理问题」的直接对策。**
        let regionPolicy = GateThresholds(performance: PerformanceGatePolicy(
            version: "perf-v2-us", semanticCloudP95Ms: 2_500,
            requiredDeviceClass: .physicalDevice, requiredBuildConfiguration: "release",
            requiredProviderRegion: "us-east"))
        let wrongRegion = ReleaseGate.evaluate(
            configVersion: "v", current: quality, baseline: baseline, thresholds: regionPolicy,
            environment: env(.physicalDevice, "release", layer: .semanticCloud, region: "cn-shanghai"))
        r.expect(wrongRegion.status == .stale,
                 "同一份 policy 在 cn-shanghai 与 us-east 下不该给同一个判决 → STALE")
        r.expect(wrongRegion.staleReason?.contains("cn-shanghai") == true, "点明实际区域")

        // ⑦ cloud 层预算为 nil = 记录但不判定，且必须说明它为什么是绿的
        let recordOnly = GateThresholds(performance: PerformanceGatePolicy(
            version: "perf-v2", semanticCloudP95Ms: nil,
            requiredDeviceClass: .physicalDevice, requiredBuildConfiguration: "release"))
        let cloudRun = ReleaseGate.evaluate(
            configVersion: "v",
            current: run(version: "v", recall5: 0.90, mrr: 0.90, p95: 1_317),
            baseline: baseline, thresholds: recordOnly,
            environment: env(.physicalDevice, "release", layer: .semanticCloud))
        let metricB = cloudRun.checks.first { $0.kind == .semanticLatency }!
        r.expect(metricB.passed, "cloud 层 P95 1317ms 不阻断 —— policy 明确不为它设阈值")
        r.expect(metricB.detail?.contains("地理位置") == true,
                 "但必须说明它为什么是绿的，否则一条恒过的检查看起来像一次通过")
        r.expect(cloudRun.status == .pass, "其余三项达标 → PASS")

        // ⑧ 同一份数字换回 perf-v1（单一 SLO）会被判 FAIL —— 分层的意义就在这个对比里
        let v1 = GateThresholds(performance: .v1)
        let underV1 = ReleaseGate.evaluate(
            configVersion: "v",
            current: run(version: "v", recall5: 0.90, mrr: 0.90, p95: 1_317),
            baseline: baseline, thresholds: v1,
            environment: env(.mac, "release", layer: .semanticCloud))
        r.expect(underV1.status == .blocked,
                 "perf-v1 用一个数字判所有层 → 云端语义被判不达标；perf-v2 把它归为「记录不判定」")
    }

    /// 用**现有真实数据**重跑 Gate，把结论记录下来。
    static func rerunGateWithRealData(_ r: CheckRunner) async {
        r.suite("Week5 · 用现有真实数据重跑 Gate")

        guard let provider = try? LocalEmbedding.make(),
              let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(true, "缺本地模型或 fixture，跳过（结论：待验证）"); return
        }
        let chunks = dataset.chunks
        let store = InMemoryVectorStore()
        for start in stride(from: 0, to: chunks.count, by: 32) {
            let batch = Array(chunks[start..<min(start + 32, chunks.count)])
            guard let vs = try? await provider.embed(batch: batch.map(\.text)) else { continue }
            for (c, v) in zip(batch, vs) {
                await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id,
                                                   chunkIndex: c.indexInBlock,
                                                   contentHash: c.contentHash,
                                                   embeddingVersion: provider.modelInfo.version,
                                                   chunkStrategy: c.strategy,
                                                   dimension: v.count, vector: v))
            }
        }
        let service = RetrievalService(provider: provider, vectors: store)
        let runner = EvalRunner(service: service, chunksProvider: { chunks })
        func cfg(_ mode: RetrievalMode) -> RetrievalConfig {
            RetrievalConfig(version: "gate-rerun", mode: mode,
                            embeddingProvider: provider.modelInfo.identifier,
                            embeddingVersion: provider.modelInfo.version,
                            chunkStrategy: .default, topK: 10)
        }
        guard let hybrid = try? await runner.run(cases: dataset.evalCases, config: cfg(.hybrid)),
              let keyword = try? await runner.run(cases: dataset.evalCases, config: cfg(.keyword)) else {
            r.expect(false, "跑批应当成功"); return
        }

        // 真实环境：这台机器、这个构建。**不伪造。**
        let actual = RunEnvironment.capture(layer: .firstResult)
        let v2 = GateThresholds(performance: .v2)
        let decision = ReleaseGate.evaluate(configVersion: "gate-rerun", current: hybrid,
                                            baseline: keyword, thresholds: v2, environment: actual)

        print("\n    ── Gate 重跑（perf-v2 · 真实环境 \(actual.deviceClass.rawValue)/\(actual.buildConfiguration)）──")
        print("    current  hybrid  in-scope R@5 \(String(format: "%.3f", hybrid.inScopeMetrics.recallAt5)) · MRR \(String(format: "%.3f", hybrid.inScopeMetrics.mrr)) · P95 \(String(format: "%.1f", hybrid.inScopeMetrics.p95Ms))ms")
        print("    baseline keyword in-scope R@5 \(String(format: "%.3f", keyword.inScopeMetrics.recallAt5)) · MRR \(String(format: "%.3f", keyword.inScopeMetrics.mrr))")
        print("    判定 → \(decision.headline)")
        for reason in decision.blockingReasons { print("      · \(reason)") }

        r.expect(decision.status == .stale,
                 "perf-v2 下 Mac 数字判 STALE —— **这不是失败，是 Gate 在正常工作**："
                 + "它拦住了「拿模拟器/Mac 的性能数字发布」这条路")
        r.expect(decision.checks.isEmpty,
                 "STALE 时不列四项检查 —— 环境不合格时那些数字没有解释意义")

        // 换回 perf-v1（允许 Mac）后才真正判四项，用于对照。
        let underV1 = ReleaseGate.evaluate(configVersion: "gate-rerun", current: hybrid,
                                           baseline: keyword, thresholds: GateThresholds(performance: .v1),
                                           environment: actual)
        print("    同一份数字换 perf-v1（允许 Mac）→ \(underV1.headline)")
        for reason in underV1.blockingReasons { print("      · \(reason)") }
        print("")
        r.expect(underV1.checks.count == 4 || underV1.status == .stale,
                 "perf-v1 下能真正判四项（或因构建配置仍不合格而 STALE）")
    }

    static func run(_ r: CheckRunner) async {
        checkRegistry(r)
        checkGate(r)
        checkGateEdges(r)
        checkPromote(r)
        checkLanding(r)
        await checkLayeredPerformanceGate(r)
        await rerunGateWithRealData(r)
        await checkSLO(r)
    }
}
