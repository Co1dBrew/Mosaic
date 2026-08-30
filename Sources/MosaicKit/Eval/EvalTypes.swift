import Foundation

/// 一条评测用例的正确答案。
///
/// `noRelevantResult` 不是「漏标 expected」：它明确表示语料中没有相关笔记，
/// 只有检索返回空列表才算通过。这个区分让无答案 query 能进入同一个 Runner，
/// 同时避免把负例混进 Recall / MRR 的分母。
public enum EvalExpectation: Sendable, Equatable, Codable {
    case relevant(noteIDs: [String])
    case noRelevantResult
}

public enum EvalLanguage: String, Sendable, Equatable, Codable, CaseIterable {
    case zh
    case en
    case mixed
}

/// 跨语言能力是当前架构边界，不能混进 Release Gate 的主指标。
public enum EvalScope: String, Sendable, Equatable, Codable, CaseIterable {
    case inScope = "in-scope"
    case crossLanguage = "cross-language"
}

/// 一条评测用例。
///
/// **Golden Set 与 Regression Set 结构完全相同**（`DECISION_LOG.md` D-UI-DEV-009）。
/// 两套结构 = 两套 Runner = 两套口径，之后必然出现「Golden 说过了、Regression 说没过」
/// 的解释成本。同构是最省的选择。
public struct EvalCase: Sendable, Equatable, Codable, Identifiable {
    public enum Source: String, Sendable, Codable { case golden, regression }

    public let id: String
    public let query: String
    public let expectation: EvalExpectation
    /// 向后兼容的便捷属性。新代码需要区分 `.noRelevantResult` 时应读取
    /// `expectation`，不能用空数组猜测标注者意图。
    public var expectedNoteIDs: [String] {
        guard case let .relevant(noteIDs) = expectation else { return [] }
        return noteIDs
    }
    public let source: Source
    public let queryLanguage: EvalLanguage?
    public let expectedLanguage: EvalLanguage?
    public let scope: EvalScope
    public let addedAt: Date
    /// 从 Failure Inspection 加进来时，记录当时的失败归因。
    public let sourceFailureType: FailureType?
    /// 人工备注，说明这条为什么值得测。
    public let note: String?

    public init(id: String = UUID().uuidString,
                query: String,
                expectedNoteIDs: [String],
                source: Source = .golden,
                addedAt: Date = Date(),
                sourceFailureType: FailureType? = nil,
                queryLanguage: EvalLanguage? = nil,
                expectedLanguage: EvalLanguage? = nil,
                scope: EvalScope = .inScope,
                note: String? = nil) {
        self.init(id: id, query: query, expectation: .relevant(noteIDs: expectedNoteIDs),
                  source: source, addedAt: addedAt,
                  sourceFailureType: sourceFailureType,
                  queryLanguage: queryLanguage, expectedLanguage: expectedLanguage,
                  scope: scope, note: note)
    }

    public init(id: String = UUID().uuidString,
                query: String,
                expectation: EvalExpectation,
                source: Source = .golden,
                addedAt: Date = Date(),
                sourceFailureType: FailureType? = nil,
                queryLanguage: EvalLanguage? = nil,
                expectedLanguage: EvalLanguage? = nil,
                scope: EvalScope = .inScope,
                note: String? = nil) {
        self.id = id
        self.query = query
        self.expectation = expectation
        self.source = source
        self.queryLanguage = queryLanguage
        self.expectedLanguage = expectedLanguage
        self.scope = scope
        self.addedAt = addedAt
        self.sourceFailureType = sourceFailureType
        self.note = note
    }

    /// 兼容已经落盘的 Week 4 数据：旧 JSON 只有 `expectedNoteIDs`。
    private enum CodingKeys: String, CodingKey {
        case id, query, expectation, expectedNoteIDs, source, addedAt, sourceFailureType
        case queryLanguage, expectedLanguage, scope, note
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        query = try values.decode(String.self, forKey: .query)
        if let decoded = try values.decodeIfPresent(EvalExpectation.self, forKey: .expectation) {
            expectation = decoded
        } else {
            expectation = .relevant(noteIDs: try values.decode([String].self, forKey: .expectedNoteIDs))
        }
        source = try values.decode(Source.self, forKey: .source)
        queryLanguage = try values.decodeIfPresent(EvalLanguage.self, forKey: .queryLanguage)
        expectedLanguage = try values.decodeIfPresent(EvalLanguage.self, forKey: .expectedLanguage)
        scope = try values.decodeIfPresent(EvalScope.self, forKey: .scope) ?? .inScope
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        sourceFailureType = try values.decodeIfPresent(FailureType.self, forKey: .sourceFailureType)
        note = try values.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(query, forKey: .query)
        try values.encode(expectation, forKey: .expectation)
        try values.encode(source, forKey: .source)
        try values.encodeIfPresent(queryLanguage, forKey: .queryLanguage)
        try values.encodeIfPresent(expectedLanguage, forKey: .expectedLanguage)
        try values.encode(scope, forKey: .scope)
        try values.encode(addedAt, forKey: .addedAt)
        try values.encodeIfPresent(sourceFailureType, forKey: .sourceFailureType)
        try values.encodeIfPresent(note, forKey: .note)
    }
}

