import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # TD-8 —— 生产索引服务
///
/// 这一组用例证明的是「接线接对了」：扫描 → 嵌入 → 校验落盘 → 内存索引，
/// 以及三条不变量（内存索引只装落盘成功的向量 · orphan 立即失效 · 不靠取消）。
@MainActor
final class RetrievalIndexingTests: XCTestCase {

    // MARK: 工具

    /// 数嵌入次数的 provider —— 「第二遍不该再嵌一次」只能靠计数证明，
    /// 记录条数不变也可能是因为覆盖写了一遍。
    private actor EmbedCounter {
        private(set) var count = 0
        func bump() { count += 1 }
        func value() -> Int { count }
    }

    private struct CountingProvider: EmbeddingProvider {
        let modelInfo = EmbeddingModelInfo(identifier: "counting", dimension: 32, version: "counting-v1")
        let counter: EmbedCounter
        var delayNanos: UInt64 = 0

        func embed(_ text: String) async throws -> [Float] {
            if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
            await counter.bump()
            return MockEmbeddingProvider.deterministicVector(for: text, dimension: 32)
        }
    }

    private struct Stack {
        let notes: ModelContainer
        let context: ModelContext
        let derived: DerivedDataStore
        let vectors: InMemoryVectorStore
        let counter: EmbedCounter
        let service: IndexingService
    }

    private func makeStack(provider: (any EmbeddingProvider)?? = nil,
                           extractor: (any ImageTextExtractor)? = nil,
                           debounceNanos: UInt64 = 50_000_000) -> Stack {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = DerivedDataStore(container: ModelContainerFactory.makeDerived(inMemory: true))
        let vectors = InMemoryVectorStore()
        let counter = EmbedCounter()
        // 默认给计数 provider；显式传 `.some(nil)` 表示「本机没有模型」。
        let resolved: (any EmbeddingProvider)? = provider ?? CountingProvider(counter: counter)
        let service = IndexingService(provider: resolved,
                                      vectors: vectors,
                                      derived: derived,
                                      noteContext: notes.mainContext,
                                      extractor: extractor,
                                      config: RetrievalConfig(mode: .hybrid, chunkStrategy: .block),
                                      debounceNanos: debounceNanos)
        return Stack(notes: notes, context: notes.mainContext, derived: derived,
                     vectors: vectors, counter: counter, service: service)
    }

    @discardableResult
    private func seed(_ ctx: ModelContext, title: String, texts: [String]) throws -> Card {
        let card = Card(userTitle: title)
        ctx.insert(card)
        for (i, t) in texts.enumerated() {
            let b = Block(kind: .text, order: i)
            b.text = t
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        return card
    }

    // MARK: 1 · 全库扫描真的把索引建起来了

    func testFullScanPersistsEmbeddingsAndPopulatesTheMemoryIndex() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: [
            "我问了 advisor 能不能延期一个学期毕业。",
            "周会上说延期的事下周开会再定。"
        ])
        try seed(stack.context, title: "合同评审", texts: ["今天把合同评审的三处修改整理好了。"])

        XCTAssertEqual(stack.derived.recordCount(), 0, "索引服务之前，derived store 一直是空的（TD-8）")

        await stack.service.indexAll()

