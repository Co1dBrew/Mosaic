import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # TD-7 —— 生产搜索接入 Hybrid
///
/// MosaicKit 的 checks 证明呈现层的纯函数；这里证明它接上真实笔记、真实索引、
/// 真实防抖之后，`SEARCH_CONTRACT.md` 的不变量仍然成立 ——
/// 尤其是 **I3（keyword 结果与 capability 无关）**，那是整个 Progressive Enhancement
/// 的可执行形式。
@MainActor
final class ProductionSearchTests: XCTestCase {

    private struct Stack {
        /// **必须持有 container**：只留 `ModelContext` 的话容器会被释放，
        /// 之后任何一次插入都会在 SwiftData 内部 trap（整个测试进程直接退出）。
        let notes: ModelContainer
        let context: ModelContext
        let derived: DerivedDataStore
        let vectors: InMemoryVectorStore
        let indexing: IndexingService
        let provider: (any EmbeddingProvider)?
    }

    private func makeStack(provider: (any EmbeddingProvider)?? = nil) -> Stack {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = DerivedDataStore(container: ModelContainerFactory.makeDerived(inMemory: true))
        let vectors = InMemoryVectorStore()
        let resolved: (any EmbeddingProvider)? = provider ?? MockEmbeddingProvider(dimension: 32)
        let indexing = IndexingService(provider: resolved,
                                       vectors: vectors,
                                       derived: derived,
                                       noteContext: notes.mainContext,
                                       config: RetrievalConfig(chunkStrategy: .block))
        return Stack(notes: notes, context: notes.mainContext, derived: derived,
                     vectors: vectors, indexing: indexing, provider: resolved)
    }

    private func makeViewModel(_ stack: Stack) -> SearchViewModel {
        SearchViewModel(provider: stack.provider,
                        vectors: stack.vectors,
                        indexing: stack.indexing,
                        derived: stack.derived,
                        noteContext: stack.context,
                        keywordDebounceNanos: 20_000_000,
                        semanticDebounceNanos: 60_000_000)
    }

    @discardableResult
    private func seed(_ ctx: ModelContext, title: String, texts: [String],
                      tags: [String] = []) throws -> Card {
        let card = Card(userTitle: title)
        ctx.insert(card)
        // 数组属性必须**插入之后**再赋值：未入上下文的 @Model 上写数组会在
        // SwiftData 内部 trap（整个测试进程会直接挂掉，看起来像用例失败）。
        if !tags.isEmpty { card.tags = tags }
        for (i, t) in texts.enumerated() {
            let b = Block(kind: .text, order: i)
            b.text = t
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        return card
    }

    private func search(_ vm: SearchViewModel, _ query: String,
                        settle: UInt64 = 400_000_000) async throws {
        vm.queryChanged(query)
        try await Task.sleep(nanoseconds: settle)
    }

    // MARK: 1 · 结果行是契约里的三个槽位

    func testResultsCarryMatchedExcerptWithHighlights() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "延期毕业", texts: [
            "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认。"
        ])
        try seed(stack.context, title: "面馆", texts: ["楼下那家面馆的辣椒油很香。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "延期 毕业")

        XCTAssertEqual(vm.phase, .ready)
        XCTAssertEqual(vm.rows.first?.noteID, card.id.uuidString)
        let row = try XCTUnwrap(vm.rows.first)
        XCTAssertFalse(row.excerpt.text.isEmpty, "Matched Excerpt 是主槽位，不能空")
        XCTAssertTrue(row.hasKeywordHit, "字面命中要有高亮 —— 这是「为什么相关」的解释")

        // 高亮区间必须落在 excerpt 坐标系内：UI 直接拿它切字符串。
        let chars = Array(row.excerpt.text)
        XCTAssertTrue(row.excerpt.highlights.allSatisfy { $0.end <= chars.count })
        XCTAssertFalse(vm.showsSemanticOnlyNotice, "有高亮就不显示「以下是相关内容」")

        // 无关的那篇不该进来（keyword AND 语义）。
        XCTAssertFalse(vm.rows.contains { $0.noteID != card.id.uuidString && $0.hasKeywordHit })
    }

    // MARK: 2 · I3 —— 语义不可用时 keyword 照常

    func testKeywordResultsSurviveWithoutAnyEmbeddingProvider() async throws {
        // provider = nil：本机没有句向量模型（iOS 上的真实情况，TD-9）。
        let stack = makeStack(provider: .some(nil))
        try seed(stack.context, title: "延期毕业", texts: ["我问了 advisor 能不能延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        vm.refreshCapability()
        XCTAssertEqual(vm.capability, .semanticUnavailable, "能力如实降级")

        try await search(vm, "延期")
        XCTAssertEqual(vm.phase, .ready, "keyword 结果照常")
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertTrue(vm.rows[0].hasKeywordHit)
    }

    /// 索引还在建立中时，keyword 也必须照常 —— I3 对每一种 capability 都成立。
    func testKeywordResultsSurviveWhileIndexIsUnavailable() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["我问了 advisor 能不能延期一个学期毕业。"])
        // 故意不建索引：内存索引为空，语义路无从命中。
        let vm = makeViewModel(stack)
        try await search(vm, "延期")

        XCTAssertEqual(vm.phase, .ready)
        XCTAssertEqual(vm.rows.count, 1, "没有索引也能按关键词找到")
    }

    // MARK: 3 · 两级触发与取消

    func testShortQueryNeverTriggersSemanticChannel() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        // 单个汉字：低于长度阈值，只走 keyword。
        try await search(vm, "延")
        XCTAssertEqual(vm.phase, .ready)
        XCTAssertFalse(SemanticGate.shouldRunSemantic(query: "延"))
    }

