import Foundation

/// # Index lifecycle
///
/// These five states are the *system* side of the two-dimensional Search state
/// model in `design/SEARCH_CONTRACT.md` §4.1. They map straight onto
/// `RetrievalCapability`, which drives `Bar / Search Status` — so the engineering
/// state machine and the designed UI states are the same five things, not two
/// vocabularies that have to be translated.
public enum IndexState: Sendable, Equatable, Codable, CustomStringConvertible {
    /// Every retrievable block has a current embedding. Hybrid available.
    case ready
    /// First build, or a rebuild after a wipe. `progress` in [0, 1] is for
    /// engineering only — the user-facing copy is indeterminate (PRD Correction 3).
    case building(progress: Double)
    /// Index exists and is usable, but content changed and work is queued.
    case rebuilding(pending: Int)
    /// Usable but knowingly behind: pending work exists and nothing is running
    /// (offline, provider unavailable, backgrounded).
    case stale(pending: Int)
    /// Cannot make progress. Keyword search must continue to work.
    case failed(reason: String)

    public var description: String {
        switch self {
        case .ready: return "ready"
        case let .building(p): return "building(\(Int(p * 100))%)"
        case let .rebuilding(n): return "rebuilding(\(n))"
        case let .stale(n): return "stale(\(n))"
        case let .failed(r): return "failed(\(r))"
        }
    }

    /// Whether vector retrieval may be used at all.
    ///
    /// `rebuilding` and `stale` still allow it: a partially current index is more
    /// useful than none, and the results it does return are validated per record.
    /// Only `building` (nothing to search yet) and `failed` fall back to keyword.
    public var allowsVectorRetrieval: Bool {
        switch self {
        case .ready, .rebuilding, .stale: return true
        case .building, .failed: return false
        }
    }

    /// **Keyword retrieval is available in every state, without exception.**
    ///
    /// This is Progressive Enhancement expressed as code rather than as a habit:
    /// the property is a constant so no future state can accidentally disable it.
    public var allowsKeywordRetrieval: Bool { true }

    /// Projection onto the designed `RetrievalCapability`.
    public var capability: String {
        switch self {
        case .ready: return "full"
        case .building: return "indexBuilding"
        case .rebuilding: return "indexRebuilding"
        case .stale: return "indexRebuilding"
        case .failed: return "semanticUnavailable"
        }
    }
}

/// Derives index state from facts, rather than letting call sites set it.
///
/// A settable state field drifts: some path forgets to clear `building`, and the
/// UI shows a spinner forever. Here the state is a pure function of
/// (total, pending, running, failure), so it cannot get stuck.
public enum IndexStateMachine {

    public static func derive(totalChunks: Int,
                              pendingChunks: Int,
                              runningJobs: Int,
                              hasEmbeddings: Bool,
                              failure: String? = nil) -> IndexState {
        if let failure, pendingChunks > 0 { return .failed(reason: failure) }
        if pendingChunks == 0 { return .ready }

        if !hasEmbeddings {
            let done = max(0, totalChunks - pendingChunks)
            let progress = totalChunks > 0 ? Double(done) / Double(totalChunks) : 0
            return .building(progress: progress)
        }
        return runningJobs > 0 ? .rebuilding(pending: pendingChunks) : .stale(pending: pendingChunks)
    }
}
