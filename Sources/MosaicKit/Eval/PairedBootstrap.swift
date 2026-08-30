import Foundation

/// # 逐用例的跑批结果
///
/// `EvalMetrics` 只有汇总数字，而**统计显著性必须逐条配对才能算**：
/// 「候选比基线低 0.015」这句话在 67 条用例上可能只是一条用例翻了面。
/// 要区分「真的退化」与「抖动」，就需要每一条用例在两次跑批里各自的命中情况。
public struct EvalCaseOutcome: Sendable, Equatable, Codable {
    public let caseID: String
    public let scope: EvalScope
    /// 是不是正例。负例不进 Recall / MRR 的分母，也不参与配对检验。
    public let isPositive: Bool
    public let hitAt1: Bool
    public let hitAt3: Bool
    public let hitAt5: Bool
    /// 第一个正确笔记的名次倒数；未命中为 0。
    public let reciprocalRank: Double
    public let latencyMs: Double

    public init(caseID: String, scope: EvalScope, isPositive: Bool,
                hitAt1: Bool, hitAt3: Bool, hitAt5: Bool,
                reciprocalRank: Double, latencyMs: Double) {
        self.caseID = caseID
        self.scope = scope
        self.isPositive = isPositive
        self.hitAt1 = hitAt1
        self.hitAt3 = hitAt3
        self.hitAt5 = hitAt5
        self.reciprocalRank = reciprocalRank
        self.latencyMs = latencyMs
    }

    public func value(for metric: PairedBootstrap.Metric) -> Double {
        switch metric {
        case .recallAt1: return hitAt1 ? 1 : 0
        case .recallAt3: return hitAt3 ? 1 : 0
        case .recallAt5: return hitAt5 ? 1 : 0
        case .mrr:       return reciprocalRank
        }
    }
}

/// # 配对 bootstrap
///
/// ## 它回答的问题
///
/// 「候选比基线低 0.015 —— 这是真的退化，还是几十条用例上的抖动？」
///
/// Release Gate 此前只比较两个点估计，零容差。在 67 条 in-scope 用例上
/// **一条用例翻面 = 0.0149**，于是任何一条边缘用例的排名波动都会阻断发布，
/// 而那不是质量信号。反过来，给点估计留一个固定容差（比如 0.010）同样是错的：
/// 容差该有多大取决于样本量与用例之间的方差，不是一个可以拍出来的常数。
///
/// ## 为什么是**配对**的
///
/// 两次跑批用的是**同一组用例**。逐条配对之后，用例本身的难度差异被消掉了，
/// 剩下的才是配置之间的差异。不配对的话，「这批用例本来就难」会被算进方差里，
/// 置信区间会宽到什么都判不出来。
///
/// ## 为什么是 bootstrap 而不是 t 检验
///
/// Recall 是 0/1 变量，MRR 的取值集合是 `{0, 1, 1/2, 1/3, …}` —— 都不接近正态，
/// 而样本量只有几十到两百。bootstrap 不假设分布形状，在这个规模上是更诚实的选择。
///
/// ## 确定性
///
/// 用固定种子的线性同余发生器，**不用系统随机源**。同一份数据每次跑出同一个区间 ——
/// 一个每次重跑都给不同答案的发布判定，没有人会相信它。
public enum PairedBootstrap {

    public enum Metric: String, Sendable, CaseIterable {
        case recallAt1, recallAt3, recallAt5, mrr

        public var label: String {
            switch self {
            case .recallAt1: return "Recall@1"
            case .recallAt3: return "Recall@3"
            case .recallAt5: return "Recall@5"
            case .mrr:       return "MRR"
            }
        }
    }

    public struct Interval: Sendable, Equatable {
        /// 点估计：`mean(current) − mean(baseline)`。
        public let delta: Double
        public let lower: Double
        public let upper: Double
        public let confidence: Double
        /// 参与配对的用例数。
        public let pairedCount: Int

        public init(delta: Double, lower: Double, upper: Double,
                    confidence: Double, pairedCount: Int) {
            self.delta = delta
            self.lower = lower
            self.upper = upper
            self.confidence = confidence
            self.pairedCount = pairedCount
        }

        /// **统计上有意义的退化**：整个区间都在 0 以下。
        ///
        /// 区间跨过 0 时，数据无法区分「退化」与「抖动」——
        /// 那时候阻断发布是在惩罚噪声。
        public var isMeaningfulRegression: Bool { upper < 0 }

        /// 统计上有意义的提升：整个区间都在 0 以上。
        public var isMeaningfulImprovement: Bool { lower > 0 }

        public var summary: String {
            String(format: "Δ %+.3f  [%+.3f, %+.3f]  n=%d",
                   delta, lower, upper, pairedCount)
        }
    }

    /// - Parameter iterations: 重采样次数。2000 次在几十到几百条用例上足够稳定，
    ///   而且在 checks 里跑得起（实测每个指标 < 10 ms）。
    /// - Returns: 配对不足 8 条时返回 `nil` —— 那个规模上任何区间都是自欺欺人。
    public static func deltaInterval(current: [EvalCaseOutcome],
                                     baseline: [EvalCaseOutcome],
                                     metric: Metric,
                                     scope: EvalScope? = .inScope,
                                     iterations: Int = 2_000,
                                     confidence: Double = 0.95,
                                     seed: UInt64 = 0x5EED_1234) -> Interval? {
        func indexed(_ outcomes: [EvalCaseOutcome]) -> [String: EvalCaseOutcome] {
            var out: [String: EvalCaseOutcome] = [:]
            for o in outcomes where o.isPositive && (scope == nil || o.scope == scope) {
                out[o.caseID] = o
            }
            return out
        }
        let cur = indexed(current), base = indexed(baseline)
        let ids = Set(cur.keys).intersection(base.keys).sorted()
        guard ids.count >= 8 else { return nil }

        let diffs = ids.map { cur[$0]!.value(for: metric) - base[$0]!.value(for: metric) }
        let point = diffs.reduce(0, +) / Double(diffs.count)

        var rng = SplitMix(seed: seed)
        var means: [Double] = []
        means.reserveCapacity(iterations)
        for _ in 0..<iterations {
            var sum = 0.0
            for _ in diffs.indices {
                sum += diffs[Int(rng.next(upperBound: UInt64(diffs.count)))]
            }
            means.append(sum / Double(diffs.count))
        }
        means.sort()
        let alpha = (1 - confidence) / 2
        let lowerIndex = Int((alpha * Double(iterations)).rounded(.down))
        let upperIndex = min(iterations - 1, Int(((1 - alpha) * Double(iterations)).rounded(.up)))
        return Interval(delta: point,
                        lower: means[max(0, lowerIndex)],
                        upper: means[upperIndex],
                        confidence: confidence,
                        pairedCount: ids.count)
    }

    /// 固定种子的伪随机源。**不用 `SystemRandomNumberGenerator`** ——
    /// 判定必须可复现，否则同一份数据两次跑批可以给出不同的上线结论。
    struct SplitMix: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func next(upperBound: UInt64) -> UInt64 {
            precondition(upperBound > 0)
            return next() % upperBound
        }
    }
}
