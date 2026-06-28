import Foundation

/// A lightweight per-block fingerprint stored in the snapshot so the differ can
/// describe deletions even after the block is gone.
public struct BlockDescriptor: Codable, Equatable, Sendable {
    public var hash: String
    public var kind: BlockKind
    public var brief: String
    /// Trimmed text length at snapshot time (0 for non-text), used to measure the
    /// *delta* of a later edit rather than the whole block size.
    public var textLength: Int

    public init(hash: String, kind: BlockKind, brief: String, textLength: Int = 0) {
        self.hash = hash
        self.kind = kind
        self.brief = brief
        self.textLength = textLength
    }

    enum CodingKeys: String, CodingKey { case hash, kind, brief, textLength }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash)
        kind = try c.decode(BlockKind.self, forKey: .kind)
        brief = try c.decode(String.self, forKey: .brief)
        textLength = (try? c.decodeIfPresent(Int.self, forKey: .textLength)) ?? 0
    }
}

/// The baseline used for change detection: blockId → descriptor, captured at the
/// time of the last successful summary (PRD §4.5 / §8 `lastSnapshot`).
public struct SummarySnapshot: Codable, Equatable, Sendable {
    public var entries: [String: BlockDescriptor]

    public init(entries: [String: BlockDescriptor] = [:]) {
        self.entries = entries
    }

    /// Builds a snapshot from the current set of blocks.
    public static func make(from blocks: [CardBlockContent]) -> SummarySnapshot {
        var map: [String: BlockDescriptor] = [:]
        for b in blocks { map[b.id] = ContentHasher.descriptor(for: b) }
        return SummarySnapshot(entries: map)
    }

    public func encodedData() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public static func decode(_ data: Data?) -> SummarySnapshot {
        guard let data, !data.isEmpty,
              let snap = try? JSONDecoder().decode(SummarySnapshot.self, from: data) else {
            return SummarySnapshot()
        }
        return snap
    }
}

/// A block present in the snapshot but no longer in the card.
public struct DeletedBlock: Equatable, Sendable {
    public let id: String
    public let kind: BlockKind
    public let brief: String

    public init(id: String, kind: BlockKind, brief: String) {
        self.id = id
        self.kind = kind
        self.brief = brief
    }
}

/// The result of comparing current blocks against a snapshot (PRD §4.5).
public struct CardDiff: Equatable, Sendable {
    public var added: [CardBlockContent]
    public var modified: [CardBlockContent]
    public var deleted: [DeletedBlock]

    public init(added: [CardBlockContent] = [], modified: [CardBlockContent] = [], deleted: [DeletedBlock] = []) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }

    public var hasChanges: Bool {
        !added.isEmpty || !modified.isEmpty || !deleted.isEmpty
    }

    /// Blocks that contribute a (possibly new) image for the update request.
    public var changedImageBlocks: [CardBlockContent] {
        (added + modified).filter { $0.isImage }
    }
}

public enum SnapshotDiffer {

    /// Compares `current` blocks with a previous `snapshot`.
    public static func diff(current: [CardBlockContent], snapshot: SummarySnapshot) -> CardDiff {
        var added: [CardBlockContent] = []
        var modified: [CardBlockContent] = []
        let currentIDs = Set(current.map { $0.id })

        for block in current.sorted(by: { $0.order < $1.order }) {
            let newHash = ContentHasher.hash(for: block)
            if let old = snapshot.entries[block.id] {
                if old.hash != newHash { modified.append(block) }
            } else {
                added.append(block)
            }
        }
        let deleted: [DeletedBlock] = snapshot.entries
            .filter { !currentIDs.contains($0.key) }
            .map { DeletedBlock(id: $0.key, kind: $0.value.kind, brief: $0.value.brief) }
            .sorted { $0.id < $1.id }
        return CardDiff(added: added, modified: modified, deleted: deleted)
    }

    /// Whether a diff is large enough to warrant an automatic update summary
    /// (PRD §4.5 "变更过小 → 跳过本次自动更新", to "避免频繁调用、控制费用").
    ///
    /// Any deletion, or any added/modified non-text block (image/audio/file/link),
    /// is always significant. For text, the *delta* matters — added text length
    /// plus the absolute change in length of modified text blocks (using the
    /// snapshot's recorded length) must reach `minTextChars`. This means editing
    /// one character in a long paragraph is NOT treated as significant.
    public static func isSignificant(_ diff: CardDiff, snapshot: SummarySnapshot, minTextChars: Int = 12) -> Bool {
        if !diff.deleted.isEmpty { return true }
        if diff.added.contains(where: { $0.kind != .text }) { return true }
        if diff.modified.contains(where: { $0.kind != .text }) { return true }

        func len(_ s: String?) -> Int { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count }
        var magnitude = 0
        for block in diff.added where block.kind == .text {
            magnitude += len(block.text)
        }
        for block in diff.modified where block.kind == .text {
            let oldLen = snapshot.entries[block.id]?.textLength ?? 0
            magnitude += abs(len(block.text) - oldLen)
        }
        return magnitude >= minTextChars
    }
}
