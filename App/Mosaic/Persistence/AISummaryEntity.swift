import Foundation
import SwiftData
import MosaicKit

/// Stored AI summary for a card: the long-lived base summary plus an append-only
/// list of update logs, and the change-detection snapshot (PRD §4.5 / §8).
@Model
final class AISummaryEntity {
    var id: UUID = UUID()

    // Base summary (preserved long-term)
    var baseTitle: String = ""
    var baseOneLiner: String = ""
    var baseType: String = ""
    var baseTopics: [String] = []
    var baseKeyPoints: [String] = []
    var baseSummary: String = ""
    var baseModelUsed: String = ""
    var baseProviderUsed: String = ""
    var baseGeneratedAt: Date = Date()
    /// False until the first base summary has been generated.
    var hasBase: Bool = false

    /// Change-detection baseline (blockId → descriptor), JSON-encoded (PRD §8 lastSnapshot).
    var snapshotData: Data = Data()

    var card: Card?

    @Relationship(deleteRule: .cascade, inverse: \UpdateLogEntity.summary)
    var updateLogs: [UpdateLogEntity]? = []

    init() {
        self.id = UUID()
    }

    /// Update logs in reverse-chronological order (newest first) for the sticker
    /// (PRD §4.5 B "倒序追加").
    var sortedUpdateLogs: [UpdateLogEntity] {
        (updateLogs ?? []).sorted { $0.generatedAt > $1.generatedAt }
    }

    var snapshot: SummarySnapshot {
        get { SummarySnapshot.decode(snapshotData) }
        set { snapshotData = newValue.encodedData() }
    }

    /// Applies a freshly generated base summary (PRD §5.1 output).
    func applyBase(_ dto: BaseSummaryDTO, provider: String, model: String, at date: Date = Date()) {
        baseTitle = dto.title
        baseOneLiner = dto.oneLiner
        baseType = dto.type
        baseTopics = dto.topics
        baseKeyPoints = dto.keyPoints
        baseSummary = dto.summary
        baseProviderUsed = provider
        baseModelUsed = model
        baseGeneratedAt = date
        hasBase = true
    }

    /// Clears the base fields + snapshot for "regenerate full summary" (PRD §4.5
    /// manual). Update-log *objects* are deleted by the caller (which has the
    /// model context) so they don't linger orphaned in the store.
    func resetForRegeneration() {
        hasBase = false
        baseTitle = ""; baseOneLiner = ""; baseType = ""
        baseTopics = []; baseKeyPoints = []; baseSummary = ""
        baseModelUsed = ""; baseProviderUsed = ""
        updateLogs = []
        snapshotData = Data()
    }
}
