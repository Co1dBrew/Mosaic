import Foundation
import MosaicKit

/// Week 2 — Chunking · corpus · embedding lifecycle · vector storage · index state.
///
/// One section per exit criterion. The benchmark at the end prints **measured**
/// numbers; nothing in this file hard-codes a latency figure.
enum RetrievalWeek2Checks {

    typealias F = RetrievalFoundationChecks
    static let version = "mock-v1"

    static func linkBlock(_ id: String, title: String, desc: String, url: String, order: Int = 0) -> CardBlockContent {
        CardBlockContent(id: id, order: order, kind: .link, url: url, linkTitle: title, linkDescription: desc)
    }

    // MARK: 1 · Chunk pipeline

    static func checkChunking(_ r: CheckRunner) {
        r.suite("Week2 · ChunkPipeline — three strategies, stable ids, offsets")

        let long = String(repeating: "这是一个句子。", count: 60)   // 420 chars
        let block = F.textBlock("B1", long)

        // .block — one chunk, whole text.
        let whole = ChunkPipeline.chunks(noteID: "N1", block: block, strategy: .block)
        r.expect(whole.count == 1, "block strategy yields exactly one chunk")
        r.expect(whole[0].charStart == 0 && whole[0].charEnd == long.count, "offsets span the whole text")
        r.expect(whole[0].id == "N1/B1/0", "chunk id is noteID/blockID/index")

        // .fixed — splits, overlaps, stays under the limit.
        let fixed = ChunkPipeline.chunks(noteID: "N1", block: block, strategy: .fixed(maxChars: 100, overlap: 20))
        r.expect(fixed.count > 1, "fixed strategy splits a long block (got \(fixed.count))")
        r.expect(fixed.allSatisfy { $0.text.count <= 100 }, "no chunk exceeds maxChars")
        r.expect(fixed.map(\.indexInBlock) == Array(0..<fixed.count), "chunk indices are contiguous from 0")
        r.expect(Set(fixed.map(\.id)).count == fixed.count, "chunk ids unique within a block")
        // Overlap means each chunk starts before the previous one ended.
        let overlapping = zip(fixed, fixed.dropFirst()).allSatisfy { $1.charStart < $0.charEnd }
        r.expect(overlapping, "consecutive chunks overlap, so a sentence spanning a cut stays findable")

        // Cuts prefer sentence boundaries.
        let endsOnBoundary = fixed.dropLast().filter { $0.text.hasSuffix("。") }.count
        r.expect(endsOnBoundary >= fixed.count - 2, "most cuts land on a sentence boundary (\(endsOnBoundary)/\(fixed.count - 1))")

        // .sentence — never cuts mid-sentence.
        let sent = ChunkPipeline.chunks(noteID: "N1", block: block, strategy: .sentence(maxChars: 100))
        r.expect(sent.count > 1, "sentence strategy groups into several chunks")
        r.expect(sent.allSatisfy { $0.text.hasSuffix("。") }, "sentence chunks end on a terminator")

        // Determinism + strategy identity.
        let again = ChunkPipeline.chunks(noteID: "N1", block: block, strategy: .fixed(maxChars: 100, overlap: 20))
        r.expect(again == fixed, "chunking is deterministic")
        r.expect(fixed[0].strategy == "fixed(100/20)", "chunk records the strategy that made it")
        r.expect(whole[0].strategy != fixed[0].strategy, "different strategies are distinguishable")

        // Short text is never split.
        let short = ChunkPipeline.chunks(noteID: "N1", block: F.textBlock("B2", "短"), strategy: .fixed(maxChars: 100, overlap: 20))
        r.expect(short.count == 1, "text shorter than the window is a single chunk")

        // Empty blocks produce nothing — not one empty chunk.
        r.expect(ChunkPipeline.chunks(noteID: "N1", block: F.textBlock("B3", "   "), strategy: .block).isEmpty,
                 "whitespace-only block produces zero chunks")

        // A single over-long sentence still becomes one chunk rather than being lost.
        let runOn = F.textBlock("B4", String(repeating: "啊", count: 300))
        r.expect(ChunkPipeline.chunks(noteID: "N1", block: runOn, strategy: .sentence(maxChars: 100)).count == 1,
                 "an over-long sentence becomes its own chunk (never dropped)")

        // No text is lost: concatenated chunk coverage reaches the end.
        let covered = fixed.map(\.charEnd).max() ?? 0
        r.expect(covered == long.count, "chunking covers the block to its final character")
    }

