import Foundation

/// 一条最终结果，带**三路排名证据**。
///
/// `keywordRank` / `vectorRank` / `fusedRank` 三个字段同时保留，是
/// `DECISION_LOG.md` D-UI-DEV-007 对检索层提的硬要求：Retrieval Lab 的
/// `K #3 · V #7 → #2` 一行就靠它，Compare Modes 的 unique hit 分组也靠它。
/// 只返回最终顺序的话，这两个功能都做不了。
public struct RetrievalResult: Sendable, Equatable {
    public let chunkID: String
    public let ref: BlockRef
    public let source: RetrievalSource
    public let text: String

    public let fusedRank: Int
    public let keywordRank: Int?
    public let vectorRank: Int?
    public let similarity: Float?
    public let keywordScore: Double?
    /// 命中区间（chunk 文本内的字符偏移）。vector 独有命中时为空 —— 这正是
    /// 24 屏「整页零高亮」的来源。
    public let matchedRanges: [TextRange]

    public init(chunkID: String, ref: BlockRef, source: RetrievalSource, text: String,
                fusedRank: Int, keywordRank: Int?, vectorRank: Int?,
                similarity: Float?, keywordScore: Double?, matchedRanges: [TextRange]) {
        self.chunkID = chunkID
        self.ref = ref
        self.source = source
        self.text = text
        self.fusedRank = fusedRank
        self.keywordRank = keywordRank
        self.vectorRank = vectorRank
        self.similarity = similarity
        self.keywordScore = keywordScore
        self.matchedRanges = matchedRanges
    }

    /// Lab 里那一行证据：`K #3 · V #7 → #2`
    public var rankEvidence: String {
        let k = keywordRank.map { "K #\($0)" } ?? "K —"
        let v = vectorRank.map { "V #\($0)" } ?? "V —"
        return "\(k) · \(v) → #\(fusedRank)"
    }

    public var isKeywordOnly: Bool { keywordRank != nil && vectorRank == nil }
    public var isVectorOnly: Bool { vectorRank != nil && keywordRank == nil }
}

/// 一次检索的完整产出。
public struct RetrievalOutcome: Sendable, Equatable {
    public let results: [RetrievalResult]
    public let trace: RetrievalTrace
    /// Compare Modes 用：只被 keyword 命中的。
    public let keywordOnly: [RetrievalResult]
    /// 只被 vector 命中的。
    public let vectorOnly: [RetrievalResult]
    /// 两路都命中的条数。
    public let bothCount: Int

    public init(results: [RetrievalResult], trace: RetrievalTrace,
                keywordOnly: [RetrievalResult], vectorOnly: [RetrievalResult], bothCount: Int) {
        self.results = results
        self.trace = trace
        self.keywordOnly = keywordOnly
        self.vectorOnly = vectorOnly
        self.bothCount = bothCount
    }
}

