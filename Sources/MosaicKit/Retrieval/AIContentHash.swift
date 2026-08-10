import Foundation

/// # AIContentHash
///
/// The single answer to: *"was this derived result produced from the content that
/// exists right now?"*
///
/// Built on the existing `ContentHasher` (already used for summary change
/// detection) rather than inventing a second canonicalisation — two hashers over
/// the same content would eventually disagree, and the disagreement would be
/// silent.
///
/// ## What is hashed
///
/// A **canonical string**, never a Swift object's memory representation.
/// `Hashable`/`hashValue` is per-process seeded and would change across launches,
/// which is exactly the property we must not have.
///
/// ## Versioning
///
/// `hashVersion` is mixed into every digest. Changing canonicalisation (adding OCR
/// text, changing trimming rules, …) means bumping it, which invalidates every
/// derived record in one step instead of leaving a mix of old and new digests that
/// compare unequal for the wrong reason.
public enum AIContentHash {

    /// Bump when the canonical representation changes in any way.
    ///
    /// - `1` — initial: reuses `ContentHasher.canonicalString(for:)`.
    ///   Image blocks contribute caption only.
    /// - `2` — Week 2: image blocks additionally mix in OCR text when available.
    public static let hashVersion = 2

    // MARK: Block-level

    /// Fingerprint of one block's **retrievable content**.
    ///
    /// ### Explicitly excluded (documented decision)
    ///
    /// | Field | In hash? | Why |
    /// |---|---|---|
    /// | `order` | **No** | Reordering does not change *what* was recorded. A moved block keeps its embedding. |
    /// | `createdAt` | **No** | Not content. |
    /// | Card `tags` | **No** | Tags are a query-time lexical signal, not embedded text. Re-tagging must not invalidate embeddings. |
    /// | Card `folder` | **No** | Organisational metadata, same reasoning as tags. |
    /// | Card `userTitle` | **No** (block level) | Belongs to the card fingerprint, not the block's. |
    /// | `isPinned` | **No** | Pure presentation. |
    ///
    /// So: **a metadata-only change does not change any block hash and therefore
    /// re-embeds nothing.** That is the intended behaviour — it is the difference
    /// between "moved a block" costing zero API calls and costing a full re-index.
    public static func forBlock(_ block: CardBlockContent, ocrText: String? = nil) -> String {
        var canonical = ContentHasher.canonicalString(for: block)
        // OCR is derived from the image asset, and the asset ref is already inside
        // the canonical string — so a changed image already changes the hash.
        // Including the OCR text as well covers the case where the *extractor*
        // improved and produced better text for the same image: the block then
        // needs re-embedding even though the user changed nothing.
        if block.kind == .image, let ocr = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
            canonical += "|ocr=\(ocr)"
        }
        return ContentHasher.hash(of: "v\(hashVersion)|\(canonical)")
    }

    // MARK: Card-level

    /// Fingerprint of a whole card's retrievable state.
    ///
    /// Unlike the block hash this **does** include order and title, because it
    /// answers a different question: "does this card need to be re-scanned?"
    /// A reorder changes the card hash (cheap re-scan) but no block hash, so the
    /// scan finds zero blocks needing re-embedding. Cheap scan, zero API cost.
    public static func forCard(title: String, blocks: [CardBlockContent]) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = blocks
            .sorted { $0.order < $1.order }
            .map { "\($0.id):\(forBlock($0))" }
            .joined(separator: "|")
        return ContentHasher.hash(of: "v\(hashVersion)|card|title=\(normalizedTitle)|\(body)")
    }

    /// Convenience: `blockID -> contentHash` for every block that contributes
    /// retrievable text. Blocks with no retrievable text are omitted — they have
    /// nothing to embed, so they must not appear as "work to do".
    public static func retrievableBlockHashes(_ blocks: [CardBlockContent]) -> [String: String] {
        var out: [String: String] = [:]
        for b in blocks where !RetrievableText.isEmpty(b) {
            out[b.id] = forBlock(b)
        }
        return out
    }
}
