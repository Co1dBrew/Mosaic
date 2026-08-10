import Foundation
import CryptoKit

/// Identity of the model that produced an embedding.
///
/// `version` is what goes into `EmbeddingJobKey` and `EmbeddingRecord`. Switching
/// provider or model must change it, otherwise vectors from two different spaces
/// would be compared against each other — which fails silently and looks like
/// "retrieval quality got worse" rather than "the index is corrupt".
public struct EmbeddingModelInfo: Sendable, Equatable, Codable {
    /// Human-readable identifier, e.g. `"mock-v1"`, `"bge-small-zh-v1.5"`.
    public let identifier: String
    /// Vector dimension. Records with a different dimension are unusable.
    public let dimension: Int
    /// Opaque version string mixed into job identity and stored on every record.
    public let version: String

    public init(identifier: String, dimension: Int, version: String) {
        self.identifier = identifier
        self.dimension = dimension
        self.version = version
    }
}

public enum EmbeddingProviderError: Error, Equatable, Sendable {
    /// Provider not configured / model not downloaded / offline.
    case unavailable(String)
    /// Transient transport failure — retryable.
    case transport(String)
    /// Provider-side throttling — retryable.
    case rateLimited
    /// Bad credentials / bad request — **not** retryable.
    case rejected(String)
    /// Empty or oversized input.
    case invalidInput(String)
}

/// Minimum surface Week 1 needs. Deliberately small: the goal is that the provider
/// is *replaceable*, not that there are many of them.
public protocol EmbeddingProvider: Sendable {
    var modelInfo: EmbeddingModelInfo { get }
    func embed(_ text: String) async throws -> [Float]
    func embed(batch texts: [String]) async throws -> [[Float]]
}

public extension EmbeddingProvider {
    /// Default batch implementation so a conformer only has to implement one method.
    /// Real providers should override this with a true batched request.
    func embed(batch texts: [String]) async throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for t in texts { out.append(try await embed(t)) }
        return out
    }
}

// MARK: - Mock

/// Deterministic provider for tests and for exercising the pipeline without a model.
///
/// The vector is derived from a SHA-256 of the input, so:
/// - same text → same vector, across processes and launches
/// - different text → different vector
///
/// It is **not** semantically meaningful. It exists to prove the plumbing, not to
/// retrieve anything. Week 2 replaces it with a real model.
public struct MockEmbeddingProvider: EmbeddingProvider {
    public let modelInfo: EmbeddingModelInfo
    /// Artificial latency, used by concurrency/cancellation tests.
    public let delayNanos: UInt64
    /// When set, every call throws this instead of returning.
    public let failure: EmbeddingProviderError?
    /// When true, the provider ignores cancellation and runs to completion — this
    /// models a provider that does not honour `Task.cancel()`, which is precisely
    /// the case stale protection has to survive.
    public let ignoresCancellation: Bool

    public init(dimension: Int = 8,
                version: String = "mock-v1",
                delayNanos: UInt64 = 0,
                failure: EmbeddingProviderError? = nil,
                ignoresCancellation: Bool = false) {
        self.modelInfo = EmbeddingModelInfo(identifier: "mock", dimension: dimension, version: version)
        self.delayNanos = delayNanos
        self.failure = failure
        self.ignoresCancellation = ignoresCancellation
    }

    public func embed(_ text: String) async throws -> [Float] {
        if delayNanos > 0 {
            if ignoresCancellation {
                // Deliberately non-cancellable sleep.
                let deadline = DispatchTime.now().uptimeNanoseconds + delayNanos
                while DispatchTime.now().uptimeNanoseconds < deadline {
                    await Task.yield()
                }
            } else {
                try await Task.sleep(nanoseconds: delayNanos)
            }
        }
        if let failure { throw failure }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingProviderError.invalidInput("empty text") }
        return Self.deterministicVector(for: trimmed, dimension: modelInfo.dimension)
    }

    /// SHA-256 → repeatable pseudo-vector in [-1, 1], L2-normalised.
    public static func deterministicVector(for text: String, dimension: Int) -> [Float] {
        var bytes: [UInt8] = []
        var counter = 0
        while bytes.count < dimension {
            let digest = SHA256.hash(data: Data("\(counter)|\(text)".utf8))
            bytes.append(contentsOf: digest)
            counter += 1
        }
        var v = (0..<dimension).map { Float(Int(bytes[$0]) - 128) / 128.0 }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { v = v.map { $0 / norm } }
        return v
    }
}

// MARK: - Future conformers (seams, not implementations)

/// On-device embedding. **Week 2.** Present so the replaceability seam is real and
/// compiled, not so it can be used — every call fails loudly rather than returning
/// a plausible-looking wrong vector.
public struct LocalEmbeddingProvider: EmbeddingProvider {
    public let modelInfo: EmbeddingModelInfo
    public init(modelInfo: EmbeddingModelInfo = .init(identifier: "local-unconfigured", dimension: 0, version: "local-v0")) {
        self.modelInfo = modelInfo
    }
    public func embed(_ text: String) async throws -> [Float] {
        throw EmbeddingProviderError.unavailable("LocalEmbeddingProvider is not implemented until Week 2")
    }
}

/// Cloud embedding. **Week 2.** Same reasoning as `LocalEmbeddingProvider`.
public struct CloudEmbeddingProvider: EmbeddingProvider {
    public let modelInfo: EmbeddingModelInfo
    public init(modelInfo: EmbeddingModelInfo = .init(identifier: "cloud-unconfigured", dimension: 0, version: "cloud-v0")) {
        self.modelInfo = modelInfo
    }
    public func embed(_ text: String) async throws -> [Float] {
        throw EmbeddingProviderError.unavailable("CloudEmbeddingProvider is not implemented until Week 2")
    }
}
