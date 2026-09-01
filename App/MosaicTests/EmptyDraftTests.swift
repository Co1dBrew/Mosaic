import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # 空白新建草稿不该变成一条永久笔记
///
/// 内核那一层（`NoteDraftChecks`）证明的是**判定规则**；这一层证明的是
/// **规则接上了真实的 SwiftData 模型**：`Card.blockContents()` 有没有把
/// 图片 / 录音 / 文档 / 链接如实映射进去，`EmptyDraftSweep` 会不会误伤。
///
/// 两层都要有。只测内核的话，「`Card` 忘了把 `imageRelativePath` 映射成
/// `imageAssetRef`」这种缺陷完全测不出来 —— 而它的后果是**删掉用户刚拍的照片**。
@MainActor
final class EmptyDraftTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() {
        super.setUp()
        container = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @discardableResult
    private func makeCard(title: String = "", tags: [String] = [],
                          configure: (Card) -> Void = { _ in }) -> Card {
        let card = Card(userTitle: title)
        context.insert(card)
        // 数组属性必须**插入之后**再赋值：未入上下文的 @Model 上写数组会在
        // SwiftData 内部 trap（整个测试进程直接挂掉，看起来像用例失败）。
        if !tags.isEmpty { card.tags = tags }
        configure(card)
        try? context.save()
        return card
    }

    private func addBlock(_ card: Card, kind: BlockKind, configure: (Block) -> Void) {
        let block = Block(kind: kind, order: (card.blocks ?? []).count)
        block.card = card
        context.insert(block)
        configure(block)
    }

    private func hasContent(_ card: Card) -> Bool {
        NoteDraftPolicy.hasMeaningfulContent(title: card.userTitle,
                                             tags: card.tags,
                                             blocks: card.blockContents())
    }

    private func noteCount() -> Int {
        (try? context.fetch(FetchDescriptor<Card>()))?.count ?? 0
    }

    // MARK: 1 · 真实模型 → 判定的映射

    /// 一条「点了新建什么都没写」的笔记：空标题 + 一个空文字块
    /// （空文字块是 `ensureTrailingTextBlock` 建的，不是用户写的）。
    func testFreshEmptyCardHasNoMeaningfulContent() {
        let card = makeCard()
        addBlock(card, kind: .text) { $0.text = "" }
        try? context.save()
        XCTAssertFalse(hasContent(card), "空标题 + 空文字块 = 没有内容")
    }

    func testWhitespaceOnlyCardHasNoMeaningfulContent() {
        let card = makeCard(title: "   ")
        addBlock(card, kind: .text) { $0.text = "\n\n\t " }
        try? context.save()
        XCTAssertFalse(hasContent(card), "纯空白不算内容")
    }

    /// **R5 · 媒体笔记必须留下。**
    ///
    /// 标题空、正文空、只有一个附件 —— 这一类最容易被
    /// 「`text.isEmpty` 就删」的实现误杀，而误杀的是用户刚拍的照片、刚录的音。
    func testMediaOnlyCardsAreAlwaysMeaningful() {
        let cases: [(String, BlockKind, (Block) -> Void)] = [
            ("图片", .image, { $0.imageRelativePath = "img/p1.jpg" }),
            ("录音", .audio, { $0.audioRelativePath = "aud/r1.m4a" }),
            ("文档", .file,  { $0.fileName = "合同.pdf" }),
            ("链接", .link,  { $0.url = "https://example.test/a" }),
        ]
        for (label, kind, configure) in cases {
            let card = makeCard()
            addBlock(card, kind: kind, configure: configure)
            try? context.save()
            XCTAssertTrue(hasContent(card),
                          "只有\(label)的笔记必须算「有内容」—— 删掉它就是删掉用户的媒体")
        }
    }

    func testTitleOrTagAloneIsMeaningful() {
        XCTAssertTrue(hasContent(makeCard(title: "会议纪要")), "只有标题也算")
        XCTAssertTrue(hasContent(makeCard(tags: ["学业"])), "只有标签也算")
    }

    // MARK: 2 · 启动清扫：清幽灵，不误伤

