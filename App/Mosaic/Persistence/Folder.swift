import Foundation
import SwiftData

/// A top-level category container (PRD §4.1 / §8).
///
/// All properties have defaults and relationships are optional so the schema is
/// compatible with SwiftData + CloudKit private-database sync (PRD §4.10).
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    /// Hex color string (e.g. "#FF8A00") used for the folder chip/icon tint.
    var colorHex: String = "#0A84FF"
    /// SF Symbol name for the folder icon.
    var iconName: String = "folder.fill"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Card.folder)
    var cards: [Card]? = []

    init(
        name: String,
        colorHex: String = "#0A84FF",
        iconName: String = "folder.fill",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Number of cards in the folder (PRD §4.1 list shows card count).
    var cardCount: Int { cards?.count ?? 0 }

    /// Cards sorted by last-modified, newest first (PRD §4.2).
    var sortedCards: [Card] {
        (cards ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    func touch() { updatedAt = Date() }
}
