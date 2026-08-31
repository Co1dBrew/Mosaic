import Foundation

/// 一套**仿真人场景**的候选 Golden Set。
///
/// 它解决的是原来 7 条用例的两个明显缺口：只有 text、query 刻意偏向 semantic。
/// 这里覆盖五种语料，既有用户记得原词的 query，也有只记得含义的自然语言表达。
///
/// - Important: 这是 synthetic fixture，不是真实用户标注。它可以证明评测管线和覆盖
///   结构成立，不能用来声称「真实用户 Recall 提升 x%」。正式 Golden Set 仍需要人
///   在设备上对真实笔记做相关性判断。
///
/// # 为什么这个类型在 `MosaicKit` 里，而 JSON 不在
///
/// 它原来整个住在 `MosaicKitChecks`（Mac 侧的 checks 可执行文件）。真机基准是另一个
/// target，用不到它 —— 而「让 golden set 的 eval 整体跑在真机上」正是 Gate 判定
/// 缺的最后一块（质量与延迟必须出自同一次跑批）。
///
/// 两条路都不好：把 140 行解析逻辑复制一份进 bench target 会漂移；把 100 KB 的
/// fixture JSON 塞进 `MosaicKit` 会让它跟着产品 app 一起发出去。
///
/// 所以拆开：**类型与解析在这里**（`decode(_:)` 只接受 `Data`，不碰 `Bundle`），
/// **数据仍只有一份 JSON**，由 checks 与 bench 两个 target 各自把同一个文件
/// 作为资源引用。谁都不复制，谁都不多发。
public enum GoldenSetFixture {

    public typealias Language = EvalLanguage

    public enum NoteRole: String, Codable {
        case target
        case distractor
    }

    public enum QueryStyle: String, Codable, CaseIterable {
        case exact
        case natural
        case mixed
    }

    public typealias Scope = EvalScope

    public enum LongRegion: String, Codable {
        case middle
        case end
    }

    // MARK: v5 —— 场景化评测集的新增标注
    //
    // 全部**可选**。v4 的 JSON 不带这些字段，仍然能被同一个解析器读出来 ——
    // 换 schema 不该让历史跑批变成不可复现的。

    /// 用例考的是哪一种检索能力。
    ///
    /// 它不是「难度的另一种说法」：`lexicalTrap` 与 `nearDuplicate` 都可以是 hard，
    /// 但**失败原因完全不同**，改进方向也不同（一个是词面对抗，一个是排序区分度）。
    /// 分类的价值在于「这一轮 60% 的失败集中在哪一类」，与 `FailureType` 同理。
    public enum Category: String, Codable, Sendable, CaseIterable {
        /// 记得意思，不记得原词。
        case semanticRecall = "semantic_recall"
        /// 要准确找到日期 / 金额 / 编号 / 版本号。
        case exactFact = "exact_fact"
        /// query 与**错误**笔记词面重合度高，正确笔记词面重合度低。
        case lexicalTrap = "lexical_trap"
        /// 两篇以上主题几乎一样，答案只在其中一篇。
        case nearDuplicate = "near_duplicate"
        /// 中文 query 找英文笔记，或反过来。
        case crossLanguage = "cross_language"
        /// 错别字 / 口语 / 缩写 / 实体记错一部分。
        case noisyQuery = "noisy_query"
        /// 只记得场景，靠上下文找。
        case contextualRecall = "contextual_recall"
        /// 语料里没有答案。
        case negative
        /// 存在两个都合理的候选。**必须在标注里说明**，不强行制造唯一答案。
        case ambiguous
    }

    public enum Difficulty: String, Codable, Sendable, CaseIterable {
        case easy, medium, hard
    }

    /// 开发集 / 留出集。
    ///
    /// 留出集**只用于发布判定**。允许在开发集上调参、分析、debug；
    /// 针对某一条留出用例加特殊逻辑属于 evaluation overfit，必须撤销。
    public enum Split: String, Codable, Sendable, CaseIterable {
        case development, holdout
    }

    /// 数据来源标记。
    ///
    /// **这一项存在的唯一目的是防止把它说成真实用户数据。**
    /// Agent 写出来的场景化用例可以叫「production-style / human-like / 场景化」，
    /// 不能叫 real user logs / actual user queries / organic traffic。
    /// 这批用例是**谁写的**。
    ///
    /// 它不是元数据装饰：一份 agent 写的评测集和一份真人写的评测集，
    /// 支撑的结论强度完全不同。所以它进每一条数据、有断言守着，
    /// 而不是只写在文档里（数据会被拷走，文档不会）。
    ///
    /// **`human_*` 两个值现在没有数据在用**，它们存在是为了让将来那份
    /// 人工评测集**不需要改 schema 就能导入**。这一点必须现在就成立：
    /// `provenance` 是可选枚举，遇到不认识的字符串**不是**解成 nil 而是
    /// 整个文件解析失败 —— 也就是说，少一个 case 就等于「拿到人工数据那天，
    /// 第一件事是发现导不进来」。
    public enum Provenance: String, Codable, Sendable {
        case agentAuthoredRealistic = "agent_authored_realistic"
        /// 真人在**看得到笔记**的情况下标注既有 query（标注者，不是提问者）。
        case humanAnnotated = "human_annotated"
        /// 真人**没看笔记**、按自己真实的回忆写下 query（提问者）。
        ///
        /// 与 `humanAnnotated` 分开是因为两者的偏差方向相反：
        /// 看着笔记写 query 会不自觉地抄词面（高估词法路），
        /// 凭记忆写 query 才是产品要面对的输入。
        case humanAuthored = "human_authored"