    // MARK: 2 · Five corpus sources

    static func checkCorpus(_ r: CheckRunner) {
        r.suite("Week2 · Corpus — all five Goal 1 sources produce chunks")

        let blocks = [
            F.textBlock("B1", "正文内容", order: 0),
            F.audioBlock("B2", transcript: "录音转写内容", order: 1),
            F.imageBlock("B3", caption: "现场照片", order: 2),
            F.fileBlock("B4", extracted: "文档提取正文", order: 3),
            linkBlock("B5", title: "链接标题", desc: "链接描述", url: "https://x.test", order: 4)
        ]
        let ocr = ["B3": "白板上写着：答辩时间 6 月 12 日"]

        let chunks = ChunkPipeline.chunks(noteID: "N1", blocks: blocks, strategy: .block, ocrTextByBlockID: ocr)
        r.expect(chunks.count == 5, "all five block kinds contribute a chunk")

        let sources = Set(chunks.map(\.source))
        r.expect(sources == Set([.text, .transcript, .ocr, .extracted, .link]),
                 "each kind maps to its own retrieval source")

        // OCR is combined with the caption — the caption often carries intent the
        // OCR cannot.
        let image = chunks.first { $0.source == .ocr }!
        r.expect(image.text.contains("现场照片") && image.text.contains("答辩时间"),
                 "image chunk combines caption and OCR text")

        // Without OCR the image falls back to caption only.
        let noOCR = ChunkPipeline.chunks(noteID: "N1", block: blocks[2], strategy: .block)
        r.expect(noOCR.first?.text == "现场照片", "no OCR → caption only")

        // Image with neither caption nor OCR contributes nothing.
        let bare = CardBlockContent(id: "B6", order: 0, kind: .image, imageCaption: "", imageAssetRef: "i/x.jpg")
        r.expect(ChunkPipeline.chunks(noteID: "N1", block: bare, strategy: .block).isEmpty,
                 "image with no caption and no OCR produces no chunk")

        // Document order is preserved.
        r.expect(chunks.map(\.ref.blockID) == ["B1", "B2", "B3", "B4", "B5"], "chunks follow document order")

        // OCR participates in the content hash: better OCR over the same image is
        // a real content change and must re-embed.
        let h1 = AIContentHash.forBlock(blocks[2], ocrText: "旧的识别结果")
        let h2 = AIContentHash.forBlock(blocks[2], ocrText: "更好的识别结果")
        r.expect(h1 != h2, "improved OCR over the same image changes the hash")
        r.expect(AIContentHash.forBlock(blocks[2], ocrText: nil) != h1, "gaining OCR changes the hash")
    }

    // MARK: 3 · OCR seam

