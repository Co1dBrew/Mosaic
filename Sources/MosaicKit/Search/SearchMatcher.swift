import Foundation

/// Pure, case- and diacritic-insensitive text matching for card search.
/// Multi-term queries are AND: every whitespace-separated token must appear in
/// the haystack or in a tag.
public enum SearchMatcher {

    public static func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func tokens(from query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Returns true when every query token is found in `haystack` or any `tag`.
    /// An empty/whitespace query returns `false` (the UI shows a prompt instead).
    public static func matches(query: String, haystack: String, tags: [String] = []) -> Bool {
        let queryTokens = tokens(from: query)
        guard !queryTokens.isEmpty else { return false }
        let hay = normalize(haystack)
        let normalizedTags = tags.map { normalize($0) }
        return queryTokens.allSatisfy { token in
            hay.contains(token) || normalizedTags.contains { $0.contains(token) }
        }
    }
}

/// Reserved filter scope for search. Phase 1 uses the default (no constraints =
/// global). Later phases can constrain by folder, tags, or pinned without
/// changing the matcher or call sites.
public struct SearchScope: Equatable, Sendable {
    public var folderID: String?
    public var requiredTags: [String]
    public var pinnedOnly: Bool

    public init(folderID: String? = nil, requiredTags: [String] = [], pinnedOnly: Bool = false) {
        self.folderID = folderID
        self.requiredTags = requiredTags
        self.pinnedOnly = pinnedOnly
    }

    /// True when no constraints are set (global search).
    public var isUnconstrained: Bool {
        folderID == nil && requiredTags.isEmpty && !pinnedOnly
    }

    /// Whether a card satisfies the scope's structural constraints (independent of
    /// the text query).
    public func allows(folderID: String?, tags: [String], isPinned: Bool) -> Bool {
        if let wanted = self.folderID, wanted != folderID { return false }
        if pinnedOnly && !isPinned { return false }
        if !requiredTags.isEmpty {
            let have = Set(tags.map { SearchMatcher.normalize($0) })
            for required in requiredTags where !have.contains(SearchMatcher.normalize(required)) {
                return false
            }
        }
        return true
    }
}