    /// App 在新建的空笔记里被划掉 → `onDisappear` 没跑到 → 数据库里留下一条幽灵。
    /// 下次启动必须清掉它。
    func testSweepRemovesGhostDraftsOnly() {
        // 幽灵两条：一条纯空，一条只有空白。
        let ghost1 = makeCard()
        addBlock(ghost1, kind: .text) { $0.text = "" }
        let ghost2 = makeCard(title: "  ")
        addBlock(ghost2, kind: .text) { $0.text = "\n" }

        // 必须留下的四条：文字 / 标题 / 标签 / 只有图片。
        let real1 = makeCard()
        addBlock(real1, kind: .text) { $0.text = "排期定在下周三" }
        let real2 = makeCard(title: "只有标题")
        let real3 = makeCard(tags: ["报销"])
        let real4 = makeCard()
        addBlock(real4, kind: .image) { $0.imageRelativePath = "img/x.jpg" }
        try? context.save()

        XCTAssertEqual(noteCount(), 6, "前置：6 条")

        let removed = EmptyDraftSweep.sweep(context: context)

        XCTAssertEqual(removed.count, 2, "只清掉两条幽灵")
        XCTAssertEqual(noteCount(), 4, "四条真笔记一条都不能少")
        XCTAssertTrue(removed.contains(ghost1.id.uuidString))
        XCTAssertTrue(removed.contains(ghost2.id.uuidString))
        // 逐条点名剩下的 —— 「还剩 4 条」证明不了剩下的是**哪** 4 条。
        let survivors = Set(((try? context.fetch(FetchDescriptor<Card>())) ?? []).map(\.id))
        for (label, card) in [("正文", real1), ("标题", real2), ("标签", real3), ("图片", real4)] {
            XCTAssertTrue(survivors.contains(card.id), "只有\(label)的笔记必须活下来")
        }
    }

    /// 清扫是幂等的：跑第二遍什么都不该动。
    /// 不幂等意味着它依赖某种一次性状态，而那种状态迟早会错。
    func testSweepIsIdempotent() {
        let ghost = makeCard()
        addBlock(ghost, kind: .text) { $0.text = "" }
        makeCard(title: "留下")
        try? context.save()

        XCTAssertEqual(EmptyDraftSweep.sweep(context: context).count, 1)
        XCTAssertEqual(EmptyDraftSweep.sweep(context: context).count, 0, "第二遍无事可做")
        XCTAssertEqual(noteCount(), 1)
    }

    /// 衍生文本（OCR / 转写）兜底：媒体引用丢了，但识别出来的字还在 ——
    /// 那时这条笔记里仍然有用户能搜到的东西，不该被当成空的删掉。
    func testSweepKeepsCardsThatOnlyHaveDerivedText() {
        let card = makeCard()
        addBlock(card, kind: .text) { $0.text = "" }
        try? context.save()

        let removed = EmptyDraftSweep.sweep(context: context) { c in
            c.id == card.id ? ["发票金额 128 元"] : []
        }
        XCTAssertTrue(removed.isEmpty, "有 OCR 文本的笔记不该被清掉")
        XCTAssertEqual(noteCount(), 1)
    }

    // MARK: 3 · 已有笔记永远不自动删

    /// 打开一条老笔记、把内容全删空、退出 —— **不能替他删掉这条笔记**。
    /// 「清空」和「删除」是两个不同的意图。
    func testExistingNoteEmptiedByUserIsNotDiscarded() {
        let card = makeCard(title: "老笔记")
        addBlock(card, kind: .text) { $0.text = "原来有内容" }
        try? context.save()

        card.userTitle = ""
        (card.blocks ?? []).forEach { $0.text = "" }
        try? context.save()

        XCTAssertFalse(
            NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: false,
                                                title: card.userTitle,
                                                tags: card.tags,
                                                blocks: card.blockContents()),
            "已有笔记被清空 → 不丢弃")
        XCTAssertTrue(
            NoteDraftPolicy.shouldDiscardOnExit(isNewDraft: true,
                                                title: card.userTitle,
                                                tags: card.tags,
                                                blocks: card.blockContents()),
            "同样的内容，如果是新建草稿则丢弃 —— isNewDraft 真的在起作用")
    }
}