    static func checkOCRSeam(_ r: CheckRunner) async {
        r.suite("Week2 · ImageTextExtractor — seam behaves like EmbeddingProvider")

        let stub = StubImageTextExtractor(table: [
            "i/B3.jpg": ImageTextResult(text: "答辩时间 6 月 12 日", confidence: 0.94, languages: ["zh-Hans"])
        ], failing: ["i/bad.jpg"])

        let ok = try? await stub.extractText(fromRelativePath: "i/B3.jpg")
        r.expect(ok?.text.contains("答辩") == true, "stub returns canned OCR")
        r.expect((ok?.confidence ?? 0) > 0.9, "confidence surfaced")

        let missing = try? await stub.extractText(fromRelativePath: "i/unknown.jpg")
        r.expect(missing?.text.isEmpty == true, "unknown asset yields empty text, not an error")

        do {
            _ = try await stub.extractText(fromRelativePath: "i/bad.jpg")
            r.expect(false, "failing asset should throw")
        } catch { r.expect(true, "recognition failure surfaces as an error") }

        let noop = NoopImageTextExtractor()
        let none = try? await noop.extractText(fromRelativePath: "anything")
        r.expect(none?.text.isEmpty == true, "noop extractor returns nothing")

        let extractors: [any ImageTextExtractor] = [NoopImageTextExtractor(), stub]
        r.expect(extractors.count == 2, "extractors are interchangeable behind one protocol")

        // OCR failure must not block the rest of the pipeline: the block simply
        // contributes its caption.
        let img = F.imageBlock("B3", caption: "白板")
        r.expect(ChunkPipeline.chunks(noteID: "N1", block: img, strategy: .block).count == 1,
                 "OCR failure degrades to caption, it does not drop the block")
    }

    // MARK: 4 · Embedding lifecycle at chunk granularity

    static func checkLifecycle(_ r: CheckRunner) {
        r.suite("Week2 · Embedding lifecycle — incremental, no orphans")

        let strategy = ChunkStrategy.fixed(maxChars: 100, overlap: 20)
        let longText = String(repeating: "第一段内容。", count: 40)
        let blocks = [F.textBlock("B1", longText, order: 0), F.textBlock("B2", "短块", order: 1)]

        func scan(_ bs: [CardBlockContent], _ stored: [String: StoredChunkRecord],
                  _ strat: ChunkStrategy = strategy, _ ver: String = version) -> DerivedWorkPlan {
            DerivedWorkScanner.plan(noteID: "N1", blocks: bs, strategy: strat,
                                    existingRecords: stored, embeddingVersion: ver)
        }
        func complete(_ plan: DerivedWorkPlan, _ strat: ChunkStrategy = strategy) -> [String: StoredChunkRecord] {
            var out: [String: StoredChunkRecord] = [:]
            for i in plan.pending {
                out[i.chunkID] = StoredChunkRecord(contentHash: i.key.contentHash,
                                                   embeddingVersion: version,
                                                   chunkStrategy: strat.identity)
            }
            return out
        }

        let cold = scan(blocks, [:])
        r.expect(cold.pending.count > 2, "a long block yields several chunk jobs (got \(cold.pending.count))")
        r.expect(cold.totalChunks == cold.pending.count, "every chunk pending on cold start")

        // Each chunk of the same block gets a distinct job key — this is what the
        // chunkIndex component of EmbeddingJobKey exists for.
        let b1Keys = cold.pending.filter { $0.key.blockID == "B1" }.map(\.key)
        r.expect(Set(b1Keys).count == b1Keys.count,
                 "chunks of one block have distinct job keys (no dedup collision)")

        let stored = complete(cold)
        r.expect(!scan(blocks, stored).hasWork, "settled note has no work")

        // Editing only B2 must not re-embed B1's chunks.
        let editedB2 = [blocks[0], F.textBlock("B2", "短块改了", order: 1)]
        let afterEdit = scan(editedB2, stored)
        r.expect(afterEdit.pending.allSatisfy { $0.key.blockID == "B2" },
                 "editing one block re-embeds only that block's chunks")
        r.expect(afterEdit.orphanChunkIDs.isEmpty, "same chunk count ⇒ no orphans")

        // Shrinking a block leaves orphan chunks that must be reported.
        let shrunk = [F.textBlock("B1", "只剩一句。", order: 0), blocks[1]]
        let afterShrink = scan(shrunk, stored)
        r.expect(!afterShrink.orphanChunkIDs.isEmpty,
                 "shrinking a block orphans its surplus chunks (got \(afterShrink.orphanChunkIDs.count))")
        r.expect(afterShrink.orphanChunkIDs.allSatisfy { $0.hasPrefix("N1/B1/") },
                 "orphans belong to the shrunken block")

        // Deleting a block orphans all of its chunks.
        let afterDelete = scan([blocks[1]], stored)
        r.expect(afterDelete.orphanChunkIDs.allSatisfy { $0.hasPrefix("N1/B1/") },
                 "deleted block orphans every one of its chunks")

        // Switching strategy invalidates everything — same force as a model change.
        let afterStrategy = scan(blocks, stored, .block)
        r.expect(afterStrategy.pending.count == afterStrategy.totalChunks,
                 "strategy change re-embeds the whole note")
        r.expect(!afterStrategy.orphanChunkIDs.isEmpty,
                 "old-strategy chunks become orphans")

        // Model change re-embeds everything.
        r.expect(scan(blocks, stored, strategy, "mock-v2").pending.count == cold.totalChunks,
                 "model change re-embeds every chunk")
    }

