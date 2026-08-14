import Foundation
import SwiftData
import Observation
import MosaicKit

/// # TD-7 —— 生产搜索接入 Hybrid
///
/// 严格按 `design/SEARCH_CONTRACT.md`（RE-FROZEN）实现，两条要点：
///
/// **一、两个正交维度，不是八个扁平状态**（§4.1）。
/// `QueryPhase` 驱动结果区，`RetrievalCapability` 驱动状态条，两者独立演进。
/// 铺平会立刻产生「索引建立中但同时在检索」这种无法回答的组合。
///
/// **二、两级触发**（§1.2）。keyword 是纯本地快通道，semantic 是慢通道且有长度门控。
/// 防抖的存在理由是**省 embedding 成本、避免抖动**，不是掩盖延迟 ——
/// 本地检索的 SLO 比人的输入停顿还快，所以调参方向是尽量小。
///
/// 用户侧**没有任何 mode 控件**，也不会看到 embedding / 向量 / RRF 这些词（§1.1）。
@Observable
@MainActor
final class SearchViewModel {

    /// §4.1 的第一个维度。只关心「结果区该显示什么」。
    enum QueryPhase: Equatable {
        case idle
        case searching
        case ready
        case noResults
    }

    // MARK: 输出

    private(set) var phase: QueryPhase = .idle
    private(set) var rows: [NoteSearchResult] = []
    private(set) var capability: RetrievalCapability = .full
    /// §2.6：整页零字面命中时，列表顶部一行说明。
    private(set) var showsSemanticOnlyNotice = false

    // MARK: 依赖

    private let provider: (any EmbeddingProvider)?
    private let vectors: InMemoryVectorStore
    private let recorder: RetrievalTraceRecorder?
    private let indexing: IndexingService?
    private let corpus: NoteCorpus
    private let noteContext: ModelContext
    private let scope: SearchScope

    /// 防抖初值（§1.2，tuning value）。keyword 是纯本地的，可以趋近 0。
    private let keywordDebounceNanos: UInt64
    private let semanticDebounceNanos: UInt64

    private var keywordTask: Task<Void, Never>?
    private var semanticTask: Task<Void, Never>?
    /// keyword 结果渲染的时刻，用于 §1.3 R4 的降级方案。
    private var keywordRenderedAt: Date?
    private var currentQuery = ""

    /// 语料缓存：搜索路径上不能每次按键把全库重切一遍。
    /// key 由笔记数 + 最近更新时间构成，任何编辑都会让它失效。
    private var cachedChunks: [NoteChunk] = []
    private var cachedChunkKey = ""

    init(provider: (any EmbeddingProvider)?,
         vectors: InMemoryVectorStore,
         recorder: RetrievalTraceRecorder? = nil,
         indexing: IndexingService? = nil,
         derived: DerivedDataStore,
         noteContext: ModelContext,
         scope: SearchScope = SearchScope(),
         keywordDebounceNanos: UInt64 = 150_000_000,
         semanticDebounceNanos: UInt64 = 400_000_000) {
        self.provider = provider
        self.vectors = vectors
        self.recorder = recorder
        self.indexing = indexing
        self.corpus = NoteCorpus(noteContext: noteContext, derived: derived)
        self.noteContext = noteContext
        self.scope = scope
        self.keywordDebounceNanos = keywordDebounceNanos
        self.semanticDebounceNanos = semanticDebounceNanos
    }

    /// 跟索引走，不抓 init 时那份 —— 中文入库后路线可能从本机英文切到云端。
    private var liveProvider: (any EmbeddingProvider)? {
        indexing?.provider ?? provider
    }

    /// 索引口径必须与 `IndexingService` 一致 —— 用另一套 chunk 策略去查同一个索引，
    /// vector 命中的 chunkID 在当前语料里找不到，会被静默丢弃。
    private var indexedStrategy: ChunkStrategy {
        indexing?.config.chunkStrategy ?? RetrievalConfig.production.chunkStrategy
    }

    private var liveRoute: EmbeddingRoute {
        if let version = liveProvider?.modelInfo.version {
            if version.contains("zh-Hans") { return .localChinese }
            if version.contains("nl-en") { return .localEnglish }
            if version.hasPrefix("cloud-") { return .cloud }
        }
        return .unavailable("语义检索不可用")
    }

