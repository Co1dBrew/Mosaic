import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Week 1 SwiftData concurrency spike
///
/// The MosaicKit checks prove the *logic* (`StaleGuard`, coordinator, scanner)
/// against an in-memory store. These tests prove the same guarantees hold against
/// **real SwiftData contexts, real `@Model` objects, and real actor hops** — which
/// is where the assumptions could quietly be wrong.
@MainActor
final class RetrievalFoundationTests: XCTestCase {

    // MARK: Fixtures

    private func makeStack() -> (notes: ModelContainer, derived: ModelContainer, store: DerivedDataStore) {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = ModelContainerFactory.makeDerived(inMemory: true)
        return (notes, derived, DerivedDataStore(container: derived))
    }

    @discardableResult
    private func makeCard(in ctx: ModelContext, text: String) throws -> (Card, Block) {
        let card = Card(userTitle: "Spike")
        ctx.insert(card)
        let block = Block(kind: .text, order: 0)
        block.text = text
        block.card = card
        ctx.insert(block)
        try ctx.save()
        return (card, block)
    }

    private func ref(_ card: Card, _ block: Block) -> BlockRef {
        BlockRef(noteID: card.id.uuidString, blockID: block.id.uuidString)
    }

    private func hash(_ block: Block) -> String {
        AIContentHash.forBlock(block.toContent())
    }

    // MARK: 1 · Stable identity against real SwiftData (IG-3)

    func testBlockIdentitySurvivesReorderEditAndRefetch() throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext

        let card = Card(userTitle: "N")
        ctx.insert(card)
        var made: [Block] = []
        for i in 0..<3 {
            let b = Block(kind: .text, order: i)
            b.text = "block \(i)"
            b.card = card
            ctx.insert(b)
            made.append(b)
        }
        try ctx.save()
        let originalIDs = made.map(\.id)

        // Reorder exactly the way NoteDetailView.moveBlocks does: rewrite `order`.
        let reordered = Array(card.orderedBlocks.reversed())
        for (i, b) in reordered.enumerated() { b.order = i }
        try ctx.save()
        XCTAssertEqual(Set(card.orderedBlocks.map(\.id)), Set(originalIDs),
                       "reorder must not change any block id")

        // Edit.
        let target = card.orderedBlocks[0]
        let idBeforeEdit = target.id
        let hashBefore = hash(target)
        target.text += " edited"
        try ctx.save()
        XCTAssertEqual(target.id, idBeforeEdit, "edit must not change block id")
        XCTAssertNotEqual(hash(target), hashBefore, "edit must change content hash")

        // "Restart": a fresh ModelContext over the same store must see the same ids.
        let fresh = ModelContext(stack.notes)
        let refetched = try fresh.fetch(FetchDescriptor<Block>())
        XCTAssertEqual(Set(refetched.map(\.id)), Set(originalIDs),
                       "block ids are persisted, so they survive a context/app restart")