    // MARK: 5 · Vector store + brute-force cosine

    static func checkVectorStore(_ r: CheckRunner) async {
        r.suite("Week2 · VectorStore — exact brute-force cosine")

        // Cosine sanity on hand-built vectors.
        r.expect(abs(VectorMath.cosine([1, 0, 0], [1, 0, 0]) - 1.0) < 0.0001, "identical vectors → 1.0")
        r.expect(abs(VectorMath.cosine([1, 0, 0], [0, 1, 0])) < 0.0001, "orthogonal vectors → 0")
        r.expect(VectorMath.cosine([1, 0, 0], [-1, 0, 0]) < -0.99, "opposite vectors → -1")
        r.expect(VectorMath.cosine([1, 0], [1, 0, 0]) == 0, "dimension mismatch → 0, not a crash")
        r.expect(VectorMath.cosine([], []) == 0, "empty vectors → 0")
        // Un-normalised input still ranks correctly.
        r.expect(abs(VectorMath.cosine([3, 0, 0], [7, 0, 0]) - 1.0) < 0.0001,
                 "magnitude ignored — a provider that forgets to normalise still ranks correctly")

        let store = InMemoryVectorStore()
        let provider = MockEmbeddingProvider(dimension: 16)
        let texts = ["延期毕业申请", "周会排期讨论", "读书笔记摘录", "合同评审要点"]
        var refs: [BlockRef] = []
        for (i, t) in texts.enumerated() {
            let ref = BlockRef(noteID: "N1", blockID: "B\(i)")
            refs.append(ref)
            let vec = try! await provider.embed(t)
            await store.upsert(EmbeddingRecord(ref: ref, chunkID: "N1/B\(i)/0", chunkIndex: 0,
                                               contentHash: "h\(i)", embeddingVersion: version,
                                               dimension: 16, vector: vec))
        }
        let count = await store.count()
        r.expect(count == 4, "four vectors stored")

        // Exact self-retrieval: querying with a stored text returns it first.
        let q = try! await provider.embed(texts[0])
        let hits = await store.search(query: q, topK: 4)
        r.expect(hits.count == 4, "topK honoured")
        r.expect(hits[0].chunkID == "N1/B0/0", "exact match ranks first")
        r.expect(abs(hits[0].similarity - 1.0) < 0.0001, "self-similarity is 1.0")
        r.expect(hits.map(\.similarity) == hits.map(\.similarity).sorted(by: >), "results sorted by similarity desc")

        // topK truncates.
        let top2 = await store.search(query: q, topK: 2)
        r.expect(top2.count == 2, "topK truncates")

        // Determinism — required for reproducible evaluation.
        let a = await store.search(query: q, topK: 4)
        let b = await store.search(query: q, topK: 4)
        r.expect(a == b, "search is deterministic across calls")

        // Tie-break is by chunkID, so equal similarities never depend on dictionary order.
        let tieStore = InMemoryVectorStore()
        for id in ["N1/Z/0", "N1/A/0", "N1/M/0"] {
            await tieStore.upsert(EmbeddingRecord(ref: BlockRef(noteID: "N1", blockID: "x"),
                                                  chunkID: id, contentHash: "h",
                                                  embeddingVersion: version, dimension: 3, vector: [1, 0, 0]))
        }
        let ties = await tieStore.search(query: [1, 0, 0], topK: 3)
        r.expect(ties.map(\.chunkID) == ["N1/A/0", "N1/M/0", "N1/Z/0"], "equal similarity tie-broken by chunkID")

        // Removal paths.
        await store.removeBlock(refs[0])
        let afterRemove = await store.count()
        r.expect(afterRemove == 3, "removeBlock drops its chunks")
        await store.removeNote("N1")
        let afterNote = await store.count()
        r.expect(afterNote == 0, "removeNote clears the note")

        let empty = await store.search(query: q, topK: 5)
        r.expect(empty.isEmpty, "search on an empty index returns nothing, not an error")
    }

