import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// A stand-in AI client returning canned responses, so we can test the full
/// SummaryService → SwiftData persistence path without a network or API key.
final class MockAIClient: AIClient, @unchecked Sendable {
    let base: BaseSummaryDTO
    let update: UpdateSummaryDTO
    private(set) var baseCalls = 0
    private(set) var updateCalls = 0

    init(base: BaseSummaryDTO, update: UpdateSummaryDTO) {
        self.base = base
        self.update = update
    }

    func generateBaseSummary(config: ProviderConfig, aggregatedText: String, images: [AIImage]) async throws -> BaseSummaryDTO {
        baseCalls += 1
        return base
    }
    func generateUpdateSummary(config: ProviderConfig, previousSummaryText: String, changeSetText: String, images: [AIImage]) async throws -> UpdateSummaryDTO {
        updateCalls += 1
        return update
    }
    func testConnection(config: ProviderConfig) async throws {}
}

@MainActor
final class SummaryIntegrationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var settings: SettingsStore!
    private var mock: MockAIClient!
    private var service: SummaryService!

    override func setUp() async throws {
        container = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        context = ModelContext(container)

        let defaults = UserDefaults(suiteName: "MosaicTests.\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults, keychain: InMemoryKeychain())
        settings.provider = .kimi
        settings.modelName = "kimi-k2.6"
        settings.visionEnabled = false
        settings.setAPIKey("test-key", for: .kimi)

        mock = MockAIClient(
            base: BaseSummaryDTO(title: "测试标题", oneLiner: "一句话概述", type: "会议记录",
                                 topics: ["产品", "排期"], keyPoints: ["要点一", "要点二"], summary: "整体总结内容"),
            update: UpdateSummaryDTO(updateOneLiner: "测试更新一句话", changes: ["新增:负责人", "修改:上线时间"])
        )
        service = SummaryService(client: mock, settings: settings)
    }

    /// Helper: a folder + card + one text block, saved.
    private func makeCard(text: String = "今天开了产品评审会,确定了下个版本的范围。") throws -> (Folder, Card, Block) {
        let folder = Folder(name: "工作")
        context.insert(folder)
        let card = Card(folder: folder)
        context.insert(card)
        let block = Block(kind: .text, order: 0)
        block.text = text
        context.insert(block)
        block.card = card
        card.blocks = [block]
        try context.save()
        return (folder, card, block)
    }

    // MARK: Model + adapter

    func testCardAdaptsBlocksToContent() throws {
        let (_, card, _) = try makeCard()
        let contents = card.blockContents()
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents.first?.kind, .text)
        XCTAssertEqual(contents.first?.text, "今天开了产品评审会,确定了下个版本的范围。")
    }

    func testCascadeDeleteRemovesCardsAndBlocks() throws {
        let (folder, _, _) = try makeCard()
        context.delete(folder)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<Card>()).isEmpty, "cards cascade-deleted")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Block>()).isEmpty, "blocks cascade-deleted")
    }

    // MARK: Base summary

    func testGenerateBaseSummaryPersistsAndSnapshots() async throws {
        let (_, card, _) = try makeCard()
        try await service.generateBaseSummary(for: card)

        let summary = try XCTUnwrap(card.summary)
        XCTAssertTrue(summary.hasBase)
        XCTAssertEqual(summary.baseTitle, "测试标题")
        XCTAssertEqual(summary.baseType, "会议记录")
        XCTAssertEqual(summary.baseTopics, ["产品", "排期"])
        XCTAssertFalse(summary.snapshot.entries.isEmpty, "snapshot captured after base")
        XCTAssertEqual(mock.baseCalls, 1)
        // No pending changes immediately after summarizing.
        XCTAssertFalse(service.hasPendingChanges(for: card))
        // AI title used for display when user title is empty.
        XCTAssertEqual(card.displayTitle, "测试标题")
    }

    func testEmptyCardThrowsEmptyContent() async throws {
        let folder = Folder(name: "空"); context.insert(folder)
        let card = Card(folder: folder); context.insert(card)
        try context.save()
        do {
            try await service.generateBaseSummary(for: card)
            XCTFail("expected emptyContent")
        } catch let error as AIError {
            XCTAssertEqual(error, .emptyContent)
        }
    }

    // MARK: Incremental update

    func testUpdateSummaryAppendsLogAndPreservesBase() async throws {
        let (_, card, block) = try makeCard()
        try await service.generateBaseSummary(for: card)

        // A significant edit.
        block.text = "今天开了产品评审会,确定了下个版本范围,并决定下周三上线,新增三位负责人分工。"
        try context.save()

        let did = try await service.generateUpdateSummary(for: card, force: true)
        XCTAssertTrue(did)

        let summary = try XCTUnwrap(card.summary)
        XCTAssertEqual(summary.updateLogs?.count, 1)
        XCTAssertEqual(summary.sortedUpdateLogs.first?.updateOneLiner, "测试更新一句话")
        XCTAssertEqual(summary.sortedUpdateLogs.first?.changes.count, 2)
        // Base preserved.
        XCTAssertTrue(summary.hasBase)
        XCTAssertEqual(summary.baseTitle, "测试标题")
        XCTAssertEqual(mock.updateCalls, 1)
    }

    func testNoChangeReturnsFalseAndDoesNotAppend() async throws {
        let (_, card, _) = try makeCard()
        try await service.generateBaseSummary(for: card)
        // No edits → diff empty.
        let did = try await service.generateUpdateSummary(for: card, force: true)
        XCTAssertFalse(did)
        XCTAssertEqual(card.summary?.updateLogs?.count ?? 0, 0)
    }

    func testInsignificantEditSkippedOnAutoButRunsOnForce() async throws {
        let (_, card, block) = try makeCard()
        try await service.generateBaseSummary(for: card)

        // Tiny edit (below significance threshold).
        block.text += "。"
        try context.save()

        // Auto (non-forced) skips.
        let auto = try await service.generateUpdateSummary(for: card, force: false)
        XCTAssertFalse(auto, "tiny edit skipped on auto")
        // Snapshot intentionally not advanced → change still pending.
        XCTAssertTrue(service.hasPendingChanges(for: card))

        // Forced runs regardless.
        let forced = try await service.generateUpdateSummary(for: card, force: true)
        XCTAssertTrue(forced)
        XCTAssertEqual(card.summary?.updateLogs?.count, 1)
    }

    // MARK: Regenerate / clear

    func testRegenerateClearsLogsAndRebuildsBase() async throws {
        let (_, card, block) = try makeCard()
        try await service.generateBaseSummary(for: card)
        block.text += " 补充了一段较长的内容用于触发更新。"
        try context.save()
        _ = try await service.generateUpdateSummary(for: card, force: true)
        XCTAssertEqual(card.summary?.updateLogs?.count, 1)

        try await service.regenerateFullSummary(for: card)
        XCTAssertEqual(card.summary?.updateLogs?.count ?? 0, 0, "regenerate clears logs")
        XCTAssertTrue(card.summary?.hasBase == true)
        // Orphaned logs are deleted, not left in the store.
        XCTAssertTrue(try context.fetch(FetchDescriptor<UpdateLogEntity>()).isEmpty)
    }

    func testClearSummaryRemovesEverything() async throws {
        let (_, card, _) = try makeCard()
        try await service.generateBaseSummary(for: card)
        XCTAssertNotNil(card.summary)

        service.clearSummary(for: card)
        XCTAssertNil(card.summary)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AISummaryEntity>()).isEmpty)
    }

    // MARK: Sorting

    func testFolderSortsCardsByUpdatedAtDescending() throws {
        let folder = Folder(name: "排序"); context.insert(folder)
        let older = Card(folder: folder); context.insert(older)
        older.updatedAt = Date(timeIntervalSince1970: 1000)
        let newer = Card(folder: folder); context.insert(newer)
        newer.updatedAt = Date(timeIntervalSince1970: 2000)
        try context.save()
        XCTAssertEqual(folder.sortedCards.first?.id, newer.id, "newest first")
    }
}
