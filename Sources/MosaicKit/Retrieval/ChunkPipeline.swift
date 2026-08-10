import Foundation

/// How a block's retrievable text is split into embeddable units.
///
/// Three strategies, comparable in the Retrieval Lab. Deliberately no more:
/// each additional strategy multiplies the evaluation matrix, and Goal 1 needs to
/// *measure* chunking, not to have every chunking idea available.
public enum ChunkStrategy: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// One chunk per block, whole text. The baseline everything else is measured against.
    case block
    /// Split at `maxChars`, preferring a sentence boundary near the cut, with
    /// `overlap` characters carried into the next chunk so a sentence spanning a
    /// cut is still findable from both sides.
    case fixed(maxChars: Int, overlap: Int)
    /// Group whole sentences until adding the next would exceed `maxChars`.
    /// Never cuts mid-sentence; a single over-long sentence becomes its own chunk.
    case sentence(maxChars: Int)

    public static let `default` = ChunkStrategy.fixed(maxChars: 240, overlap: 40)

    public var description: String {
        switch self {
        case .block: return "block"
        case let .fixed(m, o): return "fixed(\(m)/\(o))"
        case let .sentence(m): return "sentence(\(m))"
        }
    }

    /// Mixed into the chunk fingerprint: changing strategy must invalidate chunks.
    public var identity: String { description }
}

public enum ChunkPipeline {

    /// Sentence terminators covering CJK and Latin punctuation, plus newline.
    private static let terminators: Set<Character> = ["。", "！", "？", "；", "…", ".", "!", "?", ";", "\n"]

    /// Split one block into chunks.
    ///
    /// - Parameter ocrText: OCR text for image blocks, supplied by the caller.
    ///   Image OCR is *derived* data and does not live on `Block`, so it is passed
    ///   in as an overlay rather than read from the block (see `DerivedData.swift`).
    ///
    /// Returns `[]` when the block contributes no retrievable text — an empty block
    /// must produce no chunks, not one empty chunk.
    public static func chunks(noteID: String,
                              block: CardBlockContent,
                              strategy: ChunkStrategy,
                              ocrText: String? = nil) -> [NoteChunk] {
        guard let (source, text) = resolveText(block: block, ocrText: ocrText) else { return [] }

        let ref = BlockRef(noteID: noteID, blockID: block.id)
        let contentHash = AIContentHash.forBlock(block, ocrText: ocrText)
        let pieces = split(text, strategy: strategy)

        return pieces.enumerated().map { index, piece in
            NoteChunk(
                id: chunkID(ref: ref, index: index),
                ref: ref,
                source: source,
                indexInBlock: index,
                text: piece.text,
                charStart: piece.start,
                charEnd: piece.end,
                contentHash: contentHash,
                strategy: strategy.identity
            )
        }
    }

    /// All chunks for a note, in document order.
    public static func chunks(noteID: String,
                              blocks: [CardBlockContent],
                              strategy: ChunkStrategy,
                              ocrTextByBlockID: [String: String] = [:]) -> [NoteChunk] {
        blocks.sorted { $0.order < $1.order }.flatMap {
            chunks(noteID: noteID, block: $0, strategy: strategy, ocrText: ocrTextByBlockID[$0.id])
        }
    }

    /// Chunk ids are `noteID/blockID/index`.
    ///
    /// Index-based rather than content-based on purpose: when a block's content
    /// changes, *every* chunk of that block is re-embedded anyway (the block hash
    /// changed), so content-addressed ids would buy nothing and would make the
    /// orphan calculation harder to reason about.
    public static func chunkID(ref: BlockRef, index: Int) -> String {
        "\(ref.noteID)/\(ref.blockID)/\(index)"
    }

    // MARK: Text resolution

    /// The retrievable projection of a block, with OCR overlaid for images.
    public static func resolveText(block: CardBlockContent,
                                   ocrText: String?) -> (source: RetrievalSource, text: String)? {
        if block.kind == .image {
            // Prefer real OCR; fall back to the caption; combine when both exist,
            // because a caption often carries intent the OCR cannot ("答辩时间表").
            let ocr = (ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let caption = (block.imageCaption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = [caption, ocr].filter { !$0.isEmpty }.joined(separator: "\n")
            return combined.isEmpty ? nil : (.ocr, combined)
        }
        return RetrievableText.extract(from: block)
    }

    // MARK: Splitting

    struct Piece: Equatable {
        let text: String
        let start: Int
        let end: Int
    }

    static func split(_ text: String, strategy: ChunkStrategy) -> [Piece] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }

        switch strategy {
        case .block:
            return [Piece(text: text, start: 0, end: chars.count)]

        case let .fixed(maxChars, overlap):
            return splitFixed(chars, maxChars: max(1, maxChars), overlap: max(0, min(overlap, maxChars - 1)))

        case let .sentence(maxChars):
            return splitBySentence(chars, maxChars: max(1, maxChars))
        }
    }

    private static func splitFixed(_ chars: [Character], maxChars: Int, overlap: Int) -> [Piece] {
        guard chars.count > maxChars else {
            return [Piece(text: String(chars), start: 0, end: chars.count)]
        }
        var pieces: [Piece] = []
        var start = 0
        // How far back we will look for a sentence boundary rather than cutting
        // mid-sentence. A quarter of the window keeps chunks reasonably even.
        let lookback = max(1, maxChars / 4)

        while start < chars.count {
            let hardEnd = min(start + maxChars, chars.count)
            var end = hardEnd
            if hardEnd < chars.count {
                var probe = hardEnd - 1
                while probe > hardEnd - lookback && probe > start {
                    if terminators.contains(chars[probe]) { end = probe + 1; break }
                    probe -= 1
                }
            }
            let slice = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty { pieces.append(Piece(text: slice, start: start, end: end)) }
            if end >= chars.count { break }
            // Step forward by at least one character, otherwise a pathological
            // overlap value would loop forever.
            start = max(start + 1, end - overlap)
        }
        return pieces
    }

    private static func splitBySentence(_ chars: [Character], maxChars: Int) -> [Piece] {
        // Sentence boundaries first…
        var sentences: [(start: Int, end: Int)] = []
        var cursor = 0
        for i in 0..<chars.count where terminators.contains(chars[i]) {
            sentences.append((cursor, i + 1))
            cursor = i + 1
        }
        if cursor < chars.count { sentences.append((cursor, chars.count)) }
        if sentences.isEmpty { sentences = [(0, chars.count)] }

        // …then greedily group them up to maxChars.
        var pieces: [Piece] = []
        var groupStart = sentences[0].start
        var groupEnd = sentences[0].start

        for s in sentences {
            let candidateLength = s.end - groupStart
            if groupEnd > groupStart && candidateLength > maxChars {
                appendPiece(chars, groupStart, groupEnd, into: &pieces)
                groupStart = s.start
            }
            groupEnd = s.end
        }
        appendPiece(chars, groupStart, groupEnd, into: &pieces)
        return pieces
    }

    private static func appendPiece(_ chars: [Character], _ start: Int, _ end: Int, into pieces: inout [Piece]) {
        guard end > start else { return }
        let slice = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slice.isEmpty else { return }
        pieces.append(Piece(text: slice, start: start, end: end))
    }
}
