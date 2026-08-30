import Foundation

// ┌──────────────────────────────────────────────────────────────────────────┐
// │  状态：EXPERIMENTAL · NOT WIRED TO PRODUCTION                             │
// │                                                                          │
// │  `DECISION_CONFIG: ABSTENTION = EXPERIMENT_ONLY_NOT_PRODUCTION`          │
// │                                                                          │
// │  这个文件里的一切**只在评测与开发者工具里被调用**。生产检索路径              │
// │  （`RetrievalService` / `SearchViewModel` / `NoteDetailView`）一处都没有   │
// │  引用它 —— 有一条断言守着这件事（`AbstentionChecks`）。                     │
// │                                                                          │
// │  为什么没上：TD-10 未解决。v3 上四个信号全部重叠，最好的一组（云端 margin） │
// │  能在零正例损失下挡掉 6/20 负例，但**余量只有 0.0002** —— 语料稍有变化就会  │
// │  开始误杀真答案。一个会偶尔吞掉正确结果的弃答策略，比不弃答更糟。            │
// │                                                                          │
// │  因此默认值是 `neverAbstains`，产品行为与接入前**逐位一致**。               │
// │  README / PRD / 产品界面**都不得**把它描述为已交付功能。                    │
// └──────────────────────────────────────────────────────────────────────────┘

/// # 语义弃答的三态（TD-10）
///
/// **不是二元判决。** 二元会逼着一个阈值同时承担「够确定吗」和「要不要显示」两件事，
/// 而这两件事的代价完全不对称：漏掉一条真答案比多显示几条无关结果伤得多。
/// 三态给「不确定」一个去处。
///
/// - `confident`：正常显示结果。
/// - `uncertain`：**照常显示**，但在列表顶部加一行说明。契约 §2.6 已经有这行文案
///   （「没有完全匹配的关键词，以下是相关内容」），复用它，不新造。
/// - `abstain`：走 `.noResults` 的三套分叉文案（契约 §4.5）。在此之前这三套文案
///   一条都跑不到 —— 语义可用时向量路必定返回 topK。
public enum RetrievalConfidence: String, Sendable, Equatable, Codable, CaseIterable {
    case confident
    case uncertain
    case abstain

    /// 结果区是否展示结果。**`uncertain` 展示** —— 它只改变说明文案，不改变可见性。
    public var showsResults: Bool { self != .abstain }
}

/// 判决用的四个信号，全部可从一次 `RetrievalOutcome` 直接算出，不需要新模型。
public struct AbstentionSignals: Sendable, Equatable {

    /// 最高的向量相似度。**绝对值信号，最不可靠的那个**（TD-11：它被文本长度污染）。
    public let top1Similarity: Float?
    /// `top1 − top2`。**主力信号**：比值 / 差值把整体偏移抵消掉了，
    /// 所以它不像绝对值那样受长度支配。真有答案时 top1 明显突出；无答案时 topK 一片扁平。
    public let margin: Float?
    /// `top1 / mean(top2…topK)`。margin 的尺度无关版本。
    public let top1ToMeanRatio: Float?
    /// 有没有任何字面命中。零成本信号 —— keyword 路本来就跑了。
    public let hasKeywordHit: Bool
    /// 候选条数。为 0 时没有任何可判的东西。
    public let candidateCount: Int

    public init(top1Similarity: Float?, margin: Float?, top1ToMeanRatio: Float?,
                hasKeywordHit: Bool, candidateCount: Int) {
        self.top1Similarity = top1Similarity
        self.margin = margin
        self.top1ToMeanRatio = top1ToMeanRatio
        self.hasKeywordHit = hasKeywordHit
        self.candidateCount = candidateCount
    }

    /// 从一次检索产出里提取。
    ///
    /// 只看**向量路有相似度的那些结果**：keyword 独有命中没有相似度，
    /// 把它们当成 0 会凭空压低 margin。
    public static func from(_ outcome: RetrievalOutcome) -> AbstentionSignals {
        let sims = outcome.results.compactMap(\.similarity).sorted(by: >)
        let hasKeyword = outcome.results.contains { !$0.matchedRanges.isEmpty }
        guard let top1 = sims.first else {
            return AbstentionSignals(top1Similarity: nil, margin: nil, top1ToMeanRatio: nil,
                                     hasKeywordHit: hasKeyword,
                                     candidateCount: outcome.results.count)
        }
        let rest = Array(sims.dropFirst())
        let margin = rest.first.map { top1 - $0 }
        let ratio: Float? = rest.isEmpty ? nil : {
            let mean = rest.reduce(0, +) / Float(rest.count)
            return mean > 0 ? top1 / mean : nil
        }()
        return AbstentionSignals(top1Similarity: top1, margin: margin, top1ToMeanRatio: ratio,
                                 hasKeywordHit: hasKeyword, candidateCount: outcome.results.count)
    }
}

