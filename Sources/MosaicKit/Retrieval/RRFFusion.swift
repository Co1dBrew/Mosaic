import Foundation

/// 融合方式。Goal 1 默认 RRF。
public enum FusionMethod: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// Reciprocal Rank Fusion。`k` 越大，靠前名次之间的差距越平缓。
    case rrf(k: Int)
    /// 加权**名次倒数**相加：`Σ 权重 / rank`。
    ///
    /// ⚠️ 这里原本写的是「需要两路分数可比 —— 目前并不可比」，**那句话描述的不是
    /// 本实现**：下面用的是 `kw / Double(kr)`，即名次倒数，和 RRF 一样绕开了
    /// 分数可比性问题，区别只在有权重、没有 `k` 平滑。弃用理由因此不成立，已更正。
    ///
    /// 实测（§25）：本地臂上它明显优于 RRF（in-scope R@1 0.358 vs 0.269）——
    /// 因为 RRF 等权会让**弱的向量臂稀释强的 keyword 臂**。
    /// **但默认值仍是 RRF**：改它是产品决策，证据只有一个 synthetic 数据集（P1 #18）。
    case weighted(keyword: Double, vector: Double)

    /// # 默认：加权名次融合，keyword 0.7 / vector 0.3
    ///
    /// **2026-08-21 从 `rrf(k: 60)` 换过来。** 换的理由是等权 RRF 被实测证明
    /// **主动有害**，不是「加权更好听」：
    ///
    /// | 数据集 | in-scope R@1：RRF | 加权 w=0.7 | keyword 单独 |
    /// |---|---:|---:|---:|
    /// | v3（150 篇 / 67 in-scope） | 0.269 | 0.358 | 0.343 |
    /// | v4（210 篇 / 101 in-scope） | 0.287 | **0.386** | 0.386 |
    ///
    /// **RRF 把 keyword 已经排对的第一名弄丢了** —— v3 上 5 条、v4 上 10 条。
    /// 机制：RRF 等权，而本地向量臂 in-scope R@1 只有 0.069–0.104，
    /// 等权让**弱臂稀释强臂**。这与「中英双索引反而更差」是同一个失效模式。
    ///
    /// ## 为什么是 0.7 而不是各自最优
    ///
    /// 两个 provider 的最优点不同（v4 上 cloud 最优在 w=0.5 拿 0.802，
    /// local 最优在 w≥0.6 拿 0.386+），但 **w ∈ [0.6, 0.9] 是共同平台**：
    /// 选 w=0.7 云端只付 **−0.010**，本地拿 **+0.099** —— 交换比约 **10:1**。
    /// 平台宽 4 个采样点，所以这不是挑了个好看的点。
    ///
    /// ## 这个默认值管什么、不管什么
    ///
    /// 它只影响**新建**的 `RetrievalConfig`。已经 promote 进生产的配置自带
    /// 各自的 `fusion` 值，**不会被这次改动改掉** —— 生产配置只能经
    /// `promote(id:decision:)` 更换，这条纪律不因为默认值变了而松动。
    ///
    /// ## 仍然成立的限制
    ///
    /// 证据全部来自 **synthetic** 评测集。它支持的结论是「等权 RRF 是错的」，
    /// **不是**「hybrid 比 keyword 单独更好」—— v4 上两者 R@1 恰好都是 0.386。
    /// 要回答后者需要真实标注（P0 #1/#3）。
    ///
    /// 回退就是把这一行改回 `.rrf(k: 60)`。
    public static let `default` = FusionMethod.weighted(keyword: 0.7, vector: 0.3)

    /// 换掉之前的默认值。保留具名常量，便于对照实验与一行回退。
    public static let rrfDefault = FusionMethod.rrf(k: 60)

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
