import Foundation

/// # 上线阈值（backlog 5.2）
///
/// 四项，与 `DEVTOOLS.md` §4.7 的四行检查**一一对应**。
///
/// > **这些是初值，不是 PRD 定值。** `DEVTOOLS.md` §6.3 明确写了「具体阈值属
/// > tuning value，最终由 PRD / benchmark 决定，此处给出的是取值理由」。
/// > 阈值可配的意义就在这里 —— 拿到 PRD 的确切数字后改这一个结构体，
/// > 不用动判定逻辑。
public struct GateThresholds: Sendable, Equatable, Codable {

    /// Recall@5 相对 baseline 允许的最小 delta。**默认 0：不允许质量下降。**
    /// 给 Recall 留负容差等于允许「质量掉一点点但换来别的好处」，
    /// 而 Gate 的四项检查里没有任何一项能表达那个「好处」—— 那是 D6 Compare 的事。
    public var recallAt5MinDelta: Double
    /// MRR 相对 baseline 的容差。MRR 对**单条**用例的名次变化非常敏感
    /// （第 1 名掉到第 2 名，这一条就从 1.0 掉到 0.5），在几十条的集合上
    /// 抖动天然大于 Recall@5。容差是给这种抖动留的，不是给质量下降留的。
    public var mrrTolerance: Double
    /// P95 预算（毫秒）。与 PRD 的检索 SLO 同口径：**只算检索本身，不含 UI**。
    public var p95BudgetMs: Double
    /// Regression 通过率下限。为什么不是 100%：`DEVTOOLS.md` §6.3 ——
    /// 一个总是被跳过的 Gate 等于没有 Gate。
    public var regressionPassRateMin: Double

    public init(recallAt5MinDelta: Double = 0,
                mrrTolerance: Double = 0.010,
                p95BudgetMs: Double = 250,
                regressionPassRateMin: Double = 0.98) {
        self.recallAt5MinDelta = recallAt5MinDelta
        self.mrrTolerance = mrrTolerance
        self.p95BudgetMs = p95BudgetMs
        self.regressionPassRateMin = regressionPassRateMin
    }

    public static let `default` = GateThresholds()
}

/// 一行检查。**条件与实测值分开存**，因为 D7/D8 要在同一行里把两者都摆出来 ——
/// 只给「❌」而不给「310 ms > 250 ms」的 Gate 无法在 2 秒内回答「为什么不能上」。
public struct GateCheck: Sendable, Equatable, Identifiable {

    public enum Kind: String, Sendable, Equatable, Codable, CaseIterable {
        case recallAt5
        case mrr
        case p95
        case regression

        public var label: String {
            switch self {
            case .recallAt5:  return "Recall@5"
            case .mrr:        return "MRR"
            case .p95:        return "P95"
            case .regression: return "Regression"
            }
        }
    }

    public let kind: Kind
    public let passed: Bool
    /// 例：`≥ 0.825`（baseline）· `≤ 250 ms`（预算）· `≥ 98%`（阈值）
    public let conditionText: String
    /// 例：`0.875` · `310 ms` · `97.5% · 39/40`
    public let actualText: String
    /// 判定无法成立时的原因（没有 baseline / 两次跑批用例数不同）。
    /// 与「质量下降」是两回事，混为一谈会让人去调配置，而真正该做的是重跑 baseline。
    public let detail: String?

    public var id: String { kind.rawValue }

    public init(kind: Kind, passed: Bool, conditionText: String,
                actualText: String, detail: String? = nil) {
        self.kind = kind
        self.passed = passed
        self.conditionText = conditionText
        self.actualText = actualText
        self.detail = detail
    }

    /// 这一行是否该给 `Open Failures ›`（`DEVTOOLS.md` §4.7：从「不能上线」到
    /// 「为什么」只需一次点击）。只有质量类检查有失败用例可看 ——
    /// P95 超预算不对应任何一条 case。
    public var opensFailures: Bool {
        !passed && (kind == .regression || kind == .recallAt5 || kind == .mrr)
    }
}