/// # 弃答策略（可版本化、可评测、可进 Gate）
///
/// 和 `RetrievalConfig` / `PerformanceGatePolicy` 同一条纪律：**阈值是数据，不是常量**。
/// 改阈值要出新版本并记录理由，不能就地改一个字面量。
///
/// > ⚠️ **默认值刻意是「永不弃答」**（`similarityFloor = 0`、`minMargin = 0`）。
/// > 原因是 TD-10 的现状：本项目实测在 `bge-m3` 上正例 top1 最低 0.541、
/// > 负例最高 0.588 —— **重叠**，最优单阈值余量只有 0.001，不可发布。
/// > 一个默认就开始弃答的策略等于在没有校准的情况下开始丢用户的答案。
public struct AbstentionPolicy: Sendable, Equatable, Codable {

    public var version: String
    /// 绝对下限。低于它直接弃答。**只用来挡明显离谱的**，不指望它做主力。
    public var similarityFloor: Float
    /// `top1 − top2` 的下限。主力信号。
    public var minMargin: Float
    /// `top1 / mean(rest)` 的下限。0 = 不启用。
    public var minTop1ToMeanRatio: Float
    /// 没有任何字面命中时，`top1Similarity` 要达到的更高门槛。
    /// 语义独有命中本身是正常的（契约 §2.6），所以这里只是**更严**，不是禁止。
    public var floorWithoutLexicalSupport: Float
    /// 落在 `confident` 与 `abstain` 之间时给 `uncertain`。
    /// 该区间的宽度 = 主力信号阈值的这个倍数。
    public var uncertainBandMultiplier: Float

    public init(version: String = "abstain-v1",
                similarityFloor: Float = 0,
                minMargin: Float = 0,
                minTop1ToMeanRatio: Float = 0,
                floorWithoutLexicalSupport: Float = 0,
                uncertainBandMultiplier: Float = 1.5) {
        self.version = version
        self.similarityFloor = similarityFloor
        self.minMargin = minMargin
        self.minTop1ToMeanRatio = minTop1ToMeanRatio
        self.floorWithoutLexicalSupport = floorWithoutLexicalSupport
        self.uncertainBandMultiplier = uncertainBandMultiplier
    }

    /// 生产默认：**从不弃答**，与 TD-10 接入前的行为完全一致。
    /// 校准出可发布的阈值之前，产品行为不变。
    public static let neverAbstains = AbstentionPolicy()

    public var isEnabled: Bool {
        similarityFloor > 0 || minMargin > 0 || minTop1ToMeanRatio > 0
            || floorWithoutLexicalSupport > 0
    }
}

public enum AbstentionJudge {

    /// 判决。
    ///
    /// 顺序是刻意的：**先看有没有东西可判**，再看绝对下限（便宜且能挡住离谱的），
    /// 最后看主力信号。任何一条触发 `abstain` 就直接返回 —— 与 Release Gate 的
    /// `allSatisfy` 同一个理由：不做加权，不让「大部分信号还行」换来放行。
    public static func judge(_ signals: AbstentionSignals,
                             policy: AbstentionPolicy) -> RetrievalConfidence {
        // 策略未启用 → 行为与接入前完全一致。
        guard policy.isEnabled else { return .confident }
        // 一条候选都没有：这不是「不确定」，是真的没有。
        guard signals.candidateCount > 0 else { return .abstain }
        // 纯词法命中（没有任何相似度）不由语义信号判决 —— 字面命中本身就是证据。
        guard let top1 = signals.top1Similarity else {
            return signals.hasKeywordHit ? .confident : .abstain
        }

        let floor = signals.hasKeywordHit
            ? policy.similarityFloor
            : max(policy.similarityFloor, policy.floorWithoutLexicalSupport)
        if top1 < floor { return .abstain }

        var uncertain = top1 < floor * policy.uncertainBandMultiplier && floor > 0

        if policy.minMargin > 0 {
            let margin = signals.margin ?? .greatestFiniteMagnitude   // 只有一条候选时不惩罚
            if margin < policy.minMargin { return .abstain }
            if margin < policy.minMargin * policy.uncertainBandMultiplier { uncertain = true }
        }
        if policy.minTop1ToMeanRatio > 0 {
            let ratio = signals.top1ToMeanRatio ?? .greatestFiniteMagnitude
            if ratio < policy.minTop1ToMeanRatio { return .abstain }
        }
        return uncertain ? .uncertain : .confident
    }
}
