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

    /// 标题 / 标签的字面匹配。
    ///
    /// **与检索侧走同一套切分**（`QuerySegmentation`）。第一版这里是
    /// 「按空白切 + 全部命中」，而检索侧改成了 CJK 二元组 + `minimum_should_match`
    /// 之后，同一条中文长 query 在正文里能找到、在标题里找不到 ——
    /// 快通道与完整通道各说各话，用户看到的是「搜索结果先出现一条又消失」。
    ///
    /// 空 query 返回 `false`（UI 显示引导而不是全部结果）。
    public static func matches(query: String, haystack: String, tags: [String] = [],
                               segmentation: QuerySegmentation = .default,
                               cjkPolicy: CJKMatchPolicy = .default) -> Bool {
        let groups = segmentation.groups(from: query, policy: cjkPolicy)
        guard !groups.isEmpty else { return false }
        let hay = Array(TextMatcher.normalizedForOffsets(haystack + " " + tags.joined(separator: " ")))
        return TextMatcher.locate(groups: groups, inNormalized: hay) != nil
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
