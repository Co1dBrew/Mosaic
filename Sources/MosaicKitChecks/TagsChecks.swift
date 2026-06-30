import Foundation
import MosaicKit

func runTagsChecks(_ r: CheckRunner) {
    r.suite("TagUtilities.normalize / sanitize")

    r.expectEqual(TagUtilities.normalize("  工作  "), "工作", "trims")
    r.expectEqual(TagUtilities.normalize("design   patterns"), "design patterns", "collapses inner whitespace")
    r.expectNil(TagUtilities.normalize("   "), "whitespace-only -> nil")
    r.expectNil(TagUtilities.normalize(""), "empty -> nil")

    // Dedup: exact, case-insensitive (English), preserve first casing; Chinese kept
    r.expectEqual(TagUtilities.sanitize(["Work", "work", "WORK"]), ["Work"], "english case dedup, keep first")
    r.expectEqual(TagUtilities.sanitize(["工作", "工作", " 工作 "]), ["工作"], "chinese dedup")
    r.expectEqual(TagUtilities.sanitize(["a", "", "  ", "b", "a"]), ["a", "b"], "drops empties, dedups, order kept")

    r.suite("TagUtilities.add / remove / merge / topics")

    r.expectEqual(TagUtilities.add("会议", to: ["工作"]), ["工作", "会议"], "adds new tag")
    r.expectEqual(TagUtilities.add("工作", to: ["工作"]), ["工作"], "exact duplicate not added")
    r.expectEqual(TagUtilities.add("WORK", to: ["Work"]), ["Work"], "case duplicate not added")
    r.expectEqual(TagUtilities.add("  新标签 ", to: ["工作"]), ["工作", "新标签"], "normalizes added tag")

    r.expectEqual(TagUtilities.remove("Work", from: ["Work", "会议"]), ["会议"], "removes by key (case-insensitive)")
    r.expectEqual(TagUtilities.remove("不存在", from: ["工作"]), ["工作"], "removing absent tag is a no-op")

    r.expectEqual(TagUtilities.merge(["工作", "会议"], ["会议", "排期"]), ["工作", "会议", "排期"], "union dedup")

    r.expectEqual(
        TagUtilities.addingTopics(["产品评审", "排期", "工作"], to: ["工作"]),
        ["工作", "产品评审", "排期"],
        "AI topics -> tags, deduped against existing"
    )

    r.suite("TagUtilities.contains + tag search")

    r.expect(TagUtilities.contains("work", in: ["Work", "会议"]), "contains is case-insensitive")
    r.expect(!TagUtilities.contains("缺失", in: ["工作"]), "absent tag not contained")

    // Tags participate in search (Phase 1 reserved input now real)
    r.expect(SearchMatcher.matches(query: "工作", haystack: "随便的正文", tags: ["工作"]), "search matches a tag name")
    let scope = SearchScope(requiredTags: ["工作"])
    r.expect(scope.allows(folderID: nil, tags: ["工作", "会议"], isPinned: false), "requiredTags filter passes")
    r.expect(!scope.allows(folderID: nil, tags: ["会议"], isPinned: false), "requiredTags filter rejects")
}