        /// 这一条是不是真人产出的。将来报告里「多少条来自真人」读它。
        public var isHumanSourced: Bool { self != .agentAuthoredRealistic }
    }

    public struct Note: Codable, Equatable {
        public let id: String
        public let title: String
        public let source: RetrievalSource
        public let language: Language
        public let role: NoteRole
        public let content: String
        /// 同构簇 id。同一簇里的笔记**主题几乎一样**，只有细节不同 ——
        /// near-duplicate 用例的干扰项就从这里来。
        ///
        /// v4 的簇是 3 篇，而 Top-5 装得下整簇，于是 in-scope R@5 恒为 1.000，
        /// 这个指标什么都没测到。v5 的簇是 6–8 篇。
        public var cluster: String?
        /// 长文专项的两处稳定锚点。中段锚点必须落在全文 40%–60%，末段锚点
        /// 必须落在 80% 之后，保证 chunking 实验不是只测第一块。
        public let middleMarker: String?
        public let endMarker: String?

        public var blockID: String { "\(id)-block" }

        public var block: CardBlockContent {
            switch source {
            case .text:
                return CardBlockContent(id: blockID, order: 0, kind: .text, text: content)
            case .transcript:
                return CardBlockContent(id: blockID, order: 0, kind: .audio,
                                        transcript: content, audioDurationSec: 180,
                                        audioAssetRef: "synthetic-\(id).m4a")
            case .ocr:
                // OCR 是 derived overlay，不写进用户的 Block。caption 只提供人类可读的语境。
                return CardBlockContent(id: blockID, order: 0, kind: .image,
                                        imageCaption: title,
                                        imageAssetRef: "synthetic-\(id).jpg")
            case .extracted:
                return CardBlockContent(id: blockID, order: 0, kind: .file,
                                        fileName: "\(title).pdf", fileType: "pdf",
                                        extractedText: content)
            case .link:
                return CardBlockContent(id: blockID, order: 0, kind: .link,
                                        url: "https://example.invalid/\(id.lowercased())",
                                        linkTitle: title, linkDescription: content)
            }
        }

        public var ocrOverlay: [String: String] {
            source == .ocr ? [blockID: content] : [:]
        }
    }

    public struct Candidate: Codable, Equatable {
        public let id: String
        public let query: String
        public let expectedNoteIDs: [String]
        public let style: QueryStyle
        public let queryLanguage: Language
        public let expectedLanguage: Language
        public let scope: Scope
        public let longRegion: LongRegion?
        public let note: String

        // MARK: v5 标注（可选）

        /// 用户当时的处境，一句话。写它是为了让「这条 query 像不像真人问的」
        /// 可以被第二个人复核 —— 没有场景就只能凭感觉判断。
        public var scenario: String?
        public var category: Category?
        public var difficulty: Difficulty?
        /// 目标笔记的语料类型。冗余存一份是为了能直接按类型切片统计，
        /// 不必每次回查笔记表。**校验时会与笔记表对账**，对不上即数据错误。
        public var contentType: RetrievalSource?
        /// 分级相关性 `noteID -> 0...3`。
        ///
        /// 3 = 就是它 · 2 = 相关 · 1 = 部分相关 · 0 = 不相关但容易误判。
        /// 现有指标体系是 binary 的，映射规则见 `binaryRelevantNoteIDs`；
        /// 分级本身保留下来，将来上 nDCG 时不必重新标注。
        public var relevance: [String: Int]?
        /// 容易被误判成答案的笔记。**不是随机负例** —— 每一条都要能说出
        /// 「为什么容易误判」（同一家公司 / 同一个日期附近 / 同一份合同的另一版）。
        public var hardNegativeNoteIDs: [String]?
        /// 期望的产品行为，用户侧说法。
        public var expectedBehavior: String?
        /// 期望的落点：`top` / `block:<id>` / `transcript:<id>`。
        public var expectedLandingTarget: String?
        /// 这条为什么值得测。
        public var rationale: String?
        public var provenance: Provenance?
        public var split: Split?
        /// 写这条 query 的时候，作者**看得见目标笔记吗**。
        ///
        /// 只对 `human_authored` 有意义，所以是可选的（现有 agent 数据不带它）。
        /// 记它的理由：看着笔记写出来的 query 会不自觉地抄词面，
        /// 于是词法路的分数虚高 —— 那种数据能证明的东西比它看起来少得多。
        /// **将来那份人工评测集必须能回答这个问题**，字段现在就留好。
        public var notesVisibleWhileAuthoring: Bool?
        /// 这条同时属于**回归集**。
        ///
        /// 回归集不是另一批数据（`DECISION_LOG` D-UI-DEV-009：Golden 与 Regression
        /// 结构完全相同）。它是一个标记：**这几条曾经坏过，不许再坏**。
        /// Gate 的第四行读的就是它们的通过率 —— 集合为空时那一行恒过，
        /// 也就等于没有那一行。
        public var isRegression: Bool?

