import Foundation
import SwiftData
import MosaicKit

/// One appended "what changed this time" entry (PRD §4.5 B / §8).
@Model
final class UpdateLogEntity {
    var id: UUID = UUID()
    var updateOneLiner: String = ""
    var changes: [String] = []
    var modelUsed: String = ""
    var providerUsed: String = ""
    var generatedAt: Date = Date()
    /// Whether the user has seen this update (drives the unread dot, PRD §4.4).
    var isRead: Bool = false

    var summary: AISummaryEntity?

    init(dto: UpdateSummaryDTO, provider: String, model: String, at date: Date = Date()) {
        self.id = UUID()
        self.updateOneLiner = dto.updateOneLiner
        self.changes = dto.changes
        self.providerUsed = provider
        self.modelUsed = model
        self.generatedAt = date
        self.isRead = false
    }
}
