import Foundation
import MosaicKit

/// 一套**仿真人场景**的候选 Golden Set。
///
/// 它解决的是原来 7 条用例的两个明显缺口：只有 text、query 刻意偏向 semantic。
/// 这里覆盖五种语料，既有用户记得原词的 query，也有只记得含义的自然语言表达。
///
/// - Important: 这是 synthetic fixture，不是真实用户标注。它可以证明评测管线和覆盖
///   结构成立，不能用来声称「真实用户 Recall 提升 x%」。正式 Golden Set 仍需要人
///   在设备上对真实笔记做相关性判断。
enum HumanLikeGoldenFixture {

    typealias Language = EvalLanguage

    enum NoteRole: String, Codable {
        case target
        case distractor
    }

    enum QueryStyle: String, Codable, CaseIterable {
        case exact
        case natural
        case mixed
    }

    typealias Scope = EvalScope

    enum LongRegion: String, Codable {
        case middle
        case end
    }

    struct Note: Codable, Equatable {
        let id: String
        let title: String
        let source: RetrievalSource
        let language: Language
        let role: NoteRole
        let content: String
        /// 长文专项的两处稳定锚点。中段锚点必须落在全文 40%–60%，末段锚点
        /// 必须落在 80% 之后，保证 chunking 实验不是只测第一块。
        let middleMarker: String?
        let endMarker: String?

        var blockID: String { "\(id)-block" }

        var block: CardBlockContent {
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

        var ocrOverlay: [String: String] {
            source == .ocr ? [blockID: content] : [:]
        }
    }

    struct Candidate: Codable, Equatable {
        let id: String
        let query: String
        let expectedNoteIDs: [String]
        let style: QueryStyle
        let queryLanguage: Language
        let expectedLanguage: Language
        let scope: Scope
        let longRegion: LongRegion?
        let note: String

        var evalCase: EvalCase {
            EvalCase(id: id, query: query, expectedNoteIDs: expectedNoteIDs,
                     source: .golden, addedAt: .distantPast,
                     queryLanguage: queryLanguage, expectedLanguage: expectedLanguage,
                     scope: scope, note: "[\(style.rawValue)] \(note)")
        }
    }

    struct NegativeQuery: Codable, Equatable {
        let id: String
        let query: String
        let reason: String

        var evalCase: EvalCase {
            EvalCase(id: id, query: query, expectation: .noRelevantResult,
                     source: .golden, addedAt: .distantPast, note: reason)
        }
    }

    struct Dataset: Codable, Equatable {
        let version: String
        let disclaimer: String
        let notes: [Note]
        let cases: [Candidate]
        let negativeQueries: [NegativeQuery]

        var evalCases: [EvalCase] { cases.map(\.evalCase) }
        var negativeEvalCases: [EvalCase] { negativeQueries.map(\.evalCase) }
        var allEvalCases: [EvalCase] { evalCases + negativeEvalCases }

        var chunks: [NoteChunk] {
            notes.flatMap { note in
                ChunkPipeline.chunks(noteID: note.id,
                                     blocks: [note.block],
                                     strategy: .default,
                                     ocrTextByBlockID: note.ocrOverlay)
            }
        }
    }

    static func load() throws -> Dataset {
        guard let url = Bundle.module.url(forResource: "HumanLikeGoldenSet",
                                          withExtension: "json",
                                          subdirectory: "Fixtures") else {
            throw FixtureError.resourceMissing
        }
        return try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: url))
    }

    enum FixtureError: Error {
        case resourceMissing
    }
}