        XCTAssertEqual(stack.derived.recordCount(), 3, "每个 block 一条记录（block 策略）")
        let inMemory = await stack.vectors.count()
        XCTAssertEqual(inMemory, 3, "落盘的同时进内存索引")
        let embedCalls = await stack.counter.value()
        XCTAssertEqual(embedCalls, 3)
        XCTAssertEqual(stack.service.state, .ready)
        XCTAssertEqual(stack.service.pendingChunks, 0)
    }

    /// 冷启动路径：先灌回落盘的向量，**再**扫描。顺序反了会把已存好的判成 pending，
    /// 于是每次启动重嵌全库。
    func testRestartLoadsPersistedVectorsInsteadOfReEmbedding() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "笔记", texts: ["延期毕业相关的内容。"])
        await stack.service.indexAll()
        let firstPass = await stack.counter.value()
        XCTAssertEqual(firstPass, 1)

        // 新一轮「启动」：内存索引是空的，但 derived store 里有记录。
        let restarted = IndexingService(provider: CountingProvider(counter: stack.counter),
                                        vectors: InMemoryVectorStore(),
                                        derived: stack.derived,
                                        noteContext: stack.context,
                                        config: RetrievalConfig(mode: .hybrid, chunkStrategy: .block))
        await restarted.start()

        let afterRestart = await stack.counter.value()
        XCTAssertEqual(afterRestart, firstPass, "重启不重嵌 —— 已有记录直接灌回内存")
        XCTAssertEqual(restarted.indexedChunks, 1)
        XCTAssertEqual(restarted.state, .ready)
    }

    // MARK: 2 · 增量：改一处不重嵌全库，删一块立刻失效

    func testEditReEmbedsOnlyTheChangedBlock() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "笔记", texts: ["第一段内容。", "第二段内容。"])
        await stack.service.indexAll()
        let afterFirstPass = await stack.counter.value()
        XCTAssertEqual(afterFirstPass, 2)

        card.orderedBlocks[0].text = "第一段内容改过了。"
        try stack.context.save()
        await stack.service.index(noteIDs: [card.id.uuidString])

        let afterEdit = await stack.counter.value()
        XCTAssertEqual(afterEdit, 3, "只有被改的那一块重嵌")
        XCTAssertEqual(stack.derived.recordCount(), 2, "记录是覆盖写，不是追加")

        // 记录跟着新内容走。
        let ref = BlockRef(noteID: card.id.uuidString, blockID: card.orderedBlocks[0].id.uuidString)
        let chunkID = ChunkPipeline.chunkID(ref: ref, index: 0)
        XCTAssertEqual(stack.derived.record(forChunk: chunkID)?.contentHash,
                       AIContentHash.forBlock(card.orderedBlocks[0].toContent()))
    }

    func testDeletedBlockStopsBeingSearchableImmediately() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "笔记", texts: ["保留的内容。", "要删掉的内容。"])
        await stack.service.indexAll()
        XCTAssertEqual(stack.derived.recordCount(), 2)

        let doomed = card.orderedBlocks[1]
        let ref = BlockRef(noteID: card.id.uuidString, blockID: doomed.id.uuidString)
        let orphanID = ChunkPipeline.chunkID(ref: ref, index: 0)
        stack.context.delete(doomed)
        try stack.context.save()

        await stack.service.index(noteIDs: [card.id.uuidString])

        XCTAssertEqual(stack.derived.recordCount(), 1)
        XCTAssertNil(stack.derived.record(forChunk: orphanID), "orphan 记录被删")
        let remaining = await stack.vectors.allChunkIDs()
        XCTAssertFalse(remaining.contains(orphanID), "内存索引里也不再有它 —— 否则会搜到已删除的文本")
    }

    func testDeletingANoteRemovesItsDerivedData() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "笔记", texts: ["内容。"])
        await stack.service.indexAll()
        XCTAssertEqual(stack.derived.recordCount(), 1)

        let noteID = card.id.uuidString
        stack.context.delete(card)
        try stack.context.save()
        await stack.service.noteWasDeleted(noteID)

        XCTAssertEqual(stack.derived.recordCount(), 0)
        let leftInMemory = await stack.vectors.count()
        XCTAssertEqual(leftInMemory, 0, "否则搜索会命中一篇已经不存在的笔记")
    }

    // MARK: 3 · 不变量 1 —— 被 StaleGuard 拒掉的向量不能进内存索引

    func testRejectedEmbeddingNeverEntersTheMemoryIndex() async throws {
        let stack = makeStack(provider: .some(CountingProvider(counter: EmbedCounter(),
                                                               delayNanos: 300_000_000)))
        let card = try seed(stack.context, title: "笔记", texts: ["嵌入过程中会被改掉的内容。"])
        let ref = BlockRef(noteID: card.id.uuidString, blockID: card.orderedBlocks[0].id.uuidString)
        let chunkID = ChunkPipeline.chunkID(ref: ref, index: 0)

        let indexing = Task { @MainActor in await stack.service.index(noteIDs: [card.id.uuidString]) }

        // 嵌入还在跑的时候改内容 —— provider 不会因此停下（也不该指望它停）。
        try await Task.sleep(nanoseconds: 80_000_000)
        card.orderedBlocks[0].text = "改过之后的内容。"
        try stack.context.save()
        await indexing.value

        XCTAssertNil(stack.derived.record(forChunk: chunkID), "过期结果被写入路径拒绝")
        let afterRejection = await stack.vectors.count()
        XCTAssertEqual(afterRejection, 0,
                       "内存索引也不能有它 —— 磁盘上没有的过期向量继续参与检索，等于换个地方发生同一个 bug")
        XCTAssertGreaterThan(stack.service.pendingChunks, 0, "如实记下还欠一条")

        // 那次编辑自己会触发新一轮扫描，届时索引补齐。
        await stack.service.index(noteIDs: [card.id.uuidString])
        XCTAssertNotNil(stack.derived.record(forChunk: chunkID))
        let afterRetry = await stack.vectors.count()
        XCTAssertEqual(afterRetry, 1)
        XCTAssertEqual(stack.service.pendingChunks, 0)
    }

    // MARK: 4 · 合并 + 防抖

    func testRapidEditsCoalesceIntoOnePass() async throws {
        let stack = makeStack(debounceNanos: 80_000_000)
        let card = try seed(stack.context, title: "笔记", texts: ["一次输入里会保存很多次。"])

        for _ in 0..<5 { stack.service.noteDidChange(card.id.uuidString) }
        try await Task.sleep(nanoseconds: 400_000_000)

        let coalescedCalls = await stack.counter.value()
        XCTAssertEqual(coalescedCalls, 1, "五次保存合并成一次扫描")
        XCTAssertEqual(stack.derived.recordCount(), 1)
    }

    // MARK: 5 · 没有句向量模型时

    func testWithoutProviderStateIsFailedAndKeywordStillWorks() async throws {
        let stack = makeStack(provider: .some(nil))
        try seed(stack.context, title: "笔记", texts: ["延期毕业相关的内容。"])

        await stack.service.indexAll()

        XCTAssertEqual(stack.derived.recordCount(), 0, "没有模型就没有向量，**不退回 mock**")
        XCTAssertFalse(stack.service.state.allowsVectorRetrieval, "语义路明确不可用")
        XCTAssertTrue(stack.service.state.allowsKeywordRetrieval, "关键词路不受影响")
        if case .failed = stack.service.state {} else {
            XCTFail("状态应当是 failed，得到 \(stack.service.state)")
        }
    }

    // MARK: 6 · OCR 进语料

    func testOCRTextIsExtractedAndIndexed() async throws {
        let extractor = StubImageTextExtractor(table: ["img/a.jpg": ImageTextResult(text: "答辩时间 6 月 12 日",
                                                                                   confidence: 0.9)])
        let stack = makeStack(extractor: extractor)

        let card = Card(userTitle: "现场照片")
        stack.context.insert(card)
        let image = Block(kind: .image, order: 0)
        image.imageRelativePath = "img/a.jpg"
        image.card = card
        stack.context.insert(image)
        try stack.context.save()

        await stack.service.indexAll()

        let noteID = card.id.uuidString
        XCTAssertEqual(stack.derived.ocrTextByBlockID(noteID: noteID)[image.id.uuidString],
                       "答辩时间 6 月 12 日", "OCR 作为 derived 数据落盘")
        XCTAssertEqual(stack.derived.recordCount(), 1, "图片块因为有了 OCR 文本才进得了索引")

        // 第二遍不再重新识别 —— OCR 按块哈希存，图片没变就不重跑。
        await stack.service.indexAll()
        XCTAssertEqual(stack.derived.ocrCount(), 1)
    }

    // MARK: 7 · TD-8 的出口 —— vector 路真的能命中了

    func testIndexedCorpusMakesSemanticRetrievalReturnHits() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "延期毕业", texts: [
            "我问了 advisor 能不能延期一个学期毕业。",
            "楼下那家面馆的辣椒油很香。"
        ])
        await stack.service.indexAll()

        let corpus = NoteCorpus(noteContext: stack.context, derived: stack.derived)
        let chunks = corpus.chunks(strategy: stack.service.config.chunkStrategy)
        let service = RetrievalService(provider: CountingProvider(counter: stack.counter),
                                       vectors: stack.vectors)
        let outcome = await service.retrieve(query: "延期 毕业",
                                             chunks: chunks,
                                             config: RetrievalConfig(mode: .hybrid,
                                                                     embeddingVersion: "counting-v1",
                                                                     chunkStrategy: .block, topK: 5),
                                             indexState: stack.service.state)

        XCTAssertFalse(outcome.results.isEmpty)
        XCTAssertTrue(outcome.results.contains { $0.vectorRank != nil },
                      "vector 路有命中 —— 这正是 TD-8 之前做不到的事")
        XCTAssertTrue(outcome.results.contains { $0.ref.noteID == card.id.uuidString })
    }
}
