import Foundation
import SwiftData
import Observation
import MosaicKit

/// # Retrieval Lab 的 ViewModel
///
/// 职责就三件事：把当前笔记切成 chunk、跑一次检索、把三路排名交给 View。
///
/// **不做的事**：不写任何用户数据、不改索引、不做持久化。Lab 是只读工具
/// （`DEVTOOLS.md` §1.2「数据隔离」）。
@Observable
@MainActor
final class RetrievalLabViewModel {

    enum Phase: Equatable {
        case idle
        case running
        case results
        case empty
        case error(String)
    }

    // 输入
    var query: String = ""
    var mode: RetrievalMode = .hybrid
    var chunkStrategy: ChunkStrategy = .default
    var topK: Int = 20
    var fusion: FusionMethod = .default

    // 输出
    private(set) var phase: Phase = .idle
    private(set) var outcome: RetrievalOutcome?
    private(set) var indexState: IndexState = .ready
    /// 与结果一一对应的 excerpt，预先算好，避免在 `body` 里做计算。
    private(set) var excerpts: [String: Excerpt] = [:]

    /// `nil` = 本机没有可用的本地句向量模型。**不退回 mock**（TD-5）：
    /// 伪向量会让 Lab 看起来在做语义检索，实际排出来的顺序没有任何含义。
    private let provider: (any EmbeddingProvider)?
    private let vectors: InMemoryVectorStore
    private let recorder: RetrievalTraceRecorder
    private let corpus: NoteCorpus
    /// 生产索引是用哪套策略建的。选了别的策略时 vector 路命中的 chunkID 在当前语料里
    /// 找不到，会被**静默丢弃** —— Lab 必须把这件事说出来，否则看起来像「换策略语义变差」。
    let indexedStrategy: ChunkStrategy
    private var runTask: Task<Void, Never>?

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         recorder: RetrievalTraceRecorder,
         derived: DerivedDataStore,
         noteContext: ModelContext,
         indexedStrategy: ChunkStrategy = .default) {
        self.provider = provider
        self.vectors = vectors
        self.recorder = recorder
        self.corpus = NoteCorpus(noteContext: noteContext, derived: derived)
        self.indexedStrategy = indexedStrategy
    }

    var strategyMatchesIndex: Bool { chunkStrategy == indexedStrategy }

    var config: RetrievalConfig {
        RetrievalConfig(version: "retrieval-lab",
                        mode: mode,
                        embeddingProvider: provider?.modelInfo.identifier ?? "unavailable",
                        embeddingVersion: provider?.modelInfo.version ?? "unavailable",
                        chunkStrategy: chunkStrategy,
                        topK: topK,
                        fusion: fusion)
    }

    /// 跑一次检索。
    ///
    /// 失败或空结果时**保留上一次的结果**，与生产搜索同一条原则：失败不清屏
    /// （`DEVTOOLS.md` §4.2 State）。
    func run() {
        runTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { phase = .idle; return }

        phase = .running
        let config = self.config

        runTask = Task { @MainActor in
            // 语料从当前笔记现切 —— Lab 要能立刻反映刚刚改过的内容。
            let chunks = allChunks(strategy: config.chunkStrategy)
            guard !chunks.isEmpty else {
                phase = .empty
                return
            }

            let service = RetrievalService(provider: provider, vectors: vectors, recorder: recorder)
            let result = await service.retrieve(query: q, chunks: chunks,
                                                config: config, indexState: indexState)
            guard !Task.isCancelled else { return }

            outcome = result
            excerpts = Dictionary(uniqueKeysWithValues: result.results.map {
                ($0.chunkID, ExcerptBuilder.build(text: $0.text, ranges: $0.matchedRanges, budget: 60))
            })
            phase = result.results.isEmpty ? .empty : .results
        }
    }

    /// 用当前策略把全部笔记切成 chunk。
    ///
    /// 每次 Run 都重切，而不是缓存：Lab 的价值就在于换一个 chunk 策略马上看到差别，
    /// 缓存会让「换策略」变成「换策略但结果没变」的困惑。
    ///
    /// 切分实现只有 `NoteCorpus` 一处 —— Lab 与 Eval 必须看到同一份语料。
    func allChunks(strategy: ChunkStrategy) -> [NoteChunk] {
        corpus.chunks(strategy: strategy)
    }

    /// 笔记标题，结果行要显示它。
    func noteTitle(for noteID: String) -> String {
        corpus.title(noteID: noteID)
    }

    /// 索引规模，用于 `IndexStateMachine` 与页面上的说明。
    func refreshIndexState() async {
        let indexed = await vectors.count()
        let total = allChunks(strategy: chunkStrategy).count
        indexState = IndexStateMachine.derive(totalChunks: total,
                                              pendingChunks: max(0, total - indexed),
                                              runningJobs: 0,
                                              hasEmbeddings: indexed > 0)
    }
}
