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

    /// - Parameter mode: 这个 stack 的**生产配置**走哪条路。
    ///
    ///   默认是 `.hybrid`（= `RetrievalConfig.localHybridExperimental` 那一路），
    ///   **不是**当前的生产配置。理由：这个文件里多数用例验的是检索**机制** ——
    ///   两条通道各自防抖、慢通道的长度门控、索引不可用时降级 ——
    ///   而机制只有在两条通道都在的时候才验得动。用 keyword 跑它们，
    ///   每一条都会因为「慢通道压根没启动」而通过，那是假绿。
    ///
    ///   当前生产配置（keyword）自己的行为由 `testProductionIsKeywordOnly…`
    ///   那两条单独验。
    /// - Parameter maintainsVectorIndex: 覆盖「这次构建要不要维护向量索引」。
    ///   `nil` = 跟着构建配置走（测试跑在 Debug 下，于是恒为 true）。
    ///   传 `false` 才能走到 **Release + keyword 生产**那条分支 ——
    ///   不传的话那条分支在测试里根本执行不到。
    private func makeStack(provider: (any EmbeddingProvider)?? = nil,
                           mode: RetrievalMode = .hybrid,
                           maintainsVectorIndex: Bool? = nil) -> Stack {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = DerivedDataStore(container: ModelContainerFactory.makeDerived(inMemory: true))
        let vectors = InMemoryVectorStore()
        let resolved: (any EmbeddingProvider)? = provider ?? MockEmbeddingProvider(dimension: 32)
        let indexing = IndexingService(provider: resolved,
                                       vectors: vectors,
                                       derived: derived,
                                       noteContext: notes.mainContext,
                                       config: RetrievalConfig(mode: mode, chunkStrategy: .block),
                                       maintainsVectorIndex: maintainsVectorIndex)
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
        XCTAssertTrue(titleRow.excerpt.highlights.isEmpty, "excerpt 里不做高亮")
        XCTAssertFalse(titleRow.excerpt.text.isEmpty, "excerpt 槽位仍有内容（fallback 第 2 级）")

        // 但它**是**字面命中。
        //
        // 原来这里断言 `XCTAssertFalse(titleRow.hasKeywordHit)`，把「没有可高亮的
        // 片段」与「这一页没有字面命中」混成了一件事。后果在模拟器上看到了：
        // 搜一个标签，结果行标题一模一样，顶部却写着「没有完全匹配的关键词」。
        XCTAssertTrue(titleRow.hasKeywordHit, "标题命中算字面命中 —— 用户搜的词就印在标题上")
        XCTAssertFalse(vm.showsSemanticOnlyNotice,
                       "所以整页不该显示「没有完全匹配的关键词」")
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

    // MARK: 7 · 生产配置是 keyword —— 语义那一整条不发生

    /// `PRODUCTION_RETRIEVAL = KEYWORD`。这条验的是**运行时真的照做了**，
    /// 而不只是常量写着 keyword。
    ///
    /// 判据选 `capability`：语义路不在这一版产品里，状态栏就不该谈论它。
    /// 之前的行为是 —— 没有 provider → `semanticUnavailable` →
    /// 常驻一行「智能搜索暂不可用」加一个「重试」按钮，
    /// 而其实没有任何东西坏掉。**没承诺过的能力，不存在「不可用」。**
    func testProductionIsKeywordOnlyAndDoesNotAdvertiseSemantics() async throws {
        // 生产配置 = `RetrievalConfig.production`（keyword），provider 故意给 nil：
        // 这正是「本机没有句向量模型」那台设备上的情形。
        let stack = makeStack(provider: .some(nil), mode: RetrievalConfig.production.mode)
        try seed(stack.context, title: "延期毕业", texts: ["延期一个学期毕业。"])
        await stack.indexing.indexAll()

        XCTAssertEqual(RetrievalConfig.production.mode, .keyword,
                       "前置：产品决策是 keyword —— 改了这里就要改这条用例")

        let vm = makeViewModel(stack)
        try await search(vm, "延期毕业的流程是什么")

        XCTAssertEqual(vm.capability, .full,
                       "纯词法生产下 capability 必须是 full —— 没有任何东西不可用")
        XCTAssertFalse(vm.rows.isEmpty, "词法路照常出结果")
        XCTAssertEqual(vm.phase, .ready)
    }

    /// 发布构建 + keyword 生产时，索引状态**不该**卡在「建立中」。
    ///
    /// 这一条防的是修复的反面：如果 `IndexingService` 一边不做嵌入、
    /// 一边仍把这些 chunk 记成 pending，`IndexStateMachine` 会永远返回 `.building` ——
    /// 用户看到一个永远转不完的「正在准备智能搜索…」。
    ///
    /// **`maintainsVectorIndex: false` 是必需的**：测试跑在 Debug 下，
    /// 而 Debug 构建会照常维护向量索引（Developer Tools 的实验臂要用它）。
    /// 不覆盖的话这条用例测的是 Debug 的行为，而不是用户装的那一份。
    func testKeywordProductionLeavesIndexReadyRatherThanForeverBuilding() async throws {
        let stack = makeStack(provider: .some(nil), mode: .keyword, maintainsVectorIndex: false)
        try seed(stack.context, title: "排期", texts: ["下周三评审。", "会后同步结论。"])
        await stack.indexing.start()

        XCTAssertEqual(stack.indexing.state, .ready,
                       "keyword 生产下索引没有欠着的工作 —— 状态是 ready，不是 building/failed")
        XCTAssertEqual(stack.indexing.pendingChunks, 0,
                       "不做的事不该记成「还欠着」")

        // 反面：**带着 Developer Tools 的构建照常建索引**，因为实验臂要拿它做对比。
        // 两条一起才说明这个闸门是「按理由开关」，不是「一律不建」。
        let devStack = makeStack(provider: nil, mode: .keyword, maintainsVectorIndex: true)
        try seed(devStack.context, title: "排期", texts: ["下周三评审。"])
        await devStack.indexing.start()
        XCTAssertGreaterThan(devStack.indexing.indexedChunks, 0,
                             "带 Developer Tools 的构建仍然建索引 —— 否则 local-hybrid 实验臂没有对照物")
    }

    // MARK: 8 · 归一化缓存必须跨查询存活

    /// # 缓存实现了、测过了、基准跑过了 —— 但没有到达用户
    ///
    /// `retrieve` 每次都新建一个 `RetrievalService`，而它的 `normalizedText`
    /// 默认参数是 `NormalizedTextCache()` —— 于是**每一次按键都拿到一个空缓存**，
    /// 线上永远走冷路径（真机 20k 上冷 103.0 ms vs 热 67.6 ms）。
    ///
    /// 这类缺陷不会让任何既有测试变红：两条路的**结果逐位相同**，只是慢。
    /// 所以断言不能断结果，只能断「第二次查询确实更省」—— 这里断的是
    /// 缓存里有没有留下东西。
    func testNormalizedCacheSurvivesAcrossQueriesInASearchSession() async throws {
        let stack = makeStack(provider: .some(nil), mode: .keyword)
        for i in 0..<40 {
            try seed(stack.context, title: "笔记\(i)", texts: ["第 \(i) 段 关于排期与延期毕业的记录。"])
        }
        await stack.indexing.indexAll()

        let vm = makeViewModel(stack)
        try await search(vm, "排期")
        let afterFirst = await vm.normalizedCacheCountForTesting
        XCTAssertGreaterThan(afterFirst, 0,
                             "第一次查询之后缓存里必须有东西 —— 没有就说明每次查询都新建了一个空缓存")

        try await search(vm, "延期")
        let afterSecond = await vm.normalizedCacheCountForTesting
        XCTAssertEqual(afterSecond, afterFirst,
                       "第二次查询复用同一份缓存（语料没变，条目数不该重新长起来）")
    }
}
