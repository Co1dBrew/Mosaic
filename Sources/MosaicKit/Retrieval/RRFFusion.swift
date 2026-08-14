import Foundation

/// 融合方式。Goal 1 默认 RRF。
public enum FusionMethod: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// Reciprocal Rank Fusion。`k` 越大，靠前名次之间的差距越平缓。
    case rrf(k: Int)
    /// 加权分数相加。需要两路分数可比 —— 目前**并不可比**（一个是 TF 分，一个是余弦），
    /// 保留只为在 Lab 里作为对照，不作为默认。
    case weighted(keyword: Double, vector: Double)

    public static let `default` = FusionMethod.rrf(k: 60)

    public var description: String {
        switch self {
        case let .rrf(k): return "rrf(k=\(k))"
        case let .weighted(kw, v): return "weighted(\(kw)/\(v))"
        }
    }
}

/// 融合后的一条排名证据。
public struct FusedRanking: Sendable, Equatable {
    public let chunkID: String
    /// 该 chunk 在 keyword 路的名次（1-based）；`nil` = 这一路没命中。
    public let keywordRank: Int?
    /// 在 vector 路的名次（1-based）；`nil` = 这一路没命中。
    public let vectorRank: Int?
    public let fusedScore: Double

    public init(chunkID: String, keywordRank: Int?, vectorRank: Int?, fusedScore: Double) {
        self.chunkID = chunkID
        self.keywordRank = keywordRank
        self.vectorRank = vectorRank
        self.fusedScore = fusedScore
    }

    /// 只有一路命中 —— Lab 的 unique hit 分组就看这个。
    public var isUniqueHit: Bool { (keywordRank == nil) != (vectorRank == nil) }
}

/// # RRF —— Reciprocal Rank Fusion
///
/// ```
/// score(d) = Σ_路  1 / (k + rank_路(d))
/// ```
///
/// 选它而不是加权分数相加，理由只有一个但足够硬：
///
/// > **两路的分数不可比。** keyword 是 TF 归一分，vector 是余弦相似度，量纲和分布
/// > 都不一样。把它们加权相加，权重就是在拿两把不同刻度的尺子拼长度 —— 调出来的
/// > 值只对当前这批数据成立，换一批就失效。
///
/// RRF 只用**名次**，绕开了整个可比性问题。代价是丢掉分数里的强度信息
/// （第 1 名比第 2 名强多少），但换来的是稳定和可解释。
///
/// `k = 60` 是文献常用默认值，作用是压平头部差距：k 越小，第 1 名的权重越压倒性。
/// **它是 tuning value，Week 4 会用 Golden Set 实测，不是产品结论。**
///
/// 单路缺失的处理：该路不贡献任何分数（而不是给一个惩罚值）。所以一条只被 vector
/// 命中的结果仍然能进最终榜 —— 这正是 24 屏纯语义结果能出现的原因。
public enum RRFFusion {

    public static func fuse(keywordOrder: [String],
                            vectorOrder: [String],
                            method: FusionMethod = .default) -> [FusedRanking] {

        var keywordRank: [String: Int] = [:]
        for (i, id) in keywordOrder.enumerated() { keywordRank[id] = i + 1 }
        var vectorRank: [String: Int] = [:]
        for (i, id) in vectorOrder.enumerated() { vectorRank[id] = i + 1 }

        // 保持稳定的遍历顺序：先 keyword 的次序，再补 vector 独有的。
        var ordered: [String] = []
        var seen = Set<String>()
        for id in keywordOrder where !seen.contains(id) { ordered.append(id); seen.insert(id) }
        for id in vectorOrder where !seen.contains(id) { ordered.append(id); seen.insert(id) }

        var out: [FusedRanking] = []
        for id in ordered {
            let kr = keywordRank[id]
            let vr = vectorRank[id]
            let score: Double
            switch method {
            case let .rrf(k):
                let kk = Double(max(1, k))
                var s = 0.0
                if let kr { s += 1.0 / (kk + Double(kr)) }
                if let vr { s += 1.0 / (kk + Double(vr)) }
                score = s
            case let .weighted(kw, vw):
                // 名次的倒数当作可比的替身。仍然不推荐用，只为在 Lab 里做对照。
                var s = 0.0
                if let kr { s += kw / Double(kr) }
                if let vr { s += vw / Double(vr) }
                score = s
            }
            out.append(FusedRanking(chunkID: id, keywordRank: kr, vectorRank: vr, fusedScore: score))
        }

        // 同分按 chunkID 升序 —— 评测必须可复现。
        out.sort { $0.fusedScore == $1.fusedScore ? $0.chunkID < $1.chunkID : $0.fusedScore > $1.fusedScore }
        return out
    }
}
