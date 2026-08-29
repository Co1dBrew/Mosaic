import Foundation
import MosaicKit

/// # keyword 路的分段计时（P1 #9 的前置）
///
/// 20k chunks 上真机实测 keyword P95 89–98 ms，余弦只要 5.9–6.2 ms —— **差 14.5–16.8 倍**。
/// 直觉答案是「加倒排索引」，但在动手之前必须先知道**时间到底花在哪一段**：
/// 本项目已经有过至少六次直觉被实测推翻。
///
/// 分四段：
///
/// | 段 | 做什么 | 与 chunk 数的关系 |
/// |---|---|---|
/// | tokenize | query 切词 + 归一化 | **无关**（每次查询一次） |
/// | normalize | `Array(normalizedForOffsets(chunk.text))` | 线性，**每 chunk 每次查询都做** |
/// | scan | 在字符数组里找子串 | 线性 |
/// | score+sort | 打分、排序、取 topK | 线性 + O(n log n) |
///
/// `normalize` 那一段是可疑对象：它每次查询都要把**全库正文**重新折叠一遍并
/// 分配一个 `[Character]`，而结果只取决于 chunk 本身，与 query 无关 ——
/// 也就是说它**每次都在重算同一个东西**。
enum KeywordLatencyBreakdown {

    private static let queries = ["延期毕业", "排期结论", "lease termination", "CS5330", "阿莫西林 饭后"]