    // MARK: 输入

    /// 每次输入变化调用。两条通道各自防抖、各自可取消。
    func queryChanged(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = query
        keywordTask?.cancel()
        semanticTask?.cancel()

        guard !query.isEmpty else {
            phase = .idle
            rows = []
            showsSemanticOnlyNotice = false
            keywordRenderedAt = nil
            return
        }

        // §4.3：`.searching` **保留上一次结果**，清空会造成每次按键的白屏闪烁。
        phase = .searching

        // 两条通道都 `[weak self]`：搜索屏被 pop 之后，防抖里挂着的任务不该把整个
        // ViewModel（连同它持有的 ModelContext）续命，更不该在屏已经没了之后再查一次。
        keywordTask = Task { @MainActor [weak self, keywordDebounceNanos] in
            try? await Task.sleep(nanoseconds: keywordDebounceNanos)
            guard let self, !Task.isCancelled, currentQuery == query else { return }
            await runKeyword(query)
        }

        // 慢通道：长度门控 + 更长的防抖 + capability 允许。
        // 本机英文索引上的中文 query 不能拿去嵌（换语言 = 换空间）。
        guard SemanticGate.shouldRunSemantic(query: query),
              !EmbeddingRouter.shouldSkipSemantic(query: query, route: liveRoute) else { return }
        semanticTask = Task { @MainActor [weak self, semanticDebounceNanos] in
            try? await Task.sleep(nanoseconds: semanticDebounceNanos)
            guard let self, !Task.isCancelled, currentQuery == query else { return }
            refreshCapability()
            guard capability.allowsSemantic else { return }
            await runHybrid(query)
        }
    }

    /// 离开搜索屏时调用。防抖里挂着的两个任务没有必要跑完 ——
    /// 结果没有地方可去，而它们还要占着主上下文做一次全库切分。
    func cancelPendingWork() {
        keywordTask?.cancel()
        semanticTask?.cancel()
    }

    /// 进入搜索屏 / 从笔记返回时调用。返回时**重新读取** capability ——
    /// 离开期间索引可能已经就绪（§3.5）。
    func refreshCapability() {
        let state = indexing?.state ?? .ready
        capability = RetrievalCapability.derive(indexState: state,
                                                semanticProviderAvailable: liveProvider != nil)
    }

    /// `semanticUnavailable` 那条状态栏上的「重试」。用户侧文案不含技术词。
    /// 状态栏「重试」：先按当前笔记重选路线（用户可能刚填了 API Key），再重建。
    var onRetrySemantic: (() async -> Void)?

    func retrySemantic() {
        guard let indexing else { return }
        Task { @MainActor in
            await onRetrySemantic?()
            await indexing.indexAll()
            refreshCapability()
            if !currentQuery.isEmpty, capability.allowsSemantic {
                await runHybrid(currentQuery)
            }
        }
    }

    // MARK: 两条通道

    private func runKeyword(_ query: String) async {
        let outcome = await retrieve(query: query, mode: .keyword)
        guard currentQuery == query else { return }   // 期间又输入了，丢弃旧结果
        apply(outcome: outcome, query: query, upgrade: false)
        keywordRenderedAt = Date()
    }

    private func runHybrid(_ query: String) async {
        let outcome = await retrieve(query: query, mode: .hybrid)
        guard currentQuery == query else { return }
        apply(outcome: outcome, query: query, upgrade: true)
    }

    private func retrieve(query: String, mode: RetrievalMode) async -> RetrievalOutcome {
        let chunks = chunks()
        // 生产参数取**索引服务当前的那一套**（Promote 之后它就变了），
        // 而不是编译期常量 —— 否则 Release Gate 判过的配置和线上真正跑的不是一回事。
        let production = indexing?.config ?? RetrievalConfig.production
        let config = RetrievalConfig(version: production.version,
                                     mode: mode,
                                     embeddingProvider: liveProvider?.modelInfo.identifier ?? "unavailable",
                                     embeddingVersion: liveProvider?.modelInfo.version ?? "unavailable",
                                     chunkStrategy: indexedStrategy,
                                     topK: 50,
                                     fusion: production.fusion)
        let service = RetrievalService(provider: liveProvider, vectors: vectors, recorder: recorder)
        return await service.retrieve(query: query, chunks: chunks, config: config,
                                      indexState: indexing?.state ?? .ready)
    }

