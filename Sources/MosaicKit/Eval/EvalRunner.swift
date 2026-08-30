import Foundation

/// # 评测执行器
///
/// 对一组 `EvalCase` 逐条跑检索，算 Recall@K / MRR / 无结果准确率 / P50 / P95，
/// 并收集失败证据。
///
/// ## 口径（写在这里，避免以后有第二种说法）
///
/// - **命中**：期望笔记出现在 Top K 的**笔记去重列表**里。
///   以笔记而非 chunk 计：一篇笔记的 3 个 chunk 都进 Top 5 只算命中一次，
///   否则长笔记会凭 chunk 多而虚高。
/// - **Recall@K**：`命中的正例数 / 正例总数`。多个 expected 时，
///   **全部**都要落在 Top K 才算通过 —— 宽松口径（命中任意一个即算）会让
///   「找到一半」看起来和「全找到」一样好。
///
///   **分母只包含 `expected.count ≤ K` 的用例。** 一条要求两篇笔记的用例，
///   在 Top-1 的列表里**永远**不可能满足 —— 把它算成 miss，测到的是指标定义
///   而不是系统表现。`scenario-v5` 的 10 条歧义用例各有两个答案，
///   不排除的话它们会让每一条臂的 R@1 一律低约 0.05，而且**绝对下限那一行
///   会因此判错**。K=3 / K=5 时它们仍然进分母（2 ≤ 3），严格口径不变。
/// - **MRR**：第一个正确笔记的名次倒数；一条都没命中记 0。
/// - **No-result accuracy**：负例中返回空列表的比例。当前严格以
///   `results.isEmpty` 判定；在 TD-10 相关性下限落地前，不做分数猜测。
/// - **P50 / P95**：**只统计检索本身**，不含评测框架、不含 UI 动画
///   （PRD 的 SLO 也是这个口径）。
public actor EvalRunner {

    public struct Progress: Sendable, Equatable {
        public let done: Int
        public let total: Int
        public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    private let service: RetrievalService
    private let chunksProvider: @Sendable () async -> [NoteChunk]

    public init(service: RetrievalService,
                chunksProvider: @escaping @Sendable () async -> [NoteChunk]) {
        self.service = service
        self.chunksProvider = chunksProvider
    }

    /// 跑一批用例。
    ///
    /// - Parameter onProgress: 每完成一条回调一次。
    /// - Note: 支持取消 —— 中途取消**不留半份结果**（抛 `CancellationError`），
    ///   因为半份指标比没有指标更危险：它看起来像个数字。
    public func run(cases: [EvalCase],
                    config: RetrievalConfig,
                    indexState: IndexState = .ready,
                    onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> EvalRun {

        let chunks = await chunksProvider()
        var perCase: [(evalCase: EvalCase, rank: Int?, returned: [String],
                       outcome: RetrievalOutcome, latencyMs: Double)] = []

        for (i, c) in cases.enumerated() {
            try Task.checkCancellation()

            let t0 = DispatchTime.now().uptimeNanoseconds
            let outcome = await service.retrieve(query: c.query, chunks: chunks,
                                                 config: config, indexState: indexState)
            let latencyMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

            // 按笔记去重，保持排名顺序。
            var seen = Set<String>()
            var noteOrder: [String] = []
            for result in outcome.results where !seen.contains(result.ref.noteID) {
                seen.insert(result.ref.noteID)
                noteOrder.append(result.ref.noteID)
            }
            perCase.append((c, firstRelevantRank(expected: c.expectedNoteIDs, in: noteOrder),
                            noteOrder, outcome, latencyMs))
            onProgress?(Progress(done: i + 1, total: cases.count))
        }

        let golden = perCase.filter { $0.evalCase.source == .golden }
        let regression = perCase.filter { $0.evalCase.source == .regression }
        let inScope = perCase.filter {
            $0.evalCase.scope == .inScope && isRelevant($0.evalCase.expectation)
        }
        let crossLanguage = perCase.filter {
            $0.evalCase.scope == .crossLanguage && isRelevant($0.evalCase.expectation)
        }
        let inScopeRegression = regression.filter {
            $0.evalCase.scope == .inScope && isRelevant($0.evalCase.expectation)
        }

        return EvalRun(
            configVersion: config.version,
            embeddingVersion: config.embeddingVersion,
            metrics: metrics(perCase),
            goldenMetrics: metrics(golden),
            regressionMetrics: metrics(regression),
            failures: perCase.compactMap { entry in
                guard !passes(entry.evalCase.expectation, returned: entry.returned, k: 5) else { return nil }
                let first = entry.evalCase.expectedNoteIDs.first
                return EvalFailure(
                    evalCase: entry.evalCase,
                    returnedNoteIDs: Array(entry.returned.prefix(5)),
                    keywordRank: rank(of: first, in: entry.outcome, path: .keyword),
                    vectorRank: rank(of: first, in: entry.outcome, path: .vector),
                    hybridRank: entry.rank
                )
            },
            inScopeMetrics: metrics(inScope),
            crossLanguageMetrics: metrics(crossLanguage),
            inScopeRegressionMetrics: metrics(inScopeRegression),
            outcomes: perCase.map { entry in
                let expected = entry.evalCase.expectedNoteIDs
                let positive = isRelevant(entry.evalCase.expectation)
                return EvalCaseOutcome(
                    caseID: entry.evalCase.id,
                    scope: entry.evalCase.scope,
                    isPositive: positive,
                    // `expectedCount` 让配对 bootstrap 能用与汇总指标**同一个分母**：
                    // 两边分母不一致时，「置信区间」算的就不是那个点估计的区间。
                    expectedCount: expected.count,
                    hitAt1: positive && isHit(expected: expected, in: entry.returned, k: 1),
                    hitAt3: positive && isHit(expected: expected, in: entry.returned, k: 3),
                    hitAt5: positive && isHit(expected: expected, in: entry.returned, k: 5),
                    reciprocalRank: positive ? (entry.rank.map { 1.0 / Double($0) } ?? 0) : 0,
                    latencyMs: entry.latencyMs)
            }
        )
    }

    // MARK: 口径实现

    private enum Path { case keyword, vector }

    /// 某篇笔记在指定路的名次（1-based），未命中为 nil。
    private func rank(of noteID: String?, in outcome: RetrievalOutcome, path: Path) -> Int? {
        guard let noteID else { return nil }
        let ranked = outcome.results.compactMap { r -> (String, Int)? in
            let value: Int?
            switch path {
            case .keyword: value = r.keywordRank
            case .vector: value = r.vectorRank
            }
            guard let value else { return nil }
            return (r.ref.noteID, value)
        }
        return ranked.filter { $0.0 == noteID }.map(\.1).min()
    }

    /// 全部 expected 是否都在 Top K 内。
    private func isHit(expected: [String], in noteOrder: [String], k: Int) -> Bool {
        guard !expected.isEmpty else { return false }
        let top = Set(noteOrder.prefix(k))
        return expected.allSatisfy { top.contains($0) }
    }

    private func passes(_ expectation: EvalExpectation, returned: [String], k: Int) -> Bool {
        switch expectation {
        case let .relevant(noteIDs): return isHit(expected: noteIDs, in: returned, k: k)
        case .noRelevantResult: return returned.isEmpty
        }
    }

    private func isRelevant(_ expectation: EvalExpectation) -> Bool {
        if case .relevant = expectation { return true }
        return false
    }

    /// 第一个正确笔记的名次（1-based），用于 MRR。
    private func firstRelevantRank(expected: [String], in noteOrder: [String]) -> Int? {
        let wanted = Set(expected)
        guard let idx = noteOrder.firstIndex(where: { wanted.contains($0) }) else { return nil }
        return idx + 1
    }

    private func metrics(_ entries: [(evalCase: EvalCase, rank: Int?, returned: [String],
                                      outcome: RetrievalOutcome, latencyMs: Double)]) -> EvalMetrics {
        guard !entries.isEmpty else { return .zero }
        let positives = entries.filter {
            if case .relevant = $0.evalCase.expectation { return true }
            return false
        }
        let negatives = entries.filter { $0.evalCase.expectation == .noRelevantResult }
        let positiveCount = Double(positives.count)
        /// Recall@K。分母是**在 Top-K 里可满足**的那些正例（`expected.count ≤ K`）。
        func recall(_ k: Int) -> Double {
            let satisfiable = positives.filter { $0.evalCase.expectedNoteIDs.count <= k }
            guard !satisfiable.isEmpty else { return 0 }
            return Double(satisfiable.filter {
                isHit(expected: $0.evalCase.expectedNoteIDs, in: $0.returned, k: k)
            }.count) / Double(satisfiable.count)
        }
        let mrr = positiveCount == 0 ? 0 : positives.reduce(0.0) {
            $0 + ($1.rank.map { 1.0 / Double($0) } ?? 0)
        } / positiveCount
        let correctNoResult = negatives.filter { $0.returned.isEmpty }.count
        let noResultAccuracy = negatives.isEmpty
            ? 0
            : Double(correctNoResult) / Double(negatives.count)
        let sorted = entries.map(\.latencyMs).sorted()
        let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return EvalMetrics(caseCount: entries.count,
                           relevantCaseCount: positives.count,
                           noResultCaseCount: negatives.count,
                           recallAt1: recall(1), recallAt3: recall(3), recallAt5: recall(5),
                           mrr: mrr, p50Ms: p50, p95Ms: p95,
                           noResultAccuracy: noResultAccuracy,
                           falsePositiveRate: negatives.isEmpty ? 0 : 1 - noResultAccuracy)
    }
}

/// # Regression Set
///
/// 一个 query 列表，不是一个平台（`DECISION_LOG.md` D-UI-DEV-009）。
/// 不做版本化、分支、导入导出、协作、标签体系。
public struct RegressionSet: Sendable, Equatable, Codable {
    public private(set) var cases: [EvalCase]

    public init(cases: [EvalCase] = []) { self.cases = cases }

    /// 加入一条失败用例。**幂等**：同一条 query + 同一组期望不会重复加入，
    /// 否则反复点击会让 Pass Rate 的分母虚高。
    @discardableResult
    public mutating func add(_ failure: EvalFailure) -> Bool {
        let query = failure.evalCase.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if cases.contains(where: {
            $0.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
                && expectationsMatch($0.expectation, failure.evalCase.expectation)
        }) { return false }

        cases.append(EvalCase(query: query,
                              expectation: failure.evalCase.expectation,
                              source: .regression,
                              sourceFailureType: failure.failureType,
                              queryLanguage: failure.evalCase.queryLanguage,
                              expectedLanguage: failure.evalCase.expectedLanguage,
                              scope: failure.evalCase.scope,
                              note: failure.diagnosisNote))
        return true
    }

    public func contains(_ failure: EvalFailure) -> Bool {
        let query = failure.evalCase.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return cases.contains {
            $0.query.trimmingCharacters(in: .whitespacesAndNewlines) == query
                && expectationsMatch($0.expectation, failure.evalCase.expectation)
        }
    }

    public mutating func remove(id: String) { cases.removeAll { $0.id == id } }
    public var count: Int { cases.count }
}

private func expectationsMatch(_ lhs: EvalExpectation, _ rhs: EvalExpectation) -> Bool {
    switch (lhs, rhs) {
    case (.noRelevantResult, .noRelevantResult): return true
    case let (.relevant(left), .relevant(right)): return Set(left) == Set(right)
    default: return false
    }
}
