import Foundation

/// 一次嵌入调用的耗时分解。
///
/// **网络必须与计算分开**：云端 query embedding 的耗时主要由地理位置决定
/// （本项目实测 US→China P95 1317 ms，同一模型换个区域就作废）。
/// 把它们合成一个「嵌入耗时」会得到一个换服务商就要重测全部结论的数字。
public struct EmbeddingTiming: Sendable, Equatable, Codable {
    /// HTTP 往返。**地理相关**，不可跨区域比较。
    public let networkMs: Double
    /// 解析 + 归一化。本机计算，可跨区域比较。
    public let decodeMs: Double
    public var totalMs: Double { networkMs + decodeMs }
    /// 这一次调用嵌了几条文本（批量时用来算单条成本）。
    public let batchSize: Int
    /// 服务端回报的 `usage.prompt_tokens`。**计费口径是 token，不是字符**，
    /// 用「字符数 ÷ 3.7」外推出来的 token 量只能算 *estimated*；这里存的是服务端
    /// 自己报的数，成本一项因此可以写 measured。服务端不回报时为 `nil`
    /// —— 缺省不能当 0，那会把成本算成免费。
    public let promptTokens: Int?

    public init(networkMs: Double, decodeMs: Double, batchSize: Int, promptTokens: Int? = nil) {
        self.networkMs = networkMs
        self.decodeMs = decodeMs
        self.batchSize = batchSize
        self.promptTokens = promptTokens
    }
}

/// 采集嵌入耗时。`RetrievalTrace` 记的是一次检索的七段，这里记的是 provider 内部的分解。
public actor EmbeddingLatencyRecorder {
    private var samples: [EmbeddingTiming] = []
    private let limit: Int

    public init(limit: Int = 500) { self.limit = limit }

    public func record(_ timing: EmbeddingTiming) {
        samples.append(timing)
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }

    public func recent() -> [EmbeddingTiming] { samples }
    public func reset() { samples.removeAll() }

    /// 网络与计算各自的 P50 / P95。
    public func percentiles() -> (networkP50: Double, networkP95: Double,
                                  decodeP50: Double, decodeP95: Double, count: Int) {
        func pct(_ values: [Double]) -> (Double, Double) {
            guard !values.isEmpty else { return (0, 0) }
            let s = values.sorted()
            return (s[s.count / 2], s[min(s.count - 1, Int(Double(s.count) * 0.95))])
        }
        let (nP50, nP95) = pct(samples.map(\.networkMs))
        let (dP50, dP95) = pct(samples.map(\.decodeMs))
        return (nP50, nP95, dP50, dP95, samples.count)
    }

    /// 服务端回报的 token 合计，以及有多少次调用**没有**回报。
    /// 后者要一起返回：只给合计的话，一个「服务端根本不报 usage」的 provider
    /// 会显示成「这批索引花了 0 token」。
    public func promptTokenTotal() -> (tokens: Int, reportedCalls: Int, unreportedCalls: Int) {
        let reported = samples.compactMap(\.promptTokens)
        return (reported.reduce(0, +), reported.count, samples.count - reported.count)
    }
}