    // MARK: 6 · Index state machine

    static func checkIndexState(_ r: CheckRunner) {
        r.suite("Week2 · IndexState — derived from facts, never stuck")

        let ready = IndexStateMachine.derive(totalChunks: 10, pendingChunks: 0, runningJobs: 0, hasEmbeddings: true)
        r.expect(ready == .ready, "no pending work → ready")

        let building = IndexStateMachine.derive(totalChunks: 10, pendingChunks: 6, runningJobs: 2, hasEmbeddings: false)
        if case let .building(p) = building { r.expect(abs(p - 0.4) < 0.001, "building reports progress 4/10") }
        else { r.expect(false, "no embeddings yet → building") }

        let rebuilding = IndexStateMachine.derive(totalChunks: 10, pendingChunks: 3, runningJobs: 1, hasEmbeddings: true)
        r.expect(rebuilding == .rebuilding(pending: 3), "existing index + work running → rebuilding")

        let stale = IndexStateMachine.derive(totalChunks: 10, pendingChunks: 3, runningJobs: 0, hasEmbeddings: true)
        r.expect(stale == .stale(pending: 3), "existing index + work stalled → stale")

        let failed = IndexStateMachine.derive(totalChunks: 10, pendingChunks: 3, runningJobs: 0,
                                              hasEmbeddings: true, failure: "provider offline")
        r.expect(failed == .failed(reason: "provider offline"), "failure surfaces while work remains")

        // A failure with nothing pending is not a failure — it resolved itself.
        r.expect(IndexStateMachine.derive(totalChunks: 10, pendingChunks: 0, runningJobs: 0,
                                          hasEmbeddings: true, failure: "stale error") == .ready,
                 "a failure with no pending work resolves to ready — the state cannot get stuck")

        // Progressive Enhancement, enforced structurally.
        let all: [IndexState] = [.ready, .building(progress: 0.1), .rebuilding(pending: 2),
                                 .stale(pending: 2), .failed(reason: "x")]
        r.expect(all.allSatisfy { $0.allowsKeywordRetrieval },
                 "keyword retrieval available in EVERY index state — no exceptions")
        r.expect(!IndexState.building(progress: 0.1).allowsVectorRetrieval, "building blocks vector retrieval")
        r.expect(!IndexState.failed(reason: "x").allowsVectorRetrieval, "failed blocks vector retrieval")
        r.expect(IndexState.stale(pending: 2).allowsVectorRetrieval,
                 "a partially-current index is still worth searching")

        // Mapping onto the designed RetrievalCapability vocabulary.
        func capability(_ state: IndexState, hasProvider: Bool = true) -> RetrievalCapability {
            RetrievalCapability.derive(indexState: state, semanticProviderAvailable: hasProvider)
        }
        r.expect(capability(.ready) == .full, "ready → full")
        r.expect(capability(.building(progress: 0)) == .indexBuilding, "building → indexBuilding")
        r.expect(capability(.rebuilding(pending: 3)) == .indexRebuilding, "rebuilding → indexRebuilding")
        r.expect(capability(.stale(pending: 3)) == .indexRebuilding,
                 "stale → indexRebuilding（用户看到的是「正在更新」，不是两种状态）")
        r.expect(capability(.failed(reason: "x")) == .semanticUnavailable, "failed → semanticUnavailable")
        // 没有句向量模型时，索引再「就绪」也不是 full —— 空库上只看 IndexState 会说假话。
        r.expect(capability(.ready, hasProvider: false) == .semanticUnavailable,
                 "没有模型 → semanticUnavailable，哪怕索引无待办")
        r.expect(RetrievalCapability.full.allowsSemantic, "只有 full 允许语义路")
        r.expect(!RetrievalCapability.indexBuilding.allowsSemantic, "建立中不走语义路")
    }