    static func run(_ r: CheckRunner) {
        r.suite("P1 #9 · keyword 路分段计时 —— 先定位瓶颈，再决定改什么")
        print("\n    ── keyword 分段（\(buildMode)，每档 25 次查询取平均）──")
        print("     chunks   tokenize   normalize      scan  score+sort      合计   normalize 占比")

        var shares: [(Int, Double)] = []
        for scale in [1_000, 5_000, 20_000] {
            let chunks = syntheticChunks(scale)
            var tTok = 0.0, tNorm = 0.0, tScan = 0.0, tScore = 0.0
            let rounds = 25

            for i in 0..<rounds {
                let query = queries[i % queries.count]

                var t = DispatchTime.now().uptimeNanoseconds
                let tokens = SearchMatcher.tokens(from: query)
                tTok += ms(since: t)

                // normalize：把每个 chunk 的正文折叠成字符数组
                t = DispatchTime.now().uptimeNanoseconds
                var hays: [[Character]] = []
                hays.reserveCapacity(chunks.count)
                for c in chunks { hays.append(Array(TextMatcher.normalizedForOffsets(c.text))) }
                tNorm += ms(since: t)

                // scan：在已归一化的数组里找子串（与 TextMatcher.locate 同一套逻辑）
                t = DispatchTime.now().uptimeNanoseconds
                var counted: [(Int, [Int])] = []
                let needles = tokens.map { Array(TextMatcher.normalizedForOffsets($0)) }
                for (idx, hay) in hays.enumerated() {
                    var counts: [Int] = []
                    var all = true
                    for needle in needles {
                        guard !needle.isEmpty, needle.count <= hay.count else { all = false; break }
                        var found = 0, j = 0
                        while j + needle.count <= hay.count {
                            if hay[j] == needle[0], Array(hay[j..<(j + needle.count)]) == needle {
                                found += 1; j += needle.count
                            } else { j += 1 }
                        }
                        guard found > 0 else { all = false; break }
                        counts.append(found)
                    }
                    if all { counted.append((idx, counts)) }
                }
                tScan += ms(since: t)

                // score + sort
                t = DispatchTime.now().uptimeNanoseconds
                var hits: [(String, Double)] = []
                for (idx, counts) in counted {
                    let chunk = chunks[idx]
                    let norm = Double(max(1, chunk.text.count)).squareRoot()
                    var score = 0.0
                    for c in counts { score += Double(min(c, 3)) / norm }
                    hits.append((chunk.id, score * KeywordRetriever.weight(for: chunk.source)))
                }
                hits.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                _ = Array(hits.prefix(50))
                tScore += ms(since: t)
            }

            let n = Double(rounds)
            let (tok, norm, scan, score) = (tTok / n, tNorm / n, tScan / n, tScore / n)
            let total = tok + norm + scan + score
            let share = norm / total * 100
            shares.append((scale, share))
            print(String(format: "     %6d  %8.3f  %10.3f  %8.3f  %10.3f  %8.3f  %11.1f%%",
                         scale, tok, norm, scan, score, total, share))
        }

        print("""

            读法：normalize 与 query **无关** —— 它把全库正文重新折叠一遍，
            结果只取决于 chunk 自身。占比越高，说明「预计算一次、之后复用」的
            收益越大，而且**不改任何检索语义**（不像倒排索引要动匹配单位）。
        """)

        // ── 优化前 vs 优化后：同一条 retrieve，只差有没有预归一化 ──
        print("\n    ── 缓存前后（同一个 retrieve，唯一区别是 normalized 给没给）──")
        print("     chunks     优化前     优化后    提速    缓存内存")
        var speedups: [(Int, Double)] = []
        for scale in [1_000, 5_000, 20_000] {
            let chunks = syntheticChunks(scale)
            let cache = NormalizedTextCache()
            let hays = warm(cache, chunks)

            func time(_ normalized: [[Character]]?) -> Double {
                _ = KeywordRetriever.retrieve(query: "预热", chunks: chunks, topK: 50, normalized: normalized)
                let t = DispatchTime.now().uptimeNanoseconds
                for i in 0..<25 {
                    _ = KeywordRetriever.retrieve(query: queries[i % queries.count],
                                                  chunks: chunks, topK: 50, normalized: normalized)
                }
                return ms(since: t) / 25
            }
            let before = time(nil), after = time(hays)
            let mb = Double(bytes(cache)) / 1_048_576
            speedups.append((scale, before / after))
            print(String(format: "     %6d  %7.2f ms %7.2f ms  %5.2fx  %7.1f MB",
                         scale, before, after, before / after, mb))
        }
        print("")
        print("    ⚠️ 缓存不是免费的：它拿**内存**换时间，而且是 `[Character]`（每字符 16 字节）。")
        print("       要不要开、在什么规模上开，要连着内存一起看，不能只看提速倍数。")
        print("")

        // 断言：分段口径成立，**不断言具体占比**（那是要用来做决策的实测值，会变）
        r.expect(speedups.allSatisfy { $0.1 > 1.0 },
                 "预归一化在每一档上都更快 —— 若某一档反而更慢，说明缓存查找本身成了开销")
        r.expect(shares.count == 3, "三档都产出分段数字")
        r.expect(shares.allSatisfy { $0.1 > 0 }, "normalize 段确实存在且被计时")
        if let big = shares.first(where: { $0.0 == 20_000 }) {
            r.expect(true, String(format: "20k 上 normalize 占 keyword 总耗时的 %.1f%% —— 这是 #9 该先改哪里的依据", big.1))
        }
    }

