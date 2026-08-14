import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// # TD-5 —— 真实的本地 embedding
///
/// 用 Apple `NaturalLanguage` 的 `NLEmbedding`。选它而不是 Core ML 版 bge-small：
///
/// - **零下载、零依赖、完全离线。** 模型随系统提供，不占 App 体积，也不需要首次
///   启动时拉一个上百 MB 的文件。
/// - **中文原生支持。** `zh-Hans` 句向量 640 维，实测可用（见下）。
/// - Goal 1 要证明的是「检索质量可评测、可发布」，不是「模型选型最优」。先有一个
///   真实、可复现、能算出有意义 Recall 的基线，比先接一个更强但更重的模型重要。
///
/// 换成 bge-small 之类只需要新写一个 `EmbeddingProvider` 实现 —— 这正是 Week 1
/// 那个接缝存在的意义。
///
/// ## 实测：绝对间距很小，但排序正确
///
/// 8 条中文语料 / 4 条 query 上：
///
/// ```
/// 相关句 cos = 0.944   无关句 cos = 0.917      ← 只差 0.027
/// RAW        Recall@1 = 1.00   MRR = 1.000
/// CENTERED   Recall@1 = 0.75   MRR = 0.875     ← 中心化反而更差
/// ```
///
/// `NLEmbedding` 的向量空间高度各向异性（什么句子都彼此相似），所以**余弦绝对值
/// 没有解释力** —— 不要拿它当「相关度百分比」给人看。但排序只需要相对次序，而
/// 相对次序是对的。
///
/// 减去语料均值（centering）是缓解各向异性的标准做法，实测在这个规模上**反而
/// 降低了 Recall@1**，因此**不做**。等 Week 4 的 Golden Set 有了统计效力再重新判断。
///
/// ## 语言是 provider 身份的一部分
///
/// `zh-Hans` 是 640 维，`en` 是 512 维 —— **不同空间，连维度都不同**。把两种语言的
/// 向量放进同一个索引做余弦比较是没有意义的。因此每个实例锁定一种语言，并把语言
/// 编进 `modelInfo.version`：换语言 = 换模型 = 整个索引失效重建。
///
/// **已知限制：不支持跨语种检索。** 中文 query 检索不到纯英文笔记，反之亦然。
/// 这是本 provider 的边界，不是 bug；需要跨语种时换 provider。
public struct NLEmbeddingProvider: EmbeddingProvider {

    public enum Language: String, Sendable, CaseIterable {
        case simplifiedChinese = "zh-Hans"
        case english = "en"
    }

    public let modelInfo: EmbeddingModelInfo
    public let language: Language

    /// - Returns: `nil` 当系统没有该语言的句向量模型 —— 构造失败要立刻可见，
    ///   而不是留一个永远返回零向量的实例。
    public init?(language: Language = .simplifiedChinese) {
        #if canImport(NaturalLanguage)
        guard let dimension = Self.probeDimension(language) else { return nil }
        self.language = language
        self.modelInfo = EmbeddingModelInfo(
            identifier: "apple-nl-\(language.rawValue)",
            dimension: dimension,
            // 语言与模型修订都进版本号：任一改变都必须让索引失效。
            version: "nl-\(language.rawValue)-r\(Self.revision(language))"
        )
        #else
        return nil
        #endif
    }

    /// 系统是否具备该语言的句向量能力。
    public static func isAvailable(_ language: Language = .simplifiedChinese) -> Bool {
        probeDimension(language) != nil
    }

    public func embed(_ text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingProviderError.invalidInput("empty text") }

        #if canImport(NaturalLanguage)
        guard let raw = Self.vector(for: trimmed, language: language) else {
            throw EmbeddingProviderError.rejected("NLEmbedding 无法为该文本生成向量")
        }
        guard raw.count == modelInfo.dimension else {
            // 维度与声明不符意味着索引里会混进不可比的向量 —— 宁可失败。
            throw EmbeddingProviderError.rejected(
                "维度不符：期望 \(modelInfo.dimension)，得到 \(raw.count)")
        }
        return VectorMath.normalize(raw.map { Float($0) })
        #else
        throw EmbeddingProviderError.unavailable("NaturalLanguage 不可用")
        #endif
    }

    // MARK: 内部

    #if canImport(NaturalLanguage)
    private static func nlLanguage(_ l: Language) -> NLLanguage {
        switch l {
        case .simplifiedChinese: return .simplifiedChinese
        case .english: return .english
        }
    }

    private static func probeDimension(_ l: Language) -> Int? {
        NLEmbedding.sentenceEmbedding(for: nlLanguage(l))?.dimension
    }

    private static func revision(_ l: Language) -> Int {
        NLEmbedding.currentSentenceEmbeddingRevision(for: nlLanguage(l))
    }

    /// 句向量优先；拿不到时退回**词向量均值池化**。
    ///
    /// 退回是必要的：`sentenceEmbedding` 对超长文本或全是符号的文本会返回 nil，
    /// 而 chunk 里确实会出现这种内容（表格 OCR、纯 URL）。均值池化虽然粗糙，
    /// 但比整块内容检索不到强。
    ///
    /// ⚠️ 均值池化产出的是**词向量空间**（300 维），与句向量空间（640 维）不同。
    /// 维度校验会把它挡在 `embed` 之外 —— 所以这条退路目前只在维度恰好一致时生效，
    /// 实际等同于「拿不到句向量就报错」。保留代码是为了记录这个约束，
    /// 而不是假装它能兜底。真正的解法是 Week 4 之后换一个对长文本更稳的模型。
    private static func vector(for text: String, language: Language) -> [Double]? {
        let lang = nlLanguage(language)
        if let sentence = NLEmbedding.sentenceEmbedding(for: lang),
           let v = sentence.vector(for: text) {
            return v
        }
        guard let word = NLEmbedding.wordEmbedding(for: lang) else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(lang)

        var sum: [Double] = []
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            guard let v = word.vector(for: token) else { return true }
            if sum.isEmpty { sum = v } else { for i in 0..<min(sum.count, v.count) { sum[i] += v[i] } }
            count += 1
            return true
        }
        guard count > 0, !sum.isEmpty else { return nil }
        return sum.map { $0 / Double(count) }
    }
    #endif
}
