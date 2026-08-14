import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # 5.10 —— Result → Note 落点（`SEARCH_CONTRACT.md` §3）
///
/// 内核 `SearchLanding` 的 checks 证明**几何与时序的数值**符合契约；
/// 这里证明**执行顺序**符合契约：先展开转写再滚动、高亮延迟到转场之后、
/// 用户一动就取消、anchor 失效时安静退化。
@MainActor
final class SearchLandingTests: XCTestCase {

    private func makeController() -> SearchLandingController { SearchLandingController() }

    // MARK: 1 · 四类 block 命中：滚动 + 高亮

    func testBlockAnchorScrollsAndHighlightsThenFadesOut() async throws {
        let controller = makeController()
        var scrolled: [String] = []

        controller.land(anchor: .block("b1"), existingBlockIDs: ["b1", "b2"]) { scrolled.append($0) }

        // 高亮不能在转场里就出现。
        XCTAssertNil(controller.highlightedBlockID, "0ms 时还没有高亮 —— 转场中闪高亮会被动画吃掉")
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(scrolled, ["b1"], "定位在高亮之前完成")

        try await Task.sleep(nanoseconds: 150_000_000)   // 累计 ~0.21s > 0.15s
        XCTAssertEqual(controller.highlightedBlockID, "b1")
        XCTAssertEqual(controller.highlightOpacity, 1, "出现即全不透明")

        // 2.0s 保持 + 0.4s 淡出。
        try await Task.sleep(nanoseconds: 2_100_000_000)
        XCTAssertEqual(controller.highlightOpacity, 0, "保持 2.0s 之后开始淡出")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(controller.highlightedBlockID, "淡出结束后不再有高亮")
    }

    // MARK: 2 · 音频命中：先展开转写，再滚动

    func testTranscriptAnchorExpandsBeforeScrolling() async throws {
        let controller = makeController()
        var expandedWhenScrolled: String??

        controller.land(anchor: .transcript("audio-1"), existingBlockIDs: ["audio-1"]) { _ in
            expandedWhenScrolled = controller.expandedTranscriptBlockID
        }
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(controller.expandedTranscriptBlockID, "audio-1")
        XCTAssertTrue(controller.expandsTranscript("audio-1"))
        XCTAssertEqual(expandedWhenScrolled ?? nil, "audio-1",
                       "滚动发生时转写**已经**展开 —— 展开改变布局高度，同帧滚动会滚到展开前的位置")
    }

    // MARK: 3 · Title 命中：不滚动、不高亮

    func testTopAnchorNeitherScrollsNorHighlights() async throws {
        let controller = makeController()
        var scrolled = false
        controller.land(anchor: .top, existingBlockIDs: ["b1"]) { _ in scrolled = true }
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(scrolled, "标题命中落在笔记顶部，不滚动")
        XCTAssertNil(controller.highlightedBlockID, "标题命中不高亮")
        XCTAssertEqual(controller.anchor, .top)
    }

    // MARK: 4 · anchor 失效：安静退化

    func testMissingBlockDegradesToTopWithoutError() async throws {
        let controller = makeController()
        var scrolled = false
        // 索引 stale / block 已被删。
        controller.land(anchor: .block("deleted"), existingBlockIDs: ["b1"]) { _ in scrolled = true }
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(controller.anchor, .top, "退化为 .top")
        XCTAssertFalse(scrolled)
        XCTAssertNil(controller.highlightedBlockID, "不报错、不提示 —— 用户要找的笔记还在")
    }

    // MARK: 5 · 可中断

    func testUserInteractionCancelsHighlightImmediately() async throws {
        let controller = makeController()
        controller.land(anchor: .block("b1"), existingBlockIDs: ["b1"]) { _ in }
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(controller.highlightOpacity, 1)

        controller.interrupt()
        XCTAssertEqual(controller.highlightOpacity, 0, "立即开始淡出，不等 2.0s 走完")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(controller.highlightedBlockID)

        // 幂等：手势会连续触发很多次，不该重启一遍淡出。
        controller.interrupt()
        XCTAssertNil(controller.highlightedBlockID)
    }

    /// 打断发生在高亮出现**之前**（用户在转场里就开始滑）——
    /// 那之后不该再冒出来一个高亮。
    func testInterruptBeforeHighlightAppearsPreventsIt() async throws {
        let controller = makeController()
        controller.land(anchor: .block("b1"), existingBlockIDs: ["b1"]) { _ in }
        try await Task.sleep(nanoseconds: 30_000_000)
        controller.interrupt()

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(controller.highlightedBlockID, "被打断之后高亮不再出现")
        XCTAssertEqual(controller.highlightOpacity, 0)
    }

    // MARK: 6 · 只落一次点

    func testLandingHappensOnlyOnce() async throws {
        let controller = makeController()
        var scrollCount = 0
        controller.land(anchor: .block("b1"), existingBlockIDs: ["b1"]) { _ in scrollCount += 1 }
        controller.land(anchor: .block("b2"), existingBlockIDs: ["b1", "b2"]) { _ in scrollCount += 1 }
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(scrollCount, 1, "onAppear 可能多次触发，但落点只做一次 —— 否则会吞掉用户的滚动位置")
        XCTAssertEqual(controller.highlightedBlockID, "b1")
    }

    // MARK: 7 · 搜索结果确实带着 anchor 出来

    func testSearchResultsCarryAnchorFromRetrievalLayer() async throws {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derivedContainer = ModelContainerFactory.makeDerived(inMemory: true)
        let derived = DerivedDataStore(container: derivedContainer)
        let ctx = notes.mainContext

        let card = Card(userTitle: "会议记录")
        ctx.insert(card)
        let text = Block(kind: .text, order: 0)
        text.text = "排期结论：下周三前给出方案。"
        text.card = card
        ctx.insert(text)
        let audio = Block(kind: .audio, order: 1)
        audio.audioRelativePath = "a.m4a"
        audio.transcript = "录音里提到延期毕业的具体流程。"
        audio.card = card
        ctx.insert(audio)
        try ctx.save()

        let vm = SearchViewModel(provider: nil, vectors: InMemoryVectorStore(),
                                 derived: derived, noteContext: ctx,
                                 keywordDebounceNanos: 0, semanticDebounceNanos: 0)
        vm.queryChanged("延期 毕业")
        try await Task.sleep(nanoseconds: 300_000_000)

        let row = try XCTUnwrap(vm.rows.first)
        XCTAssertEqual(row.anchor, .transcript(audio.id.uuidString),
                       "转写命中给出 .transcript anchor —— 由检索层决定，UI 不猜")

        vm.queryChanged("排期 结论")
        try await Task.sleep(nanoseconds: 300_000_000)
        let textRow = try XCTUnwrap(vm.rows.first)
        XCTAssertEqual(textRow.anchor, .block(text.id.uuidString), "正文命中给出 .block anchor")
    }
}
