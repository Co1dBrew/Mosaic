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

    public struct Note: Codable, Equatable {
        public let id: String
        public let title: String
        public let source: RetrievalSource
        public let language: Language
        public let role: NoteRole
        public let content: String
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

        public var evalCase: EvalCase {
            EvalCase(id: id, query: query, expectedNoteIDs: expectedNoteIDs,
                     source: .golden, addedAt: .distantPast,
                     queryLanguage: queryLanguage, expectedLanguage: expectedLanguage,
                     scope: scope, note: "[\(style.rawValue)] \(note)")
        }
    }

    public struct NegativeQuery: Codable, Equatable {
        public let id: String
        public let query: String
        public let reason: String

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