/// # 检索统一入口
///
/// 三种 mode 走**同一条管线**，只是跳过其中一路 —— 而不是三份各自的实现。
/// 三份实现意味着三处可以各自跑偏，而 Compare Modes 比较的恰恰是它们的差异，
/// 那样比出来的可能是实现差异而不是策略差异。
public actor RetrievalService {

    /// `nil` = 本机没有可用的句向量模型。**不退回 mock**（TD-5）：伪向量会让
    /// Recall 看起来正常但毫无产品含义。此时 vector 路整条跳过，keyword 路照常 ——
    /// 与 `IndexState` 的降级走同一个出口，不是第二套逻辑。
    private let provider: (any EmbeddingProvider)?
    private let vectors: InMemoryVectorStore
    private let recorder: RetrievalTraceRecorder?
    /// keyword 路的归一化缓存。**与 `vectors` 同一类**：derived、在内存、可随时重建。
    /// `nil` = 不缓存，每次查询重新折叠全库正文（旧行为，逐位一致但慢 3 倍）。
    private let normalizedText: NormalizedTextCache?

    public init(provider: (any EmbeddingProvider)?,
                vectors: InMemoryVectorStore,
                recorder: RetrievalTraceRecorder? = nil,
                normalizedText: NormalizedTextCache? = NormalizedTextCache()) {
        self.provider = provider
        self.vectors = vectors
        self.recorder = recorder
        self.normalizedText = normalizedText
    }

    /// 执行一次检索。
    ///
    /// - Parameters:
    ///   - chunks: 当前语料（keyword 路在其上做子串定位；vector 路用它把 chunkID
    ///     还原成文本）。
    ///   - indexState: 决定 vector 路是否可用。`building` / `failed` 时自动降级为
    ///     纯 keyword —— **Progressive Enhancement 在检索层就生效，不依赖 UI 记得处理**。
    public func retrieve(query: String,
                         chunks: [NoteChunk],
                         config: RetrievalConfig,
                         indexState: IndexState = .ready) async -> RetrievalOutcome {

        let t0 = DispatchTime.now().uptimeNanoseconds
        func ms(since: UInt64) -> Double {
            Double(DispatchTime.now().uptimeNanoseconds - since) / 1_000_000
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let byID = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        // ── query processing ──
        let tQuery = DispatchTime.now().uptimeNanoseconds
        let tokens = SearchMatcher.tokens(from: trimmed)
        let queryProcessingMs = ms(since: tQuery)

        guard !tokens.isEmpty else {
            let trace = RetrievalTrace(query: trimmed, configVersion: config.version,
                                       embeddingVersion: config.embeddingVersion,
                                       indexVersion: config.chunkStrategy.identity,
                                       queryProcessingMs: queryProcessingMs,
                                       totalMs: ms(since: t0),
                                       chunkCount: chunks.count)
            await recorder?.record(trace)
            return RetrievalOutcome(results: [], trace: trace, keywordOnly: [], vectorOnly: [], bothCount: 0)
        }

        // vector 路是否真的能用：mode 要求 + 索引状态 + provider 存在，**三者都**满足。
        let wantsVector = config.mode != .keyword
        let vectorUsable = wantsVector && indexState.allowsVectorRetrieval && provider != nil
        let wantsKeyword = config.mode != .vector    // keyword 永远可用（IndexState 保证）

        // ── keyword 路 ──
        var keywordHits: [KeywordHit] = []
        var keywordMs = 0.0
        if wantsKeyword {
            let t = DispatchTime.now().uptimeNanoseconds
            // 归一化只取决于 chunk 自身，与 query 无关 —— 缓存它省掉 20k 上 68.5% 的
            // keyword 耗时，且**不改任何检索语义**（缓存与非缓存走同一个 locate 实现）。
            let hays = await normalizedText?.normalized(for: chunks)
            keywordHits = KeywordRetriever.retrieve(query: trimmed, chunks: chunks,
                                                    topK: config.candidateK, normalized: hays)
            keywordMs = ms(since: t)
        }

        // ── vector 路 ──
        var vectorHits: [VectorHit] = []
        var embedMs = 0.0, vectorMs = 0.0
        if vectorUsable, let provider {
            let tE = DispatchTime.now().uptimeNanoseconds
            let queryVector = try? await provider.embed(trimmed)
            embedMs = ms(since: tE)
            if let queryVector {
                let tV = DispatchTime.now().uptimeNanoseconds
                vectorHits = await vectors.search(query: queryVector, topK: config.candidateK)
                vectorMs = ms(since: tV)
            }
        }

        // ── 融合 ──
        let tF = DispatchTime.now().uptimeNanoseconds
        let fused: [FusedRanking]
        switch config.mode {
        case .keyword:
            fused = keywordHits.enumerated().map {
                FusedRanking(chunkID: $1.chunkID, keywordRank: $0 + 1, vectorRank: nil,
                             fusedScore: 1.0 / Double($0 + 1))
            }
        case .vector:
            fused = vectorHits.enumerated().map {
                FusedRanking(chunkID: $1.chunkID, keywordRank: nil, vectorRank: $0 + 1,
                             fusedScore: 1.0 / Double($0 + 1))
            }
        case .hybrid:
            fused = RRFFusion.fuse(keywordOrder: keywordHits.map(\.chunkID),
                                   vectorOrder: vectorHits.map(\.chunkID),
                                   method: config.fusion)
        }
        let fusionMs = ms(since: tF)

        // ── 排名 → 结果 ──
        let tR = DispatchTime.now().uptimeNanoseconds
        let keywordByID = Dictionary(uniqueKeysWithValues: keywordHits.map { ($0.chunkID, $0) })
        let similarityByID = Dictionary(uniqueKeysWithValues: vectorHits.map { ($0.chunkID, $0.similarity) })

        var results: [RetrievalResult] = []
        for (i, f) in fused.prefix(config.topK).enumerated() {
            // chunk 可能已被删除但索引尚未清理 —— 跳过而不是崩溃或返回空壳。
            guard let chunk = byID[f.chunkID] else { continue }
            let kh = keywordByID[f.chunkID]
            results.append(RetrievalResult(
                chunkID: f.chunkID, ref: chunk.ref, source: chunk.source, text: chunk.text,
                fusedRank: i + 1, keywordRank: f.keywordRank, vectorRank: f.vectorRank,
                similarity: similarityByID[f.chunkID], keywordScore: kh?.score,
                matchedRanges: kh?.ranges ?? []
            ))
        }
        let rankingMs = ms(since: tR)

        let trace = RetrievalTrace(
            query: trimmed,
            configVersion: config.version,
            embeddingVersion: config.embeddingVersion,
            indexVersion: config.chunkStrategy.identity,
            queryProcessingMs: queryProcessingMs,
            queryEmbeddingMs: embedMs,
            keywordRetrievalMs: keywordMs,
            vectorRetrievalMs: vectorMs,
            fusionMs: fusionMs,
            rankingMs: rankingMs,
            totalMs: ms(since: t0),
            chunkCount: chunks.count,
            keywordCandidates: keywordHits.count,
            vectorCandidates: vectorHits.count,
            candidateCount: Set(keywordHits.map(\.chunkID)).union(vectorHits.map(\.chunkID)).count,
            resultCount: results.count,
            contentHash: chunks.first?.contentHash ?? "",
            isStale: !indexState.allowsVectorRetrieval && wantsVector
        )
        await recorder?.record(trace)

        return RetrievalOutcome(
            results: results,
            trace: trace,
            keywordOnly: results.filter(\.isKeywordOnly),
            vectorOnly: results.filter(\.isVectorOnly),
            bothCount: results.filter { $0.keywordRank != nil && $0.vectorRank != nil }.count
        )
    }
}