    /// 把一次检索结果落到界面上。
    ///
    /// **R1**：行的身份是 noteID，不是下标 —— 重排不改变任何一行的点击目标。
    /// **R5**：不做 reorder 动画（由 View 侧的 `.animation(nil)` 保证）。
    /// **R4 降级**：keyword 结果已经渲染超过 1.5s 后，语义升级**不再重排**已有顺序，
    /// 只把新捞到的笔记追加到末尾（`SEARCH_CONTRACT.md` §1.3 明列的降级方案）——
    /// 用户此时很可能正在阅读或滚动，重排就是误触。
    private func apply(outcome: RetrievalOutcome, query: String, upgrade: Bool) {
        var newRows = SearchPresentation.rows(from: outcome, budget: 44, limit: 50)
        newRows = withLexicalMatches(newRows, query: query)
        newRows = newRows.filter { allowedByScope($0.noteID) }

        if upgrade, let renderedAt = keywordRenderedAt, Date().timeIntervalSince(renderedAt) > 1.5 {
            let existing = Set(rows.map(\.noteID))
            let appended = newRows.filter { !existing.contains($0.noteID) }
            rows = rows + appended
        } else {
            rows = newRows
        }

        showsSemanticOnlyNotice = SearchPresentation.needsSemanticOnlyNotice(rows)
        phase = rows.isEmpty ? .noResults : .ready
    }

    // MARK: 标题 / 标签 —— lexical signals，不进语料

    /// 标题与标签不参与嵌入（§2.8 语料定义），但**必须仍然搜得到** ——
    /// 否则「按标题找笔记」这个既有行为会静默消失。
    ///
    /// 排在内容命中之后：它们没有可比的融合分数，硬塞进榜单中间等于**发明**一套
    /// 相关性。顺序取最近更新优先。
    private func withLexicalMatches(_ rows: [NoteSearchResult], query: String) -> [NoteSearchResult] {
        let tokens = SearchMatcher.tokens(from: query)
        guard !tokens.isEmpty else { return rows }

        let matches = cards()
            .filter { card in
                SearchMatcher.matches(query: query,
                                      haystack: card.displayTitle,
                                      tags: card.tags)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { (noteID: $0.id.uuidString, preview: preview(of: $0)) }

        return SearchPresentation.appendingLexicalMatches(rows, lexical: matches, budget: 44, limit: 50)
    }

    private func preview(of card: Card) -> String {
        for block in card.orderedBlocks {
            guard let (_, text) = ChunkPipeline.resolveText(block: block.toContent(), ocrText: nil) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    // MARK: 语料

    private func chunks() -> [NoteChunk] {
        let cards = cards()
        let newest = cards.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let key = "\(cards.count)|\(newest)|\(indexedStrategy.identity)"
        if key != cachedChunkKey {
            cachedChunks = corpus.chunks(strategy: indexedStrategy)
            cachedChunkKey = key
        }
        return cachedChunks
    }

    private func cards() -> [Card] {
        (try? noteContext.fetch(FetchDescriptor<Card>())) ?? []
    }

    private func allowedByScope(_ noteID: String) -> Bool {
        guard !scope.isUnconstrained else { return true }
        guard let uuid = UUID(uuidString: noteID) else { return false }
        var fetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        fetch.fetchLimit = 1
        guard let card = (try? noteContext.fetch(fetch))?.first else { return false }
        return scope.allows(folderID: card.folder?.id.uuidString, tags: card.tags, isPinned: card.isPinned)
    }

    // MARK: 供 View 取用

    func card(for noteID: String) -> Card? {
        guard let uuid = UUID(uuidString: noteID) else { return nil }
        var fetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        fetch.fetchLimit = 1
        return (try? noteContext.fetch(fetch))?.first
    }
}
