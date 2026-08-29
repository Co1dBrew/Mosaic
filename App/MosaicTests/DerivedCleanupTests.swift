import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Derived 数据清理 —— 删除路径的完整覆盖
///
/// ## 修复的缺陷
///
/// 删除**文件夹**时，SwiftData 的 cascade 会删掉其中全部笔记，但 derived 数据在
/// **另一个 container / 另一个 store 文件**里 —— 没有任何 cascade 能到达它。
/// 于是：
///
/// ```
/// 删文件夹 → 笔记没了 → 向量还在 → 进 topK → 回查笔记失败 → 搜索页静默丢行
/// ```
///
/// 用户看到的不是一条错误结果，而是**少了一条结果**，且没有任何迹象。
/// 第 5 名被一条不存在的笔记占了位，真正第 6 名的笔记永远出不来。
///
/// ## 这一组用例覆盖的六件事（对应 §5.1 的要求）
///
/// 删一篇 · 删文件夹 · 删很多篇 · 删后重新索引 · 删后搜索 · 删后重启。
/// 外加历史孤儿的清理与对账口径。
@MainActor
final class DerivedCleanupTests: XCTestCase {

    private struct Stack {
        let notes: ModelContainer
        let derivedContainer: ModelContainer
        let context: ModelContext
        let derived: DerivedDataStore
        let vectors: InMemoryVectorStore
        let service: IndexingService
    }

    /// 用 OCR extractor 一起建栈：孤儿有三种形态（embedding / OCR / 内存索引），
    /// 不给 extractor 就只能测到其中两种。
    private struct StubExtractor: ImageTextExtractor {
        let engineIdentifier = "stub-ocr"
        func extractText(fromRelativePath path: String) async throws -> ImageTextResult {
            ImageTextResult(text: "扫描件正文 \(path)", confidence: 0.9)
        }
    }

    private func makeStack(notes: ModelContainer? = nil,
                           derivedContainer: ModelContainer? = nil) -> Stack {
        let notesContainer = notes ?? ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let dc = derivedContainer ?? ModelContainerFactory.makeDerived(inMemory: true)
        let derived = DerivedDataStore(container: dc)
        let vectors = InMemoryVectorStore()
        let service = IndexingService(provider: MockEmbeddingProvider(dimension: 32),
                                      vectors: vectors,
                                      derived: derived,
                                      noteContext: notesContainer.mainContext,
                                      extractor: StubExtractor(),
                                      config: RetrievalConfig(chunkStrategy: .block),
                                      debounceNanos: 20_000_000)
        return Stack(notes: notesContainer, derivedContainer: dc,
                     context: notesContainer.mainContext, derived: derived,
                     vectors: vectors, service: service)
    }

