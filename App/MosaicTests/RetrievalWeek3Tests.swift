import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Week 3 —— 三路检索与 Lab，跑在真实 SwiftData 上
///
/// MosaicKit 的 checks 证明逻辑本身；这里证明它接上真实 `@Model`、真实 fetch、
/// 真实 derived store 之后依然成立。
@MainActor
final class RetrievalWeek3Tests: XCTestCase {

    private func makeStack() -> (notes: ModelContainer, derived: ModelContainer, store: DerivedDataStore) {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = ModelContainerFactory.makeDerived(inMemory: true)
        return (notes, derived, DerivedDataStore(container: derived))
    }

    @discardableResult
    private func seed(_ ctx: ModelContext) throws -> Card {
        let card = Card(userTitle: "延期毕业相关")
        ctx.insert(card)
        let texts = [
            "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认。",
            "周会上说延期的事下周开会再定，毕业时间还有缓冲。",
            "今天把合同评审的三处修改整理好了，跟这件事无关。"
        ]
        for (i, t) in texts.enumerated() {
            let b = Block(kind: .text, order: i)
            b.text = t
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        return card
    }

    /// 建索引：切 chunk → 嵌入 → 经 StaleGuard 落库 → 灌进内存索引。
    private func buildIndex(card: Card, ctx: ModelContext, store: DerivedDataStore,
                            provider: MockEmbeddingProvider, vectors: InMemoryVectorStore,
                            strategy: ChunkStrategy = .block) async throws -> [NoteChunk] {
        let noteID = card.id.uuidString
        let plan = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(),
                                           strategy: strategy, existingRecords: [:],
                                           embeddingVersion: provider.modelInfo.version)
        for item in plan.pending {
            let vec = try await provider.embed(item.text)
            store.commit(DerivedResult(key: item.key, payload: vec),
                         chunkID: item.chunkID, chunkIndex: item.key.chunkIndex,
                         chunkStrategy: strategy.identity,
                         embeddingVersion: provider.modelInfo.version, noteContext: ctx)
            await vectors.upsert(EmbeddingRecord(ref: item.key.ref, chunkID: item.chunkID,
                                                 chunkIndex: item.key.chunkIndex,
                                                 contentHash: item.key.contentHash,
                                                 embeddingVersion: provider.modelInfo.version,
                                                 chunkStrategy: strategy.identity,
                                                 dimension: vec.count, vector: vec))
        }
        return ChunkPipeline.chunks(noteID: noteID, blocks: card.blockContents(), strategy: strategy)
    }

    // MARK: 1 · 三路排名证据在真实数据上成立

