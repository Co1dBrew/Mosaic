import Foundation

public enum RetrievalMode: String, Sendable, Equatable, Codable, CaseIterable {
    case keyword
    case vector
    case hybrid

    /// 这套 mode 会不会走词法路。
    public var usesKeyword: Bool { self != .vector }
    /// 这套 mode 会不会走向量路。**生产判定读的就是它** —— 生产配置是
    /// `.keyword` 时，语义那一整条（索引 · 查询 · 状态栏）都不该发生。
    public var usesVector: Bool { self != .keyword }
}

/// # 一套检索配置
///
/// 六个可调项，与 `design/DEVTOOLS.md` §4.2 的六个 Picker **一一对应**。不多不少 ——
/// 每多一个可调项，评测矩阵就乘一次，而 Goal 1 要的是「能量化比较」，不是「什么都能调」。
///
/// `version` 是这套配置的身份：`EmbeddingRecord` 里存的是 `embeddingVersion`
/// （只关乎向量空间），而 Release Gate 比较的是整个 `RetrievalConfig.version`
/// （还包括 chunk 策略、topK、融合方式）。两者粒度不同，不能混用。
public struct RetrievalConfig: Sendable, Equatable, Codable {
    public var version: String
    public var mode: RetrievalMode
    public var embeddingProvider: String
    public var embeddingVersion: String
    public var chunkStrategy: ChunkStrategy
    public var topK: Int
    public var fusion: FusionMethod

    /// `mode` **没有默认值**，这是刻意的。
    ///
    /// 它原来默认 `.hybrid`，于是 `RetrievalConfig.production` 只写了 `RetrievalConfig()`
    /// —— 文档写着「生产走 keyword」，而编译期常量给的是 hybrid。这种不一致不会
    /// 在任何测试里显形（两条路都能跑通），只会在真机上多花一次嵌入的钱。
    /// 去掉默认值之后，「这套配置走哪条路」必须在每个构造点写出来。
    public init(version: String = "retrieval-v1",
                mode: RetrievalMode,
                embeddingProvider: String = "local",
                embeddingVersion: String = "mock-v1",
                chunkStrategy: ChunkStrategy = .default,
                topK: Int = 20,
                fusion: FusionMethod = .default) {
        self.version = version
        self.mode = mode
        self.embeddingProvider = embeddingProvider
        self.embeddingVersion = embeddingVersion
        self.chunkStrategy = chunkStrategy
        self.topK = topK
        self.fusion = fusion
    }

    // MARK: 两套具名配置

    /// # 生产配置：**纯词法（keyword）**
    ///
    /// `PRODUCTION_RETRIEVAL = KEYWORD` 是产品决策，依据是实测：
    /// 本机语义路对 R@1 的贡献是精确的 **+0.000**（95% CI `[0, 0]`，n=113），
    /// 却把 P50 从 13.6 ms 推到 50.2 ms。**用户为一个 0 收益的功能付 3.7× 延迟。**
    ///
    /// 这个常量与 `ScenarioBaselineEvaluation` 里的 baseline 臂、
    /// `MosaicBench` 的 keyword 臂、以及 `README` / `PROJECT_STATUS` 里的说法
    /// 是同一件事。改它就要一起改那几处 —— `ProductionConfigChecks` 会盯着。
    public static let production = RetrievalConfig(version: "retrieval-v2-keyword",
                                                  mode: .keyword)

    /// # 实验臂：本机 hybrid（keyword + 本机句向量 + 加权融合）
    ///
    /// **不是生产默认**，只在 Developer Tools 的对比与 `MosaicBench` 里出现。
    /// 它保留的理由是「以后云端臂或更好的本机模型到位时，比较的对照组要还在」，
    /// 不是「它随时可以上线」。要上线得走 Release Gate 的 Promote。
    public static let localHybridExperimental = RetrievalConfig(version: "local-hybrid-experimental",
                                                               mode: .hybrid)

    /// 单路检索时，候选池要比 topK 大一些，融合才有东西可挑。
    /// 只取 topK 的话，两路各自的第 20 名就永远进不了最终榜。
    public var candidateK: Int { max(topK * 3, topK + 10) }
}