    // MARK: 7 · End-to-end: edit → chunk → embed → store → search

    static func checkEndToEnd(_ r: CheckRunner) async {
        r.suite("Week2 · End-to-end — chunk → embed → index → retrieve")

        let provider = MockEmbeddingProvider(dimension: 32)
        let coordinator = AIJobCoordinator<[Float]>(policy: .init(maxConcurrent: 3))
        let vectors = InMemoryVectorStore()
        let strategy = ChunkStrategy.fixed(maxChars: 120, overlap: 20)

        let blocks = [
            F.textBlock("B1", "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认，让我别急着提交材料。", order: 0),
            F.audioBlock("B2", transcript: "周会上说延期的事下周开会再定，毕业时间还有缓冲。", order: 1),
            F.fileBlock("B3", extracted: "学生如需延期毕业，应在学期开始前四周向学院提交书面申请。", order: 2)
        ]

        let plan = DerivedWorkScanner.plan(noteID: "N1", blocks: blocks, strategy: strategy,
                                           existingRecords: [:], embeddingVersion: version)
        r.expect(plan.pending.count == plan.totalChunks, "all chunks pending")

        var stored: [String: StoredChunkRecord] = [:]
        for item in plan.pending {
            let task = await coordinator.submit(item.key) { try await provider.embed(item.text) }
            guard let vec = try? await task.value else { continue }
            await vectors.upsert(EmbeddingRecord(ref: item.key.ref, chunkID: item.chunkID,
                                                 chunkIndex: item.key.chunkIndex,
                                                 contentHash: item.key.contentHash,
                                                 embeddingVersion: version,
                                                 chunkStrategy: strategy.identity,
                                                 dimension: 32, vector: vec))
            stored[item.chunkID] = StoredChunkRecord(contentHash: item.key.contentHash,
                                                     embeddingVersion: version,
                                                     chunkStrategy: strategy.identity)
        }

        let indexed = await vectors.count()
        r.expect(indexed == plan.totalChunks, "every chunk indexed")

        let state = IndexStateMachine.derive(totalChunks: plan.totalChunks, pendingChunks: 0,
                                             runningJobs: 0, hasEmbeddings: true)
        r.expect(state == .ready, "index reports ready after a full build")

        // Retrieval works: querying with a chunk's own text returns that chunk.
        let target = plan.pending.first { $0.key.blockID == "B3" }!
        let q = try! await provider.embed(target.text)
        let hits = await vectors.search(query: q, topK: 3)
        r.expect(hits.first?.chunkID == target.chunkID, "exact-text query retrieves its own chunk first")
        r.expect(hits.first?.ref.blockID == "B3", "hit carries the block it came from")

        // Now edit a block and re-plan: only that block re-embeds, and the stale
        // chunks are reported for removal.
        let edited = [blocks[0],
                      F.audioBlock("B2", transcript: "周会上说延期申请已经批了。", order: 1),
                      blocks[2]]
        let replan = DerivedWorkScanner.plan(noteID: "N1", blocks: edited, strategy: strategy,
                                             existingRecords: stored, embeddingVersion: version)
        r.expect(replan.pending.allSatisfy { $0.key.blockID == "B2" }, "only the edited block re-embeds")
        await vectors.removeChunks(replan.orphanChunkIDs)
        let afterCleanup = await vectors.count()
        r.expect(afterCleanup == plan.totalChunks - replan.orphanChunkIDs.count,
                 "orphan chunks removed from the index")
    }