/// 失败归因。**固定 7 类，不可自由输入**（`DECISION_LOG.md` D-UI-DEV-005）。
///
/// Failure Type 是拿来统计的（「这一轮 60% 的失败是 chunking」）。
/// 自由文本没有统计价值。
public enum FailureType: String, Sendable, Equatable, Codable, CaseIterable {
    case chunking
    case embedding
    case keyword
    case fusion
    case missingData
    case staleIndex
    case other

    public var label: String {
        switch self {
        case .chunking:    return "Chunking"
        case .embedding:   return "Embedding"
        case .keyword:     return "Keyword"
        case .fusion:      return "Fusion"
        case .missingData: return "Missing Data"
        case .staleIndex:  return "Stale Index"
        case .other:       return "Other"
        }
    }

    /// 给出这一类失败的典型证据，Failure Inspection 直接显示，省掉「凭经验猜」。
    public var evidenceHint: String {
        switch self {
        case .chunking:    return "期望笔记的 chunk 里没有完整的语义单元 —— 切分把话切断了"
        case .embedding:   return "vector 排名很低，但人读上下文明显相关"
        case .keyword:     return "同义词 / 异形词，keyword 路 not found"
        case .fusion:      return "单路排名很高，融合后反而跌出 Top K"
        case .missingData: return "语料里根本没有这段文本（OCR / 转写 / 文档提取缺失）"
        case .staleIndex:  return "contentHash 与当前内容不一致"
        case .other:       return "以上都不是 —— 必须填写说明"
        }
    }
}

/// 一条失败用例的完整证据。
public struct EvalFailure: Sendable, Equatable {
    public let evalCase: EvalCase
    /// 实际返回的笔记 id，按最终排名。
    public let returnedNoteIDs: [String]
    /// 每一路各自的名次或 `nil`（未命中）。
    public let keywordRank: Int?
    public let vectorRank: Int?
    public let hybridRank: Int?
    /// 人工归因，未标注时为 nil。
    public var failureType: FailureType?
    public var diagnosisNote: String?

    public init(evalCase: EvalCase, returnedNoteIDs: [String],
                keywordRank: Int?, vectorRank: Int?, hybridRank: Int?,
                failureType: FailureType? = nil, diagnosisNote: String? = nil) {
        self.evalCase = evalCase
        self.returnedNoteIDs = returnedNoteIDs
        self.keywordRank = keywordRank
        self.vectorRank = vectorRank
        self.hybridRank = hybridRank
        self.failureType = failureType
        self.diagnosisNote = diagnosisNote
    }

    /// 未标注归因的失败没有统计价值 —— UI 应当催促标注。
    public var isTriaged: Bool { failureType != nil }
}

/// 一次评测的指标。
public struct EvalMetrics: Sendable, Equatable, Codable {
    /// 正例 + 负例总数。Recall / MRR 的分母只用 `relevantCaseCount`。
    public let caseCount: Int
    public let relevantCaseCount: Int
    public let noResultCaseCount: Int
    public let recallAt1: Double
    public let recallAt3: Double
    public let recallAt5: Double
    public let mrr: Double
    public let p50Ms: Double
    public let p95Ms: Double
    /// 正确返回空列表的负例数 / `noResultCaseCount`。没有负例时记 0（不适用）。
    public let noResultAccuracy: Double
    /// 负例中返回了任意结果的比例。没有负例时记 0（不适用）。
    public let falsePositiveRate: Double

    public init(caseCount: Int, relevantCaseCount: Int? = nil, noResultCaseCount: Int = 0,
                recallAt1: Double, recallAt3: Double, recallAt5: Double,
                mrr: Double, p50Ms: Double, p95Ms: Double,
                noResultAccuracy: Double = 0, falsePositiveRate: Double = 0) {
        self.caseCount = caseCount
        self.relevantCaseCount = relevantCaseCount ?? caseCount
        self.noResultCaseCount = noResultCaseCount
        self.recallAt1 = recallAt1
        self.recallAt3 = recallAt3
        self.recallAt5 = recallAt5
        self.mrr = mrr
        self.p50Ms = p50Ms
        self.p95Ms = p95Ms
        self.noResultAccuracy = noResultAccuracy
        self.falsePositiveRate = falsePositiveRate
    }

