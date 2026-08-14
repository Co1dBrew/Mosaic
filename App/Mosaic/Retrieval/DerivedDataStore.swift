import Foundation
import SwiftData
import MosaicKit

/// # SwiftData concurrency model for derived writes
///
/// ## The finding
///
/// Authoritative note content lives in SwiftData's **main context**, and every user
/// edit happens on `@MainActor` (SwiftUI views, `CardEditorView.commitNow()`).
/// Stale protection requires that no edit interleave between *"read the current
/// content hash"* and *"write the derived record"*.
///
/// If validation runs on a background actor, there is necessarily an `await`
/// between reading the hash and performing the write — and `await` is exactly where
/// a `@MainActor` edit can run. The window is small, which makes it worse: it fails
/// rarely and non-reproducibly.
///
/// ## The resolution
///
/// The validated write is a **synchronous `@MainActor` critical section**:
///
/// ```
/// off-main:  embed(text)                    ← the expensive part, never on main
///    hop  ─▶ @MainActor {
///              read current hash            ┐ no await between these three,
///              StaleGuard.decide(...)       │ so no edit can interleave
///              write derived record         ┘
///            }
/// ```
///
/// ## Why not `@ModelActor`
///
/// A background `@ModelActor` is the right tool when the data being validated *and*
/// written both live in that actor. Here they do not: the truth about content lives
/// in the main context. Mirroring the hash into the derived store would put both
/// together, but the mirror would lag behind edits — and a stale mirror means
/// accepting a stale result, the exact bug being prevented.
///
/// If derived writes ever become a main-thread cost, the fix is batching
/// (`commitBatch`), not moving validation off-main.
@MainActor
final class DerivedDataStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    // MARK: The sanctioned write path

    /// Validate against current content and persist, atomically with respect to
    /// `@MainActor` edits.
    ///
    /// - Parameter noteContext: the **main** model context, where authoritative note
    ///   content lives. Read synchronously inside this call.
    @discardableResult
    func commit(_ result: DerivedResult<[Float]>,
                chunkID: String,
                chunkIndex: Int = 0,
                chunkStrategy: String = ChunkStrategy.block.identity,
                embeddingVersion: String,
                noteContext: ModelContext,
                ocrText: String? = nil) -> DerivedWriteDecision {
        // --- critical section: no `await` from here to the end of the method ---
        let writeContext = Self.readWriteContext(for: result.key.ref,
                                                 in: noteContext,
                                                 embeddingVersion: embeddingVersion,
                                                 ocrText: ocrText)
        let decision = StaleGuard.decide(for: result, context: writeContext)
        guard decision.isAccepted else { return decision }

        upsert(EmbeddingRecord(ref: result.key.ref,
                               chunkID: chunkID,
                               chunkIndex: chunkIndex,
                               contentHash: result.key.contentHash,
                               embeddingVersion: result.key.embeddingVersion,
                               chunkStrategy: chunkStrategy,
                               dimension: result.payload.count,
                               vector: result.payload,
                               createdAt: result.producedAt))
        try? context.save()
        return .accept
        // --- end critical section ---
    }

    /// Batch variant: N validated writes in **one** main-actor hop and one save.
    /// Each result is validated independently — a stale one is rejected without
    /// affecting the others.
    @discardableResult
    func commitBatch(_ items: [(result: DerivedResult<[Float]>, chunkID: String, chunkIndex: Int, strategy: String)],
                     embeddingVersion: String,
                     noteContext: ModelContext,
                     ocrTextByBlockID: [String: String] = [:]) -> [DerivedWriteDecision] {
        var decisions: [DerivedWriteDecision] = []
        decisions.reserveCapacity(items.count)
        for item in items {
            let ctx = Self.readWriteContext(for: item.result.key.ref,
                                            in: noteContext,
                                            embeddingVersion: embeddingVersion,
                                            ocrText: ocrTextByBlockID[item.result.key.blockID])
            let decision = StaleGuard.decide(for: item.result, context: ctx)
            decisions.append(decision)
            guard decision.isAccepted else { continue }
            upsert(EmbeddingRecord(ref: item.result.key.ref, chunkID: item.chunkID,
                                   chunkIndex: item.chunkIndex,
                                   contentHash: item.result.key.contentHash,
                                   embeddingVersion: item.result.key.embeddingVersion,
                                   chunkStrategy: item.strategy,
                                   dimension: item.result.payload.count,
                                   vector: item.result.payload,
                                   createdAt: item.result.producedAt))
        }
        try? context.save()
        return decisions
    }

    /// Reads authoritative current state for a block. Synchronous by contract —
    /// making this `async` would reopen the race it exists to close.
    static func readWriteContext(for ref: BlockRef,
                                 in noteContext: ModelContext,
                                 embeddingVersion: String,
                                 ocrText: String? = nil) -> DerivedWriteContext {
        guard let noteUUID = UUID(uuidString: ref.noteID),
              let blockUUID = UUID(uuidString: ref.blockID) else {
            return DerivedWriteContext(noteExists: false, currentContentHash: nil,
                                       currentEmbeddingVersion: embeddingVersion)
        }

        var cardFetch = FetchDescriptor<Card>(predicate: #Predicate { $0.id == noteUUID })
        cardFetch.fetchLimit = 1
        guard let cards = try? noteContext.fetch(cardFetch), !cards.isEmpty else {
            return DerivedWriteContext(noteExists: false, currentContentHash: nil,
                                       currentEmbeddingVersion: embeddingVersion)
        }

        var blockFetch = FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockUUID })
        blockFetch.fetchLimit = 1
        let blocks = (try? noteContext.fetch(blockFetch)) ?? []

        var hash: String?
        if let block = blocks.first {
            let content = block.toContent()
            // A block that no longer contributes retrievable text is treated as
            // gone: keeping a vector for it would leave an unreachable record.
            if ChunkPipeline.resolveText(block: content, ocrText: ocrText) != nil {
                hash = AIContentHash.forBlock(content, ocrText: ocrText)
            }
        }

        return DerivedWriteContext(noteExists: true, currentContentHash: hash,
                                   currentEmbeddingVersion: embeddingVersion)
    }

    // MARK: Embedding queries

    func record(forChunk chunkID: String) -> EmbeddingRecord? {
        entity(forChunk: chunkID)?.toValue()
    }

    func recordCount() -> Int {
        ((try? context.fetch(FetchDescriptor<EmbeddingRecordEntity>())) ?? []).count
    }

    /// `chunkID -> StoredChunkRecord` for one note — the shape
    /// `DerivedWorkScanner.plan` consumes.
    func existingRecords(noteID: String) -> [String: StoredChunkRecord] {
        var fetch = FetchDescriptor<EmbeddingRecordEntity>(predicate: #Predicate { $0.noteID == noteID })
        fetch.fetchLimit = 50_000
        let rows = (try? context.fetch(fetch)) ?? []
        var out: [String: StoredChunkRecord] = [:]
        for row in rows {
            out[row.chunkID] = StoredChunkRecord(contentHash: row.contentHash,
                                                 embeddingVersion: row.embeddingVersion,
                                                 chunkStrategy: row.chunkStrategy)
        }
        return out
    }

    /// Every stored record, for rebuilding the in-memory vector index at launch.
    func allRecords() -> [EmbeddingRecord] {
        ((try? context.fetch(FetchDescriptor<EmbeddingRecordEntity>())) ?? []).map { $0.toValue() }
    }

    /// Every chunk id stored for one note — what a note deletion has to clean up.
    func chunkIDs(noteID: String) -> [String] {
        var fetch = FetchDescriptor<EmbeddingRecordEntity>(predicate: #Predicate { $0.noteID == noteID })
        fetch.fetchLimit = 50_000
        return ((try? context.fetch(fetch)) ?? []).map(\.chunkID)
    }

    // MARK: Embedding mutations

    func deleteChunks(_ chunkIDs: [String]) {
        guard !chunkIDs.isEmpty else { return }
        for id in chunkIDs {
            if let e = entity(forChunk: id) { context.delete(e) }
        }
        try? context.save()
    }

    /// Wipes every derived record. Safe by construction — this store contains no
    /// user data, so there is nothing here that cannot be rebuilt.
    func deleteAll() {
        for e in (try? context.fetch(FetchDescriptor<EmbeddingRecordEntity>())) ?? [] { context.delete(e) }
        for e in (try? context.fetch(FetchDescriptor<ImageTextExtractionEntity>())) ?? [] { context.delete(e) }
        try? context.save()
    }

    private func entity(forChunk chunkID: String) -> EmbeddingRecordEntity? {
        var fetch = FetchDescriptor<EmbeddingRecordEntity>(predicate: #Predicate { $0.chunkID == chunkID })
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first
    }

    private func upsert(_ record: EmbeddingRecord) {
        if let existing = entity(forChunk: record.chunkID) {
            existing.apply(record)
        } else {
            context.insert(EmbeddingRecordEntity(record: record))
        }
    }

    // MARK: OCR

    /// Stored OCR for a block, **only if it still matches the current content hash**.
    /// A mismatch means the image changed, so the old text must not be used.
    func ocrText(for ref: BlockRef, currentContentHashIgnoringOCR: String? = nil) -> String? {
        guard let e = ocrEntity(for: ref) else { return nil }
        if let expected = currentContentHashIgnoringOCR, e.contentHash != expected { return nil }
        return e.text.isEmpty ? nil : e.text
    }

    func ocrTextByBlockID(noteID: String) -> [String: String] {
        var fetch = FetchDescriptor<ImageTextExtractionEntity>(predicate: #Predicate { $0.noteID == noteID })
        fetch.fetchLimit = 10_000
        let rows = (try? context.fetch(fetch)) ?? []
        var out: [String: String] = [:]
        for row in rows where !row.text.isEmpty { out[row.blockID] = row.text }
        return out
    }

    func saveOCR(_ extraction: ImageTextExtraction, engineIdentifier: String) {
        if let existing = ocrEntity(for: extraction.ref) {
            existing.contentHash = extraction.contentHash
            existing.text = extraction.text
            existing.confidence = extraction.confidence
            existing.engineIdentifier = engineIdentifier
            existing.extractedAt = extraction.extractedAt
        } else {
            context.insert(ImageTextExtractionEntity(ref: extraction.ref,
                                                     contentHash: extraction.contentHash,
                                                     text: extraction.text,
                                                     confidence: extraction.confidence,
                                                     engineIdentifier: engineIdentifier,
                                                     extractedAt: extraction.extractedAt))
        }
        try? context.save()
    }

    /// Drops one note's OCR. Called when the note is deleted — OCR is keyed by
    /// block hash, so an orphaned row would never be invalidated by content change.
    func deleteOCR(noteID: String) {
        var fetch = FetchDescriptor<ImageTextExtractionEntity>(predicate: #Predicate { $0.noteID == noteID })
        fetch.fetchLimit = 10_000
        for e in (try? context.fetch(fetch)) ?? [] { context.delete(e) }
        try? context.save()
    }

    func ocrCount() -> Int {
        ((try? context.fetch(FetchDescriptor<ImageTextExtractionEntity>())) ?? []).count
    }

    private func ocrEntity(for ref: BlockRef) -> ImageTextExtractionEntity? {
        let note = ref.noteID, block = ref.blockID
        var fetch = FetchDescriptor<ImageTextExtractionEntity>(
            predicate: #Predicate { $0.noteID == note && $0.blockID == block }
        )
        fetch.fetchLimit = 1
        return (try? context.fetch(fetch))?.first
    }
}