    @discardableResult
    private func seed(_ ctx: ModelContext, title: String, texts: [String],
                      folder: Folder? = nil, imagePath: String? = nil) throws -> Card {
        let card = Card(userTitle: title, folder: folder)
        ctx.insert(card)
        var order = 0
        for t in texts {
            let b = Block(kind: .text, order: order); order += 1
            b.text = t
            b.card = card
            ctx.insert(b)
        }
        if let imagePath {
            let b = Block(kind: .image, order: order)
            b.imageRelativePath = imagePath
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        return card
    }

    // MARK: 1 · 删一篇

    func testDeletingOneNoteRemovesAllOfItsDerivedData() async throws {
        let stack = makeStack()
        let keep = try seed(stack.context, title: "留下", texts: ["延期毕业需要提前四周申请。"])
        let drop = try seed(stack.context, title: "删掉", texts: ["搜索 beta 周五交付。"],
                            imagePath: "img/drop.jpg")
        await stack.service.indexAll()

        XCTAssertGreaterThan(stack.derived.recordCount(), 0)
        XCTAssertEqual(stack.derived.ocrCount(), 1, "图片块产出了一条 OCR")

        let dropID = drop.id.uuidString
        stack.context.delete(drop)
        try stack.context.save()
        await stack.service.noteWasDeleted(dropID)

        XCTAssertFalse(stack.derived.embeddingNoteIDs().contains(dropID), "embedding 清干净")
        XCTAssertFalse(stack.derived.ocrNoteIDs().contains(dropID), "OCR 清干净")
        let indexed = await stack.vectors.noteIDs()
        XCTAssertFalse(indexed.contains(dropID), "内存索引清干净")
        XCTAssertTrue(indexed.contains(keep.id.uuidString), "没有误伤别的笔记")

        let report = await stack.service.consistencyReport()
        XCTAssertTrue(report.isConsistent, report.summary)
    }

    // MARK: 2 · 删文件夹（这是原来漏掉的那条路径）

    func testDeletingAFolderCleansUpEveryNoteInsideIt() async throws {
        let stack = makeStack()
        let folder = Folder(name: "工作")
        stack.context.insert(folder)
        for i in 0..<5 {
            try seed(stack.context, title: "会议 \(i)", texts: ["第 \(i) 次会议纪要，讨论了排期。"],
                     folder: folder, imagePath: i == 0 ? "img/f0.jpg" : nil)
        }
        try seed(stack.context, title: "未归类", texts: ["和文件夹无关的一条笔记。"])
        await stack.service.indexAll()
        XCTAssertEqual(stack.derived.embeddingNoteIDs().count, 6)

        // 生产代码在 FolderManageView.delete(_:) 里做的两步：**先收集 id，再删**。
        let noteIDs = (folder.cards ?? []).map { $0.id.uuidString }
        XCTAssertEqual(noteIDs.count, 5)
        stack.context.delete(folder)
        try stack.context.save()
        await stack.service.notesWereDeleted(noteIDs)

        let report = await stack.service.consistencyReport()
        XCTAssertTrue(report.isConsistent, report.summary)
        XCTAssertEqual(stack.derived.embeddingNoteIDs().count, 1, "只剩未归类那一篇")
        XCTAssertEqual(stack.derived.ocrCount(), 0, "文件夹里那张图的 OCR 也清掉了")
    }

    /// 回归：修复前的行为。把 cascade 删除模拟出来但**不做** derived 清理，
    /// 对账必须把它报出来 —— 否则这一整组用例都可能在测一个恒真命题。
    func testWithoutCleanupTheOrphansAreDetectable() async throws {
        let stack = makeStack()
        let folder = Folder(name: "工作")
        stack.context.insert(folder)
        for i in 0..<3 {
            try seed(stack.context, title: "会议 \(i)", texts: ["第 \(i) 次会议纪要。"], folder: folder)
        }
        try seed(stack.context, title: "留下", texts: ["另一条。"])
        await stack.service.indexAll()

        stack.context.delete(folder)          // ← 修复前：只删笔记，不通知检索栈
        try stack.context.save()

        let report = await stack.service.consistencyReport()
        XCTAssertFalse(report.isConsistent, "漏清理必须被对账抓到")
        XCTAssertEqual(report.orphanNoteIDs.count, 3)
        XCTAssertEqual(report.orphanEmbeddingNoteIDs.count, 3)
        XCTAssertEqual(report.orphanIndexedNoteIDs.count, 3)
    }

    // MARK: 3 · 删很多篇

    func testDeletingManyNotesLeavesNoOrphans() async throws {
        let stack = makeStack()
        var ids: [String] = []
        for i in 0..<40 {
            let card = try seed(stack.context, title: "笔记 \(i)", texts: ["内容 \(i) 关于排期与预算。"])
            if i % 2 == 0 { ids.append(card.id.uuidString) }
        }
        await stack.service.indexAll()
        XCTAssertEqual(stack.derived.embeddingNoteIDs().count, 40)

        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }
            var fetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
            fetch.fetchLimit = 1
            if let card = try stack.context.fetch(fetch).first { stack.context.delete(card) }
        }
        try stack.context.save()
        await stack.service.notesWereDeleted(ids)