    public static let zero = EvalMetrics(caseCount: 0, recallAt1: 0, recallAt3: 0,
                                         recallAt5: 0, mrr: 0, p50Ms: 0, p95Ms: 0)

    /// 新字段读取旧 baseline 时取「全是正例、没有负例」，避免升级后丢掉历史记录。
    private enum CodingKeys: String, CodingKey {
        case caseCount, relevantCaseCount, noResultCaseCount
        case recallAt1, recallAt3, recallAt5, mrr, p50Ms, p95Ms
        case noResultAccuracy, falsePositiveRate
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        caseCount = try values.decode(Int.self, forKey: .caseCount)
        relevantCaseCount = try values.decodeIfPresent(Int.self, forKey: .relevantCaseCount) ?? caseCount
        noResultCaseCount = try values.decodeIfPresent(Int.self, forKey: .noResultCaseCount) ?? 0
        recallAt1 = try values.decode(Double.self, forKey: .recallAt1)
        recallAt3 = try values.decode(Double.self, forKey: .recallAt3)
        recallAt5 = try values.decode(Double.self, forKey: .recallAt5)
        mrr = try values.decode(Double.self, forKey: .mrr)
        p50Ms = try values.decode(Double.self, forKey: .p50Ms)
        p95Ms = try values.decode(Double.self, forKey: .p95Ms)
        noResultAccuracy = try values.decodeIfPresent(Double.self, forKey: .noResultAccuracy) ?? 0
        falsePositiveRate = try values.decodeIfPresent(Double.self, forKey: .falsePositiveRate) ?? 0
    }
}

/// 一次评测跑批的结果。
public struct EvalRun: Sendable, Equatable {
    public let configVersion: String
    public let embeddingVersion: String
    public let startedAt: Date
    /// Golden + Regression 合并后的整体指标。
    public let metrics: EvalMetrics
    /// 仅支持边界内的**正例**。Release Gate 与 Compare 使用这组指标。
    public let inScopeMetrics: EvalMetrics
    /// 已知架构边界的跨语言正例，只作诊断报告。
    public let crossLanguageMetrics: EvalMetrics
    /// 仅 Golden Set 部分。
    public let goldenMetrics: EvalMetrics
    /// 仅 Regression Set 部分。`caseCount == 0` 表示集合为空。
    public let regressionMetrics: EvalMetrics
    /// Regression 中支持边界内的正例；负例与跨语言 case 暂不进入 Gate。
    public let inScopeRegressionMetrics: EvalMetrics
    public let failures: [EvalFailure]
    /// 逐用例结果。**统计显著性必须逐条配对才能算** —— 汇总数字里
    /// 「低 0.015」既可能是真的退化，也可能是一条用例翻了面。
    public let outcomes: [EvalCaseOutcome]

    public init(configVersion: String, embeddingVersion: String, startedAt: Date = Date(),
                metrics: EvalMetrics, goldenMetrics: EvalMetrics,
                regressionMetrics: EvalMetrics, failures: [EvalFailure],
                inScopeMetrics: EvalMetrics? = nil,
                crossLanguageMetrics: EvalMetrics = .zero,
                inScopeRegressionMetrics: EvalMetrics? = nil,
                outcomes: [EvalCaseOutcome] = []) {
        self.configVersion = configVersion
        self.embeddingVersion = embeddingVersion
        self.startedAt = startedAt
        self.metrics = metrics
        self.inScopeMetrics = inScopeMetrics ?? metrics
        self.crossLanguageMetrics = crossLanguageMetrics
        self.goldenMetrics = goldenMetrics
        self.regressionMetrics = regressionMetrics
        self.inScopeRegressionMetrics = inScopeRegressionMetrics ?? regressionMetrics
        self.failures = failures
        self.outcomes = outcomes
    }

    /// Regression 通过率 —— Release Gate 的第四项检查。
    ///
    /// **与 Recall@5 同口径**（全部 expected 落在 Top 5 即通过），
    /// 避免出现两套「通过」的定义。集合为空时视为 1.0：没有回归用例就没有回归。
    public var regressionPassRate: Double {
        inScopeRegressionMetrics.relevantCaseCount == 0 ? 1.0 : inScopeRegressionMetrics.recallAt5
    }