    func testHybridReturnsAllThreeRanksOnRealNotes() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx)
        let provider = MockEmbeddingProvider(dimension: 32)
        let vectors = InMemoryVectorStore()
        let chunks = try await buildIndex(card: card, ctx: ctx, store: stack.store,
                                          provider: provider, vectors: vectors)

        let service = RetrievalService(provider: provider, vectors: vectors)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 5)
        let outcome = await service.retrieve(query: "延期 毕业", chunks: chunks, config: config)

        XCTAssertFalse(outcome.results.isEmpty)
        XCTAssertEqual(outcome.results.map(\.fusedRank), Array(1...outcome.results.count))
        XCTAssertTrue(outcome.results.contains { $0.keywordRank != nil && $0.vectorRank != nil },
                      "存在两路都命中的结果")
        // 排名证据可读，且能定位回 block —— Search Result → Note 的 anchor。
        let top = outcome.results[0]
        XCTAssertTrue(top.rankEvidence.contains("→"))
        XCTAssertNotNil(UUID(uuidString: top.ref.blockID), "结果携带可解析的 blockID")

        let blockUUID = UUID(uuidString: top.ref.blockID)!
        var fetch = FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockUUID })
        fetch.fetchLimit = 2
        XCTAssertEqual(try ctx.fetch(fetch).count, 1, "blockID 能唯一定位回一个 Block")
    }

    // MARK: 2 · Matched Excerpt 端到端

    func testMatchedExcerptHasCorrectHighlightOffsets() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx)
        let provider = MockEmbeddingProvider(dimension: 32)
        let vectors = InMemoryVectorStore()
        let chunks = try await buildIndex(card: card, ctx: ctx, store: stack.store,
                                          provider: provider, vectors: vectors)

        let service = RetrievalService(provider: provider, vectors: vectors)
        let config = RetrievalConfig(mode: .keyword, embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 5)
        let outcome = await service.retrieve(query: "延期", chunks: chunks, config: config)
        XCTAssertFalse(outcome.results.isEmpty)

        for result in outcome.results {
            let excerpt = ExcerptBuilder.build(text: result.text, ranges: result.matchedRanges, budget: 44)
            XCTAssertFalse(excerpt.text.isEmpty)
            XCTAssertFalse(excerpt.highlights.isEmpty, "keyword 命中必须带高亮")
            // 高亮区间落在 excerpt 内，且取出来确实是 query 词。
            let chars = Array(excerpt.text)
            for h in excerpt.highlights {
                XCTAssertLessThanOrEqual(h.end, chars.count)
                XCTAssertEqual(String(chars[h.start..<h.end]), "延期",
                               "高亮区间取出的正是命中词")
            }
        }
    }

    // MARK: 3 · Progressive Enhancement 在检索层就生效

    func testSemanticUnavailableFallsBackToKeywordAutomatically() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx)
        let provider = MockEmbeddingProvider(dimension: 32)
        let vectors = InMemoryVectorStore()
        let chunks = try await buildIndex(card: card, ctx: ctx, store: stack.store,
                                          provider: provider, vectors: vectors)

        let service = RetrievalService(provider: provider, vectors: vectors)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 5)

        for state: IndexState in [.failed(reason: "offline"), .building(progress: 0.2)] {
            let outcome = await service.retrieve(query: "延期 毕业", chunks: chunks,
                                                 config: config, indexState: state)
            XCTAssertFalse(outcome.results.isEmpty, "\(state) 下关键词搜索仍然可用")
            XCTAssertTrue(outcome.results.allSatisfy { $0.vectorRank == nil },
                          "\(state) 下自动降级为纯关键词")
            XCTAssertTrue(outcome.trace.isStale, "trace 标记本次未用到语义路")
        }

        // 索引就绪时语义路回来。
        let ready = await service.retrieve(query: "延期 毕业", chunks: chunks,
                                           config: config, indexState: .ready)
        XCTAssertTrue(ready.results.contains { $0.vectorRank != nil }, "就绪后语义路恢复")
    }

    // MARK: 4 · Lab ViewModel 完整链路

    func testLabViewModelRunsEndToEnd() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx)
        let provider = MockEmbeddingProvider(dimension: 32)
        let vectors = InMemoryVectorStore()
        _ = try await buildIndex(card: card, ctx: ctx, store: stack.store,
                                 provider: provider, vectors: vectors)

        let vm = RetrievalLabViewModel(provider: provider, vectors: vectors,
                                       recorder: RetrievalTraceRecorder(),
                                       derived: stack.store, noteContext: ctx)
        await vm.refreshIndexState()
        XCTAssertEqual(vm.indexState, .ready, "索引状态由事实推导")

        vm.query = "延期 毕业"
        vm.mode = .hybrid
        vm.run()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(vm.phase, .results)
        XCTAssertNotNil(vm.outcome)
        XCTAssertFalse(vm.excerpts.isEmpty, "excerpt 已预先算好，不在 body 里计算")
        XCTAssertEqual(vm.excerpts.count, vm.outcome?.results.count)
        // 结果行显示的标题来自真实笔记。
        let top = vm.outcome!.results[0]
        XCTAssertEqual(vm.noteTitle(for: top.ref.noteID), "延期毕业相关")

        // 换 chunk 策略必须重切，否则「换策略结果没变」会让人以为坏了。
        // 种子文本每块恰好一句，所以 .sentence 与 .block 切出来一样多 —— 用一个
        // 必定切分的窗口来验证重切确实发生。
        let original = vm.allChunks(strategy: .block)
        vm.chunkStrategy = .fixed(maxChars: 12, overlap: 2)
        let resplit = vm.allChunks(strategy: vm.chunkStrategy)
        XCTAssertGreaterThan(resplit.count, original.count, "换策略后重新切分，chunk 数变多")
        XCTAssertTrue(resplit.allSatisfy { $0.strategy == "fixed(12/2)" }, "chunk 记录了新策略")

        // 空 query 回到 idle，不是空结果页。
        vm.query = "   "
        vm.run()
        XCTAssertEqual(vm.phase, .idle)
    }

    // MARK: 5 · Trace 记录真实管线

    func testTraceRecordsRealPipeline() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let card = try seed(ctx)
        let provider = MockEmbeddingProvider(dimension: 32)
        let vectors = InMemoryVectorStore()
        let recorder = RetrievalTraceRecorder()
        let chunks = try await buildIndex(card: card, ctx: ctx, store: stack.store,
                                          provider: provider, vectors: vectors)

        let service = RetrievalService(provider: provider, vectors: vectors, recorder: recorder)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 5)
        _ = await service.retrieve(query: "延期 毕业", chunks: chunks, config: config)

        let latest = await recorder.latest()
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.chunkCount, chunks.count, "chunkCount 真实")
        XCTAssertGreaterThan(latest?.totalMs ?? 0, 0, "总耗时被真实测量")
        XCTAssertGreaterThan(latest?.candidateCount ?? 0, 0, "候选数真实")
        XCTAssertFalse(latest?.contentHash.isEmpty ?? true, "contentHash 已记录")
        XCTAssertEqual(latest?.isStale, false, "索引就绪时不标 stale")
    }
}
