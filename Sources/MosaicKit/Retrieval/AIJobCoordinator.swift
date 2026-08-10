import Foundation

/// Injectable sleeper so retry backoff is testable without real waiting.
public protocol JobSleeper: Sendable {
    func sleep(nanoseconds: UInt64) async throws
}

public struct RealSleeper: JobSleeper {
    public init() {}
    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

/// Records requested delays instead of waiting. Retry tests assert on the pattern.
public actor RecordingSleeper: JobSleeper {
    public private(set) var delays: [UInt64] = []
    public init() {}
    public func sleep(nanoseconds: UInt64) async throws { delays.append(nanoseconds) }
    public func recorded() -> [UInt64] { delays }
}

/// # AIJobCoordinator
///
/// Minimum viable scheduler for derived AI work on a single device.
///
/// Provides exactly what Week 1 needs and nothing more:
/// queue · concurrency limit · deduplication · retry · cancellation · stats.
///
/// Explicitly **not** here: persistence of the queue, priority scheduling,
/// distributed workers, a job dashboard. This is one iOS app; a durable workflow
/// engine would be more machinery than the problem has.
///
/// ## Deduplication
///
/// Keyed by `EmbeddingJobKey`, which includes `contentHash`. So:
/// - submitting the same block+content twice → second caller awaits the first task
/// - submitting the same block after an edit → different key → a real second job
///
/// That second property is why dedup is safe. Deduping on `blockID` alone would
/// swallow the job for the edited content.
public actor AIJobCoordinator<Value: Sendable> {

    public struct Policy: Sendable {
        public var maxConcurrent: Int
        public var maxAttempts: Int
        public var baseBackoffNanos: UInt64

        public init(maxConcurrent: Int = 2, maxAttempts: Int = 3, baseBackoffNanos: UInt64 = 200_000_000) {
            self.maxConcurrent = max(1, maxConcurrent)
            self.maxAttempts = max(1, maxAttempts)
            self.baseBackoffNanos = baseBackoffNanos
        }
    }

    public struct Stats: Sendable, Equatable {
        public var submitted = 0
        public var deduped = 0
        /// Number of times the operation body actually ran (retries included).
        public var attempts = 0
        public var succeeded = 0
        public var failed = 0
        public var cancelled = 0
        public var retried = 0
        public var peakConcurrent = 0
        public init() {}
    }

    private let policy: Policy
    private let sleeper: any JobSleeper

    private var inFlight: [EmbeddingJobKey: Task<Value, Error>] = [:]
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

    public private(set) var stats = Stats()

    public init(policy: Policy = Policy(), sleeper: any JobSleeper = RealSleeper()) {
        self.policy = policy
        self.sleeper = sleeper
    }

    // MARK: Submission

    /// Submit work for `key`. Returns the in-flight task when one already exists.
    ///
    /// The returned `Task` is the caller's handle: `await task.value` for the
    /// result, `task.cancel()` to request cancellation.
    @discardableResult
    public func submit(_ key: EmbeddingJobKey,
                       operation: @escaping @Sendable () async throws -> Value) -> Task<Value, Error> {
        stats.submitted += 1
        if let existing = inFlight[key] {
            stats.deduped += 1
            return existing
        }

        let policy = self.policy
        let sleeper = self.sleeper

        let task = Task<Value, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            await self.acquireSlot()

            var lastError: Error = EmbeddingProviderError.unavailable("no attempt made")
            var attempt = 0

            while attempt < policy.maxAttempts {
                if Task.isCancelled {
                    await self.finish(key, outcome: .cancelled)
                    throw CancellationError()
                }
                attempt += 1
                await self.noteAttempt()
                do {
                    let value = try await operation()
                    // A job can be cancelled while the provider was working. The
                    // value is still returned to the caller — discarding it here
                    // would hide the "provider ignored cancellation" case that
                    // StaleGuard exists to catch. Correctness is enforced at the
                    // persistence boundary, not here.
                    await self.finish(key, outcome: .succeeded)
                    return value
                } catch is CancellationError {
                    await self.finish(key, outcome: .cancelled)
                    throw CancellationError()
                } catch {
                    lastError = error
                    guard Self.isRetryable(error), attempt < policy.maxAttempts else { break }
                    await self.noteRetry()
                    let backoff = policy.baseBackoffNanos << UInt64(attempt - 1)
                    try? await sleeper.sleep(nanoseconds: backoff)
                }
            }

            await self.finish(key, outcome: .failed)
            throw lastError
        }

        inFlight[key] = task
        return task
    }

    /// Cancel any in-flight job for `key`.
    ///
    /// Best-effort by design: a provider that ignores cancellation still finishes.
    /// That is fine — `StaleGuard` refuses the result at the write boundary.
    public func cancel(_ key: EmbeddingJobKey) {
        inFlight[key]?.cancel()
    }

    public func cancelAll() {
        for (_, task) in inFlight { task.cancel() }
    }

    public func isInFlight(_ key: EmbeddingJobKey) -> Bool { inFlight[key] != nil }
    public var inFlightCount: Int { inFlight.count }
    public func currentStats() -> Stats { stats }

    // MARK: Internals

    private enum Outcome { case succeeded, failed, cancelled }

    private func noteAttempt() { stats.attempts += 1 }
    private func noteRetry() { stats.retried += 1 }

    private func finish(_ key: EmbeddingJobKey, outcome: Outcome) {
        inFlight.removeValue(forKey: key)
        switch outcome {
        case .succeeded: stats.succeeded += 1
        case .failed: stats.failed += 1
        case .cancelled: stats.cancelled += 1
        }
        releaseSlot()
    }

    /// Concurrency gate. The slot count is conserved: `releaseSlot` hands the slot
    /// straight to the next waiter instead of decrementing and letting it re-increment,
    /// which would allow a third task to slip in between.
    private func acquireSlot() async {
        if running < policy.maxConcurrent {
            running += 1
            stats.peakConcurrent = max(stats.peakConcurrent, running)
            return
        }
        let id = UUID()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append((id: id, continuation: c))
        }
        stats.peakConcurrent = max(stats.peakConcurrent, running)
    }

    private func releaseSlot() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()   // slot transferred; `running` unchanged
        } else {
            running = max(0, running - 1)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let e = error as? EmbeddingProviderError else { return false }
        switch e {
        case .transport, .rateLimited: return true
        case .unavailable, .rejected, .invalidInput: return false
        }
    }
}
