import Foundation
import MosaicKit

/// Week 1 Runtime Foundation checks.
///
/// One section per exit criterion, so a failure names the criterion it breaks.
enum RetrievalFoundationChecks {

    // MARK: Fixtures

    static func textBlock(_ id: String, _ text: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .text, text: text)
    }
    static func audioBlock(_ id: String, transcript: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .audio, transcript: transcript, audioAssetRef: "a/\(id).m4a")
    }
    static func fileBlock(_ id: String, extracted: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .file,
                         fileName: "doc.pdf", fileType: "PDF", extractedText: extracted)
    }
    static func imageBlock(_ id: String, caption: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .image, imageCaption: caption, imageAssetRef: "i/\(id).jpg")
    }

    static let version = "mock-v1"

    // MARK: 1 · Stable identity (IG-3)

    static func checkIdentity(_ r: CheckRunner) {
        r.suite("Week1 · Identity — block identity survives edit / reorder / restart")

        // Blocks carry their own UUID; `order` is a separate field. The app's
        // reorder path (CardEditorView.moveBlocks) rewrites `order` only.
        let b1 = textBlock("B1", "alpha", order: 0)
        let b2 = textBlock("B2", "beta", order: 1)

        // Reorder: same ids, swapped order.
        let r1 = textBlock("B1", "alpha", order: 1)
        let r2 = textBlock("B2", "beta", order: 0)
        r.expect(b1.id == r1.id && b2.id == r2.id, "reorder preserves block id")
        r.expect(AIContentHash.forBlock(b1) == AIContentHash.forBlock(r1),
                 "reorder does not change block content hash (no re-embed)")

        // Edit: same id, different hash.
        let edited = textBlock("B1", "alpha edited", order: 0)
        r.expect(edited.id == b1.id, "edit preserves block id")
        r.expect(AIContentHash.forBlock(edited) != AIContentHash.forBlock(b1),
                 "edit changes block content hash")

        // Restart: ids are persisted UUIDs, so re-materialising the same content
        // yields the same ref. Hash is a pure function of content, not of process.
        let ref = BlockRef(noteID: "N1", blockID: "B1")
        let refAgain = BlockRef(noteID: "N1", blockID: "B1")
        r.expect(ref == refAgain, "BlockRef is value-equal across materialisations")
        r.expect(AIContentHash.forBlock(b1) == AIContentHash.forBlock(textBlock("B1", "alpha", order: 99)),
                 "same content + same id ⇒ same hash regardless of order (restart-safe)")

        // Card hash DOES move on reorder — cheap rescan, zero re-embed.
        let cardA = AIContentHash.forCard(title: "T", blocks: [b1, b2])
        let cardB = AIContentHash.forCard(title: "T", blocks: [r1, r2])
        r.expect(cardA != cardB, "card hash changes on reorder (triggers rescan)")
    }

    // MARK: 2 · AIContentHash

    static func checkHash(_ r: CheckRunner) {
        r.suite("Week1 · AIContentHash — deterministic, content-sensitive")

        let a = textBlock("B1", "同样的内容")
        let b = textBlock("B1", "同样的内容")
        r.expect(AIContentHash.forBlock(a) == AIContentHash.forBlock(b), "same content → same hash")
        r.expect(AIContentHash.forBlock(a) == AIContentHash.forBlock(a), "deterministic across calls")
        r.expect(AIContentHash.forBlock(a).count == 64, "SHA-256 hex digest")

        r.expect(AIContentHash.forBlock(textBlock("B1", "x")) != AIContentHash.forBlock(textBlock("B1", "y")),
                 "changed text → different hash")

        r.expect(AIContentHash.forBlock(audioBlock("B2", transcript: "一")) !=
                 AIContentHash.forBlock(audioBlock("B2", transcript: "二")),
                 "changed transcript → different hash")

        r.expect(AIContentHash.forBlock(fileBlock("B3", extracted: "p")) !=
                 AIContentHash.forBlock(fileBlock("B3", extracted: "q")),
                 "changed extracted document text → different hash")

        r.expect(AIContentHash.forBlock(imageBlock("B4", caption: "猫")) !=
                 AIContentHash.forBlock(imageBlock("B4", caption: "狗")),
                 "changed image caption (OCR stand-in) → different hash")

        // Documented decision: metadata that does not affect retrieval must NOT
        // change the hash, otherwise re-tagging or moving a note re-embeds it.
        let base = textBlock("B1", "内容", order: 0)
        let moved = textBlock("B1", "内容", order: 7)
        r.expect(AIContentHash.forBlock(base) == AIContentHash.forBlock(moved),
                 "metadata-only change (order) does NOT change hash — documented decision")

        // Whitespace is normalised, so a trailing newline is not a content change.
        r.expect(AIContentHash.forBlock(textBlock("B1", "内容")) ==
                 AIContentHash.forBlock(textBlock("B1", "  内容\n")),
                 "surrounding whitespace normalised")

        // Card-level includes title.
        let blocks = [textBlock("B1", "x", order: 0)]
        r.expect(AIContentHash.forCard(title: "A", blocks: blocks) !=
                 AIContentHash.forCard(title: "B", blocks: blocks),
                 "card hash includes title")

        // Blocks with no retrievable text are excluded from the work map.
        let map = AIContentHash.retrievableBlockHashes([
            textBlock("B1", "有内容"),
            textBlock("B2", "   "),
            imageBlock("B3", caption: "")
        ])
        r.expect(map.keys.sorted() == ["B1"], "empty blocks excluded from retrievable hashes")
    }

    // MARK: 3 · Provider replaceability

    static func checkProvider(_ r: CheckRunner) async {
        r.suite("Week1 · EmbeddingProvider — replaceable, mock deterministic")

        let mock = MockEmbeddingProvider(dimension: 8)
        let v1 = try? await mock.embed("hello")
        let v2 = try? await mock.embed("hello")
        r.expect(v1 != nil && v1 == v2, "mock provider deterministic for same input")
        r.expect(v1?.count == 8, "vector dimension matches modelInfo")

        let v3 = try? await mock.embed("world")
        r.expect(v1 != v3, "different input → different vector")

        let norm = (v1 ?? []).reduce(0) { $0 + $1 * $1 }
        r.expect(abs(norm - 1.0) < 0.001, "vector is L2-normalised")

        let batch = try? await mock.embed(batch: ["a", "b"])
        r.expect(batch?.count == 2, "batch embed returns one vector per input")
        r.expect(batch?.first == (try? await mock.embed("a")), "batch matches single-shot")

        // Empty input is rejected rather than silently producing a vector.
        do { _ = try await mock.embed("   "); r.expect(false, "empty input should throw") }
        catch { r.expect(true, "empty input rejected") }

        // 可替换性：管线只依赖协议。三个实现（mock / 本地 NLEmbedding / 云端）
        // 编译于同一个协议之下 —— 这正是 TD-5 能被一个文件关闭的原因。
        var providers: [any EmbeddingProvider] = [MockEmbeddingProvider()]
        if let local = try? LocalEmbedding.make() { providers.append(local) }
        providers.append(CloudEmbeddingProvider(baseURL: "https://x.test/v1", apiKey: "k",
                                                model: "text-embedding-3-small", dimension: 1536))
        r.expect(providers.count >= 2, "多个实现共用一个协议（\(providers.count) 个）")
        r.expect(Set(providers.map { $0.modelInfo.version }).count == providers.count,
                 "每个 provider 的 version 互不相同 —— 换 provider 必须让索引失效")

        // Version identity flows into the job key.
        let k = EmbeddingJobKey(noteID: "N", blockID: "B", contentHash: "h", embeddingVersion: mock.modelInfo.version)
        r.expect(k.embeddingVersion == "mock-v1", "job key carries embedding version")
    }

    // MARK: 4 · Job identity & coordinator

    static func checkCoordinator(_ r: CheckRunner) async {
        r.suite("Week1 · AIJobCoordinator — dedup / concurrency / retry / cancellation")

        let keyA = EmbeddingJobKey(noteID: "N", blockID: "B", contentHash: "h1", embeddingVersion: version)
        let keyAPrime = EmbeddingJobKey(noteID: "N", blockID: "B", contentHash: "h1", embeddingVersion: version)
        let keyEdited = EmbeddingJobKey(noteID: "N", blockID: "B", contentHash: "h2", embeddingVersion: version)
        r.expect(keyA == keyAPrime, "same 4-tuple → equal key")
        r.expect(keyA != keyEdited, "content change → different key")
        r.expect(keyA != EmbeddingJobKey(noteID: "N", blockID: "B", contentHash: "h1", embeddingVersion: "other"),
                 "embedding version change → different key")

        // --- dedup ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 4))
            let counter = Counter()
            let t1 = await coord.submit(keyA) { await counter.bump(); try? await Task.sleep(nanoseconds: 30_000_000); return 1 }
            let t2 = await coord.submit(keyAPrime) { await counter.bump(); return 2 }
            _ = try? await t1.value
            _ = try? await t2.value
            let runs = await counter.value
            let stats = await coord.currentStats()
            r.expect(runs == 1, "identical key executed once (dedup)")
            r.expect(stats.deduped == 1, "dedup counted")
        }

        // --- edit must NOT be deduped ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 4))
            let counter = Counter()
            let t1 = await coord.submit(keyA) { await counter.bump(); try? await Task.sleep(nanoseconds: 20_000_000); return 1 }
            let t2 = await coord.submit(keyEdited) { await counter.bump(); return 2 }
            _ = try? await t1.value
            _ = try? await t2.value
            let runs = await counter.value
            r.expect(runs == 2, "edited content is a different job — NOT deduped")
        }

        // --- concurrency limit ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 2))
            var tasks: [Task<Int, Error>] = []
            for i in 0..<6 {
                let k = EmbeddingJobKey(noteID: "N", blockID: "B\(i)", contentHash: "h", embeddingVersion: version)
                tasks.append(await coord.submit(k) { try? await Task.sleep(nanoseconds: 20_000_000); return i })
            }
            for t in tasks { _ = try? await t.value }
            let stats = await coord.currentStats()
            r.expect(stats.peakConcurrent <= 2, "peak concurrency respected (observed \(stats.peakConcurrent))")
            r.expect(stats.succeeded == 6, "all six jobs completed")
        }

        // --- retry on retryable error, with backoff ---
        do {
            let sleeper = RecordingSleeper()
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 1, maxAttempts: 3, baseBackoffNanos: 100),
                                              sleeper: sleeper)
            let k = EmbeddingJobKey(noteID: "N", blockID: "R", contentHash: "h", embeddingVersion: version)
            let t = await coord.submit(k) { throw EmbeddingProviderError.transport("boom") }
            _ = try? await t.value
            let stats = await coord.currentStats()
            let delays = await sleeper.recorded()
            r.expect(stats.attempts == 3, "retried up to maxAttempts (attempts=\(stats.attempts))")
            r.expect(stats.retried == 2, "two retries between three attempts")
            r.expect(stats.failed == 1, "job ultimately failed")
            r.expect(delays == [100, 200], "exponential backoff 100→200 (got \(delays))")
        }

        // --- non-retryable error is not retried ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 1, maxAttempts: 3, baseBackoffNanos: 1),
                                              sleeper: RecordingSleeper())
            let k = EmbeddingJobKey(noteID: "N", blockID: "X", contentHash: "h", embeddingVersion: version)
            let t = await coord.submit(k) { throw EmbeddingProviderError.rejected("401") }
            _ = try? await t.value
            let stats = await coord.currentStats()
            r.expect(stats.attempts == 1, "auth failure not retried")
        }

        // --- cancellation ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 2))
            let k = EmbeddingJobKey(noteID: "N", blockID: "C", contentHash: "h", embeddingVersion: version)
            let t = await coord.submit(k) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 1
            }
            await coord.cancel(k)
            _ = try? await t.value
            let stats = await coord.currentStats()
            r.expect(stats.cancelled == 1, "cancellation observed")
            let stillThere = await coord.isInFlight(k)
            r.expect(!stillThere, "cancelled job removed from in-flight table")
        }

        // --- slot released after failure (no leak) ---
        do {
            let coord = AIJobCoordinator<Int>(policy: .init(maxConcurrent: 1, maxAttempts: 1, baseBackoffNanos: 1),
                                              sleeper: RecordingSleeper())
            for i in 0..<3 {
                let k = EmbeddingJobKey(noteID: "N", blockID: "F\(i)", contentHash: "h", embeddingVersion: version)
                let t = await coord.submit(k) { throw EmbeddingProviderError.rejected("no") }
                _ = try? await t.value
            }
            let k = EmbeddingJobKey(noteID: "N", blockID: "OK", contentHash: "h", embeddingVersion: version)
            let t = await coord.submit(k) { 42 }
            let v = try? await t.value
            r.expect(v == 42, "gate slot released after failures — queue not deadlocked")
        }
    }

    // MARK: 5 · Stale protection (the Week 1 headline)

    static func checkStaleProtection(_ r: CheckRunner) async {
        r.suite("Week1 · Stale Protection — old results never overwrite new content")

        let ref = BlockRef(noteID: "N1", blockID: "B1")
        let v12 = "hash_v12", v13 = "hash_v13"

        func result(_ hash: String, _ vec: [Float] = [1, 0, 0]) -> DerivedResult<[Float]> {
            DerivedResult(key: EmbeddingJobKey(ref: ref, contentHash: hash, embeddingVersion: version), payload: vec)
        }
        func ctx(_ hash: String?, noteExists: Bool = true, ver: String = version) -> DerivedWriteContext {
            DerivedWriteContext(noteExists: noteExists, currentContentHash: hash, currentEmbeddingVersion: ver)
        }

        // The canonical scenario from the spec.
        r.expect(StaleGuard.decide(for: result(v12), context: ctx(v13)) ==
                 .reject(.contentChanged(expected: v12, current: v13)),
                 "v12 result rejected after note advanced to v13")
        r.expect(StaleGuard.decide(for: result(v13), context: ctx(v13)).isAccepted,
                 "current result accepted")

        r.expect(StaleGuard.decide(for: result(v12), context: ctx(nil)) == .reject(.blockDeleted),
                 "result for deleted block rejected")
        r.expect(StaleGuard.decide(for: result(v12), context: ctx(v12, noteExists: false)) == .reject(.noteDeleted),
                 "result for deleted note rejected")
        r.expect(StaleGuard.decide(for: result(v12), context: ctx(v12, ver: "other")) ==
                 .reject(.embeddingVersionChanged(expected: version, current: "other")),
                 "result from superseded embedding version rejected")

        // --- end-to-end through the persistence boundary ---

        // Case A: provider IGNORES cancellation, finishes after the edit landed.
        do {
            let store = InMemoryDerivedStore(embeddingVersion: version)
            await store.setHash(ref, v12)
            let coord = AIJobCoordinator<[Float]>(policy: .init(maxConcurrent: 2))
            let provider = MockEmbeddingProvider(delayNanos: 60_000_000, ignoresCancellation: true)

            let key12 = EmbeddingJobKey(ref: ref, contentHash: v12, embeddingVersion: version)
            let started = Counter()
            let t = await coord.submit(key12) {
                await started.bump()
                return try await provider.embed("old content")
            }

            // Wait until the job is genuinely inside the provider call. Cancelling
            // before that point would make the coordinator short-circuit, which is
            // the *easy* case — the case worth testing is a provider already at work.
            while await started.value == 0 { await Task.yield() }

            // user edits mid-flight
            await store.setHash(ref, v13)
            await coord.cancel(key12)   // best-effort; provider ignores it

            if let vec = try? await t.value {
                let decision = await store.commit(DerivedResult(key: key12, payload: vec), chunkID: "c0", dimension: 8)
                r.expect(!decision.isAccepted, "provider ignored cancellation, but result was refused at persist")
                r.expect(decision.rejection == .contentChanged(expected: v12, current: v13), "refusal reason is contentChanged")
            } else {
                r.expect(false, "expected the non-cancellable provider to return a value")
            }
            let stored = await store.record(for: ref)
            r.expect(stored == nil, "no stale record written")
        }

        // Case B: old task returns AFTER the new task already wrote.
        do {
            let store = InMemoryDerivedStore(embeddingVersion: version)
            await store.setHash(ref, v13)
            let newVec: [Float] = [0, 1, 0]
            let d1 = await store.commit(DerivedResult(key: .init(ref: ref, contentHash: v13, embeddingVersion: version),
                                                      payload: newVec), chunkID: "c1", dimension: 3)
            r.expect(d1.isAccepted, "new result persisted")

            let d2 = await store.commit(DerivedResult(key: .init(ref: ref, contentHash: v12, embeddingVersion: version),
                                                      payload: [9, 9, 9]), chunkID: "c0", dimension: 3)
            r.expect(!d2.isAccepted, "late old result refused")
            let stored = await store.record(for: ref)
            r.expect(stored?.vector == newVec, "new result remains authoritative")
            r.expect(stored?.contentHash == v13, "stored record still tagged v13")
        }

        // Case C: multiple rapid edits — only the final version may persist.
        do {
            let store = InMemoryDerivedStore(embeddingVersion: version)
            let versions = ["h1", "h2", "h3", "h4", "h5"]
            await store.setHash(ref, versions.last!)
            var accepted = 0
            for h in versions {
                let d = await store.commit(DerivedResult(key: .init(ref: ref, contentHash: h, embeddingVersion: version),
                                                         payload: [Float(versions.firstIndex(of: h)!)]),
                                           chunkID: "c", dimension: 1)
                if d.isAccepted { accepted += 1 }
            }
            r.expect(accepted == 1, "exactly one of five rapid-edit results persisted")
            let stored = await store.record(for: ref)
            r.expect(stored?.contentHash == "h5", "the surviving record is the newest content")
        }

        // Case D: retry returns stale output after the content moved on.
        do {
            let store = InMemoryDerivedStore(embeddingVersion: version)
            await store.setHash(ref, v12)
            let sleeper = RecordingSleeper()
            let coord = AIJobCoordinator<[Float]>(policy: .init(maxConcurrent: 1, maxAttempts: 3, baseBackoffNanos: 1),
                                                  sleeper: sleeper)
            let key12 = EmbeddingJobKey(ref: ref, contentHash: v12, embeddingVersion: version)
            let attempts = Counter()
            let t = await coord.submit(key12) {
                let n = await attempts.bumpAndGet()
                if n < 3 { throw EmbeddingProviderError.transport("flaky") }
                return [7, 7, 7] as [Float]
            }
            // Edit lands while the job is still retrying.
            await store.setHash(ref, v13)
            let vec = try? await t.value
            r.expect(vec != nil, "retry eventually produced a value")
            let d = await store.commit(DerivedResult(key: key12, payload: vec ?? []), chunkID: "c", dimension: 3)
            r.expect(!d.isAccepted, "successful retry of a stale job still refused at persist")
            let stored = await store.record(for: ref)
            r.expect(stored == nil, "no record written from stale retry")
        }
    }

    // MARK: 6 · Restart / recovery

    static func checkRestart(_ r: CheckRunner) async {
        r.suite("Week1 · Restart — rescan is safe and idempotent")

        let strategy = ChunkStrategy.block
        let blocks = [
            textBlock("B1", "第一段", order: 0),
            audioBlock("B2", transcript: "录音转写", order: 1),
            textBlock("B3", "   ", order: 2)          // no retrievable text
        ]
        func scan(_ bs: [CardBlockContent],
                  _ stored: [String: StoredChunkRecord],
                  _ ver: String = version) -> DerivedWorkPlan {
            DerivedWorkScanner.plan(noteID: "N1", blocks: bs, strategy: strategy,
                                    existingRecords: stored, embeddingVersion: ver)
        }
        func store(_ plan: DerivedWorkPlan) -> [String: StoredChunkRecord] {
            var out: [String: StoredChunkRecord] = [:]
            for item in plan.pending {
                out[item.chunkID] = StoredChunkRecord(contentHash: item.key.contentHash,
                                                      embeddingVersion: version,
                                                      chunkStrategy: strategy.identity)
            }
            return out
        }

        // Cold start: nothing stored.
        let cold = scan(blocks, [:])
        r.expect(cold.pending.count == 2, "cold start queues the two retrievable blocks")
        r.expect(cold.upToDate.isEmpty, "nothing up to date on cold start")
        r.expect(!cold.pending.contains { $0.key.blockID == "B3" }, "empty block produces no work")

        // Everything embedded at current hashes → no work.
        let stored = store(cold)
        let warm = scan(blocks, stored)
        r.expect(warm.pending.isEmpty, "rescan after full completion queues nothing (idempotent)")
        r.expect(warm.upToDate.count == 2, "both chunks reported up to date")

        // Simulate "app killed mid-job": one chunk never got written.
        var partial = stored
        partial.removeValue(forKey: ChunkPipeline.chunkID(ref: BlockRef(noteID: "N1", blockID: "B2"), index: 0))
        let afterCrash = scan(blocks, partial)
        r.expect(afterCrash.pending.map(\.key.blockID) == ["B2"], "restart re-queues only the unfinished chunk")
        r.expect(afterCrash.orphanChunkIDs.isEmpty, "no orphans after a clean crash")

        // Edit while the app was closed → stale record detected on rescan.
        let editedBlocks = [textBlock("B1", "第一段改过了", order: 0), blocks[1], blocks[2]]
        r.expect(scan(editedBlocks, stored).pending.map(\.key.blockID) == ["B1"],
                 "content edited offline is re-queued")

        // Embedding version bump invalidates everything.
        r.expect(scan(blocks, stored, "mock-v2").pending.count == 2, "model change re-queues every chunk")

        // Deleted block leaves an orphan record to clean up.
        let afterDelete = scan([blocks[0]], stored)
        r.expect(afterDelete.orphanChunkIDs == ["N1/B2/0"], "deleted block reported as orphan chunk")

        // Block losing its text is also an orphan (not silently kept).
        let emptied = [textBlock("B1", "第一段", order: 0), audioBlock("B2", transcript: "", order: 1)]
        r.expect(scan(emptied, stored).orphanChunkIDs == ["N1/B2/0"],
                 "block that lost its text becomes an orphan")

        // No "running" state is ever persisted, so nothing can get stuck.
        r.expect(warm.hasWork == false, "a fully-derived note reports no work — no stuck running flag possible")
    }

    // MARK: 7 · RetrievalTrace foundation

    static func checkTrace(_ r: CheckRunner) async {
        r.suite("Week1 · RetrievalTrace — recorder boundary")

        let rec = RetrievalTraceRecorder(capacity: 3)
        for i in 0..<5 {
            await rec.record(RetrievalTrace(query: "q\(i)", configVersion: "retrieval-v1", embeddingVersion: version))
        }
        let count = await rec.count()
        r.expect(count == 3, "ring buffer bounded to capacity")
        let recent = await rec.recent()
        r.expect(recent.first?.query == "q4", "newest first")
        r.expect(recent.last?.query == "q2", "oldest retained is q2")

        let t = RetrievalTrace(query: "延期毕业", configVersion: "retrieval-v1",
                               embeddingVersion: version, indexVersion: "idx1",
                               chunkCount: 10, candidateCount: 6, resultCount: 3,
                               contentHash: "abc", isStale: false)
        r.expect(t.query == "延期毕业" && t.chunkCount == 10 && !t.isStale,
                 "trace carries identity + volume + staleness fields")

        // Codable so it can be dumped for debugging without a UI.
        let data = try? JSONEncoder().encode(t)
        let back = data.flatMap { try? JSONDecoder().decode(RetrievalTrace.self, from: $0) }
        r.expect(back == t, "trace round-trips through Codable")

        await rec.clear()
        let cleared = await rec.count()
        r.expect(cleared == 0, "recorder clears")
    }

    // MARK: 8 · Derived-data boundary

    static func checkBoundary(_ r: CheckRunner) {
        r.suite("Week1 · Derived data boundary — core note data untouched")

        // Derived types reference core data by id only.
        let ref = BlockRef(noteID: "N1", blockID: "B1")
        let chunk = NoteChunk(id: "N1/B1/0", ref: ref, source: .text, indexInBlock: 0,
                              text: "hello", contentHash: "h")
        r.expect(chunk.ref.noteID == "N1", "chunk points at note by id")

        let rec = EmbeddingRecord(ref: ref, chunkID: chunk.id, contentHash: "h",
                                  embeddingVersion: version, dimension: 3, vector: [1, 2, 3])
        r.expect(rec.ref == ref && rec.contentHash == "h", "embedding record carries validation fields")

        // Corpus definition: which projection each block kind contributes.
        r.expect(RetrievableText.extract(from: textBlock("B", "t"))?.source == .text, "text → .text")
        r.expect(RetrievableText.extract(from: audioBlock("B", transcript: "t"))?.source == .transcript,
                 "audio → .transcript")
        r.expect(RetrievableText.extract(from: fileBlock("B", extracted: "t"))?.source == .extracted,
                 "document → .extracted")
        r.expect(RetrievableText.extract(from: imageBlock("B", caption: "t"))?.source == .ocr,
                 "image → .ocr (caption stands in until IG-1 is closed)")

        let link = CardBlockContent(id: "B", order: 0, kind: .link,
                                    url: "https://x.test", linkTitle: "T", linkDescription: "D")
        r.expect(RetrievableText.extract(from: link)?.text.contains("T") == true, "link contributes title/description")

        r.expect(RetrievableText.isEmpty(textBlock("B", "  ")), "whitespace-only text contributes nothing")

        // All derived types are Codable ⇒ they can be rebuilt from scratch.
        r.expect((try? JSONEncoder().encode(chunk)) != nil, "NoteChunk is Codable (rebuildable)")
        r.expect((try? JSONEncoder().encode(rec)) != nil, "EmbeddingRecord is Codable (rebuildable)")
    }

    // MARK: Entry point

    static func run(_ r: CheckRunner) async {
        checkIdentity(r)
        checkHash(r)
        await checkProvider(r)
        await checkCoordinator(r)
        await checkStaleProtection(r)
        await checkRestart(r)
        await checkTrace(r)
        checkBoundary(r)
    }
}