        // And the ref is resolvable back to a unique block — this is what the future
        // Search Result → ScrollViewReader anchor depends on.
        let anchor = ref(card, target)
        let blockUUID = UUID(uuidString: anchor.blockID)!
        var byID = FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockUUID })
        byID.fetchLimit = 2
        let resolved = try fresh.fetch(byID)
        XCTAssertEqual(resolved.count, 1, "BlockRef resolves to exactly one block")
    }

    // MARK: 2 · Stale protection across real contexts — the headline

    func testStaleEmbeddingRejectedWhenNoteEditedMidFlight() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let (card, block) = try makeCard(in: ctx, text: "v12 内容")

        let provider = MockEmbeddingProvider(dimension: 8, delayNanos: 40_000_000, ignoresCancellation: true)
        let coordinator = AIJobCoordinator<[Float]>(policy: .init(maxConcurrent: 2))
        let anchor = ref(card, block)
        let hash12 = hash(block)
        let key12 = EmbeddingJobKey(ref: anchor, contentHash: hash12,
                                    embeddingVersion: provider.modelInfo.version)

        let text = RetrievableText.extract(from: block.toContent())!.text
        let job = await coordinator.submit(key12) { try await provider.embed(text) }

        // The user edits while the embedding is in flight. This runs on @MainActor,
        // exactly as NoteDetailView does.
        block.text = "v13 内容（已修改）"
        card.touch()
        try ctx.save()
        let hash13 = hash(block)
        XCTAssertNotEqual(hash12, hash13)

        // Provider ignores cancellation, so a value still comes back.
        await coordinator.cancel(key12)
        let vector = try await job.value
        XCTAssertEqual(vector.count, 8)

        let decision = stack.store.commit(DerivedResult(key: key12, payload: vector),
                                          chunkID: key12.chunkID,
                                          embeddingVersion: provider.modelInfo.version,
                                          noteContext: ctx)
        XCTAssertFalse(decision.isAccepted, "stale v12 result must not persist")
        XCTAssertEqual(decision.rejection, .contentChanged(expected: hash12, current: hash13))
        XCTAssertNil(stack.store.record(forChunk: key12.chunkID), "nothing written")
        XCTAssertEqual(stack.store.recordCount(), 0)

        // The v13 job then succeeds and becomes authoritative.
        let key13 = EmbeddingJobKey(ref: anchor, contentHash: hash13,
                                    embeddingVersion: provider.modelInfo.version)
        let text13 = RetrievableText.extract(from: block.toContent())!.text
        let vector13 = try await provider.embed(text13)
        let accept = stack.store.commit(DerivedResult(key: key13, payload: vector13),
                                        chunkID: key13.chunkID,
                                        embeddingVersion: provider.modelInfo.version,
                                        noteContext: ctx)
        XCTAssertTrue(accept.isAccepted)
        XCTAssertEqual(stack.store.record(forChunk: key13.chunkID)?.contentHash, hash13)

        // A late v12 result arriving after v13 landed must still be refused.
        let late = stack.store.commit(DerivedResult(key: key12, payload: vector),
                                      chunkID: key12.chunkID,
                                      embeddingVersion: provider.modelInfo.version,
                                      noteContext: ctx)
        XCTAssertFalse(late.isAccepted, "late old result refused even after a good write")
        XCTAssertEqual(stack.store.record(forChunk: key13.chunkID)?.vector, vector13,
                       "v13 remains authoritative")
        XCTAssertEqual(stack.store.recordCount(), 1, "no duplicate rows")
    }

    func testRapidEditsLeaveOnlyNewestEmbedding() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let (card, block) = try makeCard(in: ctx, text: "e0")
        let anchor = ref(card, block)
        let provider = MockEmbeddingProvider(dimension: 4)
        let version = provider.modelInfo.version

        var keys: [EmbeddingJobKey] = []
        for i in 0..<5 {
            block.text = "e\(i)"
            try ctx.save()
            keys.append(EmbeddingJobKey(ref: anchor, contentHash: hash(block), embeddingVersion: version))
        }
        let finalHash = hash(block)

        var accepted = 0
        for key in keys {
            let vec = try await provider.embed(key.contentHash)
            if stack.store.commit(DerivedResult(key: key, payload: vec), chunkID: key.chunkID,
                                  embeddingVersion: version, noteContext: ctx).isAccepted {
                accepted += 1
            }
        }
        XCTAssertEqual(accepted, 1, "only the result matching current content persists")
        XCTAssertEqual(stack.store.record(forChunk: keys[0].chunkID)?.contentHash, finalHash)
        XCTAssertEqual(stack.store.recordCount(), 1)
    }

    func testDeletedNoteAndDeletedBlockRejectWrites() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 4)
        let version = provider.modelInfo.version

        // Deleted block.
        let (card, block) = try makeCard(in: ctx, text: "内容")
        let anchor = ref(card, block)
        let key = EmbeddingJobKey(ref: anchor, contentHash: hash(block), embeddingVersion: version)
        let vec = try await provider.embed("内容")
        ctx.delete(block)
        try ctx.save()
        let d1 = stack.store.commit(DerivedResult(key: key, payload: vec), chunkID: key.chunkID,
                                    embeddingVersion: version, noteContext: ctx)
        XCTAssertEqual(d1.rejection, .blockDeleted)

        // Deleted note.
        let (card2, block2) = try makeCard(in: ctx, text: "另一条")
        let anchor2 = ref(card2, block2)
        let key2 = EmbeddingJobKey(ref: anchor2, contentHash: hash(block2), embeddingVersion: version)
        let vec2 = try await provider.embed("另一条")
        ctx.delete(card2)          // cascade deletes its blocks
        try ctx.save()
        let d2 = stack.store.commit(DerivedResult(key: key2, payload: vec2), chunkID: key2.chunkID,
                                    embeddingVersion: version, noteContext: ctx)
        XCTAssertEqual(d2.rejection, .noteDeleted)

        // Superseded embedding version.
        let (card3, block3) = try makeCard(in: ctx, text: "第三条")
        let key3 = EmbeddingJobKey(ref: ref(card3, block3), contentHash: hash(block3),
                                   embeddingVersion: "old-model")
        let vec3 = try await provider.embed("第三条")
        let d3 = stack.store.commit(DerivedResult(key: key3, payload: vec3), chunkID: key3.chunkID,
                                    embeddingVersion: version, noteContext: ctx)
        XCTAssertEqual(d3.rejection, .embeddingVersionChanged(expected: "old-model", current: version))

        XCTAssertEqual(stack.store.recordCount(), 0, "no rejected write reached the store")
    }

    // MARK: 3 · Restart safety

    func testRestartRescanRequeuesOnlyUnfinishedWork() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 4)
        let version = provider.modelInfo.version

        let card = Card(userTitle: "N")
        ctx.insert(card)
        for i in 0..<3 {
            let b = Block(kind: .text, order: i)
            b.text = "段落 \(i)"
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        let noteID = card.id.uuidString

        func plan(_ store: DerivedDataStore = stack.store) -> DerivedWorkPlan {
            DerivedWorkScanner.plan(noteID: noteID,
                                    blocks: card.blockContents(),
                                    strategy: .block,
                                    existingRecords: store.existingRecords(noteID: noteID),
                                    embeddingVersion: version)
        }

        // Cold start.
        XCTAssertEqual(plan().pending.count, 3)

        // Complete two of three, then "crash".
        for item in plan().pending.prefix(2) {
            let vec = try await provider.embed(item.text)
            stack.store.commit(DerivedResult(key: item.key, payload: vec), chunkID: item.chunkID,
                               chunkStrategy: ChunkStrategy.block.identity,
                               embeddingVersion: version, noteContext: ctx)
        }

        // Restart: brand-new store object over the same container, nothing in memory.
        let afterRestart = DerivedDataStore(container: stack.derived)
        let restartPlan = DerivedWorkScanner.plan(
            noteID: noteID, blocks: card.blockContents(), strategy: .block,
            existingRecords: afterRestart.existingRecords(noteID: noteID),
            embeddingVersion: version)
        XCTAssertEqual(restartPlan.pending.count, 1, "restart re-queues exactly the unfinished block")
        XCTAssertEqual(restartPlan.upToDate.count, 2)
        XCTAssertTrue(restartPlan.orphanChunkIDs.isEmpty, "an interrupted job leaves no orphan")

        // Finish it; a further restart finds nothing to do (idempotent).
        for item in restartPlan.pending {
            let vec = try await provider.embed(item.text)
            afterRestart.commit(DerivedResult(key: item.key, payload: vec), chunkID: item.chunkID,
                                chunkStrategy: ChunkStrategy.block.identity,
                                embeddingVersion: version, noteContext: ctx)
        }
        let settled = DerivedWorkScanner.plan(
            noteID: noteID, blocks: card.blockContents(), strategy: .block,
            existingRecords: afterRestart.existingRecords(noteID: noteID),
            embeddingVersion: version)
        XCTAssertFalse(settled.hasWork, "fully derived note reports no work — no stuck 'running' state")
        XCTAssertEqual(afterRestart.recordCount(), 3)

        // Deleting a block turns its record into a reported orphan, not silent debris.
        let victim = card.orderedBlocks[0]
        ctx.delete(victim)
        try ctx.save()
        let withOrphan = DerivedWorkScanner.plan(
            noteID: noteID, blocks: card.blockContents(), strategy: .block,
            existingRecords: afterRestart.existingRecords(noteID: noteID),
            embeddingVersion: version)
        XCTAssertEqual(withOrphan.orphanChunkIDs.count, 1)
        afterRestart.deleteChunks(withOrphan.orphanChunkIDs)
        XCTAssertEqual(afterRestart.recordCount(), 2, "orphan cleaned up")
    }

    // MARK: 4 · Derived-data boundary

    func testDeletingAllDerivedDataLeavesNotesIntact() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 4)
        let version = provider.modelInfo.version

        let (card, block) = try makeCard(in: ctx, text: "重要笔记内容")
        let anchor = ref(card, block)
        let key = EmbeddingJobKey(ref: anchor, contentHash: hash(block), embeddingVersion: version)
        let vec = try await provider.embed("重要笔记内容")
        XCTAssertTrue(stack.store.commit(DerivedResult(key: key, payload: vec), chunkID: key.chunkID,
                                         embeddingVersion: version, noteContext: ctx).isAccepted)
        XCTAssertEqual(stack.store.recordCount(), 1)

        // Nuke every derived record.
        stack.store.deleteAll()
        XCTAssertEqual(stack.store.recordCount(), 0)

        // User data is untouched — different container, different store file.
        let cards = try ctx.fetch(FetchDescriptor<Card>())
        let blocks = try ctx.fetch(FetchDescriptor<Block>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.text, "重要笔记内容")

        // And it is fully rebuildable.
        let rebuilt = DerivedWorkScanner.plan(noteID: card.id.uuidString,
                                              blocks: card.blockContents(), strategy: .block,
                                              existingRecords: stack.store.existingRecords(noteID: card.id.uuidString),
                                              embeddingVersion: version)
        XCTAssertEqual(rebuilt.pending.count, 1, "wiped derived data is simply re-derived")
    }

    // MARK: 5 · End-to-end pipeline shape

    func testEditToPersistPipelineWithConcurrencyAndDedup() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 8, delayNanos: 5_000_000)
        let version = provider.modelInfo.version
        let coordinator = AIJobCoordinator<[Float]>(policy: .init(maxConcurrent: 2))

        let card = Card(userTitle: "Pipeline")
        ctx.insert(card)
        for i in 0..<6 {
            let b = Block(kind: .text, order: i)
            b.text = "内容 \(i)"
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        let noteID = card.id.uuidString

        let plan = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(), strategy: .block,
                                           existingRecords: [:], embeddingVersion: version)
        XCTAssertEqual(plan.pending.count, 6)

        // Submit every item twice — dedup must collapse the duplicates.
        var jobs: [(EmbeddingJobKey, Task<[Float], Error>)] = []
        for item in plan.pending {
            let t1 = await coordinator.submit(item.key) { try await provider.embed(item.text) }
            _ = await coordinator.submit(item.key) { try await provider.embed(item.text) }
            jobs.append((item.key, t1))
        }
        for (key, task) in jobs {
            let vec = try await task.value
            stack.store.commit(DerivedResult(key: key, payload: vec), chunkID: key.chunkID,
                               embeddingVersion: version, noteContext: ctx)
        }

        let stats = await coordinator.currentStats()
        XCTAssertEqual(stats.deduped, 6, "each duplicate submission deduped")
        XCTAssertLessThanOrEqual(stats.peakConcurrent, 2, "concurrency limit honoured")
        XCTAssertEqual(stack.store.recordCount(), 6, "one record per block")

        let settled = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(), strategy: .block,
                                              existingRecords: stack.store.existingRecords(noteID: noteID),
                                              embeddingVersion: version)
        XCTAssertFalse(settled.hasWork, "pipeline reached a settled state")
    }
}
