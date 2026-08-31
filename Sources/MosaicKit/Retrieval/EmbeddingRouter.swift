import Foundation

/// 生产环境该用哪一套 embedding。
///
/// **一个索引只能有一个向量空间。** 中文 640 维、英文 512 维、云端通常 1536 维，
/// 混进同一个 store 做余弦是没有意义的，而且看起来会像「检索质量突然变差」。
/// 所以这里输出的是**整库一条路线**，不是按块切换。
///
/// 优先级见 `choose` 的文档：**Cloud → Local → Keyword**（D-AI-003）。
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

    /// # 能力层级（D-AI-003）
    ///
    /// ```
    /// Cloud Semantic   ← 已配置 + 用户已同意
    ///   ↓ fallback
    /// Local Semantic   ← 本机有能覆盖当前语料语种的模型
    ///   ↓ fallback
    /// Keyword Only     ← 永远可用，最终保障
    /// ```
    ///
    /// **云端优先是实测结论，不是偏好**：在 150 篇 / 114 条 query 的 v3 集上，
    /// cross-language R@5 本地 0.128 → 云端 0.936，in-scope R@1 0.269 → 0.866。
    /// 差距不是调参能补的（`EMBEDDING_EXPERIMENT.md`）。
    ///
    /// **但云端不是默认开**：`cloudConsentGranted` 默认 false，因为它把整库笔记
    /// 发给第三方。没同意时**优先降级到本地**而不是弹窗打扰 —— 只有本地也顶不上
    /// （语料语种与本机模型对不上）时才返回 `.cloudNeedsConsent` 去问用户。
    ///
    /// - Parameter cloudConsentGranted: 用户是否已明确同意把笔记文字发到云端。
    public static func choose(corpusContainsHan: Bool,
                              localChineseAvailable: Bool,
                              localEnglishAvailable: Bool,
                              cloudConfigured: Bool,
                              cloudConsentGranted: Bool = false) -> EmbeddingRoute {
        // 1 · 云端：已配置且已授权 —— 质量最好，且是唯一能做跨语言的一路。
        if cloudConfigured && cloudConsentGranted { return .cloud }

        // 2 · 本地：本机模型能不能覆盖当前语料的语种。
        //    覆盖不了时用它等于把中文笔记配英文模型，排出来的顺序没有意义。
        if corpusContainsHan {
            if localChineseAvailable { return .localChinese }
        } else if localEnglishAvailable {
            return .localEnglish
        }

        // 3 · 本地顶不上，而云端只差一次授权 —— 这时候才值得问用户。
        if cloudConfigured { return .cloudNeedsConsent }

        // 4 · 都没有：语义整条缺席，keyword 照常。
        return .unavailable(corpusContainsHan
            ? "笔记含中文，但本机没有中文句向量，且未配置云端 embedding。关键词搜索不受影响。"
            : "本机没有可用的句向量模型，语义检索不可用；关键词搜索不受影响。")
    }

    /// # 「开启云端能搜到英文文档」—— D-AI-003 的已知缺口
    ///
    /// `choose` 在「本地可用 + 云端已配置但未授权」时返回 `.localChinese`，
    /// **不返回 `.cloudNeedsConsent`** —— 那是刻意的：本地顶得上时不该弹窗打扰。
    ///
    /// 但它留下一个缺口：**双语库**下本地语义只覆盖一种语种，
    /// 中文 query 搜不到英文文档，而系统安静地用本地跑完，**不告诉用户还有更好的选项**。
    /// 用户看到的是「搜不到」，不是「有个开关能搜到」。
    ///
    /// 实测代价（v4 · 210 篇 / 65 条跨语言 query）：
    /// cross-language R@5 本地 **0.092** → 云端 **0.892**。这不是边角差异。
    ///
    /// 所以路由之外单独给一个提示信号。**它不改变路由**（`choose` 的返回值不变），
    /// 只回答「要不要顺带告诉用户一句」。分开的理由：路由是能力判定，
    /// 提示是产品沟通，混在一个返回值里会让「弹不弹窗」变成路由的副作用。
    ///
    /// 四个条件缺一不可 —— 少任何一个，这句提示要么没用要么是骚扰：
    ///
    /// 1. 当前走的是**本地**语义（云端已经在用就没什么可提示的）
    /// 2. 云端**已配置**（没配 Key 时提示只会让人去做一件更长的事）
    /// 3. 用户**尚未授权**（已授权还提示 = 打扰）
    /// 4. 语料**确实是双语**（单语库上本地够用，提示是纯噪声）
    /// **返回的是判断，不是文案。** 用户可见的句子由 App 侧的 `Copy` 提供 ——
    /// `SEARCH_CONTRACT.md` §1.1.1 有一张禁用词表（向量 / 语义检索 / chunk / index …），
    /// 而内核不该、也没法执行那张表。内核只回答「这一刻值不值得说一句」。
    ///
    /// **第五个条件是这一版有没有语义路。** `PRODUCTION_RETRIEVAL = KEYWORD` 之下
    /// 这句提示是一句空头支票：用户照着开了云端，搜索行为一点不变 ——
    /// 因为语义那一整条压根不跑。它比不提示更糟，因为它还要用户去授权一次数据外发。
    public static func shouldOfferCloudUpgrade(route: EmbeddingRoute,
                                               cloudConfigured: Bool,
                                               cloudConsentGranted: Bool,
                                               corpusContainsHan: Bool,
                                               corpusContainsLatin: Bool,
                                               semanticInProduction: Bool = true) -> Bool {
        guard semanticInProduction else { return false }
        guard !route.usesCloud else { return false }
        guard cloudConfigured, !cloudConsentGranted else { return false }
        guard corpusContainsHan && corpusContainsLatin else { return false }
        switch route {
        case .localChinese, .localEnglish:
            return true
        case .cloud, .cloudNeedsConsent, .unavailable:
            // `.cloudNeedsConsent` 已经会在 UI 上出现授权入口，不需要第二句提示。
            // `.unavailable` 是另一个状态，`explanation` 已经在说了。
            return false
        }
    }

    /// 当前 provider 是本机英文时，中文 query 不能拿去嵌 —— 换语言就是换空间。
    /// 这种 query 只走关键词。
    public static func shouldSkipSemantic(query: String, route: EmbeddingRoute) -> Bool {
        if case .localEnglish = route { return ScriptDetection.containsHan(query) }
        return false
    }
}
