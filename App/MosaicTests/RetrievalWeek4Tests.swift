import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Week 4 —— Eval Center / Compare / Failure Inspection 接上真实 SwiftData
///
/// MosaicKit 的 checks 证明口径本身（Recall@K / MRR / 幂等 / 取消）；这里证明
/// 它接上真实笔记、真实 chunk 切分、真实落盘之后依然成立。
///
/// 用 `MockEmbeddingProvider`：这些用例断言的是**管线**（跑得起来、指标算得出、
/// 失败收得到、回归集写得进），不是检索质量。质量数字要用真实 provider 测，
/// 见 `EvalChecks` 的 Golden Set 实测。
@MainActor
final class RetrievalWeek4Tests: XCTestCase {

    private func makeStack() -> (notes: ModelContainer, derived: ModelContainer, store: DerivedDataStore) {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = ModelContainerFactory.makeDerived(inMemory: true)
        return (notes, derived, DerivedDataStore(container: derived))
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

    private func makeDatasetStore() -> EvalDatasetStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eval-\(UUID().uuidString)", isDirectory: true)
        return EvalDatasetStore(directory: dir)
    }

    private func makeViewModel(store: EvalDatasetStore,
                               provider: (any EmbeddingProvider)?,
                               ctx: ModelContext,
                               derived: DerivedDataStore) -> RetrievalEvalViewModel {
        RetrievalEvalViewModel(store: store, provider: provider,
                               corpus: NoteCorpus(noteContext: ctx, derived: derived))
    }

    /// 轮询到跑批结束。评测是 `Task` 驱动的，没有可等待的句柄。
    private func waitUntilFinished(_ vm: RetrievalEvalViewModel, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !vm.isBusy, vm.phase != .idle { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("评测未在 \(timeout)s 内结束，phase = \(vm.phase)")
    }

    // MARK: 1 · D5 —— 在真实笔记上跑出指标

    func testEvalRunProducesMetricsOnRealNotes() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let delay = try seed(ctx, title: "延期毕业相关",
                             texts: ["我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认。"])
        let contract = try seed(ctx, title: "合同评审",
                                texts: ["今天把合同评审的三处修改整理好了，法务反馈了三处。"])

        let store = makeDatasetStore()
        // query 按空白切分后逐个子串定位（`TextMatcher` 的口径），所以「延期 毕业」
        // 两个 token 都能在正文里定位到，而「延期毕业」作为整串定位不到。
        XCTAssertTrue(store.addGolden(query: "延期 毕业", expectedNoteIDs: [delay.id.uuidString]))
        XCTAssertTrue(store.addGolden(query: "合同 修改", expectedNoteIDs: [contract.id.uuidString]))

        let vm = makeViewModel(store: store, provider: MockEmbeddingProvider(dimension: 32),
                               ctx: ctx, derived: stack.store)
        vm.selection = .golden
        vm.mode = .hybrid
        vm.topK = 5
        vm.run()
        try await waitUntilFinished(vm)

        XCTAssertEqual(vm.phase, .done)
        let run = try XCTUnwrap(vm.run)
        XCTAssertEqual(run.metrics.caseCount, 2, "两条用例都被执行")
        XCTAssertEqual(run.goldenMetrics.caseCount, 2, "Golden 部分单独统计")
        XCTAssertEqual(run.regressionMetrics.caseCount, 0, "回归集为空")
        XCTAssertEqual(run.regressionPassRate, 1.0, "没有回归用例就没有回归")
        XCTAssertTrue((0...1).contains(run.metrics.recallAt5))
        XCTAssertGreaterThan(run.metrics.p50Ms, 0, "延迟只统计检索本身，但不该是 0")

        XCTAssertEqual(run.metrics.recallAt5, 1.0, "两条用例都被召回")
        XCTAssertTrue(run.failures.isEmpty, "全部命中时没有失败用例")

        // config.version 由可调项拼出来，与实际参数不会对不上。
        XCTAssertTrue(run.configVersion.contains("hybrid") && run.configVersion.contains("k5"),
                      "配置身份记录了实际参数（得到 \(run.configVersion)）")
    }

    // MARK: 2 · 没有句向量模型时，keyword 评测照常

