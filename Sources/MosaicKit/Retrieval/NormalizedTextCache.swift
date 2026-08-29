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
    public func normalized(for chunks: [NoteChunk]) -> [[Character]] {
        var out: [[Character]] = []
        out.reserveCapacity(chunks.count)
        for chunk in chunks {
            if let hit = entries[chunk.id], hit.contentHash == chunk.contentHash {
                out.append(hit.chars)
            } else {
                let chars = Array(TextMatcher.normalizedForOffsets(chunk.text))
                entries[chunk.id] = Entry(contentHash: chunk.contentHash, chars: chars)
                out.append(chars)
            }
        }
        return out
    }

    /// 清空。derived 数据随时可以丢。
    public func reset() { entries.removeAll() }

    public var count: Int { entries.count }

    /// 粗略内存占用。`Character` 是 16 字节，所以这个缓存和向量库是同一量级 ——
    /// 报出来是为了让「要不要开」有依据，不是装饰。
    public var estimatedBytes: Int {
        entries.values.reduce(0) { $0 + $1.chars.count * 16 + $1.contentHash.utf8.count }
    }
}