// MARK: - Test doubles

/// Minimal counter usable from concurrent contexts.
actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
    func bumpAndGet() -> Int { value += 1; return value }
}

/// In-memory `DerivedStore`. Mirrors what the SwiftData store must do: read
/// current state and write **inside the same actor hop**.
actor InMemoryDerivedStore: DerivedStore {
    private var currentHashes: [BlockRef: String] = [:]
    private var deletedNotes: Set<String> = []
    private var records: [BlockRef: EmbeddingRecord] = [:]
    private let embeddingVersion: String

    init(embeddingVersion: String) { self.embeddingVersion = embeddingVersion }

    func setHash(_ ref: BlockRef, _ hash: String?) {
        if let hash { currentHashes[ref] = hash } else { currentHashes.removeValue(forKey: ref) }
    }
    func deleteNote(_ noteID: String) { deletedNotes.insert(noteID) }

    func writeContext(for ref: BlockRef, embeddingVersion _: String) -> DerivedWriteContext {
        DerivedWriteContext(noteExists: !deletedNotes.contains(ref.noteID),
                            currentContentHash: currentHashes[ref],
                            currentEmbeddingVersion: embeddingVersion)
    }
    func upsert(_ record: EmbeddingRecord) { records[record.ref] = record }
    func record(for ref: BlockRef) -> EmbeddingRecord? { records[ref] }
    func recordCount() -> Int { records.count }
}
