import Foundation
import SwiftData
import MosaicKit

/// # Derived-data schema
///
/// Deliberately kept in a **separate `ModelContainer` with its own store file**,
/// not merged into the note schema. That is what makes the boundary real rather
/// than aspirational:
///
/// - "Delete all derived data" is one file removal. It cannot touch a user note,
///   because the notes are in a different file.
/// - Derived data never enters CloudKit sync. Embeddings are large, device-local,
///   and cheap to rebuild — syncing them would spend the user's quota on
///   regenerable bytes.
/// - `Card` / `Block` / `Folder` schema is **unchanged**. Goal 1 requires zero
///   destructive migration of user data, and this is how that promise is kept.
///
/// The only link back to core data is a pair of id strings. No SwiftData
/// relationship, so no cascade rule can propagate from here into user content.

/// One embedding per **chunk**.
///
/// Week 2 changed the grain: a block that splits into 7 chunks has 7 vectors.
/// `chunkID` is therefore the identity, and `blockID` exists for range queries and
/// cleanup.
@Model
final class EmbeddingRecordEntity {
    /// `noteID/blockID/index` — the primary identity.
    var chunkID: String = ""
    var noteID: String = ""
    var blockID: String = ""
    var chunkIndex: Int = 0
    /// Hash of the block content this vector was produced from.
    var contentHash: String = ""
    /// Version of the model that produced it.
    var embeddingVersion: String = ""
    /// Identity of the chunk strategy — a strategy switch invalidates records the
    /// same way a model switch does.
    var chunkStrategy: String = ""
    var dimension: Int = 0
    /// `[Float]` packed little-endian. Stored as `Data` because a large `[Float]`
    /// property is awkward for SwiftData and pointless to make queryable.
    var vectorData: Data = Data()
    var createdAt: Date = Date()

    init(record: EmbeddingRecord) {
        self.chunkID = record.chunkID
        self.noteID = record.ref.noteID
        self.blockID = record.ref.blockID
        self.chunkIndex = record.chunkIndex
        self.contentHash = record.contentHash
        self.embeddingVersion = record.embeddingVersion
        self.chunkStrategy = record.chunkStrategy
        self.dimension = record.dimension
        self.vectorData = Self.pack(record.vector)
        self.createdAt = record.createdAt
    }

    var ref: BlockRef { BlockRef(noteID: noteID, blockID: blockID) }
    var vector: [Float] { Self.unpack(vectorData, count: dimension) }

    func apply(_ record: EmbeddingRecord) {
        chunkIndex = record.chunkIndex
        contentHash = record.contentHash
        embeddingVersion = record.embeddingVersion
        chunkStrategy = record.chunkStrategy
        dimension = record.dimension
        vectorData = Self.pack(record.vector)
        createdAt = record.createdAt
    }

    func toValue() -> EmbeddingRecord {
        EmbeddingRecord(ref: ref, chunkID: chunkID, chunkIndex: chunkIndex,
                        contentHash: contentHash, embeddingVersion: embeddingVersion,
                        chunkStrategy: chunkStrategy, dimension: dimension,
                        vector: vector, createdAt: createdAt)
    }

    static func pack(_ v: [Float]) -> Data {
        var copy = v
        return copy.withUnsafeMutableBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data, count: Int) -> [Float] {
        guard count > 0, data.count >= count * MemoryLayout<Float>.size else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
    }
}

/// OCR text for one image block.
///
/// **Derived, so it lives here** rather than on `Block`. Unlike `Block.transcript`
/// (user-visible and user-editable per PRD §4.3.2) and `Block.extractedText`, OCR
/// output is never shown in the Note Editor and never edited by the user. Putting a
/// machine artefact into the note schema — and therefore into CloudKit sync — would
/// cost the user quota for zero user-facing benefit.
@Model
final class ImageTextExtractionEntity {
    var noteID: String = ""
    var blockID: String = ""
    /// Hash of the block the OCR was produced from. OCR is a pure function of the
    /// image asset, and the asset ref is already inside that hash — so when the
    /// image changes, this record is automatically stale.
    var contentHash: String = ""
    var text: String = ""
    var confidence: Double = 0
    /// Which engine produced it; a new engine is a reason to re-extract.
    var engineIdentifier: String = ""
    var extractedAt: Date = Date()

    init(ref: BlockRef, contentHash: String, text: String,
         confidence: Double, engineIdentifier: String, extractedAt: Date = Date()) {
        self.noteID = ref.noteID
        self.blockID = ref.blockID
        self.contentHash = contentHash
        self.text = text
        self.confidence = confidence
        self.engineIdentifier = engineIdentifier
        self.extractedAt = extractedAt
    }

    var ref: BlockRef { BlockRef(noteID: noteID, blockID: blockID) }
}
