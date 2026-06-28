import Foundation
import MosaicKit

func runDiffChecks(_ r: CheckRunner) {
    r.suite("ContentHasher")

    let textA = CardBlockContent(id: "1", order: 0, kind: .text, text: "hello")
    let textAReordered = CardBlockContent(id: "1", order: 5, kind: .text, text: "hello")
    let textB = CardBlockContent(id: "1", order: 0, kind: .text, text: "world")

    r.expectEqual(ContentHasher.hash(for: textA), ContentHasher.hash(for: textA), "deterministic")
    r.expectEqual(ContentHasher.hash(for: textA), ContentHasher.hash(for: textAReordered), "order does not affect hash")
    r.expect(ContentHasher.hash(for: textA) != ContentHasher.hash(for: textB), "content change changes hash")

    let img1 = CardBlockContent(id: "2", order: 0, kind: .image, imageCaption: "cat", imageAssetRef: "a.jpg")
    let img2 = CardBlockContent(id: "2", order: 0, kind: .image, imageCaption: "cat", imageAssetRef: "b.jpg")
    r.expect(ContentHasher.hash(for: img1) != ContentHasher.hash(for: img2), "image asset change changes hash")

    r.suite("SummarySnapshot encode/decode")

    let blocks = [textA, img1]
    let snap = SummarySnapshot.make(from: blocks)
    r.expectEqual(snap.entries.count, 2)
    let roundtrip = SummarySnapshot.decode(snap.encodedData())
    r.expectEqual(roundtrip, snap, "snapshot survives encode/decode")
    r.expectEqual(SummarySnapshot.decode(nil).entries.count, 0, "nil decodes to empty")
    r.expectEqual(SummarySnapshot.decode(Data()).entries.count, 0, "empty data decodes to empty")

    r.suite("SnapshotDiffer")

    // Baseline: block 1 (text "hello"), block 2 (image a.jpg)
    let baseline = SummarySnapshot.make(from: [textA, img1])

    // Current: block 1 modified, block 3 added, block 2 deleted
    let current = [
        CardBlockContent(id: "1", order: 0, kind: .text, text: "hello world changed"),
        CardBlockContent(id: "3", order: 1, kind: .link, url: "https://x.test")
    ]
    let diff = SnapshotDiffer.diff(current: current, snapshot: baseline)
    r.expectEqual(diff.added.map { $0.id }, ["3"], "added block 3")
    r.expectEqual(diff.modified.map { $0.id }, ["1"], "modified block 1")
    r.expectEqual(diff.deleted.map { $0.id }, ["2"], "deleted block 2")
    r.expectEqual(diff.deleted.first?.kind, .image, "deleted descriptor remembers kind")
    r.expect(diff.hasChanges, "diff has changes")

    // No changes
    let same = SnapshotDiffer.diff(current: [textA, img1], snapshot: baseline)
    r.expect(!same.hasChanges, "identical content -> no changes")

    // Reorder only -> no modification
    let reordered = SnapshotDiffer.diff(current: [textAReordered, img1], snapshot: baseline)
    r.expect(!reordered.hasChanges, "reorder alone is not a change")

    r.suite("SnapshotDiffer.isSignificant")

    let emptySnap = SummarySnapshot()

    // Tiny added text -> not significant
    let tinyAdd = CardDiff(added: [CardBlockContent(id: "9", order: 0, kind: .text, text: "ab")])
    r.expect(!SnapshotDiffer.isSignificant(tinyAdd, snapshot: emptySnap), "2-char added text below threshold")

    // Large added text -> significant
    let bigAdd = CardDiff(added: [CardBlockContent(id: "9", order: 0, kind: .text, text: String(repeating: "字", count: 50))])
    r.expect(SnapshotDiffer.isSignificant(bigAdd, snapshot: emptySnap), "large added text is significant")

    // Added non-text block -> always significant
    let imgAdd = CardDiff(added: [CardBlockContent(id: "7", order: 0, kind: .image, imageAssetRef: "a.jpg")])
    r.expect(SnapshotDiffer.isSignificant(imgAdd, snapshot: emptySnap), "added image always significant")

    // Deleted -> significant
    let deleted = CardDiff(deleted: [DeletedBlock(id: "1", kind: .text, brief: "x")])
    r.expect(SnapshotDiffer.isSignificant(deleted, snapshot: emptySnap), "deletion always significant")

    // Non-text modify -> significant
    let imgMod = CardDiff(modified: [CardBlockContent(id: "2", order: 0, kind: .image, imageAssetRef: "z.jpg")])
    r.expect(SnapshotDiffer.isSignificant(imgMod, snapshot: emptySnap), "image change always significant")

    // Text DELTA: tiny edit to a long block -> not significant; large delta -> significant
    let original = CardBlockContent(id: "1", order: 0, kind: .text, text: String(repeating: "x", count: 30))
    let baseSnap = SummarySnapshot.make(from: [original])
    let oneCharEdit = CardDiff(modified: [CardBlockContent(id: "1", order: 0, kind: .text, text: String(repeating: "x", count: 31))])
    r.expect(!SnapshotDiffer.isSignificant(oneCharEdit, snapshot: baseSnap), "1-char delta on long block not significant")
    let bigEdit = CardDiff(modified: [CardBlockContent(id: "1", order: 0, kind: .text, text: String(repeating: "x", count: 30) + String(repeating: "y", count: 20))])
    r.expect(SnapshotDiffer.isSignificant(bigEdit, snapshot: baseSnap), "20-char delta is significant")
}