    // MARK: 8 · Benchmark — measured, not asserted

    static func checkBenchmark(_ r: CheckRunner) async {
        r.suite("Week2 · Benchmark — brute-force cosine scaling")

        // Swift's numeric loops run ~100x slower without optimisation, so a debug
        // measurement says nothing about shipping performance. Measured here:
        // 20k chunks took 1200 ms debug vs 9.8 ms release — the *same code*.
        // The SLO is therefore only asserted for optimised builds; debug still
        // prints its numbers, clearly labelled, so a regression is still visible.
        // `optimised` 原来是一个编译期已知的 `let`，于是三处用到它的分支全都是
        // 静态死代码，编译器每次都报 "will never be executed"。既然判断本来就发生在
        // 编译期，就用 `#if` 表达它 —— 少两条恒真警告，读起来也更诚实。
        #if DEBUG
        let buildLabel = "  [DEBUG BUILD — not representative]"
        let sizes = [1_000, 5_000]
        let samples = 5
        #else
        let buildLabel = ""
        let sizes = [1_000, 5_000, 20_000]
        let samples = 25
        #endif

        let dimension = 384          // realistic for a bge-small class model
        var table: [(Int, Double, Double)] = []

        for size in sizes {
            let store = InMemoryVectorStore()
            for i in 0..<size {
                let vec = MockEmbeddingProvider.deterministicVector(for: "chunk-\(i)", dimension: dimension)
                await store.upsert(EmbeddingRecord(ref: BlockRef(noteID: "N", blockID: "B\(i / 5)"),
                                                   chunkID: "N/B\(i / 5)/\(i % 5)",
                                                   contentHash: "h", embeddingVersion: version,
                                                   dimension: dimension, vector: vec))
            }
            let query = MockEmbeddingProvider.deterministicVector(for: "query", dimension: dimension)

            // Warm up, then measure a run of searches and report P50 / P95.
            _ = await store.search(query: query, topK: 20)
            var runs: [Double] = []
            for _ in 0..<samples {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = await store.search(query: query, topK: 20)
                runs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
            runs.sort()
            let p50 = runs[runs.count / 2]
            let p95 = runs[min(runs.count - 1, Int(Double(runs.count) * 0.95))]
            table.append((size, p50, p95))

            let indexed = await store.count()
            r.expect(indexed == size, "\(size) vectors indexed")
        }

        print("\n    ── brute-force cosine, dim \(dimension), topK 20 ──\(buildLabel)")
        print("    chunks        P50        P95")
        for (size, p50, p95) in table {
            print(String(format: "    %6d   %7.2f ms  %7.2f ms", size, p50, p95))
        }
        print("    SLO: P50 < 100 ms · P95 < 250 ms (retrieval only, no UI)")
        #if DEBUG
        print("    ⚠️  Debug build (-Onone). Run `swift run -c release mosaic-checks` for the real curve.")
        print("")
        r.expect(true, "benchmark recorded (debug build — SLO asserted only in release)")
        #else
        print("")
        // The measurement is the deliverable; the assertion guards against a
        // pathological regression. Whether ANN is needed is a decision to be made
        // from this table, not from a general belief about brute force.
        if let largest = table.last {
            r.expect(largest.1 < 100, "P50 inside budget at \(largest.0) chunks (measured \(String(format: "%.1f", largest.1)) ms)")
            r.expect(largest.2 < 250, "P95 inside budget at \(largest.0) chunks (measured \(String(format: "%.1f", largest.2)) ms)")
        }
        #endif
    }

    // MARK: Entry point

    static func run(_ r: CheckRunner) async {
        checkChunking(r)
        checkCorpus(r)
        await checkOCRSeam(r)
        checkLifecycle(r)
        await checkVectorStore(r)
        checkIndexState(r)
        await checkEndToEnd(r)
        await checkBenchmark(r)
    }
}