        /// 分级 → binary 的映射：**≥2 算相关**。
        ///
        /// 1 分（部分相关）不进分母也不算命中 —— 把「勉强沾边」算成命中会让
        /// Recall 虚高，算成错误又会惩罚一个合理的结果。它只在将来上 nDCG 时有用。
        public var binaryRelevantNoteIDs: [String] {
            guard let relevance, !relevance.isEmpty else { return expectedNoteIDs }
            return relevance.filter { $0.value >= 2 }.keys.sorted()
        }

        public var evalCase: EvalCase {
            EvalCase(id: id, query: query, expectedNoteIDs: expectedNoteIDs,
                     source: (isRegression ?? false) ? .regression : .golden,
                     addedAt: .distantPast,
                     queryLanguage: queryLanguage, expectedLanguage: expectedLanguage,
                     scope: scope, note: "[\(style.rawValue)] \(note)")
        }
    }

    public struct NegativeQuery: Codable, Equatable {
        public let id: String
        public let query: String
        public let reason: String
        public var scenario: String?
        public var queryLanguage: Language?
        public var difficulty: Difficulty?
        /// 负例同样可以有 hard negative：语料里有主题相近但确实答不上的笔记。
        public var hardNegativeNoteIDs: [String]?
        public var provenance: Provenance?
        public var split: Split?
        /// 这条同时属于**回归集**。
        ///
        /// 回归集不是另一批数据（`DECISION_LOG` D-UI-DEV-009：Golden 与 Regression
        /// 结构完全相同）。它是一个标记：**这几条曾经坏过，不许再坏**。
        /// Gate 的第四行读的就是它们的通过率 —— 集合为空时那一行恒过，
        /// 也就等于没有那一行。
        public var isRegression: Bool?

        public var evalCase: EvalCase {
            EvalCase(id: id, query: query, expectation: .noRelevantResult,
                     source: .golden, addedAt: .distantPast, note: reason)
        }
    }

    public struct Dataset: Codable, Equatable {
        public let version: String
        public let disclaimer: String
        public let notes: [Note]
        public let cases: [Candidate]
        public let negativeQueries: [NegativeQuery]
        /// 冻结这一份数据的内容指纹。留出集一旦冻结就不该再动 ——
        /// 有指纹才能证明「这次判定用的是冻结的那一份」。
        public var checksum: String?

        /// 只取某一个 split 的全部用例（正例 + 负例）。
        ///
        /// 发布判定读 `.holdout`，调参与分析读 `.development`。
        /// **没有标 split 的用例视为 development** —— v4 的历史数据落在这里，
        /// 它们不该悄悄进入发布判定。
        public func evalCases(split: Split) -> [EvalCase] {
            let positives = cases
                .filter { ($0.split ?? .development) == split }
                .map(\.evalCase)
            let negatives = negativeQueries
                .filter { ($0.split ?? .development) == split }
                .map(\.evalCase)
            return positives + negatives
        }

        public var evalCases: [EvalCase] { cases.map(\.evalCase) }
        public var negativeEvalCases: [EvalCase] { negativeQueries.map(\.evalCase) }
        public var allEvalCases: [EvalCase] { evalCases + negativeEvalCases }

        public var chunks: [NoteChunk] {
            notes.flatMap { note in
                ChunkPipeline.chunks(noteID: note.id,
                                     blocks: [note.block],
                                     strategy: .default,
                                     ocrTextByBlockID: note.ocrOverlay)
            }
        }
    }

    /// 从 `Data` 解码。**故意不接受 `Bundle`** —— 资源在哪由调用方决定：
    /// Mac 侧的 checks 从 `Bundle.module` 拿，真机 bench 从测试 bundle 拿，
    /// 而解析逻辑只有这一份。
    public static func decode(_ data: Data) throws -> Dataset {
        try JSONDecoder().decode(Dataset.self, from: data)
    }

    public enum FixtureError: Error {
        case resourceMissing
    }
}