    func testKeywordEvaluationRunsWithoutEmbeddingProvider() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "延期毕业相关",
                            texts: ["我问了 advisor 能不能延期一个学期毕业。"])

        let store = makeDatasetStore()
        store.addGolden(query: "延期 毕业", expectedNoteIDs: [card.id.uuidString])

        // provider = nil：**不退回 mock**。语义路整条跳过，keyword 路照常。
        let vm = makeViewModel(store: store, provider: nil, ctx: ctx, derived: stack.store)
        vm.selection = .golden
        vm.mode = .keyword
        vm.run()
        try await waitUntilFinished(vm)

        XCTAssertEqual(vm.phase, .done)
        XCTAssertEqual(vm.run?.metrics.recallAt1, 1.0, "没有模型也能评测词法路")
        XCTAssertFalse(vm.providerAvailable)

        // 而语义路必须明确失败，不能静默给出一个看起来正常的数字。
        vm.mode = .hybrid
        vm.run()
        if case .failed = vm.phase {} else {
            XCTFail("没有模型时语义评测必须明确失败，phase = \(vm.phase)")
        }
        XCTAssertNil(vm.baselineRun)
    }

    // MARK: 3 · D9 —— 失败收集、归因、加入回归集

    func testFailureTriageAndRegressionAdd() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        try seed(ctx, title: "无关笔记", texts: ["楼下那家面馆的辣椒油很香。"])

        let store = makeDatasetStore()
        // 期望一篇不存在的笔记 —— 这是确定会失败的用例（与 EvalChecks 的 g7 同一手法）。
        store.addGolden(query: "完全不存在的内容 xyzzy", expectedNoteIDs: ["missing-note"])

        let vm = makeViewModel(store: store, provider: MockEmbeddingProvider(dimension: 32),
                               ctx: ctx, derived: stack.store)
        vm.selection = .golden
        vm.run()
        try await waitUntilFinished(vm)

        XCTAssertEqual(vm.failures.count, 1, "失败用例被收集")
        XCTAssertFalse(vm.failures[0].isTriaged, "初始未归因")
        XCTAssertFalse(vm.isInRegressionSet(at: 0))

        vm.setFailureType(.missingData, at: 0)
        vm.setDiagnosisNote("语料里根本没有这段文本", at: 0)
        XCTAssertTrue(vm.failures[0].isTriaged)

        XCTAssertTrue(vm.addToRegressionSet(at: 0), "首次加入成功")
        XCTAssertFalse(vm.addToRegressionSet(at: 0), "重复加入被拒绝 —— 否则 Pass Rate 分母虚高")
        XCTAssertTrue(vm.isInRegressionSet(at: 0), "按钮据此变为 In Regression Set（禁用）")

        let regressionCase = try XCTUnwrap(store.dataset.regression.cases.first)
        XCTAssertEqual(regressionCase.source, .regression)
        XCTAssertEqual(regressionCase.sourceFailureType, .missingData, "归因随用例保留，可用于统计")

        // 下一次 Eval 自动带上回归集，两部分分开统计。
        vm.selection = .both
        vm.run()
        try await waitUntilFinished(vm)
        let run = try XCTUnwrap(vm.run)
        XCTAssertEqual(run.goldenMetrics.caseCount, 1)
        XCTAssertEqual(run.regressionMetrics.caseCount, 1)
        XCTAssertEqual(run.regressionPassRate, run.regressionMetrics.recallAt5,
                       "Pass Rate 与 Recall@5 同口径")
    }

    // MARK: 4 · D6 —— 两次跑批的 delta 与 trade-off

    func testComparisonAgainstBaselineConfig() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "延期毕业相关",
                            texts: ["我问了 advisor 能不能延期一个学期毕业。",
                                    "周会上说延期的事下周开会再定。"])

        let store = makeDatasetStore()
        store.addGolden(query: "延期毕业", expectedNoteIDs: [card.id.uuidString])

        let vm = makeViewModel(store: store, provider: MockEmbeddingProvider(dimension: 32),
                               ctx: ctx, derived: stack.store)
        vm.selection = .golden
        vm.mode = .hybrid
        vm.run()
        try await waitUntilFinished(vm)
        XCTAssertTrue(vm.deltas.isEmpty, "只有一次跑批时无从对比")

        vm.baselineMode = .keyword
        vm.run(baseline: true)
        try await waitUntilFinished(vm)

        XCTAssertNotNil(vm.baselineRun)
        XCTAssertTrue(vm.isComparable, "两次跑批必须跑在同一批用例上")
        let deltas = vm.deltas
        XCTAssertEqual(deltas.count, 6, "质量四项 + 延迟两项，在同一张表里")
        XCTAssertEqual(deltas.map(\.label), ["Recall@1", "Recall@3", "Recall@5", "MRR", "P50", "P95"])
        XCTAssertTrue(deltas.filter { $0.polarity == .lowerIsBetter }.count == 2, "延迟两项越小越好")
        let summary = try XCTUnwrap(vm.tradeoffSummary)
        XCTAssertFalse(summary.contains("PASS") || summary.contains("FAIL"),
                       "Eval 不下判定 —— 那是 Release Gate 的事")
    }

    /// D9 的 `Add to Regression Set` 会当场把 `.both` 的用例数 +1。
    /// 如果 baseline 这时去取「现在的数据集」，delta 里就混进了用例集的变化 ——
    /// 那不是配置的差异。**这个 bug 是在模拟器上实跑 Flow B 时发现的。**
    func testBaselineRunsTheSameCaseSetAsCurrent() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "延期毕业相关", texts: ["我问了 advisor 能不能延期一个学期毕业。"])

        let store = makeDatasetStore()
        store.addGolden(query: "延期 毕业", expectedNoteIDs: [card.id.uuidString])
        store.addGolden(query: "认知革命", expectedNoteIDs: [card.id.uuidString])

        let vm = makeViewModel(store: store, provider: nil, ctx: ctx, derived: stack.store)
        vm.selection = .both
        vm.mode = .keyword
        vm.run()
        try await waitUntilFinished(vm)
        XCTAssertEqual(vm.run?.metrics.caseCount, 2)
        XCTAssertEqual(vm.failures.count, 1)

        // 归因并加入回归集 —— 数据集当场从 2 条变成 3 条。
        vm.setFailureType(.missingData, at: 0)
        XCTAssertTrue(vm.addToRegressionSet(at: 0))
        XCTAssertEqual(store.count(.both), 3, "数据集确实变大了")

        vm.baselineMode = .keyword
        vm.baselineTopK = 5
        vm.run(baseline: true)
        try await waitUntilFinished(vm)

        XCTAssertEqual(vm.baselineRun?.metrics.caseCount, 2,
                       "baseline 跑 current 当时的那一批，而不是变大后的数据集")
        XCTAssertTrue(vm.isComparable)
        XCTAssertFalse(vm.deltas.isEmpty)

        // 重跑 current 会作废旧 baseline —— 否则会拿新 current 去比一份跑在
        // 别的用例上的 baseline。
        vm.run()
        try await waitUntilFinished(vm)
        XCTAssertNil(vm.baselineRun)
        XCTAssertTrue(vm.deltas.isEmpty)
        XCTAssertEqual(vm.run?.metrics.caseCount, 3, "重跑才会带上新加的回归用例")
    }

    // MARK: 5 · 数据集落盘与坏用例识别

    func testDatasetStorePersistsAndFlagsDanglingCases() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx, title: "延期毕业相关", texts: ["延期一个学期毕业。"])

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eval-\(UUID().uuidString)", isDirectory: true)
        let store = EvalDatasetStore(directory: dir)
        XCTAssertTrue(store.addGolden(query: "延期毕业", expectedNoteIDs: [card.id.uuidString]))
        XCTAssertFalse(store.addGolden(query: " 延期毕业 ", expectedNoteIDs: [card.id.uuidString]),
                       "同 query + 同期望重复加入被拒绝")
        XCTAssertTrue(store.addGolden(query: "已删笔记的用例", expectedNoteIDs: ["gone"]))
        XCTAssertNil(store.lastError, "写盘不能静默失败")

        // 换一个实例读同一个目录 —— 标注是人工判断，重启后必须还在。
        let reopened = EvalDatasetStore(directory: dir)
        XCTAssertEqual(reopened.count(.golden), 2, "数据集落盘并可重新读出")
        XCTAssertEqual(Set(reopened.dataset.golden.map(\.query)), ["延期毕业", "已删笔记的用例"])

        let vm = makeViewModel(store: reopened, provider: MockEmbeddingProvider(dimension: 32),
                               ctx: ctx, derived: stack.store)
        vm.selection = .golden
        let dangling = vm.danglingCases
        XCTAssertEqual(dangling.count, 1, "引用已删笔记的用例被标出来")
        XCTAssertEqual(dangling.first?.query, "已删笔记的用例")

        reopened.removeGolden(id: dangling[0].id)
        XCTAssertEqual(EvalDatasetStore(directory: dir).count(.golden), 1, "删除同样落盘")
    }

    // MARK: 6 · 空数据集不给一个看起来正常的 0.000

    func testEmptyDatasetFailsLoudly() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        try seed(ctx, title: "笔记", texts: ["随便什么内容。"])

        let vm = makeViewModel(store: makeDatasetStore(),
                               provider: MockEmbeddingProvider(dimension: 32),
                               ctx: ctx, derived: stack.store)
        vm.selection = .golden
        vm.run()

        if case let .failed(message) = vm.phase {
            XCTAssertTrue(message.contains("数据集为空"))
        } else {
            XCTFail("空数据集必须明确失败，而不是给出 0.000")
        }
        XCTAssertNil(vm.run)
    }
}