    /// 缓存版与非缓存版**必须逐位一致**。
    ///
    /// 这是这次优化的全部前提：它是纯粹去掉重复计算，**不是**换匹配单位。
    /// 所以在真实评测集上逐条比对命中列表、分数、以及**高亮区间**
    /// —— range 尤其重要，`SEARCH_CONTRACT.md` §2 要求高亮由检索层返回的 range 驱动，
    /// range 错了高亮就跟着错。
    static func checkCacheIsBitIdentical(_ r: CheckRunner) async {
        r.suite("P1 #9 · 归一化缓存 —— 结果必须与优化前逐位一致")

        guard let dataset = try? HumanLikeGoldenFixture.load() else {
            r.expect(false, "fixture 应当可加载"); return
        }
        let chunks = dataset.chunks
        let cache = NormalizedTextCache()
        let hays = await cache.normalized(for: chunks)

        var compared = 0, identical = 0
        var rangesCompared = 0
        // 正例 + 负例 + 一批边界 query 全过一遍
        let queries = dataset.evalCases.map(\.query)
            + dataset.negativeEvalCases.map(\.query)
            + ["", "   ", "a", "解约", "提前解约", "CS5330", "cs5330", "ＣＳ５３３０", "café", "cafe"]

        for q in queries {
            let before = KeywordRetriever.retrieve(query: q, chunks: chunks, topK: 50)
            let after = KeywordRetriever.retrieve(query: q, chunks: chunks, topK: 50, normalized: hays)
            compared += 1
            if before == after { identical += 1 }
            rangesCompared += before.reduce(0) { $0 + $1.ranges.count }
        }

        r.expect(identical == compared,
                 "\(compared) 条 query（含正例/负例/全角/变音符/子串边界）的命中列表、"
                 + "分数与高亮区间全部逐位一致（\(identical)/\(compared)）")
        r.expect(rangesCompared > 0, "比对确实覆盖到了高亮区间（共 \(rangesCompared) 个 range）")

        // contentHash 变了必须自失效 —— 不能靠调用方记得清缓存
        guard let first = chunks.first else { r.expect(false, "fixture 应当非空"); return }
        let edited = NoteChunk(id: first.id, ref: first.ref, source: first.source,
                               indexInBlock: first.indexInBlock,
                               text: "完全不同的内容 delta echo foxtrot",
                               contentHash: first.contentHash + "-edited",
                               strategy: first.strategy)
        let refreshed = await cache.normalized(for: [edited])
        r.expect(String(refreshed[0]) == TextMatcher.normalizedForOffsets(edited.text),
                 "contentHash 变了 → 缓存自动不命中并重算。**不依赖调用方记得清**")

        let stale = await cache.normalized(for: [first])
        r.expect(String(stale[0]) == TextMatcher.normalizedForOffsets(first.text),
                 "同一个 id 换回原 hash 也要拿到对的正文")

        // 数量对不上时忽略缓存，宁可慢也不能错位
        let mismatched = KeywordRetriever.retrieve(query: "毕业", chunks: chunks, topK: 50,
                                                   normalized: Array(hays.prefix(3)))
        r.expect(mismatched == KeywordRetriever.retrieve(query: "毕业", chunks: chunks, topK: 50),
                 "normalized 数量与 chunks 对不上 → 忽略它就地算，**不能把 A 的正文当成 B 的**")

        let bytes = await cache.estimatedBytes
        print(String(format: "\n    缓存 %d 条 · 约 %.1f MB（20k chunks 线性外推约 %.0f MB，*estimated*）\n",
                     chunks.count, Double(bytes) / 1_048_576,
                     Double(bytes) / 1_048_576 * 20_000 / Double(max(chunks.count, 1))))
    }

    /// actor 是异步的，而这一段计时是同步的 —— 用一个小桥接把缓存预热好。
    private static func warm(_ cache: NormalizedTextCache, _ chunks: [NoteChunk]) -> [[Character]] {
        let sem = DispatchSemaphore(value: 0)
        var out: [[Character]] = []
        Task { out = await cache.normalized(for: chunks); sem.signal() }
        sem.wait()
        return out
    }

    private static func bytes(_ cache: NormalizedTextCache) -> Int {
        let sem = DispatchSemaphore(value: 0)
        var out = 0
        Task { out = await cache.estimatedBytes; sem.signal() }
        sem.wait()
        return out
    }

    private static func ms(since t: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
    }

    private static func syntheticChunks(_ count: Int) -> [NoteChunk] {
        (0..<count).map { i in
            NoteChunk(id: "c\(i)", ref: BlockRef(noteID: "n\(i / 20)", blockID: "b\(i)"),
                      source: .text, indexInBlock: 0,
                      text: "第 \(i) 段 关于 排期 与 延期毕业 的记录 lease termination parking space CS5330 阿莫西林 饭后 record \(i)",
                      contentHash: "h\(i)")
        }
    }

    static var buildMode: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
