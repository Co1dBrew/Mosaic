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

    // Tiny text edit -> not significant
    let tiny = CardDiff(modified: [CardBlockContent(id: "1", order: 0, kind: .text, text: "ab")])
    r.expect(!SnapshotDiffer.isSignificant(tiny), "2-char text edit below threshold")

    // Large text edit -> significant
    let big = CardDiff(modified: [CardBlockContent(id: "1", order: 0, kind: .text, text: String(repeating: "字", count: 50))])
    r.expect(SnapshotDiffer.isSignificant(big), "large text edit is significant")

    // Added block -> always significant
    let added = CardDiff(added: [CardBlockContent(id: "9", order: 0, kind: .text, text: "x")])
    r.expect(SnapshotDiffer.isSignificant(added), "added block always significant")

    // Deleted -> significant
    let deleted = CardDiff(deleted: [DeletedBlock(id: "1", kind: .text, brief: "x")])
    r.expect(SnapshotDiffer.isSignificant(deleted), "deletion always significant")

    // Non-text modify -> significant
    let imgMod = CardDiff(modified: [CardBlockContent(id: "2", order: 0, kind: .image, imageAssetRef: "z.jpg")])
    r.expect(SnapshotDiffer.isSignificant(imgMod), "image change always significant")
}
