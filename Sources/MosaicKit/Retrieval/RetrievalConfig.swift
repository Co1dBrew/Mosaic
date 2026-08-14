import Foundation

public enum RetrievalMode: String, Sendable, Equatable, Codable, CaseIterable {
    case keyword
    case vector
    case hybrid
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

    public init(version: String = "retrieval-v1",
                mode: RetrievalMode = .hybrid,
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

    /// 生产默认：隐式 Hybrid + RRF。用户侧没有任何 mode 开关
    /// （`SEARCH_CONTRACT` §1.1）。
    public static let production = RetrievalConfig()

    /// 单路检索时，候选池要比 topK 大一些，融合才有东西可挑。
    /// 只取 topK 的话，两路各自的第 20 名就永远进不了最终榜。
    public var candidateK: Int { max(topK * 3, topK + 10) }
}
