import Foundation
import MosaicKit

func runSearchChecks(_ r: CheckRunner) {
    r.suite("SearchMatcher")

    let hay = """
    周三产品评审会要点
    今天讨论了下个版本的排期与分工
    录音转写:我们决定下周三上线
    https://example.com 产品路线图 The product roadmap
    会议记录 Meeting notes
    """

    // Title / body hits
    r.expect(SearchMatcher.matches(query: "评审会", haystack: hay), "matches Chinese substring in title")
    r.expect(SearchMatcher.matches(query: "排期", haystack: hay), "matches text body")
    r.expect(SearchMatcher.matches(query: "上线", haystack: hay), "matches transcript line")
    r.expect(SearchMatcher.matches(query: "example.com", haystack: hay), "matches link url")

    // Case / diacritic insensitivity
    r.expect(SearchMatcher.matches(query: "MEETING", haystack: hay), "case-insensitive")
    r.expect(SearchMatcher.matches(query: "roadmap", haystack: hay), "lowercase matches mixed case")
    r.expect(SearchMatcher.matches(query: "Café", haystack: "我们去 cafe 喝咖啡"), "diacritic-insensitive")

    // Multi-term AND
    r.expect(SearchMatcher.matches(query: "产品 排期", haystack: hay), "all terms present -> match")
    r.expect(!SearchMatcher.matches(query: "产品 不存在", haystack: hay), "one missing term -> no match")

    // Whitespace handling
    r.expect(SearchMatcher.matches(query: "  评审会  ", haystack: hay), "trims surrounding whitespace")

    // Empty query
    r.expect(!SearchMatcher.matches(query: "", haystack: hay), "empty query -> false")
    r.expect(!SearchMatcher.matches(query: "   ", haystack: hay), "whitespace query -> false")

    // No match
    r.expect(!SearchMatcher.matches(query: "完全没有", haystack: hay), "absent term -> false")

    // Tag-only match (term not in haystack but in a tag)
    r.expect(SearchMatcher.matches(query: "工作", haystack: hay, tags: ["工作", "会议"]), "matches a tag")
    r.expect(!SearchMatcher.matches(query: "工作", haystack: hay, tags: []), "no tag, not in haystack -> false")

    r.suite("SearchScope")

    let global = SearchScope()
    r.expect(global.isUnconstrained, "default scope is global")
    r.expect(global.allows(folderID: "F1", tags: [], isPinned: false), "global allows any card")

    let folderScoped = SearchScope(folderID: "F1")
    r.expect(folderScoped.allows(folderID: "F1", tags: [], isPinned: false), "matches folder")
    r.expect(!folderScoped.allows(folderID: "F2", tags: [], isPinned: false), "rejects other folder")

    let pinned = SearchScope(pinnedOnly: true)
    r.expect(pinned.allows(folderID: "F1", tags: [], isPinned: true), "pinned passes pinnedOnly")
    r.expect(!pinned.allows(folderID: "F1", tags: [], isPinned: false), "unpinned rejected by pinnedOnly")

    let tagged = SearchScope(requiredTags: ["工作"])
    r.expect(tagged.allows(folderID: "F1", tags: ["工作", "会议"], isPinned: false), "has required tag")
    r.expect(!tagged.allows(folderID: "F1", tags: ["会议"], isPinned: false), "missing required tag")
}
