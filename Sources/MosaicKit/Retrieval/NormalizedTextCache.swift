import Foundation

/// # keyword 路的归一化缓存
///
/// ## 它解决的是一件纯粹的浪费
///
/// `TextMatcher.locate` 每次都要把 chunk 正文折叠成 `[Character]` 再扫。
/// 而这个数组**只取决于 chunk 自身，与 query 无关** —— 也就是说每一次查询都在
/// 重算同一个东西。20k chunks 上实测：这一段占 keyword 总耗时的 **68.5%**
/// （分段数据见 `KeywordLatencyBreakdown`，折叠 35.7 ms + 数组 27.7 ms）。
///
/// ## 为什么不是倒排索引
///
/// 直觉答案是「keyword 慢就上倒排索引」。但本项目的匹配是**纯子串**、没有分词器 ——
/// 「解约」必须能命中「提前解约」。token 倒排做不到这件事，要保子串语义得上 n-gram
/// 索引，那会引入一整套新的 derived 结构。而**先把这 68.5% 的重复计算去掉不改任何语义**，
/// 所以先做这一步，测完再决定还要不要索引。
///
/// 顺带被数据否掉的另一个方案：改用原生 `String.range(of:options:)` 免掉数组分配。
/// 实测**更慢** —— 20k 上命中 91 ms / 未命中 242 ms，而折叠+数组只要 63 ms。
///
/// ## 失效靠 contentHash，不靠调用方记得清
///
/// 与写入路径同一套原则：内容变了 `contentHash` 就变，缓存自动不命中。
/// 调用方**不需要**记得在编辑后清缓存 —— 那种「记得调用」的正确性这个项目不采用。
///
/// ## 它是 derived，可随时清空
///
/// 与 `InMemoryVectorStore` 同一类：丢了就重建，不进 CloudKit，不进用户数据。
/// 内存代价见 `estimatedBytes`。
public actor NormalizedTextCache {

    private struct Entry {
        let contentHash: String
        let chars: [Character]
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// **批量**解析。一次调用拿一整批 —— 逐个 chunk 走 actor 会产生 20k 次跨隔离跳转，
    /// 那比它省下来的还贵。
    ///
    /// 未命中（新 chunk 或 `contentHash` 变了）就地计算并写回。
    ///
    /// ## 未命中的那一批是并行折叠的
    ///
    /// 真机实测（iPhone Air · iOS 27 · release · 20k chunks）：
    /// 冷查询 P50 **103.0 ms**，热查询 P50 **67.6 ms** —— 差的 35.4 ms 就是这一段。
    /// 而 perf-v2 给 Metric A 的 P50 预算是 100 ms，于是**冷路径超了预算**。
    ///
    /// 每个 chunk 的折叠只取决于它自己，彼此没有任何依赖 —— 这是天然可并行的形状，
    /// 串行跑它只是在浪费另外几个核。**语义逐位不变**：并行的只是「谁来算」，
    /// 算法还是同一个 `TextMatcher.normalizedForOffsets`，
    /// 结果按原下标写回原位置（`checkCacheIsBitIdentical` 守着这一点）。
    public func normalized(for chunks: [NoteChunk]) async -> [[Character]] {
        var out = [[Character]](repeating: [], count: chunks.count)
        var missIndices: [Int] = []
        for (i, chunk) in chunks.enumerated() {
            if let hit = entries[chunk.id], hit.contentHash == chunk.contentHash {
                out[i] = hit.chars
            } else {
                missIndices.append(i)
            }
        }
        guard !missIndices.isEmpty else { return out }

        let folded = await Self.fold(missIndices.map { chunks[$0].text })
        for (k, i) in missIndices.enumerated() {
            out[i] = folded[k]
            entries[chunks[i].id] = Entry(contentHash: chunks[i].contentHash, chars: folded[k])
        }
        return out
    }

    /// 并行折叠一批文本。**`nonisolated`** —— 它不碰 `entries`，
    /// 放在 actor 的同步临界区里跑会把这段 CPU 时间变成一把全局锁。
    ///
    /// 小批量直接串行：任务派发本身有成本，而「库里只有几百个 chunk」是常态，
    /// 不是边界情况。阈值取 512 —— 那时串行折叠还不到 2 ms（真机），
    /// 派发几个子任务反而更贵。
    nonisolated static func fold(_ texts: [String]) async -> [[Character]] {
        let n = texts.count
        guard n >= parallelThreshold else {
            return texts.map { Array(TextMatcher.normalizedForOffsets($0)) }
        }

        // 切片数取核数，不是 chunk 数：20k 个子任务的调度开销会吃掉并行的收益。
        let slices = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let per = (n + slices - 1) / slices

        // 结果按**切片下标**归位再拼接。用「谁先算完谁先进」的顺序会让
        // 输出与输入对不上 —— 那不是变慢，是把 A 的正文当成 B 的。
        var byslice = [[[Character]]](repeating: [], count: slices)
        await withTaskGroup(of: (Int, [[Character]]).self) { group in
            for s in 0..<slices {
                let lo = s * per
                let hi = min(lo + per, n)
                guard lo < hi else { continue }
                let slice = Array(texts[lo..<hi])
                group.addTask {
                    (s, slice.map { Array(TextMatcher.normalizedForOffsets($0)) })
                }
            }
            for await (s, chars) in group { byslice[s] = chars }
        }
        return byslice.flatMap { $0 }
    }

    /// 低于这个规模串行跑。见 `fold`。
    nonisolated static let parallelThreshold = 512

    /// 清空。derived 数据随时可以丢。
    public func reset() { entries.removeAll() }

    public var count: Int { entries.count }

    /// 粗略内存占用。`Character` 是 16 字节，所以这个缓存和向量库是同一量级 ——
    /// 报出来是为了让「要不要开」有依据，不是装饰。
    public var estimatedBytes: Int {
        entries.values.reduce(0) { $0 + $1.chars.count * 16 + $1.contentHash.utf8.count }
    }
}