    func testRapidTypingKeepsOnlyTheLatestQueryResults() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["我问了 advisor 能不能延期一个学期毕业。"])
        try seed(stack.context, title: "合同评审", texts: ["今天把合同评审的三处修改整理好了。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        // 连续输入：前面几次都应当被取消，只有最后一次的结果落地。
        vm.queryChanged("延")
        vm.queryChanged("延期")
        vm.queryChanged("合同")
        try await Task.sleep(nanoseconds: 400_000_000)

        // 榜首必须属于最后那个 query。（不断言总条数：语义路没有相关性下限，
        // 会把整个语料按余弦排下来 —— 见 TD-10。）
        XCTAssertEqual(vm.card(for: vm.rows[0].noteID)?.displayTitle, "合同评审",
                       "旧 query 的结果不得覆盖新 query")
        XCTAssertTrue(vm.rows[0].hasKeywordHit, "榜首是字面命中的那条")
    }

    /// §4.3：`.searching` 保留上一次结果 —— 清空会造成每次按键的白屏闪烁。
    func testSearchingKeepsPreviousResults() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["我问了 advisor 能不能延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "延期")
        XCTAssertEqual(vm.rows.count, 1)

        vm.queryChanged("延期毕")            // 立刻检查，防抖还没到
        XCTAssertEqual(vm.phase, .searching)
        XCTAssertEqual(vm.rows.count, 1, "检索中仍显示上一次结果")

        // 离屏即取消：防抖里挂着的任务不该在用例结束后还去碰主上下文。
        vm.cancelPendingWork()
    }

    // MARK: 4 · 标题与标签仍然搜得到（不进语料，但是 lexical signal）

    /// 标题与标签**不进语料**（§2.8），所以只有把它们作为 lexical signal 补回来，
    /// 「按标题找笔记」这个既有行为才不会静默消失。
    /// 用 provider = nil 跑：语义路一关，唯一能让这两篇进榜的就是 lexical 通道。
    func testTitleAndTagMatchesStillAppear() async throws {
        let stack = makeStack(provider: .some(nil))
        let byTitle = try seed(stack.context, title: "报销流程", texts: ["与标题无关的正文内容。"])
        let byTag = try seed(stack.context, title: "随手记", texts: ["另一段无关正文。"], tags: ["报销"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "报销")

        let ids = Set(vm.rows.map(\.noteID))
        XCTAssertTrue(ids.contains(byTitle.id.uuidString), "按标题仍然搜得到")
        XCTAssertTrue(ids.contains(byTag.id.uuidString), "按标签仍然搜得到")

        // 标题命中：落点是笔记顶部，不滚动、不高亮（§3.2 / §2.4）。
        let titleRow = try XCTUnwrap(vm.rows.first { $0.noteID == byTitle.id.uuidString })
        XCTAssertEqual(titleRow.anchor, .top)
        XCTAssertFalse(titleRow.hasKeywordHit)
        XCTAssertFalse(titleRow.excerpt.text.isEmpty, "excerpt 槽位仍有内容（fallback 第 2 级）")
    }

    // MARK: 5 · 空态与清空

    func testEmptyQueryReturnsToIdleAndClearsResults() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "延期")
        XCTAssertEqual(vm.phase, .ready)

        vm.queryChanged("   ")
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertFalse(vm.showsSemanticOnlyNotice)
    }

    /// `.noResults` 这个状态必须真的可达 —— §4.5 为它写了三套分叉文案。
    /// 语义不可用时（iOS 上的现状）它由 keyword 通道决定，行为明确。
    func testNoMatchesReportsNoResultsWhenSemanticIsUnavailable() async throws {
        let stack = makeStack(provider: .some(nil))
        try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "完全不存在的内容")
        XCTAssertEqual(vm.phase, .noResults)
        XCTAssertTrue(vm.rows.isEmpty)
    }

    /// **TD-10 —— 已知缺口，此用例记录现状而不是认可它。**
    ///
    /// 向量检索没有相关性下限：`InMemoryVectorStore.search` 按余弦排完取 Top K，
    /// 再离谱的 query 也会拿回整个语料。后果是语义可用时 `.noResults` 几乎不可达。
    ///
    /// **不在这里随手加一个阈值**：本项目已实测 `NLEmbedding` 的余弦绝对值没有解释力
    /// （相关 0.944 / 无关 0.917，只差 0.027），拍一个数字进去等于编数据。
    /// 它要由 Golden Set + 一组「本就不该有答案」的负例 query 来定，
    /// 而那组负例现在还不存在。
    func testSemanticChannelCurrentlyHasNoRelevanceFloor() async throws {
        let stack = makeStack()
        try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "完全不存在的内容")

        XCTAssertEqual(vm.phase, .ready, "现状：语义路把整个语料按余弦排下来")
        XCTAssertTrue(vm.showsSemanticOnlyNotice,
                      "至少这一行说明是对的：整页零字面命中时告诉用户「以下是相关内容」")
    }

    // MARK: 6 · 结果被删掉的笔记不会留在榜上

    func testDeletedNoteDisappearsFromNextSearch() async throws {
        let stack = makeStack()
        let card = try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "延期")
        XCTAssertEqual(vm.rows.count, 1)

        let noteID = card.id.uuidString
        stack.context.delete(card)
        try stack.context.save()
        await stack.indexing.noteWasDeleted(noteID)

        try await search(vm, "延期")
        XCTAssertTrue(vm.rows.isEmpty, "笔记删了就不该再出现在结果里")
    }
}
