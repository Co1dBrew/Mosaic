import Foundation

/// Parsed base-summary payload (PRD §5.1 JSON contract).
/// Defensively decoded: missing fields degrade to safe defaults rather than
/// throwing, and arrays tolerate `null`.
public struct BaseSummaryDTO: Equatable, Sendable, Codable {
    public var title: String
    public var oneLiner: String
    public var type: String
    public var topics: [String]
    public var keyPoints: [String]
    public var summary: String

    public init(
        title: String = "",
        oneLiner: String = "",
        type: String = "",
        topics: [String] = [],
        keyPoints: [String] = [],
        summary: String = ""
    ) {
        self.title = title
        self.oneLiner = oneLiner
        self.type = type
        self.topics = topics
        self.keyPoints = keyPoints
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case title
        case oneLiner = "one_liner"
        case type
        case topics
        case keyPoints = "key_points"
        case summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = Self.string(c, .title)
        self.oneLiner = Self.string(c, .oneLiner)
        self.type = Self.string(c, .type)
        self.topics = Self.stringArray(c, .topics)
        self.keyPoints = Self.stringArray(c, .keyPoints)
        self.summary = Self.string(c, .summary)
    }

    /// True when the model returned essentially nothing usable.
    public var isEmpty: Bool {
        title.isEmpty && oneLiner.isEmpty && summary.isEmpty &&
            topics.isEmpty && keyPoints.isEmpty
    }
}

/// Parsed incremental-update payload (PRD §5.2 JSON contract).
public struct UpdateSummaryDTO: Equatable, Sendable, Codable {
    public var updateOneLiner: String
    public var changes: [String]

    public init(updateOneLiner: String = "", changes: [String] = []) {
        self.updateOneLiner = updateOneLiner
        self.changes = changes
    }

    enum CodingKeys: String, CodingKey {
        case updateOneLiner = "update_one_liner"
        case changes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.updateOneLiner = Self.string(c, .updateOneLiner)
        self.changes = Self.stringArray(c, .changes)
    }

    public var isEmpty: Bool {
        updateOneLiner.isEmpty && changes.isEmpty
    }
}

// MARK: - Defensive decoding helpers

extension BaseSummaryDTO {
    static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String {
        DefensiveDecode.string(c, key)
    }
    static func stringArray(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        DefensiveDecode.stringArray(c, key)
    }
}

extension UpdateSummaryDTO {
    static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String {
        DefensiveDecode.string(c, key)
    }
    static func stringArray(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        DefensiveDecode.stringArray(c, key)
    }
}

/// Shared defensive-decoding helpers tolerant of null, missing, wrong-typed,
/// or single-instead-of-array values from loosely-conforming models.
enum DefensiveDecode {
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String {
        // `try?` flattens the already-optional `decodeIfPresent` result.
        let value = try? c.decodeIfPresent(String.self, forKey: key)
        return (value ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func stringArray<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
        if let arr = (try? c.decodeIfPresent([String].self, forKey: key)) ?? nil {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let single = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil {
            let t = single.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [t]
        }
        return []
    }
}
