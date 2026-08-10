import Foundation

/// # Stale Result Protection
///
/// The single most important rule in the retrieval stack:
///
/// > **A derived result may only be persisted if the content it was computed from
/// > is still the current content.**
///
/// ## Why cancellation is not enough
///
/// It is tempting to rely on "when the user edits, we cancel the running job".
/// That is an **optimisation**, not a correctness guarantee, because:
///
/// 1. `Task.cancel()` is cooperative. A provider that never checks
///    `Task.isCancelled` — a synchronous C library, a URLSession that already has
///    the bytes, a third-party SDK — will run to completion and hand back a result.
/// 2. Cancellation races the completion. The job may finish *before* the cancel is
///    observed, then resume on the main actor after the edit has landed.
/// 3. A retry can outlive the edit that should have invalidated it.
/// 4. Nothing cancels across a process restart.
///
/// In every one of those cases the old result is still sitting there, ready to be
/// written. So the check lives at the **persistence boundary**, where it cannot be
/// bypassed, and it is based on data (`contentHash`), not on control flow.
///
/// ```
/// Note v12 ──▶ job starts (hash h12)
///                  │
///   user edits ────┼──▶ Note v13 (hash h13)
///                  │
///              job finishes, returns result tagged h12
///                  │
///          StaleGuard.decide(h12 vs current h13) ──▶ .reject(.contentChanged)
///                  │
///              v13 remains authoritative
/// ```

/// Why a derived result was refused.
public enum StaleRejection: Equatable, Sendable, CustomStringConvertible {
    /// Block content changed after the job started.
    case contentChanged(expected: String, current: String)
    /// The active embedding model changed after the job started.
    case embeddingVersionChanged(expected: String, current: String)
    /// The note no longer exists.
    case noteDeleted
    /// The block no longer exists (deleted, or no longer has retrievable text).
    case blockDeleted

    public var description: String {
        switch self {
        case let .contentChanged(e, c):
            return "contentChanged(expected \(e.prefix(8)), current \(c.prefix(8)))"
        case let .embeddingVersionChanged(e, c):
            return "embeddingVersionChanged(expected \(e), current \(c))"
        case .noteDeleted: return "noteDeleted"
        case .blockDeleted: return "blockDeleted"
        }
    }
}

public enum DerivedWriteDecision: Equatable, Sendable {
    case accept
    case reject(StaleRejection)

    public var isAccepted: Bool { self == .accept }
    public var rejection: StaleRejection? {
        if case let .reject(r) = self { return r }
        return nil
    }
}

/// A snapshot of *current* state, read at the moment of the write.
///
/// Must be read **inside** the same isolation as the write itself. Reading it
/// earlier and awaiting in between reintroduces the exact race this guards against.
public struct DerivedWriteContext: Sendable, Equatable {
    /// `nil` when the note no longer exists.
    public let noteExists: Bool
    /// Current hash of the target block; `nil` when the block is gone or has no
    /// retrievable text any more.
    public let currentContentHash: String?
    /// Embedding version currently in force.
    public let currentEmbeddingVersion: String

    public init(noteExists: Bool, currentContentHash: String?, currentEmbeddingVersion: String) {
        self.noteExists = noteExists
        self.currentContentHash = currentContentHash
        self.currentEmbeddingVersion = currentEmbeddingVersion
    }
}

public enum StaleGuard {

    /// The gate. Every derived write goes through this, with no exceptions and no
    /// "trusted" callers.
    ///
    /// Order of checks is deliberate: existence first (a deleted note makes the
    /// other questions meaningless), then model version, then content.
    public static func decide<P>(for result: DerivedResult<P>,
                                 context: DerivedWriteContext) -> DerivedWriteDecision {
        guard context.noteExists else { return .reject(.noteDeleted) }

        guard let currentHash = context.currentContentHash else {
            return .reject(.blockDeleted)
        }

        guard result.key.embeddingVersion == context.currentEmbeddingVersion else {
            return .reject(.embeddingVersionChanged(expected: result.key.embeddingVersion,
                                                    current: context.currentEmbeddingVersion))
        }

        guard result.key.contentHash == currentHash else {
            return .reject(.contentChanged(expected: result.key.contentHash, current: currentHash))
        }

        return .accept
    }
}

// MARK: - Reference persistence boundary

/// Anything that stores derived data.
///
/// Split out so the guard can be tested against an in-memory implementation, and
/// so the app's SwiftData store is *forced* through the same entry point.
public protocol DerivedStore: Actor {
    /// Current state for a block, read inside the store's isolation.
    func writeContext(for ref: BlockRef, embeddingVersion: String) -> DerivedWriteContext
    /// Unconditional write. **Never call directly** — go through `commit`.
    func upsert(_ record: EmbeddingRecord)
    func record(for ref: BlockRef) -> EmbeddingRecord?
}

public extension DerivedStore {

    /// The only sanctioned way to persist an embedding.
    ///
    /// Reads current state and writes **within the same actor hop**, so no edit can
    /// interleave between the check and the write.
    @discardableResult
    func commit(_ result: DerivedResult<[Float]>, chunkID: String, dimension: Int) -> DerivedWriteDecision {
        let context = writeContext(for: result.key.ref, embeddingVersion: result.key.embeddingVersion)
        let decision = StaleGuard.decide(for: result, context: context)
        guard decision.isAccepted else { return decision }
        upsert(EmbeddingRecord(
            ref: result.key.ref,
            chunkID: chunkID,
            contentHash: result.key.contentHash,
            embeddingVersion: result.key.embeddingVersion,
            dimension: dimension,
            vector: result.payload,
            createdAt: result.producedAt
        ))
        return .accept
    }
}
