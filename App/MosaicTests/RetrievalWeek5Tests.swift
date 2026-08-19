import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Week 5 —— Release Gate / Promote 接上真实数据（backlog 5.1–5.4）
///
/// 内核 checks 证明判定逻辑本身（四项检查、阈值边界、promote 的前置条件）；
/// 这里证明**接线是通的**：Eval 跑出来的结果确实喂给了 Gate，Promote 确实换掉了
/// 生产配置，并且换完之后索引服务用的是新那套 —— 否则 Promote 只是改了一行 JSON。
@MainActor
final class RetrievalWeek5Tests: XCTestCase {

    private func makeStack() -> (notes: ModelContainer, derived: ModelContainer, store: DerivedDataStore) {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = ModelContainerFactory.makeDerived(inMemory: true)
        return (notes, derived, DerivedDataStore(container: derived))
    }

    private func tempDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("release-\(UUID().uuidString)", isDirectory: true)
    }

    @discardableResult
    private func seed(_ ctx: ModelContext, title: String, texts: [String]) throws -> Card {
        let card = Card(userTitle: title)
        ctx.insert(card)
        for (i, t) in texts.enumerated() {
            let b = Block(kind: .text, order: i)
            b.text = t
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        return card
    }

    private func waitUntilFinished(_ vm: RetrievalEvalViewModel, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !vm.isBusy, vm.phase != .idle { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("评测未在 \(timeout)s 内结束，phase = \(vm.phase)")
    }


    /// 接受模拟器 + 当前构建的性能 policy。
    ///
    /// 这些用例测的是 **Promote 机制**（谁能换生产配置），不是性能。
    /// 用生产的 `perf-v2` 会让它们全部 STALE —— 那个行为本身由
    /// `testDefaultPolicyBlocksPromoteFromSimulatorNumbers` 单独守。
    private func installPermissivePerformancePolicy(_ store: ReleaseStore) {
        store.updateThresholds(GateThresholds(performance: PerformanceGatePolicy(
            version: "test-permissive",
            firstResultP50Ms: 100_000, firstResultP95Ms: 100_000,
            semanticLocalP95Ms: 100_000,
            requiredDeviceClass: .simulator,
            requiredBuildConfiguration: "debug")))
    }

    // MARK: 1 · 注册表落盘

    func testReleaseStorePersistsRegistryAcrossLaunches() throws {
        let dir = tempDirectory()
        let store = ReleaseStore(directory: dir)
        XCTAssertEqual(store.registry.records.count, 1)
        XCTAssertNil(store.registry.candidate)

        let draft = try XCTUnwrap(store.duplicate(from: store.registry.production.id) { $0.topK = 35 })
        store.setCandidate(id: draft.id)
        XCTAssertNil(store.lastError, "写盘不能静默失败")

        // 「哪一套配置在线上跑」不可重建 —— 重启后必须还在。
        let reopened = ReleaseStore(directory: dir)
        XCTAssertEqual(reopened.registry.records.count, 2)
        XCTAssertEqual(reopened.registry.candidate?.config.topK, 35)
        XCTAssertEqual(reopened.productionConfig.version, store.productionConfig.version)

        // 跑批结果**不**落盘：隔了一次重启的评测结果不该拿来放行上线。
        XCTAssertNil(reopened.latestRun)
        XCTAssertEqual(reopened.decision.status, .stale)
    }

    // MARK: 2 · Eval → Gate 的接线

    func testEvalRunFeedsTheGateAndBaselineIsRequired() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "延期毕业相关", texts: ["我问了 advisor 能不能延期一个学期毕业。"])

        let release = ReleaseStore(directory: tempDirectory())
        installPermissivePerformancePolicy(release)
        let datasets = EvalDatasetStore(directory: tempDirectory())
        datasets.addGolden(query: "延期 毕业", expectedNoteIDs: [card.id.uuidString])

        // provider 必须存在：生产配置是 hybrid，而**没有句向量模型的机器上根本
        // 无法验证一套 hybrid 配置** —— 那种情况下 Gate 会一直 STALE，这是对的
        // （TD-9 的模拟器现状），不是 Gate 坏了。
        let vm = RetrievalEvalViewModel(store: datasets, provider: MockEmbeddingProvider(dimension: 16),
                                        corpus: NoteCorpus(noteContext: ctx, derived: stack.store),
                                        release: release)
        // 没有跑批 → STALE，不是 PASS。
        XCTAssertEqual(release.decision.status, .stale)

        // 初值直接取自要判定的那套配置 —— 不然每次都要手动对齐六个 Picker。
        XCTAssertEqual(vm.mode, release.evaluationTarget.config.mode)
        XCTAssertEqual(vm.topK, release.evaluationTarget.config.topK)
        vm.selection = .golden
        vm.run()
        try await waitUntilFinished(vm)

        XCTAssertNotNil(release.latestRun, "current 跑批喂给了 Gate")
        XCTAssertEqual(release.latestRun?.configVersion, release.evaluationTarget.config.version,
                       "参数与生产记录一致时，版本号取记录的 —— 否则 Gate 永远 STALE")
        // 只有 current 没有 baseline：质量类检查无法成立，不能默认放行。
        XCTAssertEqual(release.decision.status, .blocked)
        let recallCheck = try XCTUnwrap(release.decision.checks.first { $0.kind == .recallAt5 })
        XCTAssertFalse(recallCheck.passed)
        XCTAssertTrue(recallCheck.detail?.contains("baseline") == true,
                      "说明是「还没跑 baseline」而不是「质量下降」")

        vm.baselineMode = .keyword
        vm.baselineTopK = 5
        vm.run(baseline: true)
        try await waitUntilFinished(vm)
        XCTAssertNotNil(release.latestBaselineRun, "baseline 跑批也喂给了 Gate")
        XCTAssertEqual(release.decision.checks.count, 4)
    }

    /// 随手在 Eval 里改一个 topK 跑出来的结果，版本号与候选配置对不上 ——
    /// Gate 必须报 STALE 而不是拿它放行。这正是「改完参数没重跑评测就上线」的形态。
    func testAdHocParametersMakeTheGateStale() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "笔记", texts: ["延期一个学期毕业。"])

        let release = ReleaseStore(directory: tempDirectory())
        installPermissivePerformancePolicy(release)
        let datasets = EvalDatasetStore(directory: tempDirectory())
        datasets.addGolden(query: "延期 毕业", expectedNoteIDs: [card.id.uuidString])

        let vm = RetrievalEvalViewModel(store: datasets, provider: nil,
                                        corpus: NoteCorpus(noteContext: ctx, derived: stack.store),
                                        release: release)
        vm.selection = .golden
        vm.mode = .keyword    // 注册表里没有任何一条记录是 keyword/k37
        vm.topK = 37
        vm.run()
        try await waitUntilFinished(vm)

        XCTAssertTrue(release.latestRun?.configVersion.contains("k37") == true,
                      "临时参数的版本号是描述串，不是记录版本号")
        XCTAssertEqual(release.decision.status, .stale)
        XCTAssertTrue(release.decision.staleReason?.contains("重跑评测") == true)
    }

    // MARK: 3 · Promote —— 端到端

    func testPromoteReplacesProductionConfigAndRebuildsTheIndex() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        try seed(ctx, title: "笔记", texts: [String(repeating: "延期毕业的讨论内容。", count: 40)])

        let release = ReleaseStore(directory: tempDirectory())
        installPermissivePerformancePolicy(release)
        let vectors = InMemoryVectorStore()
        let indexing = IndexingService(provider: MockEmbeddingProvider(dimension: 16),
                                       vectors: vectors,
                                       derived: stack.store,
                                       noteContext: ctx,
                                       config: release.productionConfig)
        await indexing.start()
        let chunksUnderProduction = await vectors.count()
        XCTAssertGreaterThan(chunksUnderProduction, 0, "生产策略下先建起索引")

        // 派生一条 chunk 策略不同的候选。
        let candidate = try XCTUnwrap(release.duplicate(from: release.registry.production.id) {
            $0.chunkStrategy = .block
        })
        release.setCandidate(id: candidate.id)

        let gate = ReleaseGateViewModel(store: release, indexing: indexing)
        XCTAssertFalse(gate.canPromote, "还没有评测结果时不可 Promote")

        // 手工喂两次跑批（这里测的是 Promote 的副作用，不是评测本身）。
        let metrics = EvalMetrics(caseCount: 4, recallAt1: 0.75, recallAt3: 1, recallAt5: 1,
                                  mrr: 0.875, p50Ms: 5, p95Ms: 9)
        let baselineMetrics = EvalMetrics(caseCount: 4, recallAt1: 0.5, recallAt3: 0.75, recallAt5: 0.75,
                                          mrr: 0.625, p50Ms: 5, p95Ms: 8)
        release.recordRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "mock-v1",
                                  metrics: metrics, goldenMetrics: metrics,
                                  regressionMetrics: .zero, failures: []))
        release.recordBaselineRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "mock-v1",
                                          metrics: baselineMetrics, goldenMetrics: baselineMetrics,
                                          regressionMetrics: .zero, failures: []))

        XCTAssertEqual(gate.decision.status, .pass)
        XCTAssertTrue(gate.canPromote)

        gate.promote()
        XCTAssertEqual(release.productionConfig.chunkStrategy, .block, "生产配置换成了候选")
        XCTAssertNotNil(release.registry.production.promotedAt, "写入 promotedAt")
        XCTAssertNil(release.registry.candidate, "promote 之后不再有候选")

        // 索引服务必须跟着换 —— 否则线上跑的还是旧策略，Gate 判过的那套从未生效。
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(indexing.config.chunkStrategy, .block)
        let chunksAfter = await vectors.count()
        XCTAssertGreaterThan(chunksAfter, 0, "换策略后索引重建，不是清空后不管")
        XCTAssertNotEqual(chunksAfter, chunksUnderProduction,
                          "block 策略与默认的 fixed(240/40) chunk 数不同 —— 索引确实按新策略重建了")

        // 重启后仍然是新配置。
        let reopened = ReleaseStore(directory: release.registryDirectoryForTesting)
        XCTAssertEqual(reopened.productionConfig.chunkStrategy, .block)
    }

    /// 判定 BLOCKED 时，Promote 不只是按钮置灰 —— 注册表本身拒绝。
    func testBlockedDecisionCannotPromoteEvenIfCalledDirectly() throws {
        let release = ReleaseStore(directory: tempDirectory())
        // 环境宽松（允许模拟器），但**延迟预算保持严格** —— 这一条测的正是
        // 「P95 超预算时不能 promote」，宽松的延迟预算会让它测不到东西。
        release.updateThresholds(GateThresholds(performance: PerformanceGatePolicy(
            version: "test-strict-latency",
            firstResultP50Ms: 100, firstResultP95Ms: 250,
            requiredDeviceClass: .simulator, requiredBuildConfiguration: "debug")))
        let candidate = try XCTUnwrap(release.duplicate(from: release.registry.production.id) { $0.topK = 30 })
        release.setCandidate(id: candidate.id)

        let metrics = EvalMetrics(caseCount: 4, recallAt1: 1, recallAt3: 1, recallAt5: 1,
                                  mrr: 1, p50Ms: 200, p95Ms: 999)      // P95 远超预算
        let baselineMetrics = EvalMetrics(caseCount: 4, recallAt1: 0.5, recallAt3: 0.5, recallAt5: 0.5,
                                          mrr: 0.5, p50Ms: 5, p95Ms: 8)
        release.recordRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                  metrics: metrics, goldenMetrics: metrics,
                                  regressionMetrics: .zero, failures: []))
        release.recordBaselineRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                          metrics: baselineMetrics, goldenMetrics: baselineMetrics,
                                          regressionMetrics: .zero, failures: []))

        XCTAssertEqual(release.decision.status, .blocked)
        // 绕过 ViewModel 直接调 store —— 拦截必须在更下面一层。
        XCTAssertFalse(release.promote(id: candidate.id, decision: release.decision))
        XCTAssertNotEqual(release.productionConfig.topK, 30, "生产配置没有被换掉")
        XCTAssertTrue(release.lastError?.contains("Release Gate 未通过") == true)
    }

    // MARK: 4 · 生产搜索用的是被 Promote 的那套配置

    func testProductionSearchUsesPromotedConfigVersion() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        try seed(ctx, title: "延期毕业", texts: ["我问了 advisor 能不能延期一个学期毕业。"])

        let release = ReleaseStore(directory: tempDirectory())
        installPermissivePerformancePolicy(release)
        let candidate = try XCTUnwrap(release.duplicate(from: release.registry.production.id) { $0.topK = 30 })
        release.setCandidate(id: candidate.id)
        let metrics = EvalMetrics(caseCount: 2, recallAt1: 1, recallAt3: 1, recallAt5: 1,
                                  mrr: 1, p50Ms: 3, p95Ms: 6)
        let baseline = EvalMetrics(caseCount: 2, recallAt1: 0.5, recallAt3: 0.5, recallAt5: 0.5,
                                   mrr: 0.5, p50Ms: 3, p95Ms: 6)
        release.recordRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                  metrics: metrics, goldenMetrics: metrics,
                                  regressionMetrics: .zero, failures: []))
        release.recordBaselineRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                          metrics: baseline, goldenMetrics: baseline,
                                          regressionMetrics: .zero, failures: []))

        let vectors = InMemoryVectorStore()
        let indexing = IndexingService(provider: nil, vectors: vectors, derived: stack.store,
                                       noteContext: ctx, config: release.productionConfig)
        let gate = ReleaseGateViewModel(store: release, indexing: indexing)
        gate.promote()
        try await Task.sleep(nanoseconds: 300_000_000)

        let recorder = RetrievalTraceRecorder()
        let vm = SearchViewModel(provider: nil, vectors: vectors, recorder: recorder,
                                 indexing: indexing, derived: stack.store, noteContext: ctx,
                                 keywordDebounceNanos: 0, semanticDebounceNanos: 0)
        vm.queryChanged("延期 毕业")
        try await Task.sleep(nanoseconds: 400_000_000)

        let traces = await recorder.recent()
        let trace = try XCTUnwrap(traces.first)
        XCTAssertEqual(trace.configVersion, candidate.config.version,
                       "线上检索用的是被 Promote 的那套配置，不是编译期常量")
    }

    // MARK: 5 · 默认 policy 必须拦住模拟器数字

    /// **分层 policy 的产品主张**：模拟器 / debug 的性能数字没有资格换生产配置。
    /// 这一条用生产默认 `perf-v2`，刻意不装宽松 policy。
    func testDefaultPolicyBlocksPromoteFromSimulatorNumbers() throws {
        let release = ReleaseStore(directory: tempDirectory())   // 默认 perf-v2
        let candidate = try XCTUnwrap(release.duplicate(from: release.registry.production.id) { $0.topK = 30 })
        release.setCandidate(id: candidate.id)

        let good = EvalMetrics(caseCount: 4, recallAt1: 1, recallAt3: 1, recallAt5: 1,
                               mrr: 1, p50Ms: 5, p95Ms: 9)
        let base = EvalMetrics(caseCount: 4, recallAt1: 0.5, recallAt3: 0.5, recallAt5: 0.5,
                               mrr: 0.5, p50Ms: 5, p95Ms: 9)
        release.recordRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                  metrics: good, goldenMetrics: good,
                                  regressionMetrics: .zero, failures: []))
        release.recordBaselineRun(EvalRun(configVersion: candidate.config.version, embeddingVersion: "m",
                                          metrics: base, goldenMetrics: base,
                                          regressionMetrics: .zero, failures: []))

        XCTAssertEqual(release.decision.status, .stale,
                       "质量四项全绿，但数字来自模拟器 / debug → STALE，不是 PASS")
        XCTAssertTrue(release.decision.staleReason?.contains("测量环境") == true,
                      "说明原因是环境不合格，而不是质量或延迟")
        XCTAssertFalse(release.promote(id: candidate.id, decision: release.decision),
                       "STALE 的判定无法 promote —— 拿不到真机数字就换不了生产配置")
        XCTAssertNotEqual(release.productionConfig.topK, 30, "生产配置没有被换掉")
        XCTAssertNotNil(release.latestRunEnvironment, "recordRun 必须捕获当时的测量环境")
    }
}

extension ReleaseStore {
    /// 测试用：重开一个实例读同一个目录。生产代码不需要暴露它。
    var registryDirectoryForTesting: URL { storageDirectory }
}
