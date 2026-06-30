import Foundation
import MosaicKit

func runPinningChecks(_ r: CheckRunner) {
    r.suite("CardSorting (pinned first, then updatedAt desc)")

    func key(_ id: String, _ pinned: Bool, _ t: TimeInterval) -> CardSortKey {
        CardSortKey(id: id, isPinned: pinned, updatedAt: Date(timeIntervalSince1970: t))
    }

    // Pinned before unpinned, even if unpinned is newer.
    let a = key("a", false, 2000)  // newer, unpinned
    let b = key("b", true, 1000)   // older, pinned
    r.expect(CardSorting.isOrderedBefore(b, a), "pinned comes before unpinned")
    r.expect(!CardSorting.isOrderedBefore(a, b), "unpinned does not come before pinned")

    // Ordering of a mixed set.
    let keys = [
        key("u_old", false, 100),
        key("p_new", true, 300),
        key("u_new", false, 400),
        key("p_old", true, 200)
    ]
    let ordered = CardSorting.ordered(keys).map { $0.id }
    r.expectEqual(ordered, ["p_new", "p_old", "u_new", "u_old"],
                  "pinned (newest first) then unpinned (newest first)")

    // Stable id tiebreak when pinned + updatedAt equal.
    let t1 = key("z", true, 500)
    let t2 = key("a", true, 500)
    r.expect(CardSorting.isOrderedBefore(t2, t1), "equal pinned+date -> ordered by id")
}
