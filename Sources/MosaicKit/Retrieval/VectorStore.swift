import Foundation

/// A vector hit, before any fusion or ranking.
public struct VectorHit: Sendable, Equatable {
    public let chunkID: String
    public let ref: BlockRef
    public let similarity: Float
    public init(chunkID: String, ref: BlockRef, similarity: Float) {
        self.chunkID = chunkID
        self.ref = ref
        self.similarity = similarity
    }
}

public enum VectorMath {

    /// Cosine similarity.
    ///
    /// Providers are expected to return L2-normalised vectors, in which case this
    /// reduces to a dot product. The normalisation is applied anyway because a
    /// provider that forgets would otherwise produce silently wrong rankings —
    /// and "ranking is subtly wrong" is the hardest class of bug to notice.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    public static func normalize(_ v: [Float]) -> [Float] {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard n > 0 else { return v }
        return v.map { $0 / n }
    }
}

/// Read side of the vector index.
public protocol VectorSearching: Sendable {
    func search(query: [Float], topK: Int) async -> [VectorHit]
    func count() async -> Int
}

/// # Brute-force vector index
///
/// Exhaustive cosine over every vector. **This is the correct Week 2 choice**, not
/// a placeholder to be apologised for:
///
/// - It is *exact*. An approximate index can only be evaluated against an exact
///   baseline, so the exact one has to exist first.
/// - Personal note corpora are small. The benchmark (`swift run mosaic-checks`)
///   measures the real curve; ANN is a decision to be made from that data, not
///   from a general belief that "brute force does not scale".
/// - It has no build step, so it can never be stale relative to the records it
///   was built from — one less failure mode while the pipeline is being shaped.
///
/// Adding ANN would be scope expansion and is explicitly deferred until the
/// benchmark says the SLO (P50 < 100 ms / P95 < 250 ms) is at risk.
public actor InMemoryVectorStore: VectorSearching {

    private struct Entry {
        let ref: BlockRef
        let vector: [Float]
    }

    private var entries: [String: Entry] = [:]   // chunkID → entry
    private var byBlock: [BlockRef: Set<String>] = [:]

    public init() {}

    // MARK: Write

    public func upsert(_ record: EmbeddingRecord) {
        entries[record.chunkID] = Entry(ref: record.ref, vector: record.vector)
        byBlock[record.ref, default: []].insert(record.chunkID)
    }

    public func upsert(_ records: [EmbeddingRecord]) {
        for r in records { upsert(r) }
    }

    public func removeChunks(_ chunkIDs: [String]) {
        for id in chunkIDs {
            if let e = entries.removeValue(forKey: id) {
                byBlock[e.ref]?.remove(id)
                if byBlock[e.ref]?.isEmpty == true { byBlock.removeValue(forKey: e.ref) }
            }
        }
    }

    public func removeBlock(_ ref: BlockRef) {
        for id in byBlock[ref] ?? [] { entries.removeValue(forKey: id) }
        byBlock.removeValue(forKey: ref)
    }

    public func removeNote(_ noteID: String) {
        let refs = byBlock.keys.filter { $0.noteID == noteID }
        for r in refs { removeBlock(r) }
    }

    public func removeAll() {
        entries.removeAll()
        byBlock.removeAll()
    }

    // MARK: Read

    public func search(query: [Float], topK: Int) async -> [VectorHit] {
        guard !query.isEmpty, topK > 0 else { return [] }
        var hits: [VectorHit] = []
        hits.reserveCapacity(entries.count)
        for (chunkID, e) in entries {
            let sim = VectorMath.cosine(query, e.vector)
            hits.append(VectorHit(chunkID: chunkID, ref: e.ref, similarity: sim))
        }
        // Deterministic ordering: similarity desc, then chunkID asc. Without the
        // tie-break, equal-similarity results would come back in dictionary order,
        // which varies per process and would make evaluation non-reproducible.
        hits.sort { $0.similarity == $1.similarity ? $0.chunkID < $1.chunkID : $0.similarity > $1.similarity }
        return Array(hits.prefix(topK))
    }

    public func count() async -> Int { entries.count }
    public func chunkIDs(for ref: BlockRef) -> [String] { Array(byBlock[ref] ?? []).sorted() }
    public func allChunkIDs() -> [String] { entries.keys.sorted() }
}
