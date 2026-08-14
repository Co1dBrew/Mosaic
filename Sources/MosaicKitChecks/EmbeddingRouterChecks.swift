import Foundation
import MosaicKit

enum EmbeddingRouterChecks {

    static func run(_ r: CheckRunner) {
        r.suite("EmbeddingRouter · 中文走云端 / 纯英文走本地")

        checkScriptDetection(r)
        checkRouting(r)
        checkQuerySkip(r)
    }

    private static func checkScriptDetection(_ r: CheckRunner) {
        r.expect(ScriptDetection.containsHan("延期毕业"), "简体汉字算中文")
        r.expect(ScriptDetection.containsHan("畢業延期"), "繁体汉字算中文")
        r.expect(ScriptDetection.containsHan("hello 世界"), "中英混排算「有中文」")
        r.expect(!ScriptDetection.containsHan("graduation deferral"), "纯英文不算中文")
        r.expect(!ScriptDetection.containsHan("123 ?!"), "数字标点不算中文")
        r.expect(!ScriptDetection.containsHan(""), "空字符串不算中文")
        r.expect(!ScriptDetection.containsHan("ひらがなカタカナ"), "假名不算汉字")

        let chineseBlock = CardBlockContent(id: "b1", order: 0, kind: .text, text: "问 advisor 能不能延期")
        r.expect(ScriptDetection.containsHan(title: "Note", blocks: [chineseBlock]),
                 "块正文有汉字 → 这篇含中文")

        let englishBlock = CardBlockContent(id: "b2", order: 0, kind: .text, text: "Ask the advisor about deferral")
        r.expect(!ScriptDetection.containsHan(title: "Meeting notes", tags: ["work"], blocks: [englishBlock]),
                 "标题 / 标签 / 正文都无汉字 → 纯英文")
        r.expect(ScriptDetection.containsHan(title: "会议", tags: [], blocks: [englishBlock]),
                 "标题有汉字也算")
        r.expect(ScriptDetection.containsHan(title: "", tags: ["延期"], blocks: [englishBlock]),
                 "标签有汉字也算")
        r.expect(ScriptDetection.containsHan(title: "", blocks: [englishBlock], extraTexts: ["设备安装位置"]),
                 "OCR / 附加文本有汉字也算")
    }

    private static func checkRouting(_ r: CheckRunner) {
        // 本机中文模型在时永远优先 —— 不因为库里有中文就改走云端（Mac）。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true) == .localChinese,
                 "本机中文可用 → 离线中文，不走云端")

        // iOS 现状：无中文模型，笔记有中文。**同意之后**才是云端 ——
        // 没同意的那一支由下面「隐私闸门」一节单独守。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .cloud,
                 "有中文 + 无本机中文 + 云端已配 + 已同意 → 云端")

        if case .unavailable(let reason) = EmbeddingRouter.choose(corpusContainsHan: true,
                                                                   localChineseAvailable: false,
                                                                   localEnglishAvailable: true,
                                                                   cloudConfigured: false) {
            r.expect(reason.contains("中文"), "有中文但云端没配 → 不可用，并说清原因")
            r.expect(reason.contains("关键词"), "不可用时必须声明关键词不受影响")
        } else {
            r.expect(false, "有中文、无本机中文、无云端 → 必须 unavailable")
        }

        // 纯英文。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: false) == .localEnglish,
                 "纯英文 + 本机英文 → 本地英文")

        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true) == .localEnglish,
                 "纯英文即使配了云端也先用本地 —— 「先用本地」")

        // 空库 / 无汉字，本机什么都没有。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: false,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .cloud,
                 "本机两种语言都没有、云端已配 → 云端兜底")

        if case .unavailable = EmbeddingRouter.choose(corpusContainsHan: false,
                                                      localChineseAvailable: false,
                                                      localEnglishAvailable: false,
                                                      cloudConfigured: false) {
            r.expect(true, "什么都没有 → unavailable")
        } else {
            r.expect(false, "什么都没有应 unavailable")
        }
    }

    private static func checkQuerySkip(_ r: CheckRunner) {
        // ── 隐私闸门：云端那一路要用户先点头 ──
        r.suite("Week6 · 云端路线的隐私闸门 —— 没同意就不上传")

        let configuredNoConsent = EmbeddingRouter.choose(corpusContainsHan: true,
                                                         localChineseAvailable: false,
                                                         localEnglishAvailable: true,
                                                         cloudConfigured: true,
                                                         cloudConsentGranted: false)
        r.expect(configuredNoConsent == .cloudNeedsConsent,
                 "云端配好但没同意 → cloudNeedsConsent，不是 cloud")
        r.expect(configuredNoConsent.needsCloudConsent, "UI 据此展示同意入口")
        r.expect(!configuredNoConsent.usesCloud,
                 "没同意时不算「在用云端」—— 这一条决定了会不会真的发出请求")

        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .cloud,
                 "同意之后才走云端")

        // 默认参数必须是**不同意**：一个默认放行的隐私闸门等于没有闸门。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: false,
                                        cloudConfigured: true) == .cloudNeedsConsent,
                 "cloudConsentGranted 的默认值是 false —— 默认放行的闸门等于没有闸门")

        // 本机能做的事不上传：有本机中文模型时，同意与否都不走云端。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .localChinese,
                 "本机中文模型优先于云端 —— 能离线做的事不该上传")
        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .localEnglish,
                 "纯英文库优先本机英文 —— 同样不上传")

        // 「没配」与「配了没同意」必须能区分开：下一步动作完全不同。
        let notConfigured = EmbeddingRouter.choose(corpusContainsHan: true,
                                                   localChineseAvailable: false,
                                                   localEnglishAvailable: false,
                                                   cloudConfigured: false,
                                                   cloudConsentGranted: true)
        r.expect(notConfigured != .cloudNeedsConsent,
                 "没配置 → unavailable（去设置里填），不是 needsConsent（问用户要不要开）")
        r.expect(configuredNoConsent.explanation.contains("不会发出任何请求"),
                 "文案要明确承诺「在此之前不发请求」")

        r.expect(EmbeddingRouter.shouldSkipSemantic(query: "延期毕业", route: .localEnglish),
                 "英文索引上的中文 query 不能拿去嵌")
        r.expect(!EmbeddingRouter.shouldSkipSemantic(query: "deferral", route: .localEnglish),
                 "英文 query 走本机英文")
        r.expect(!EmbeddingRouter.shouldSkipSemantic(query: "延期毕业", route: .cloud),
                 "云端（多语言）不跳过中文 query")
        r.expect(!EmbeddingRouter.shouldSkipSemantic(query: "延期毕业", route: .localChinese),
                 "本机中文不跳过中文 query")
    }
}
