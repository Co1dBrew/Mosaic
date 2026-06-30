import Foundation

/// Lightweight key used to order cards (PRD §4.2 / P1 pinning). Keeps the sort
/// rule pure and testable, independent of SwiftData.
public struct CardSortKey: Sendable, Equatable {
    public let id: String
    public let isPinned: Bool
    public let updatedAt: Date

    public init(id: String, isPinned: Bool, updatedAt: Date) {
        self.id = id
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

public enum CardSorting {
    /// Pinned first, then `updatedAt` descending; stable tiebreak by id.
    public static func isOrderedBefore(_ a: CardSortKey, _ b: CardSortKey) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id < b.id
    }

    public static func ordered(_ keys: [CardSortKey]) -> [CardSortKey] {
        keys.sorted(by: isOrderedBefore)
    }
}
