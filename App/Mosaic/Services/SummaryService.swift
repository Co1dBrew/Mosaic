import Foundation
import SwiftData
import MosaicKit

/// Orchestrates AI summary generation: gathers card content from SwiftData,
/// builds the request via MosaicKit, calls the AI, and persists the results
/// (PRD §4.5 / §4.6). Model mutations run on the main actor; image compression
/// and networking run off it (PRD §6.3).
@MainActor
final class SummaryService {
    private let client: AIClient
    private let settings: SettingsStore
    private let imagePipeline: ImagePipeline
    private let limits: AggregationLimits

    init(
        client: AIClient = URLSessionAIClient(),
        settings: SettingsStore,
        imagePipeline: ImagePipeline = ImagePipeline(),
        limits: AggregationLimits = .default
    ) {
        self.client = client
        self.settings = settings
        self.imagePipeline = imagePipeline
        self.limits = limits
    }

    // MARK: Base summary

    /// Generates (or regenerates) the base summary for a card (PRD §4.5 A).
    func generateBaseSummary(for card: Card) async throws {
        let config = try resolveConfig()
        let title = card.userTitle
        let blocks = card.blockContents()
        let aggregated = CardContentAggregator.aggregate(title: title, blocks: blocks, limits: limits)

        let imagePaths = imagePathsForBase(card)
        let images = config.supportsVision ? await loadImages(paths: imagePaths) : []

        if aggregated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            throw AIError.emptyContent
        }

        let dto = try await client.generateBaseSummary(config: config, aggregatedText: aggregated, images: images)

        let summary = ensureSummary(for: card)
        summary.applyBase(dto, provider: config.provider.displayName, model: config.model)
        summary.snapshot = SummarySnapshot.make(from: blocks)
        try? card.modelContext?.save()
    }

    /// "Regenerate full summary" — archive/clear old base + logs, then regenerate
    /// (PRD §4.5 manual "重新生成完整总结").
    func regenerateFullSummary(for card: Card) async throws {
        if let summary = card.summary {
            for log in summary.updateLogs ?? [] { card.modelContext?.delete(log) }
            summary.resetForRegeneration()
            try? card.modelContext?.save()
        }
        try await generateBaseSummary(for: card)
    }

    // MARK: Incremental update

    /// Generates an incremental update summary from the change set (PRD §4.5 B).
    /// Returns `false` when there is nothing to summarize. When `force` is false
    /// (auto trigger), small changes are skipped per `isSignificant`.
    @discardableResult
    func generateUpdateSummary(for card: Card, force: Bool) async throws -> Bool {
        guard let summary = card.summary, summary.hasBase else {
            // No base yet → generate base instead of an update.
            try await generateBaseSummary(for: card)
            return true
        }
        let config = try resolveConfig()
        let current = card.blockContents()
        let snapshot = summary.snapshot
        let diff = SnapshotDiffer.diff(current: current, snapshot: snapshot)

        guard diff.hasChanges else { return false }
        if !force && !SnapshotDiffer.isSignificant(diff) {
            // Skip auto-update for small changes (PRD §4.5 "变更过小 → 跳过").
            // The snapshot is intentionally NOT advanced: these edits stay
            // pending against the last summarized baseline and accumulate until
            // they are collectively significant (or the user forces an update),
            // so a series of tiny edits is never silently dropped.
            return false
        }

        let changeSetText = CardContentAggregator.changeSetText(diff: diff, limits: limits)
        let previous = Self.renderPreviousSummary(summary)
        let imagePaths = diff.changedImageBlocks.compactMap { $0.imageAssetRef }.filter { !$0.isEmpty }
        let images = config.supportsVision ? await loadImages(paths: imagePaths) : []

        if changeSetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty {
            return false
        }

        let dto = try await client.generateUpdateSummary(
            config: config,
            previousSummaryText: previous,
            changeSetText: changeSetText,
            images: images
        )

        let log = UpdateLogEntity(dto: dto, provider: config.provider.displayName, model: config.model)
        card.modelContext?.insert(log)
        log.summary = summary
        if summary.updateLogs == nil { summary.updateLogs = [] }
        summary.updateLogs?.append(log)
        summary.snapshot = SummarySnapshot.make(from: current)
        try? card.modelContext?.save()
        return true
    }

    /// Whether the card has significant un-summarized changes (drives auto-update
    /// decisions and the "needs update" hint without making a network call).
    func hasPendingChanges(for card: Card) -> Bool {
        guard let summary = card.summary, summary.hasBase else { return false }
        let diff = SnapshotDiffer.diff(current: card.blockContents(), snapshot: summary.snapshot)
        return diff.hasChanges
    }

    /// Clears a card's AI summary and all its update logs without regenerating
    /// (PRD §4.10 "清除某卡片 AI 摘要(含更新记录)").
    func clearSummary(for card: Card) {
        guard let summary = card.summary else { return }
        card.summary = nil
        card.modelContext?.delete(summary)
        try? card.modelContext?.save()
    }

    // MARK: Connection test

    func testConnection() async throws {
        let config = try resolveConfig()
        try await client.testConnection(config: config)
    }

    // MARK: Helpers

    private func resolveConfig() throws -> ProviderConfig {
        switch settings.makeProviderConfig() {
        case let .success(config): return config
        case let .failure(error): throw error
        }
    }

    private func ensureSummary(for card: Card) -> AISummaryEntity {
        if let s = card.summary { return s }
        let s = AISummaryEntity()
        card.modelContext?.insert(s)
        s.card = card
        card.summary = s
        return s
    }

    /// Image relative paths for the base summary, capped to the most recent N
    /// (PRD §4.3.3 "超出时取较近的若干张").
    private func imagePathsForBase(_ card: Card) -> [String] {
        let paths = card.orderedBlocks
            .filter { $0.kind == .image && !$0.imageRelativePath.isEmpty }
            .map { $0.imageRelativePath }
        if paths.count <= limits.maxImages { return paths }
        return Array(paths.suffix(limits.maxImages))
    }

    /// Compresses + base64-encodes images off the main thread.
    private func loadImages(paths: [String]) async -> [AIImage] {
        guard !paths.isEmpty else { return [] }
        let capped = Array(paths.prefix(limits.maxImages))
        let pipeline = imagePipeline
        return await Task.detached(priority: .userInitiated) {
            #if canImport(UIKit)
            return capped.compactMap { pipeline.aiImage(forRelativePath: $0) }
            #else
            return []
            #endif
        }.value
    }

    /// Renders the existing base summary as context text for the update prompt
    /// (PRD §5.3 (A)).
    static func renderPreviousSummary(_ s: AISummaryEntity) -> String {
        var parts: [String] = []
        if !s.baseTitle.isEmpty { parts.append("标题:\(s.baseTitle)") }
        if !s.baseOneLiner.isEmpty { parts.append("一句话:\(s.baseOneLiner)") }
        if !s.baseType.isEmpty { parts.append("类型:\(s.baseType)") }
        if !s.baseTopics.isEmpty { parts.append("主题:\(s.baseTopics.joined(separator: "、"))") }
        if !s.baseKeyPoints.isEmpty {
            parts.append("要点:\n- " + s.baseKeyPoints.joined(separator: "\n- "))
        }
        if !s.baseSummary.isEmpty { parts.append("总结:\(s.baseSummary)") }
        return parts.joined(separator: "\n")
    }
}