/// 一次上线判定。
public struct GateDecision: Sendable, Equatable {

    /// `DEVTOOLS.md` §4.7 的三态。**没有第四态** ——
    /// 「没跑过评测」与「评测结果早于当前配置」的补救动作完全一样（去跑评测），
    /// 多一个状态只会多一处文案分叉。
    public enum Status: String, Sendable, Equatable {
        case pass
        case blocked
        case stale
    }

    public let status: Status
    /// 这次判定针对哪一套配置。`promote` 会核对它 ——
    /// 「改完参数没重跑评测就上线」时判定还是绿的，但它判的是上一套配置。
    public let configVersion: String
    public let evaluatedAt: Date
    public let checks: [GateCheck]
    /// stale 时的一句说明。
    public let staleReason: String?

    public init(status: Status, configVersion: String, evaluatedAt: Date,
                checks: [GateCheck], staleReason: String? = nil) {
        self.status = status
        self.configVersion = configVersion
        self.evaluatedAt = evaluatedAt
        self.checks = checks
        self.staleReason = staleReason
    }

    public var isPass: Bool { status == .pass }

    public var blockingChecks: [GateCheck] { checks.filter { !$0.passed } }

    public var blockingReasons: [String] {
        if let staleReason { return [staleReason] }
        return blockingChecks.map { "\($0.kind.label) \($0.actualText)（要求 \($0.conditionText)）" }
    }

    /// 判定区那一行 34pt 加粗的字。
    public var headline: String {
        switch status {
        case .pass:    return "PASS"
        case .blocked: return "PROMOTION BLOCKED"
        case .stale:   return "STALE"
        }
    }
}

/// # Release Gate（backlog 5.2）
///
/// ## 判定规则：任一项 FAIL 即阻断。不做加权，不做总分。
///
/// 加权总分会制造「大部分指标都很好」的错觉，而 Release Gate 存在的**唯一意义**
/// 就是拦住这种错觉（`DECISION_LOG.md` D-UI-DEV-008）。所以判定就是 `allSatisfy`，
/// 这一行代码是整个模块的产品主张。
///
/// ## Gate 与 Eval 的分工
///
/// Eval 只讲 trade-off，**不下 PASS / FAIL**；判定只在这里发生。
/// 两个地方都能说 PASS 的系统，最后总有一个地方说了算，而那个地方不会是文档写的那个。
public enum ReleaseGate {

    /// 浮点比较的容差。`0.875 >= 0.875` 在二进制下可能因为一次除法差 1 ulp，
    /// 那会表现成「Recall 与 baseline 完全相同却被判失败」。
    private static let epsilon = 1e-9

