import Foundation

/// Pure tag helpers (PRD §4.9 标签). Tags are plain strings on the card; these
/// functions keep them normalized and de-duplicated. Dedup is case- and
/// diacritic-insensitive (so "Work" == "work"); Chinese is unaffected and the
/// original display casing is preserved.
public enum TagUtilities {

    /// Dedup key — reuses the search normalization (lowercase + fold).
    public static func key(_ tag: String) -> String {
        SearchMatcher.normalize(tag)
    }

    /// Trims and collapses internal whitespace; returns `nil` for an empty tag.
    public static func normalize(_ tag: String) -> String? {
        let collapsed = tag
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Normalizes a list: drops empties, de-dups by key (keeping the first /
    /// original casing), preserves order.
    public static func sanitize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            guard let norm = normalize(raw) else { continue }
            if seen.insert(key(norm)).inserted { result.append(norm) }
        }
        return result
    }

    public static func add(_ tag: String, to existing: [String]) -> [String] {
        sanitize(existing + [tag])
    }

    public static func remove(_ tag: String, from existing: [String]) -> [String] {
        let k = key(tag)
        return existing.filter { key($0) != k }
    }

    /// Union of two lists (order preserved, de-duped).
    public static func merge(_ a: [String], _ b: [String]) -> [String] {
        sanitize(a + b)
    }

    /// Adds AI summary topics as tags, de-duped against existing.
    public static func addingTopics(_ topics: [String], to existing: [String]) -> [String] {
        merge(existing, topics)
    }

    public static func contains(_ tag: String, in tags: [String]) -> Bool {
        let k = key(tag)
        return tags.contains { key($0) == k }
    }
}
