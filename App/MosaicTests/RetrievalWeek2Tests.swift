import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// # Week 2 — chunking · OCR · lifecycle · vector index, against real SwiftData
///
/// The MosaicKit checks prove the logic in isolation. These prove it survives real
/// `@Model` objects, real fetches, and the real derived store — including OCR
/// running through Vision on an image the test generates itself.
@MainActor
final class RetrievalWeek2Tests: XCTestCase {

    private func makeStack() -> (notes: ModelContainer, derived: ModelContainer, store: DerivedDataStore) {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = ModelContainerFactory.makeDerived(inMemory: true)
        return (notes, derived, DerivedDataStore(container: derived))
    }

    private let strategy = ChunkStrategy.fixed(maxChars: 120, overlap: 20)

    // MARK: 1 · Chunk-granular lifecycle on real models

    func testLongBlockProducesManyChunksAndEditsAreIncremental() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 16)
        let version = provider.modelInfo.version

        let card = Card(userTitle: "长笔记")
        ctx.insert(card)
        let long = Block(kind: .text, order: 0)
        long.text = String(repeating: "这是一段会被切开的内容。", count: 30)
        long.card = card
        ctx.insert(long)
        let short = Block(kind: .text, order: 1)
        short.text = "短块"
        short.card = card
        ctx.insert(short)
        try ctx.save()
        let noteID = card.id.uuidString

        func plan(_ store: DerivedDataStore = stack.store) -> DerivedWorkPlan {
            DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(), strategy: strategy,
                                    existingRecords: store.existingRecords(noteID: noteID),
                                    embeddingVersion: version)
        }
        func embedAll(_ p: DerivedWorkPlan) async throws {
            for item in p.pending {
                let vec = try await provider.embed(item.text)
                stack.store.commit(DerivedResult(key: item.key, payload: vec),
                                   chunkID: item.chunkID, chunkIndex: item.key.chunkIndex,
                                   chunkStrategy: strategy.identity,
                                   embeddingVersion: version, noteContext: ctx)
            }
        }

        let cold = plan()
        XCTAssertGreaterThan(cold.pending.count, 2, "a long block splits into several chunks")
        XCTAssertEqual(cold.pending.count, cold.totalChunks)

        // Distinct job keys per chunk — this is what chunkIndex in the key is for.
        let keys = cold.pending.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "no two chunks share a job key")

        try await embedAll(cold)
        XCTAssertEqual(stack.store.recordCount(), cold.totalChunks, "one record per chunk")
        XCTAssertFalse(plan().hasWork, "settled after a full build")

        // Editing the short block must not touch the long block's chunks.
        short.text = "短块改了"
        try ctx.save()
        let afterEdit = plan()
        XCTAssertTrue(afterEdit.pending.allSatisfy { $0.key.blockID == short.id.uuidString },
                      "only the edited block re-embeds")
        XCTAssertTrue(afterEdit.orphanChunkIDs.isEmpty)

        // Shrinking the long block orphans its surplus chunks.
        let before = stack.store.recordCount()
        long.text = "只剩一句话了。"
        try ctx.save()
        let afterShrink = plan()
        XCTAssertFalse(afterShrink.orphanChunkIDs.isEmpty, "surplus chunks reported as orphans")
        stack.store.deleteChunks(afterShrink.orphanChunkIDs)
        XCTAssertLessThan(stack.store.recordCount(), before, "orphans actually removed")

        try await embedAll(plan())
        XCTAssertFalse(plan().hasWork, "settles again after the shrink")
    }

    // MARK: 2 · OCR through Vision, on a real generated image

    func testVisionOCRFeedsChunkPipelineAndHash() async throws {
        let extractor = VisionImageTextExtractor()

        // Render a PNG containing known printed text, write it into MediaStore,
        // and run the real extractor over it.
        let text = "MOSAIC 2026"
        guard let data = Self.renderPNG(text: text) else {
            throw XCTSkip("cannot render test image on this platform")
        }
        let relativePath = "test-ocr-\(UUID().uuidString).png"
        let url = MediaStore.shared.absoluteURL(for: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await extractor.extractText(fromRelativePath: relativePath)
        XCTAssertFalse(result.text.isEmpty, "Vision recognised something in the rendered image")
        XCTAssertTrue(result.text.uppercased().contains("MOSAIC"),
                      "recognised the printed word (got: \(result.text))")
        XCTAssertGreaterThan(result.confidence, 0, "confidence reported")

        // OCR text flows into the chunk pipeline and into the content hash.
        let block = CardBlockContent(id: "B1", order: 0, kind: .image,
                                     imageCaption: "海报", imageAssetRef: relativePath)
        let chunks = ChunkPipeline.chunks(noteID: "N1", block: block, strategy: .block, ocrText: result.text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].source, .ocr)
        XCTAssertTrue(chunks[0].text.contains("海报"), "caption retained")
        XCTAssertTrue(chunks[0].text.uppercased().contains("MOSAIC"), "OCR text included")

        XCTAssertNotEqual(AIContentHash.forBlock(block, ocrText: result.text),
                          AIContentHash.forBlock(block, ocrText: nil),
                          "gaining OCR changes the block hash, so the block re-embeds")

        // Missing asset fails loudly rather than returning empty text.
        do {
            _ = try await extractor.extractText(fromRelativePath: "does-not-exist.png")
            XCTFail("missing asset should throw")
        } catch let e as ImageTextExtractionError {
            XCTAssertEqual(e, .assetMissing("does-not-exist.png"))
        }
    }

    // MARK: 3 · OCR persistence in the derived store

    func testOCRIsStoredAsDerivedDataAndInvalidatedByImageChange() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext

        let card = Card(userTitle: "含图片")
        ctx.insert(card)
        let img = Block(kind: .image, order: 0)
        img.imageRelativePath = "img/a.jpg"
        img.caption = "白板"
        img.card = card
        ctx.insert(img)
        try ctx.save()

        let ref = BlockRef(noteID: card.id.uuidString, blockID: img.id.uuidString)
        let hashBefore = AIContentHash.forBlock(img.toContent())

        stack.store.saveOCR(ImageTextExtraction(ref: ref, contentHash: hashBefore,
                                                text: "答辩时间 6 月 12 日", confidence: 0.9),
                            engineIdentifier: "vision-accurate-v1")
        XCTAssertEqual(stack.store.ocrCount(), 1)
        XCTAssertEqual(stack.store.ocrText(for: ref, currentContentHashIgnoringOCR: hashBefore),
                       "答辩时间 6 月 12 日")

        // Replacing the image changes the block hash, so the stored OCR is stale
        // and must not be handed back.
        img.imageRelativePath = "img/b.jpg"
        try ctx.save()
        let hashAfter = AIContentHash.forBlock(img.toContent())
        XCTAssertNotEqual(hashBefore, hashAfter)
        XCTAssertNil(stack.store.ocrText(for: ref, currentContentHashIgnoringOCR: hashAfter),
                     "OCR from the previous image is refused")

        // OCR lives in the derived store, so wiping derived data removes it and
        // leaves the note untouched.
        stack.store.deleteAll()
        XCTAssertEqual(stack.store.ocrCount(), 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Block>()).count, 1, "the image block survives")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Block>()).first?.caption, "白板")
    }

    // MARK: 4 · Full pipeline: five sources → index → retrieve

    func testFiveSourcePipelineIntoVectorIndex() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 32)
        let version = provider.modelInfo.version
        let vectors = InMemoryVectorStore()

        let card = Card(userTitle: "五类语料")
        ctx.insert(card)

        let text = Block(kind: .text, order: 0)
        text.text = "我问了 advisor 能不能延期一个学期毕业。"
        text.card = card; ctx.insert(text)

        let audio = Block(kind: .audio, order: 1)
        audio.audioRelativePath = "a/1.m4a"
        audio.transcript = "周会上说延期的事下周开会再定。"
        audio.card = card; ctx.insert(audio)

        let image = Block(kind: .image, order: 2)
        image.imageRelativePath = "i/1.jpg"
        image.caption = "白板照片"
        image.card = card; ctx.insert(image)

        let doc = Block(kind: .file, order: 3)
        doc.fileRelativePath = "d/1.pdf"; doc.fileName = "Handbook.pdf"; doc.fileType = "PDF"
        doc.extractedText = "学生如需延期毕业，应在学期开始前四周提交书面申请。"
        doc.card = card; ctx.insert(doc)

        let link = Block(kind: .link, order: 4)
        link.url = "https://neu.test/extended-study"
        link.linkTitle = "Extended Study Option"
        link.linkDescription = "students who need additional time to complete degree requirements"
        link.card = card; ctx.insert(link)

        try ctx.save()
        let noteID = card.id.uuidString

        // OCR is supplied as a derived overlay — it is not on `Block`.
        let imageRef = BlockRef(noteID: noteID, blockID: image.id.uuidString)
        stack.store.saveOCR(ImageTextExtraction(ref: imageRef,
                                                contentHash: AIContentHash.forBlock(image.toContent()),
                                                text: "延期申请截止 6 月 1 日", confidence: 0.88),
                            engineIdentifier: "stub")
        let ocrOverlay = stack.store.ocrTextByBlockID(noteID: noteID)
        XCTAssertEqual(ocrOverlay.count, 1)

        let plan = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(),
                                           strategy: .block,
                                           existingRecords: stack.store.existingRecords(noteID: noteID),
                                           embeddingVersion: version,
                                           ocrTextByBlockID: ocrOverlay)
        XCTAssertEqual(plan.totalChunks, 5, "all five sources contribute exactly one chunk each")
        XCTAssertEqual(Set(plan.pending.map(\.source)),
                       Set([.text, .transcript, .ocr, .extracted, .link]),
                       "every Goal 1 corpus source is represented")

        for item in plan.pending {
            let vec = try await provider.embed(item.text)
            let decision = stack.store.commit(DerivedResult(key: item.key, payload: vec),
                                              chunkID: item.chunkID, chunkIndex: item.key.chunkIndex,
                                              embeddingVersion: version, noteContext: ctx,
                                              ocrText: ocrOverlay[item.key.blockID])
            XCTAssertTrue(decision.isAccepted, "\(item.source) chunk persisted")
            await vectors.upsert(EmbeddingRecord(ref: item.key.ref, chunkID: item.chunkID,
                                                 chunkIndex: item.key.chunkIndex,
                                                 contentHash: item.key.contentHash,
                                                 embeddingVersion: version,
                                                 dimension: 32, vector: vec))
        }

        XCTAssertEqual(stack.store.recordCount(), 5)
        let indexed = await vectors.count()
        XCTAssertEqual(indexed, 5)

        // Retrieval reaches the OCR-derived chunk — the corpus source that did not
        // exist before Week 2.
        let ocrItem = plan.pending.first { $0.source == .ocr }!
        let q = try await provider.embed(ocrItem.text)
        let hits = await vectors.search(query: q, topK: 3)
        XCTAssertEqual(hits.first?.chunkID, ocrItem.chunkID, "OCR chunk is retrievable")
        XCTAssertEqual(hits.first?.ref.blockID, image.id.uuidString)

        // Index reports ready.
        let state = IndexStateMachine.derive(totalChunks: plan.totalChunks, pendingChunks: 0,
                                             runningJobs: 0, hasEmbeddings: true)
        XCTAssertEqual(state, .ready)
    }

    // MARK: 5 · Index rebuild from the derived store after "restart"

    func testVectorIndexRebuildsFromDerivedStoreOnLaunch() async throws {
        let stack = makeStack()
        let ctx = stack.notes.mainContext
        let provider = MockEmbeddingProvider(dimension: 16)
        let version = provider.modelInfo.version

        let card = Card(userTitle: "N")
        ctx.insert(card)
        for i in 0..<4 {
            let b = Block(kind: .text, order: i)
            b.text = "段落 \(i) 的内容"
            b.card = card
            ctx.insert(b)
        }
        try ctx.save()
        let noteID = card.id.uuidString

        let plan = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(), strategy: .block,
                                           existingRecords: [:], embeddingVersion: version)
        for item in plan.pending {
            let vec = try await provider.embed(item.text)
            stack.store.commit(DerivedResult(key: item.key, payload: vec),
                               chunkID: item.chunkID, chunkIndex: item.key.chunkIndex,
                               embeddingVersion: version, noteContext: ctx)
        }
        XCTAssertEqual(stack.store.recordCount(), 4)

        // "Relaunch": fresh store object, fresh in-memory index, rebuilt from disk.
        let afterRestart = DerivedDataStore(container: stack.derived)
        let rebuilt = InMemoryVectorStore()
        await rebuilt.upsert(afterRestart.allRecords())
        let count = await rebuilt.count()
        XCTAssertEqual(count, 4, "vector index reconstructed from persisted records")

        let q = try await provider.embed(plan.pending[0].text)
        let hits = await rebuilt.search(query: q, topK: 1)
        XCTAssertEqual(hits.first?.chunkID, plan.pending[0].chunkID,
                       "rebuilt index retrieves correctly — no build step to get stale")

        let settled = DerivedWorkScanner.plan(noteID: noteID, blocks: card.blockContents(), strategy: .block,
                                              existingRecords: afterRestart.existingRecords(noteID: noteID),
                                              embeddingVersion: version)
        XCTAssertFalse(settled.hasWork, "nothing re-queued after restart")
    }

    // MARK: Helpers

    /// Renders text into a PNG so the OCR test does not depend on a bundled asset.
    private static func renderPNG(text: String) -> Data? {
        #if canImport(UIKit)
        let size = CGSize(width: 600, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: attributes)
        }
        return image.pngData()
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
