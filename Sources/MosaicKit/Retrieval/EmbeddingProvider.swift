import Foundation
import CryptoKit

/// Identity of the model that produced an embedding.
///
/// `version` is what goes into `EmbeddingJobKey` and `EmbeddingRecord`. Switching
/// provider or model must change it, otherwise vectors from two different spaces
/// would be compared against each other — which fails silently and looks like
/// "retrieval quality got worse" rather than "the index is corrupt".
public struct EmbeddingModelInfo: Sendable, Equatable, Codable {
    /// Human-readable identifier, e.g. `"mock-v1"`, `"bge-small-zh-v1.5"`.
    public let identifier: String
    /// Vector dimension. Records with a different dimension are unusable.
    public let dimension: Int
    /// Opaque version string mixed into job identity and stored on every record.
    public let version: String

    public init(identifier: String, dimension: Int, version: String) {
        self.identifier = identifier
        self.dimension = dimension
        self.version = version
    }
}

public enum EmbeddingProviderError: Error, Equatable, Sendable {
    /// Provider not configured / model not downloaded / offline.
    case unavailable(String)
    /// Transient transport failure — retryable.
    case transport(String)
    /// Provider-side throttling — retryable.
    case rateLimited
    /// Bad credentials / bad request — **not** retryable.
    case rejected(String)
    /// Empty or oversized input.
    case invalidInput(String)
}

/// Minimum surface Week 1 needs. Deliberately small: the goal is that the provider
/// is *replaceable*, not that there are many of them.
public protocol EmbeddingProvider: Sendable {
    var modelInfo: EmbeddingModelInfo { get }
    func embed(_ text: String) async throws -> [Float]
    func embed(batch texts: [String]) async throws -> [[Float]]
}

public extension EmbeddingProvider {
    /// Default batch implementation so a conformer only has to implement one method.
    /// Real providers should override this with a true batched request.
    func embed(batch texts: [String]) async throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for t in texts { out.append(try await embed(t)) }
        return out
    }
}

// MARK: - Mock

/// Deterministic provider for tests and for exercising the pipeline without a model.
///
/// The vector is derived from a SHA-256 of the input, so:
/// - same text → same vector, across processes and launches
/// - different text → different vector
///
/// It is **not** semantically meaningful. It exists to prove the plumbing, not to
/// retrieve anything. Week 2 replaces it with a real model.
public struct MockEmbeddingProvider: EmbeddingProvider {
    public let modelInfo: EmbeddingModelInfo
    /// Artificial latency, used by concurrency/cancellation tests.
    public let delayNanos: UInt64
    /// When set, every call throws this instead of returning.
    public let failure: EmbeddingProviderError?
    /// When true, the provider ignores cancellation and runs to completion — this
    /// models a provider that does not honour `Task.cancel()`, which is precisely
    /// the case stale protection has to survive.
    public let ignoresCancellation: Bool

    public init(dimension: Int = 8,
                version: String = "mock-v1",
                delayNanos: UInt64 = 0,
                failure: EmbeddingProviderError? = nil,
                ignoresCancellation: Bool = false) {
        self.modelInfo = EmbeddingModelInfo(identifier: "mock", dimension: dimension, version: version)
        self.delayNanos = delayNanos
        self.failure = failure
        self.ignoresCancellation = ignoresCancellation
    }

    public func embed(_ text: String) async throws -> [Float] {
        if delayNanos > 0 {
            if ignoresCancellation {
                // Deliberately non-cancellable sleep.
                let deadline = DispatchTime.now().uptimeNanoseconds + delayNanos
                while DispatchTime.now().uptimeNanoseconds < deadline {
                    await Task.yield()
                }
            } else {
                try await Task.sleep(nanoseconds: delayNanos)
            }
        }
        if let failure { throw failure }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingProviderError.invalidInput("empty text") }
        return Self.deterministicVector(for: trimmed, dimension: modelInfo.dimension)
    }

    /// SHA-256 → repeatable pseudo-vector in [-1, 1], L2-normalised.
    public static func deterministicVector(for text: String, dimension: Int) -> [Float] {
        var bytes: [UInt8] = []
        var counter = 0
        while bytes.count < dimension {
            let digest = SHA256.hash(data: Data("\(counter)|\(text)".utf8))
            bytes.append(contentsOf: digest)
            counter += 1
        }
        var v = (0..<dimension).map { Float(Int(bytes[$0]) - 128) / 128.0 }
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { v = v.map { $0 / norm } }
        return v
    }
}

// MARK: - Future conformers (seams, not implementations)

