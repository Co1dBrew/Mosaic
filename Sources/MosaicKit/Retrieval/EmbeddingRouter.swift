import Foundation

/// 生产环境该用哪一套 embedding。
///
/// **一个索引只能有一个向量空间。** 中文 640 维、英文 512 维、云端通常 1536 维，
/// 混进同一个 store 做余弦是没有意义的，而且看起来会像「检索质量突然变差」。
/// 所以这里输出的是**整库一条路线**，不是按块切换。
///
/// 优先级（iOS 上没有中文模型，这是给那种设备写的）：
///
/// 1. 本机有中文模型 → 用它（Mac 上的 zh-Hans，离线、已测过）
/// 2. 笔记里有汉字、本机没有中文模型 → 云端（大模型 /embeddings）
/// 3. 纯英文（没有任何汉字）→ 本机英文
/// 4. 以上都没有 → 不可用，关键词照常
///
/// **云端那一路要用户先同意。** 它把笔记正文发到第三方，而且是**整库**发 ——
/// 这比「生成一篇摘要」重得多，不能靠已经配了 API Key 就推定授权
/// （摘要与录音上传都有各自的明确同意，这里没有理由例外）。
public enum EmbeddingRoute: Equatable, Sendable {
    case localChinese
    case localEnglish
    case cloud
    /// 云端已配置好，但用户还没同意上传笔记内容。**此时不发任何请求。**
    ///
    /// 它与 `.unavailable` 分开，是因为两者的下一步动作完全不同：
    /// 一个是「问用户要不要开」，一个是「去设置里配」。合并成一个状态，
    /// UI 就只能给一句什么都没说的「不可用」。
    case cloudNeedsConsent
    case unavailable(String)

    public var usesCloud: Bool {
        if case .cloud = self { return true }
        return false
    }

    /// 还差用户点头。UI 据此决定是否展示同意入口。
    public var needsCloudConsent: Bool { self == .cloudNeedsConsent }

    /// Developer Mode / 状态条用的一句话，不含实现细节以外的词。
    public var explanation: String {
        switch self {
        case .localChinese:
            return "本机中文句向量可用，离线检索。"
        case .localEnglish:
            return "笔记为纯英文，使用本机英文句向量（离线）。"
        case .cloud:
            return "笔记含中文且本机没有中文模型，语义检索走云端 embedding。"
        case .cloudNeedsConsent:
            return "笔记含中文且本机没有中文模型。云端已配置，但需要你先同意上传笔记文字才会启用 —— 在此之前不会发出任何请求。"
        case .unavailable(let reason):
            return reason
        }
    }
}

public enum EmbeddingRouter {

    /// - Parameter cloudConsentGranted: 用户是否已明确同意把笔记文字发到云端。
    ///   **默认 false**：没有明确同意时，云端那一路一律降级为 `.cloudNeedsConsent`，
    ///   `ProductionEmbedding` 据此不构造 provider，于是一个请求都发不出去。
    public static func choose(corpusContainsHan: Bool,
                              localChineseAvailable: Bool,
                              localEnglishAvailable: Bool,
                              cloudConfigured: Bool,
                              cloudConsentGranted: Bool = false) -> EmbeddingRoute {
        // 本机模型优先于云端，与同意与否无关 —— 能离线做的事不该上传。
        if localChineseAvailable { return .localChinese }

        func cloudRoute() -> EmbeddingRoute {
            cloudConsentGranted ? .cloud : .cloudNeedsConsent
        }

        if corpusContainsHan {
            if cloudConfigured { return cloudRoute() }
            return .unavailable("笔记含中文，但本机没有中文句向量，且未配置云端 embedding。关键词搜索不受影响。")
        }

        // 纯英文库优先走本机英文：离线、不上传、零成本。
        if localEnglishAvailable { return .localEnglish }

        if cloudConfigured { return cloudRoute() }
        return .unavailable("本机没有可用的句向量模型，语义检索不可用；关键词搜索不受影响。")
    }

    /// 当前 provider 是本机英文时，中文 query 不能拿去嵌 —— 换语言就是换空间。
    /// 这种 query 只走关键词。
    public static func shouldSkipSemantic(query: String, route: EmbeddingRoute) -> Bool {
        if case .localEnglish = route { return ScriptDetection.containsHan(query) }
        return false
    }
}
