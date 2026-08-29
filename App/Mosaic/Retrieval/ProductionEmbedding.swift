import Foundation
import MosaicKit

/// 把 `EmbeddingRouter` 的抽象选择落实成一个真正能 embed 的 provider。
enum ProductionEmbedding {

    struct Decision {
        let route: EmbeddingRoute
        let provider: (any EmbeddingProvider)?
    }

    /// - Parameters:
    ///   - cloudConfigured: 云端**参数**齐了（Key / 模型 / URL）—— 与同意无关。
    ///   - cloudConsentGranted: 用户是否明确同意上传笔记文字。
    ///   - makeCloud: 只有在真的要走云端时才求值。**没同意就不构造** ——
    ///     构造本身会把 API Key 拷进请求对象，没必要在未授权路径上做这件事。
    ///
    /// 两个布尔分开传，是因为「没配」和「配了但没同意」的下一步动作完全不同：
    /// 一个是去设置里填，一个是问用户要不要开。合成一个 `cloudOK` 就只能给一句
    /// 什么都没说的「不可用」。
    static func decide(corpusContainsHan: Bool,
                       cloudConfigured: Bool,
                       cloudConsentGranted: Bool,
                       makeCloud: () -> Result<any EmbeddingProvider, EmbeddingProviderError>) -> Decision {

        let route = EmbeddingRouter.choose(
            corpusContainsHan: corpusContainsHan,
            localChineseAvailable: NLEmbeddingProvider.isAvailable(.simplifiedChinese),
            localEnglishAvailable: NLEmbeddingProvider.isAvailable(.english),
            cloudConfigured: cloudConfigured,
            cloudConsentGranted: cloudConsentGranted
        )

        switch route {
        case .localChinese:
            return Decision(route: route, provider: try? LocalEmbedding.make(language: .simplifiedChinese))
        case .localEnglish:
            return Decision(route: route, provider: try? LocalEmbedding.make(language: .english))
        case .cloud:
            switch makeCloud() {
            case .success(let provider):
                return Decision(route: route, provider: provider)
            case .failure(let error):
                return Decision(route: .unavailable("云端 embedding 不可用：\(error)。关键词搜索不受影响。"),
                                provider: nil)
            }
        case .cloudNeedsConsent, .unavailable:
            // **这是隐私闸门真正生效的地方**：provider 为 nil，检索层拿不到东西
            // 可用，于是一个网络请求都发不出去。
            return Decision(route: route, provider: nil)
        }
    }

    /// 单篇笔记是否含汉字。**编辑热路径只算这一篇**，不扫全库。
    @MainActor
    static func noteContainsHan(_ card: Card, derived: DerivedDataStore) -> Bool {
        let ocr = derived.ocrTextByBlockID(noteID: card.id.uuidString)
        // 不要用 `displayTitle`：空标题的回退文案是「未命名笔记」，
        // 会让纯英文库被误判成含中文。
        let title = [card.userTitle, card.summary?.baseTitle]
            .compactMap { $0 }
            .joined(separator: " ")
        return ScriptDetection.containsHan(title: title,
                                           tags: card.tags,
                                           blocks: card.blockContents(),
                                           extraTexts: Array(ocr.values))
    }

    /// 标题、标签、正文、转写、OCR 任何一处有汉字即视为库里「有中文」。
    ///
    /// ⚠️ **这是 O(全库) 的**：实测 200 篇 × 5 块约 26 ms，且全程在 main actor 上。
    /// 只能在低频时机调用（启动 / 手动 Rescan / 设置变更），**绝不能放进编辑路径**。
    @MainActor
    static func corpusContainsHan(cards: [Card], derived: DerivedDataStore) -> Bool {
        cards.contains { noteContainsHan($0, derived: derived) }
    }

    /// 库里有没有拉丁字母。**只用来判断「是不是双语库」**（P1 #8 的提示条件），
    /// 不参与路由 —— 路由只关心「有没有中文」，因为那才决定要不要中文模型。
    ///
    /// 与 `corpusContainsHan` 同样是 O(全库) 且在 main actor 上，
    /// 所以两者**在同一次 rescan 里一起调**，不各扫一遍。
    @MainActor
    static func corpusContainsLatin(cards: [Card], derived: DerivedDataStore) -> Bool {
        cards.contains { card in
            let ocr = derived.ocrTextByBlockID(noteID: card.id.uuidString)
            // 同 `noteContainsHan`：不用 displayTitle，回退文案会污染判断。
            let title = [card.userTitle, card.summary?.baseTitle]
                .compactMap { $0 }
                .joined(separator: " ")
            return ScriptDetection.containsLatin(title: title,
                                                 tags: card.tags,
                                                 blocks: card.blockContents(),
                                                 extraTexts: Array(ocr.values))
        }
    }
}
