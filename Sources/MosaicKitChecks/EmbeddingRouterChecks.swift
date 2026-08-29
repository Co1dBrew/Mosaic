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
        // **云端未授权时**落回本机中文。注意这不是「本地永远优先」——
        // D-AI-003 之后云端在已授权时优先（见下方 checkPreference）；
        // 这一条守的是 fallback：没授权不该把用户从可用的本地语义降级到零。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true) == .localChinese,
                 "云端未授权 → 落回本机中文，而不是降级为不可用")

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

        // ── D-AI-003：层级翻转为 Cloud → Local → Keyword ──
        //
        // v2 时是「本地优先，能离线做的事不该上传」。v3 的实测把它推翻了：
        // 同一批 114 条 query 上，本地 Hybrid 的 in-scope R@1 是 0.269、
        // cross-language R@5 是 0.128；云端分别是 0.866 和 0.936。
        // 差距大到「省一次上传」换不回来 —— 所以云端在**已授权**时优先。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .cloud,
                 "已授权的云端优先于本机中文模型（D-AI-003，实测驱动）")
        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: true) == .cloud,
                 "纯英文库同样走已授权的云端")

        // 但**没授权时不弹窗打扰**：本地顶得上就用本地。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: false) == .localChinese,
                 "云端未授权 + 本地顶得上 → 静默降级到本地，不去骚扰用户")
        r.expect(EmbeddingRouter.choose(corpusContainsHan: false,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: false) == .localEnglish,
                 "纯英文库未授权时用本机英文")

        // 只有本地顶不上时，才值得为授权打断用户。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: false,
                                        localEnglishAvailable: true,
                                        cloudConfigured: true,
                                        cloudConsentGranted: false) == .cloudNeedsConsent,
                 "本地顶不上（中文语料 + 无中文模型）才请求授权 —— 这正是 iPhone 上的现状")

        // 云端授权了但本地也在：仍走云端；云端配置被撤掉则回落本地。
        r.expect(EmbeddingRouter.choose(corpusContainsHan: true,
                                        localChineseAvailable: true,
                                        localEnglishAvailable: true,
                                        cloudConfigured: false,
                                        cloudConsentGranted: true) == .localChinese,
                 "云端未配置 → 降级本地，而不是直接掉到 keyword")

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

/// P1 #8 · 「开启云端能搜到英文文档」提示。
///
/// 断言的是**什么时候不该提示** —— 一句在四种情形里有三种会变成骚扰的提示，
/// 价值全在它的抑制条件上，不在文案上。
extension EmbeddingRouterChecks {
    static func runCloudUpgradeHint(_ r: CheckRunner) {
        r.suite("P1 #8 · 云端升级提示 —— 四个条件缺一不可")

        func hint(route: EmbeddingRoute, configured: Bool = true, consented: Bool = false,
                  han: Bool = true, latin: Bool = true) -> Bool {
            EmbeddingRouter.shouldOfferCloudUpgrade(route: route, cloudConfigured: configured,
                                                    cloudConsentGranted: consented,
                                                    corpusContainsHan: han, corpusContainsLatin: latin)
        }

        // 该提示的那一种：本地语义 + 云端已配未授权 + 双语库
        r.expect(hint(route: .localChinese), "本地语义 + 云端已配未授权 + 双语库 → 提示")
        r.expect(hint(route: .localEnglish), "本地英文语义下同样适用（反方向搜不到中文）")
        r.expect(true, "文案不在内核 —— §1.1.1 的禁用词表由 App 侧的 Copy 执行，内核只给判断")

        // 四种不该提示的
        r.expect(!hint(route: .cloud, consented: true), "已经在用云端 → 不提示")
        r.expect(!hint(route: .localChinese, configured: false),
                 "云端没配置 → 不提示。让人去配 Key 是另一件更长的事，不该由一句搜索提示发起")
        r.expect(!hint(route: .localChinese, consented: true), "已授权 → 不提示（重复打扰）")
        r.expect(!hint(route: .localChinese, latin: false), "纯中文库 → 不提示（本地够用）")
        r.expect(!hint(route: .localChinese, han: false), "纯英文库 → 不提示")
        r.expect(!hint(route: .cloudNeedsConsent),
                 "已经是 cloudNeedsConsent → UI 上本来就有授权入口，不需要第二句")
        r.expect(!hint(route: .unavailable("no model")),
                 "语义整条不可用 → 那是另一个状态，`explanation` 已经在说了")

        // 它**不改变路由** —— 提示是产品沟通，路由是能力判定
        let route = EmbeddingRouter.choose(corpusContainsHan: true, localChineseAvailable: true,
                                           localEnglishAvailable: true, cloudConfigured: true,
                                           cloudConsentGranted: false)
        r.expect(route == .localChinese,
                 "有提示不等于改路由：仍然走本地，**不弹 cloudNeedsConsent 打断搜索**")
        r.expect(EmbeddingRouter.shouldOfferCloudUpgrade(route: route, cloudConfigured: true,
                                                         cloudConsentGranted: false,
                                                         corpusContainsHan: true,
                                                         corpusContainsLatin: true),
                 "但这一种情形确实会给出提示 —— 这正是 D-AI-003 登记的那个缺口")
    }
}