        let report = await stack.service.consistencyReport()
        XCTAssertTrue(report.isConsistent, report.summary)
        XCTAssertEqual(stack.derived.embeddingNoteIDs().count, 20)
        let indexedCount = await stack.vectors.count()
        XCTAssertEqual(indexedCount, 20)
    }

    // MARK: 4 · 删除之后重新索引，不会把孤儿带回来

    func testReindexAfterDeletionDoesNotResurrectDerivedData() async throws {
        let stack = makeStack()
        let drop = try seed(stack.context, title: "删掉", texts: ["会被删掉的内容。"])
        try seed(stack.context, title: "留下", texts: ["会留下的内容。"])
        await stack.service.indexAll()

        let dropID = drop.id.uuidString
        stack.context.delete(drop)
        try stack.context.save()
        await stack.service.notesWereDeleted([dropID])

        await stack.service.indexAll()                 // 全库重扫
        await stack.service.index(noteIDs: [dropID])   // 显式点名一篇已删除的笔记

        let report = await stack.service.consistencyReport()
        XCTAssertTrue(report.isConsistent, report.summary)
        XCTAssertEqual(stack.derived.embeddingNoteIDs().count, 1)
    }

    // MARK: 5 · 删除之后搜索：孤儿不能占 topK 名额

    func testSearchDoesNotSpendTopKOnDeletedNotes() async throws {
        let stack = makeStack()
        // 十篇高度相似的笔记 —— 相似是必需的：只有它们互相竞争 topK，
        // 「一个名额被孤儿占掉」才会真的把一篇活着的笔记挤出去。
        var cards: [Card] = []
        for i in 0..<10 {
            cards.append(try seed(stack.context, title: "排期 \(i)",
                                  texts: ["第 \(i) 版排期：搜索 beta 交付时间与验收安排。"]))
        }
        await stack.service.indexAll()

        let service = RetrievalService(provider: MockEmbeddingProvider(dimension: 32),
                                       vectors: stack.vectors)
        let config = RetrievalConfig(version: "cleanup-test", mode: .hybrid,
                                     embeddingProvider: "mock", embeddingVersion: "mock-v1",
                                     chunkStrategy: .block, topK: 5)
        let corpus = NoteCorpus(noteContext: stack.context, derived: stack.derived)

        // 删掉前 3 篇，**不做** derived 清理 → 孤儿会进 topK。
        let deleted = Set(cards.prefix(3).map { $0.id.uuidString })
        for card in cards.prefix(3) { stack.context.delete(card) }
        try stack.context.save()

        let dirty = await service.retrieve(query: "排期 交付 验收",
                                           chunks: corpus.chunks(strategy: .block),
                                           config: config)
        let dirtyNotes = Set(dirty.results.map { $0.ref.noteID })
        XCTAssertTrue(dirtyNotes.isDisjoint(with: deleted),
                      "已删除的笔记**永远**不出现在结果里 —— 它在语料里查不到文本")
        XCTAssertEqual(dirty.results.count, 5,
                       "而且不再少给结果：孤儿被跳过后继续往下取，Top-5 仍然是满的")

        await stack.service.notesWereDeleted(Array(deleted))

        let clean = await service.retrieve(query: "排期 交付 验收",
                                           chunks: corpus.chunks(strategy: .block),
                                           config: config)
        let cleanNotes = clean.results.map { $0.ref.noteID }
        XCTAssertTrue(Set(cleanNotes).isDisjoint(with: deleted), "清理后 topK 里没有已删除的笔记")
        XCTAssertEqual(Set(cleanNotes).count, 5, "五个名额全部给了还活着的笔记")

        // **清理前后返回的不一定是同一批笔记，这是对的。**
        //
        // 第一版这里断言了「两批相同」，实测不成立。原因：孤儿不只占 topK 名额，
        // 它同样占**候选**名额 —— vector 路只取 candidateK 条，孤儿在里面就意味着
        // 少了 3 条活着的候选进入融合。清理之后那 3 个位置让给了更深的活笔记，
        // 融合排名因此变化。
        //
        // 结论是「跳过陈旧项」只能保证不少给结果，**保证不了排名与干净索引一致**。
        // 所以清理必须真的做，不能靠检索侧兜底。这条注释就是那个理由。
        XCTAssertTrue(Set(cleanNotes).isSubset(of: Set(cards.map { $0.id.uuidString })),
                      "两次返回的都是语料里真实存在的笔记")
    }

    // MARK: 6 · 重启：历史孤儿在启动时被清掉

    func testStartupReconcilesOrphansLeftBehindByAnOlderBuild() async throws {
        // 两个 container 跨「重启」保持不变 —— 这正是历史孤儿的产生方式：
        // 上一个版本的代码删了笔记没清 derived，记录留在磁盘上。
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derivedContainer = ModelContainerFactory.makeDerived(inMemory: true)

        let first = makeStack(notes: notes, derivedContainer: derivedContainer)
        let drop = try seed(first.context, title: "旧版本删掉的", texts: ["历史遗留内容。"])
        try seed(first.context, title: "留下", texts: ["还在的内容。"])
        await first.service.indexAll()
        let dropID = drop.id.uuidString

        // 模拟旧版本：删笔记，**不通知检索栈**。
        first.context.delete(drop)
        try first.context.save()
        XCTAssertTrue(first.derived.embeddingNoteIDs().contains(dropID), "孤儿确实留在磁盘上")

        // 「重启」：新的 service，新的内存索引，同一份磁盘数据。
        let second = makeStack(notes: notes, derivedContainer: derivedContainer)
        await second.service.start()

        let report = await second.service.consistencyReport()
        XCTAssertTrue(report.isConsistent, report.summary)
        XCTAssertFalse(second.derived.embeddingNoteIDs().contains(dropID),
                       "启动时的对账清掉了历史孤儿 —— 只修未来的删除路径不够")
        let indexed = await second.vectors.noteIDs()
        XCTAssertFalse(indexed.contains(dropID))
    }

    /// 空笔记库不触发清理。读取失败与「用户真的删光了」在这一层不可区分，
    /// 而猜错方向的代价是把整份索引删掉（云端还要重新花钱）。
    func testEmptyCorpusDoesNotWipeTheIndex() async throws {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derivedContainer = ModelContainerFactory.makeDerived(inMemory: true)
        let first = makeStack(notes: notes, derivedContainer: derivedContainer)
        try seed(first.context, title: "唯一一篇", texts: ["内容。"])
        await first.service.indexAll()
        let before = first.derived.recordCount()
        XCTAssertGreaterThan(before, 0)

        // 笔记库读不出来的等价情形：一篇都没有，而 derived 里还有数据。
        let emptyNotes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let second = makeStack(notes: emptyNotes, derivedContainer: derivedContainer)
        let report = await second.service.reconcileOrphans()

        XCTAssertFalse(report.isConsistent, "如实报告不一致")
        XCTAssertEqual(second.derived.recordCount(), before, "但一条都没删")
    }
}
