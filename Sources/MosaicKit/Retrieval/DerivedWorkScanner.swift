import Foundation

/// One unit of derived work to schedule. Week 2: chunk-granular.
public struct DerivedWorkItem: Sendable, Equatable {
    public let key: EmbeddingJobKey
    public let chunkID: String
    public let source: RetrievalSource
    public let text: String

    public init(key: EmbeddingJobKey, chunkID: String, source: RetrievalSource, text: String) {
        self.key = key
        self.chunkID = chunkID
        self.source = source
        self.text = text
    }
}

/// What a scan concluded for one note.
public struct DerivedWorkPlan: Sendable, Equatable {
    /// Chunks whose embedding is missing or stale.
    public let pending: [DerivedWorkItem]
    /// Stored chunk ids that no longer correspond to any current chunk — delete.
    /// Produced by block deletion, by a block losing its text, **and by a block
    /// shrinking from N chunks to fewer**.
    public let orphanChunkIDs: [String]
    /// Chunks already embedded at the current hash, version and strategy.
    public let upToDate: [String]
    /// Every chunk the note currently has.
    public let totalChunks: Int

    public init(pending: [DerivedWorkItem], orphanChunkIDs: [String],
                upToDate: [String], totalChunks: Int) {
        self.pending = pending
        self.orphanChunkIDs = orphanChunkIDs
        self.upToDate = upToDate
        self.totalChunks = totalChunks
    }

    public var hasWork: Bool { !pending.isEmpty || !orphanChunkIDs.isEmpty }
}

/// What is already stored for one chunk.
public struct StoredChunkRecord: Sendable, Equatable {
    public let contentHash: String
    public let embeddingVersion: String
    public let chunkStrategy: String

    public init(contentHash: String, embeddingVersion: String,
                chunkStrategy: String = ChunkStrategy.block.identity) {
        self.contentHash = contentHash
        self.embeddingVersion = embeddingVersion
        self.chunkStrategy = chunkStrategy
    }
}

/// # Restart & recovery strategy
///
/// Mosaic does **not** persist a job queue. On launch it re-derives what needs
/// doing by comparing current content against stored embeddings, and re-queues.
///
/// - **The desired state is already on disk.** "Which chunks lack a current
///   embedding" is a pure function of (blocks, records). A persisted queue would be
///   a second source of truth that can disagree with the first — and when they
///   disagree, the queue is always the wrong one.
/// - **A killed job leaves nothing behind.** Writes happen only after
///   `StaleGuard` accepts, so an interrupted job has written no partial state.
/// - **No status field can get stuck.** "Running" is never persisted, so a crash
///   cannot leave a chunk permanently marked in-progress.
/// - **Idempotent by construction.** Re-queueing a completed job produces no work.
public enum DerivedWorkScanner {

    /// Compare one note's current chunks against stored embeddings.
    ///
    /// - Parameters:
    ///   - existingRecords: `chunkID -> StoredChunkRecord` already stored for this note.
    ///   - ocrTextByBlockID: OCR overlay for image blocks (derived data, not on `Block`).
    public static func plan(noteID: String,
                            blocks: [CardBlockContent],
                            strategy: ChunkStrategy,
                            existingRecords: [String: StoredChunkRecord],
                            embeddingVersion: String,
                            ocrTextByBlockID: [String: String] = [:]) -> DerivedWorkPlan {

        let chunks = ChunkPipeline.chunks(noteID: noteID, blocks: blocks,
                                          strategy: strategy, ocrTextByBlockID: ocrTextByBlockID)

        var pending: [DerivedWorkItem] = []
        var upToDate: [String] = []
        var seen = Set<String>()

        for chunk in chunks {
            seen.insert(chunk.id)
            if let existing = existingRecords[chunk.id],
               existing.contentHash == chunk.contentHash,
               existing.embeddingVersion == embeddingVersion,
               existing.chunkStrategy == chunk.strategy {
                upToDate.append(chunk.id)
                continue
            }
            pending.append(DerivedWorkItem(
                key: EmbeddingJobKey(ref: chunk.ref,
                                     chunkIndex: chunk.indexInBlock,
                                     contentHash: chunk.contentHash,
                                     embeddingVersion: embeddingVersion),
                chunkID: chunk.id,
                source: chunk.source,
                text: chunk.text
            ))
        }

        let orphans = existingRecords.keys.filter { !seen.contains($0) }.sorted()

        return DerivedWorkPlan(pending: pending,
                               orphanChunkIDs: orphans,
                               upToDate: upToDate,
                               totalChunks: chunks.count)
    }
}
