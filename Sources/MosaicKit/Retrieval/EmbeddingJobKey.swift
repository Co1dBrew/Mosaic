import Foundation

/// # Job identity
///
/// Two jobs are "the same job" iff all four components match:
///
/// ```
/// noteID + blockID + contentHash + embeddingVersion
/// ```
///
/// Each component earns its place:
///
/// - **noteID / blockID** — *what* is being embedded.
/// - **contentHash** — *which version* of it. This is the component that makes
///   dedup safe: if the content changed, the key changes, so the new job cannot be
///   deduplicated against the in-flight old one. Without it, "same block already
///   running" would suppress the job for the *edited* content and the index would
///   silently keep the old vector.
/// - **embeddingVersion** — *which vector space*. Switching model must re-embed
///   everything; sharing a key across versions would mix incomparable vectors.
///
/// The key is also what travels with the result to the persistence boundary, where
/// `StaleGuard` re-checks it against current state. Identity and validation use the
/// same four fields on purpose — one concept, not two.
public struct EmbeddingJobKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let noteID: String
    public let blockID: String
    /// Week 2: a block splits into N chunks, each with its own vector. Without
    /// this component two chunks of the same block would share a key and the
    /// second would be silently deduplicated away.
    public let chunkIndex: Int
    public let contentHash: String
    public let embeddingVersion: String

    public init(noteID: String, blockID: String, chunkIndex: Int = 0,
                contentHash: String, embeddingVersion: String) {
        self.noteID = noteID
        self.blockID = blockID
        self.chunkIndex = chunkIndex
        self.contentHash = contentHash
        self.embeddingVersion = embeddingVersion
    }

    public init(ref: BlockRef, chunkIndex: Int = 0, contentHash: String, embeddingVersion: String) {
        self.init(noteID: ref.noteID, blockID: ref.blockID, chunkIndex: chunkIndex,
                  contentHash: contentHash, embeddingVersion: embeddingVersion)
    }

    /// Deterministic chunk id for this key.
    public var chunkID: String { ChunkPipeline.chunkID(ref: ref, index: chunkIndex) }

    public var ref: BlockRef { BlockRef(noteID: noteID, blockID: blockID) }

    /// Same block + same model, regardless of content version. Used to find the
    /// record a new result should replace.
    public var slot: BlockRef { ref }

    public var description: String {
        "\(noteID.prefix(8))/\(blockID.prefix(8))[\(chunkIndex)]@\(contentHash.prefix(8))#\(embeddingVersion)"
    }
}

/// A finished derived computation, carrying the identity it was computed from.
///
/// Results are **always** passed around in this envelope. A bare `[Float]` has no
/// way to prove which content it describes, and once that information is lost the
/// persistence boundary cannot do its job.
public struct DerivedResult<Payload: Sendable>: Sendable {
    public let key: EmbeddingJobKey
    public let payload: Payload
    public let producedAt: Date

    public init(key: EmbeddingJobKey, payload: Payload, producedAt: Date = Date()) {
        self.key = key
        self.payload = payload
        self.producedAt = producedAt
    }
}

extension DerivedResult: Equatable where Payload: Equatable {}