    /// 按 Failure Type 统计 —— 这是固定 7 类的全部意义。
    public func failureBreakdown() -> [(type: FailureType, count: Int)] {
        var counts: [FailureType: Int] = [:]
        for f in failures {
            guard let t = f.failureType else { continue }
            counts[t, default: 0] += 1
        }
        return counts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .map { (type: $0.key, count: $0.value) }
    }
}

/// 两次评测的逐项对比。
public struct MetricDelta: Sendable, Equatable, Identifiable {
    public enum Direction: Sendable { case better, worse, unchanged }
    /// 指标越大越好（Recall / MRR），还是越小越好（延迟）。
    public enum Polarity: Sendable { case higherIsBetter, lowerIsBetter }

    public let id: String
    public let label: String
    public let current: Double
    public let baseline: Double
    public let polarity: Polarity
    /// 格式化用的小数位；延迟类为 0。
    public let decimals: Int
    public let unit: String

    public init(label: String, current: Double, baseline: Double,
                polarity: Polarity, decimals: Int = 3, unit: String = "") {
        self.id = label
        self.label = label
        self.current = current
        self.baseline = baseline
        self.polarity = polarity
        self.decimals = decimals
        self.unit = unit
    }

    public var delta: Double { current - baseline }

    public var direction: Direction {
        if abs(delta) < 1e-9 { return .unchanged }
        switch polarity {
        case .higherIsBetter: return delta > 0 ? .better : .worse
        case .lowerIsBetter:  return delta < 0 ? .better : .worse
        }
    }

    public func formatted(_ v: Double) -> String {
        unit.isEmpty ? String(format: "%.\(decimals)f", v) : "\(Int(v.rounded())) \(unit)"
    }

    public var deltaText: String {
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        return sign + formatted(abs(delta))
    }
}

public enum EvalComparison {
    /// 质量与延迟**放在同一张表里**（`DECISION_LOG.md` D-UI-DEV-003）。
    /// 分开放会让人只看 Recall 就下结论。
    public static func compare(current: EvalMetrics, baseline: EvalMetrics) -> [MetricDelta] {
        [
            MetricDelta(label: "Recall@1", current: current.recallAt1, baseline: baseline.recallAt1, polarity: .higherIsBetter),
            MetricDelta(label: "Recall@3", current: current.recallAt3, baseline: baseline.recallAt3, polarity: .higherIsBetter),
            MetricDelta(label: "Recall@5", current: current.recallAt5, baseline: baseline.recallAt5, polarity: .higherIsBetter),
            MetricDelta(label: "MRR", current: current.mrr, baseline: baseline.mrr, polarity: .higherIsBetter),
            MetricDelta(label: "P50", current: current.p50Ms, baseline: baseline.p50Ms, polarity: .lowerIsBetter, decimals: 0, unit: "ms"),
            MetricDelta(label: "P95", current: current.p95Ms, baseline: baseline.p95Ms, polarity: .lowerIsBetter, decimals: 0, unit: "ms")
        ]
    }

    /// 一句话概括 trade-off。**不给 PASS / FAIL** —— 判定是 Release Gate 的事，
    /// Eval 只负责把权衡讲清楚（`DEVTOOLS.md` §4.6）。
    public static func tradeoffSummary(_ deltas: [MetricDelta]) -> String {
        let quality = deltas.filter { $0.polarity == .higherIsBetter }
        let latency = deltas.filter { $0.polarity == .lowerIsBetter }
        let qualityUp = quality.filter { $0.direction == .better }
        let qualityDown = quality.filter { $0.direction == .worse }
        let latencyUp = latency.filter { $0.direction == .worse }

        if qualityUp.isEmpty && qualityDown.isEmpty && latencyUp.isEmpty {
            return "与基线基本一致，没有可观察的差异。"
        }
        var parts: [String] = []
        if !qualityUp.isEmpty && qualityDown.isEmpty { parts.append("质量提升") }
        else if !qualityDown.isEmpty && qualityUp.isEmpty { parts.append("质量下降") }
        else if !qualityUp.isEmpty && !qualityDown.isEmpty { parts.append("质量有涨有跌") }
        parts.append(latencyUp.isEmpty ? "延迟未回退" : "延迟回退")

        let detail = deltas
            .filter { $0.direction != .unchanged }
            .map { "\($0.label) \($0.deltaText)" }
            .joined(separator: " · ")
        return parts.joined(separator: "，") + "。" + detail + "。是否上线由 Release Gate 判定。"
    }
}