    public static func evaluate(configVersion: String,
                                current: EvalRun?,
                                baseline: EvalRun?,
                                thresholds: GateThresholds = .default,
                                now: Date = Date()) -> GateDecision {

        guard let current else {
            return GateDecision(status: .stale, configVersion: configVersion, evaluatedAt: now,
                                checks: [], staleReason: "还没有评测结果 —— 先在 Eval Center 跑一次。")
        }
        guard current.configVersion == configVersion else {
            return GateDecision(status: .stale, configVersion: configVersion, evaluatedAt: now,
                                checks: [],
                                staleReason: "评测跑的是 \(current.configVersion)，当前配置是 \(configVersion) —— 重跑评测。")
        }

        // baseline 缺席 / 用例集不同 → 质量类检查**无法成立**。
        // 这不是「质量下降」，补救动作也不同（去跑 baseline，而不是去调配置），
        // 所以 detail 要把这一点说清楚，否则会有人在这里开始调 topK。
        let comparability: String?
        if baseline == nil {
            comparability = "还没有 baseline 跑批 —— 在 Eval Compare 里跑一次 baseline。"
        } else if let baseline, baseline.metrics.caseCount != current.metrics.caseCount {
            comparability = "两次跑批的用例数不同（current \(current.metrics.caseCount) / baseline \(baseline.metrics.caseCount)）—— delta 无意义，重跑 baseline。"
        } else {
            comparability = nil
        }

        var checks: [GateCheck] = []

        // ── 1 · Recall@5 ≥ baseline − tolerance ──
        if let baseline, comparability == nil {
            let floor = baseline.metrics.recallAt5 + thresholds.recallAt5MinDelta
            checks.append(GateCheck(
                kind: .recallAt5,
                passed: current.metrics.recallAt5 >= floor - epsilon,
                conditionText: "≥ \(fixed(floor))",
                actualText: fixed(current.metrics.recallAt5)))
        } else {
            checks.append(GateCheck(kind: .recallAt5, passed: false,
                                    conditionText: "≥ baseline",
                                    actualText: fixed(current.metrics.recallAt5),
                                    detail: comparability))
        }

        // ── 2 · MRR ≥ baseline − tolerance ──
        if let baseline, comparability == nil {
            let floor = baseline.metrics.mrr - thresholds.mrrTolerance
            checks.append(GateCheck(
                kind: .mrr,
                passed: current.metrics.mrr >= floor - epsilon,
                conditionText: "≥ \(fixed(floor))（baseline \(fixed(baseline.metrics.mrr)) − 容差 \(fixed(thresholds.mrrTolerance)))",
                actualText: fixed(current.metrics.mrr)))
        } else {
            checks.append(GateCheck(kind: .mrr, passed: false,
                                    conditionText: "≥ baseline − \(fixed(thresholds.mrrTolerance))",
                                    actualText: fixed(current.metrics.mrr),
                                    detail: comparability))
        }

        // ── 3 · P95 ≤ 预算 ──（不需要 baseline：预算是绝对值，不是相对值）
        checks.append(GateCheck(
            kind: .p95,
            passed: current.metrics.p95Ms <= thresholds.p95BudgetMs + epsilon,
            conditionText: "≤ \(ms(thresholds.p95BudgetMs))",
            actualText: ms(current.metrics.p95Ms)))

        // ── 4 · Regression Pass Rate ≥ 阈值 ──
        let rate = current.regressionPassRate
        let n = current.regressionMetrics.caseCount
        checks.append(GateCheck(
            kind: .regression,
            passed: rate >= thresholds.regressionPassRateMin - epsilon,
            conditionText: "≥ \(percent(thresholds.regressionPassRateMin))",
            actualText: n == 0
                ? "\(percent(rate)) · 回归集为空"
                : "\(percent(rate)) · \(current.regressionPassedCount)/\(n)",
            detail: n == 0 ? "回归集还没有用例 —— 没有回归用例就没有回归，这一项恒过。" : nil))

        // **判定 = allSatisfy。** 这一行就是 D-UI-DEV-008。
        return GateDecision(status: checks.allSatisfy(\.passed) ? .pass : .blocked,
                            configVersion: configVersion,
                            evaluatedAt: now,
                            checks: checks)
    }

    // MARK: 格式化（判定文案要能直接摆进 D7/D8 那四行）

    private static func fixed(_ v: Double) -> String { String(format: "%.3f", v) }
    private static func ms(_ v: Double) -> String { "\(Int(v.rounded())) ms" }
    private static func percent(_ v: Double) -> String {
        let p = v * 100
        return p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
    }
}

public extension EvalRun {
    /// 回归集里通过的条数。Pass Rate 与 Recall@5 同口径，所以这里由 Recall@5 反推 ——
    /// 单独再存一份计数会立刻产生「两个数对不上」的可能。
    var regressionPassedCount: Int {
        Int((regressionMetrics.recallAt5 * Double(regressionMetrics.caseCount)).rounded())
    }
}
