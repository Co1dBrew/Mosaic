import Foundation

/// # RetrievalTrace — foundation only
///
/// Week 1 establishes the domain model and the recorder boundary. Most latency
/// fields stay zero until the retrieval pipeline exists in Week 3; the point is
/// that the shape and the seam are fixed now, so Week 3 fills values in rather
/// than inventing a structure mid-flight.
///
/// The question a trace must answer is **"why did this query return the wrong
/// thing?"** — not "how many milliseconds". Which is why `contentHash` and the
/// three version fields sit alongside the timings: most wrong results are a stale
/// or mis-versioned index, not a slow one.
public struct RetrievalTrace: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let query: String
    public let createdAt: Date

    // Identity — "which configuration produced this?"
    public var configVersion: String
    public var embeddingVersion: String
    public var indexVersion: String

    // Pipeline latencies (milliseconds). Week 3 populates these.
    public var queryProcessingMs: Double
    public var queryEmbeddingMs: Double
    public var keywordRetrievalMs: Double
    public var vectorRetrievalMs: Double
    public var fusionMs: Double
    public var rankingMs: Double
    public var totalMs: Double

    // Volumes — "did we even retrieve candidates?"
    public var chunkCount: Int
    public var keywordCandidates: Int
    public var vectorCandidates: Int
    public var candidateCount: Int
    public var resultCount: Int

    /// Fingerprint of the index state consulted. `isStale` true ⇒ results may have
    /// been produced from embeddings that no longer describe current content.
    public var contentHash: String
    public var isStale: Bool

    public init(id: UUID = UUID(),
                query: String,
                createdAt: Date = Date(),
                configVersion: String = "",
                embeddingVersion: String = "",
                indexVersion: String = "",
                queryProcessingMs: Double = 0,
                queryEmbeddingMs: Double = 0,
                keywordRetrievalMs: Double = 0,
                vectorRetrievalMs: Double = 0,
                fusionMs: Double = 0,
                rankingMs: Double = 0,
                totalMs: Double = 0,
                chunkCount: Int = 0,
                keywordCandidates: Int = 0,
                vectorCandidates: Int = 0,
                candidateCount: Int = 0,
                resultCount: Int = 0,
                contentHash: String = "",
                isStale: Bool = false) {
        self.id = id
        self.query = query
        self.createdAt = createdAt
        self.configVersion = configVersion
        self.embeddingVersion = embeddingVersion
        self.indexVersion = indexVersion
        self.queryProcessingMs = queryProcessingMs
        self.queryEmbeddingMs = queryEmbeddingMs
        self.keywordRetrievalMs = keywordRetrievalMs
        self.vectorRetrievalMs = vectorRetrievalMs
        self.fusionMs = fusionMs
        self.rankingMs = rankingMs
        self.totalMs = totalMs
        self.chunkCount = chunkCount
        self.keywordCandidates = keywordCandidates
        self.vectorCandidates = vectorCandidates
        self.candidateCount = candidateCount
        self.resultCount = resultCount
        self.contentHash = contentHash
        self.isStale = isStale
    }
}

/// In-memory ring buffer of recent traces.
///
/// Deliberately **not** persisted: traces are a debugging aid for the current
/// session, and writing them to SwiftData would put diagnostic churn into the same
/// store as user notes (and into CloudKit sync).
///
/// Recording is unconditional — including when Developer Mode is off — because the
/// PRD's local retrieval SLO (P50 < 100 ms / P95 < 250 ms) can only be measured on
/// the real user path. Cost is a struct append into a bounded array.
public actor RetrievalTraceRecorder {
    public static let defaultCapacity = 20

    private var buffer: [RetrievalTrace] = []
    private let capacity: Int

    public init(capacity: Int = RetrievalTraceRecorder.defaultCapacity) {
        self.capacity = max(1, capacity)
        buffer.reserveCapacity(self.capacity)
    }

    public func record(_ trace: RetrievalTrace) {
        buffer.append(trace)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }

    /// Newest first.
    public func recent() -> [RetrievalTrace] { buffer.reversed() }
    public func latest() -> RetrievalTrace? { buffer.last }
    public func count() -> Int { buffer.count }
    public func clear() { buffer.removeAll(keepingCapacity: true) }
}
