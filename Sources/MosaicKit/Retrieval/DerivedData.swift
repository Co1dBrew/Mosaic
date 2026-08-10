import Foundation

/// # Derived Retrieval Data — boundary types
///
/// **Core user data** (`Card` / `Block` / `Folder` / `Tag`) lives in SwiftData and is
/// authored by the user. **Derived data** (chunks, embeddings, traces) is computed
/// *from* core data and is, by definition, reconstructible.
///
/// The rule that makes the whole retrieval stack safe to iterate on:
///
/// > Deleting **all** derived data must never lose a single user note.
///
/// Consequences that shaped these types:
///
/// - Derived records reference core data **by id only** (`noteID` / `blockID` strings).
///   No SwiftData relationships, no cascade rules pointing back into user content.
/// - Derived records carry the `contentHash` and `embeddingVersion` they were built
///   from, so any consumer can tell whether they still describe current content.
/// - Nothing here is a `@Model`. These are value types in MosaicKit; the app maps
///   them onto its own storage at the boundary. That keeps `Card` / `Block` schema
///   untouched — Goal 1 requires **zero** destructive migration of user data.
///
/// Week 1 defines the boundary and the identity/validation rules. Actual vector
/// storage and retrieval land in Week 2.

// MARK: - Block reference

/// A stable pointer to one block inside one note.
///
/// This is the anchor the future Search Result → Note navigation relies on:
/// `noteID` selects the card, `blockID` selects the scroll target.
public struct BlockRef: Hashable, Sendable, Codable {
    public let noteID: String
    public let blockID: String

    public init(noteID: String, blockID: String) {
        self.noteID = noteID
        self.blockID = blockID
    }
}

// MARK: - Retrievable text

/// Which part of a block feeds retrieval.
///
/// This is deliberately explicit rather than "just concatenate everything":
/// each block kind has exactly one retrievable projection, and the list of
/// projections *is* the Goal 1 corpus definition.
public enum RetrievalSource: String, Sendable, Codable, CaseIterable {
    case text          // Text block body
    case transcript    // Audio block transcript
    case ocr           // Image block OCR text — see `imageOCRUnavailable`
    case extracted     // Document block extracted text
    case link          // Link title / description / URL
}

public enum RetrievableText {

    /// Goal 1 corpus: Text · Audio transcript · Image OCR · Document extracted text ·
    /// Link title/description. Title and tags are lexical signals handled at query
    /// time, not embedded here.
    ///
    /// - Important: **Image OCR is not yet available** (`IG-1`). `CardBlockContent`
    ///   has no OCR field — the existing pipeline sends images to a multimodal model
    ///   and stores a *summary*, which is not retrievable text. Until an OCR pipeline
    ///   exists, image blocks contribute their user-authored caption only, and this
    ///   function reports `.ocr` with whatever caption text is present. That is a
    ///   deliberate under-approximation, not an oversight.
    public static func extract(from block: CardBlockContent) -> (source: RetrievalSource, text: String)? {
        func clean(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch block.kind {
        case .text:
            let t = clean(block.text)
            return t.isEmpty ? nil : (.text, t)
        case .audio:
            let t = clean(block.transcript)
            return t.isEmpty ? nil : (.transcript, t)
        case .image:
            // IG-1: caption stands in for OCR text until the OCR pipeline exists.
            let t = clean(block.imageCaption)
            return t.isEmpty ? nil : (.ocr, t)
        case .file:
            let t = clean(block.extractedText)
            return t.isEmpty ? nil : (.extracted, t)
        case .link:
            let parts = [clean(block.linkTitle), clean(block.linkDescription), clean(block.url)]
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : (.link, parts.joined(separator: " — "))
        }
    }

    /// True when this block currently contributes nothing to retrieval.
    public static func isEmpty(_ block: CardBlockContent) -> Bool {
        extract(from: block) == nil
    }
}

// MARK: - Derived records (value types; storage comes in Week 2)

/// One retrievable unit.
///
/// `charStart` / `charEnd` are character offsets into the block's **resolved
/// retrievable text** (the same string `ChunkPipeline.resolveText` returns). They
/// exist so a future match can be mapped back to a position for Matched Excerpt
/// windowing — without them, a hit in chunk 3 of 7 could only be located by
/// re-searching the block.
public struct NoteChunk: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let ref: BlockRef
    public let source: RetrievalSource
    /// Index of this chunk within its block (0-based).
    public let indexInBlock: Int
    public let text: String
    public let charStart: Int
    public let charEnd: Int
    /// Content hash of the *block* this chunk came from.
    public let contentHash: String
    /// Identity of the strategy that produced it — changing strategy invalidates chunks.
    public let strategy: String

    public init(id: String, ref: BlockRef, source: RetrievalSource,
                indexInBlock: Int, text: String,
                charStart: Int = 0, charEnd: Int = 0,
                contentHash: String, strategy: String = ChunkStrategy.block.identity) {
        self.id = id
        self.ref = ref
        self.source = source
        self.indexInBlock = indexInBlock
        self.text = text
        self.charStart = charStart
        self.charEnd = charEnd
        self.contentHash = contentHash
        self.strategy = strategy
    }
}

/// OCR text for one image block.
///
/// **Derived, not core.** Unlike `Block.transcript` (user-visible and user-editable
/// per PRD §4.3.2) and `Block.extractedText`, OCR output is never shown in the Note
/// Editor and never edited. Storing it on `Block` would put a machine artefact into
/// the user's note schema and into CloudKit sync, for no user-facing benefit.
///
/// It is keyed by the *block* content hash: OCR is a pure function of the image
/// asset, and the asset ref is already part of that hash. So when the image
/// changes, the hash changes, and the old OCR is automatically stale.
public struct ImageTextExtraction: Sendable, Equatable, Codable {
    public let ref: BlockRef
    /// Hash of the block the OCR was produced from.
    public let contentHash: String
    public let text: String
    /// Recognition confidence in [0, 1] when the engine reports one.
    public let confidence: Double
    public let extractedAt: Date

    public init(ref: BlockRef, contentHash: String, text: String,
                confidence: Double = 0, extractedAt: Date = Date()) {
        self.ref = ref
        self.contentHash = contentHash
        self.text = text
        self.confidence = confidence
        self.extractedAt = extractedAt
    }
}

/// One embedding, tagged with everything needed to decide whether it is still valid.
///
/// `contentHash` + `embeddingVersion` together answer "was this produced from the
/// content that exists right now, by the model we're using right now?". Any
/// mismatch means the record is stale and must not be used or overwritten blindly.
public struct EmbeddingRecord: Sendable, Equatable, Codable {
    public let ref: BlockRef
    /// **Primary identity.** One record per chunk, not per block — a block that
    /// splits into 7 chunks has 7 vectors.
    public let chunkID: String
    public let chunkIndex: Int
    public let contentHash: String
    public let embeddingVersion: String
    /// Strategy identity, so a strategy switch invalidates records the same way a
    /// model switch does.
    public let chunkStrategy: String
    public let dimension: Int
    public let vector: [Float]
    public let createdAt: Date

    public init(ref: BlockRef, chunkID: String, chunkIndex: Int = 0, contentHash: String,
                embeddingVersion: String, chunkStrategy: String = ChunkStrategy.block.identity,
                dimension: Int, vector: [Float], createdAt: Date = Date()) {
        self.ref = ref
        self.chunkID = chunkID
        self.chunkIndex = chunkIndex
        self.contentHash = contentHash
        self.embeddingVersion = embeddingVersion
        self.chunkStrategy = chunkStrategy
        self.dimension = dimension
        self.vector = vector
        self.createdAt = createdAt
    }
}