/// 本地 embedding 的解析入口。
///
/// TD-5 已在 Week 3 后关闭：真实实现是 `NLEmbeddingProvider`（Apple
/// `NaturalLanguage`，中文 640 维，完全离线）。这里只负责「拿一个能用的本地
/// provider」，拿不到就明确失败，而不是退回 mock —— 静默退回 mock 会让评测数字
/// 看起来正常但毫无意义。
public enum LocalEmbedding {
    public static func make(language: NLEmbeddingProvider.Language = .simplifiedChinese) throws -> any EmbeddingProvider {
        guard let provider = NLEmbeddingProvider(language: language) else {
            throw EmbeddingProviderError.unavailable("系统未提供 \(language.rawValue) 句向量模型")
        }
        return provider
    }
}

/// # 云端 embedding —— OpenAI 兼容 `/v1/embeddings`
///
/// 存在的意义不是「云端更强」，而是 Week 6 要做的 **Local vs Cloud 对比实验**
/// 需要一个真实的对照组：质量 / 延迟 / 成本三项，拿数据说话。
///
/// 复用既有的 `ProviderConfig`（baseURL / apiKey 与摘要功能同一套配置），
/// 所以不引入第二套凭据管理。
///
/// **维度由服务端决定**，构造时必须显式声明并与实际返回校验 —— 维度不符意味着
/// 索引里会混进不可比的向量，宁可失败也不能写进去。
public struct CloudEmbeddingProvider: EmbeddingProvider {
    public let modelInfo: EmbeddingModelInfo
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession

    public init(baseURL: String, apiKey: String, model: String, dimension: Int,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.modelInfo = EmbeddingModelInfo(identifier: "cloud-\(model)",
                                            dimension: dimension,
                                            version: "cloud-\(model)-d\(dimension)")
    }

    public func embed(_ text: String) async throws -> [Float] {
        try await embed(batch: [text]).first ?? []
    }

    /// 真正的批量请求 —— 云端按请求计费，逐条发送会把成本乘以条数。
    public func embed(batch texts: [String]) async throws -> [[Float]] {
        let cleaned = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ !$0.isEmpty }) else {
            throw EmbeddingProviderError.invalidInput("empty text in batch")
        }
        let request = try Self.makeRequest(baseURL: baseURL, apiKey: apiKey,
                                           model: modelInfo.identifier
                                               .replacingOccurrences(of: "cloud-", with: ""),
                                           inputs: cleaned)
        let (data, response) = try await runTransport(request)
        guard let http = response as? HTTPURLResponse else {
            throw EmbeddingProviderError.transport("no HTTP response")
        }
        try Self.mapStatus(http.statusCode, body: data)
        let vectors = try Self.parse(data, expectedCount: cleaned.count, dimension: modelInfo.dimension)
        return vectors.map { VectorMath.normalize($0) }
    }

    private func runTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch { throw EmbeddingProviderError.transport(error.localizedDescription) }
    }

    // MARK: 可单测的纯函数部分

    public static func makeRequest(baseURL: String, apiKey: String,
                                   model: String, inputs: [String]) throws -> URLRequest {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/embeddings") else {
            throw EmbeddingProviderError.rejected("invalid baseURL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": model, "input": inputs]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 状态码 → 错误类型。**可重试与不可重试必须分开**，否则 401 会被无谓地重试三次。
    public static func mapStatus(_ code: Int, body: Data) throws {
        switch code {
        case 200...299: return
        case 429: throw EmbeddingProviderError.rateLimited
        case 401, 403: throw EmbeddingProviderError.rejected("认证失败（\(code)）")
        case 400...499: throw EmbeddingProviderError.rejected("请求被拒绝（\(code)）")
        default: throw EmbeddingProviderError.transport("服务端错误（\(code)）")
        }
    }

    /// 解析 OpenAI 兼容响应，并**按 `index` 重排** —— 服务端不保证返回顺序，
    /// 顺序错乱会让向量与文本对不上，而且完全静默。
    public static func parse(_ data: Data, expectedCount: Int, dimension: Int) throws -> [[Float]] {
        struct Response: Decodable {
            struct Item: Decodable { let index: Int; let embedding: [Double] }
            let data: [Item]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw EmbeddingProviderError.rejected("响应无法解析")
        }
        guard decoded.data.count == expectedCount else {
            throw EmbeddingProviderError.rejected(
                "返回条数不符：期望 \(expectedCount)，得到 \(decoded.data.count)")
        }
        let ordered = decoded.data.sorted { $0.index < $1.index }
        for item in ordered where item.embedding.count != dimension {
            throw EmbeddingProviderError.rejected(
                "维度不符：期望 \(dimension)，得到 \(item.embedding.count)")
        }
        return ordered.map { $0.embedding.map(Float.init) }
    }
}
