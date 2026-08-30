import Foundation
import MosaicKit

/// Week 5 · TD-7 —— 生产搜索的呈现层：chunk 级结果 → 一行一笔记。
///
/// 这里守的是 `design/SEARCH_CONTRACT.md` §2.5 / §2.6 / §2.8 / §3.1 与 §4.1 的
/// capability 投影。全是纯函数，所以每条契约对应一条断言。
enum SearchPresentationChecks {

    typealias F = RetrievalFoundationChecks

    /// 三篇笔记：延期（两个 block）· 面馆 · 录音转写。
    static func corpus() -> [NoteChunk] {
        let notes: [(id: String, blocks: [CardBlockContent])] = [
            ("delay", [F.textBlock("B1", "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认。", order: 0),
                       F.textBlock("B2", "延期申请要在学期开始前四周交给学院。", order: 1)]),
            ("noodle", [F.textBlock("B3", "楼下那家面馆的辣椒油很香。", order: 0)]),
            ("audio", [F.audioBlock("B4", transcript: "周会上说延期的事下周开会再定。", order: 0)])
        ]
        return notes.flatMap { note in
            ChunkPipeline.chunks(noteID: note.id, blocks: note.blocks, strategy: .block)
        }
    }

    static func makeOutcome(query: String) async -> RetrievalOutcome {
        let provider = MockEmbeddingProvider(dimension: 32)
        let store = InMemoryVectorStore()
        let chunks = corpus()
        for c in chunks {
            let v = try! await provider.embed(c.text)
            await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, chunkIndex: c.indexInBlock,
                                               contentHash: c.contentHash,
                                               embeddingVersion: provider.modelInfo.version,
                                               dimension: 32, vector: v))
        }
        let service = RetrievalService(provider: provider, vectors: store)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: provider.modelInfo.version,
                                     chunkStrategy: .block, topK: 20)
        return await service.retrieve(query: query, chunks: chunks, config: config)
    }

    // MARK: 1 · 一行一笔记

    static func checkRows(_ r: CheckRunner) async {
        r.suite("TD-7 · 搜索结果行 —— 一笔记一行，excerpt 解释相关性")

        let outcome = await makeOutcome(query: "延期")
        let rows = SearchPresentation.rows(from: outcome)

        r.expect(!rows.isEmpty, "有结果")
        r.expect(Set(rows.map(\.noteID)).count == rows.count,
                 "每篇笔记只出现一行 —— 同一篇的两个 chunk 都命中时不能刷屏")
        r.expect(rows.map(\.rank) == Array(1...rows.count), "rank 从 1 连续")

        // §2.5：选中的是该笔记融合得分最高的 chunk。
        if let delay = rows.first(where: { $0.noteID == "delay" }) {
            let best = outcome.results.filter { $0.ref.noteID == "delay" }.min { $0.fusedRank < $1.fusedRank }
            r.expect(delay.anchor.blockID == best?.ref.blockID,
                     "选的是得分最高的那个 chunk（\(best?.ref.blockID ?? "-")）")
            r.expect(!delay.excerpt.text.isEmpty, "excerpt 非空")
            r.expect(delay.hasKeywordHit, "字面命中的行带高亮")
            let chars = Array(delay.excerpt.text)
            r.expect(delay.excerpt.highlights.allSatisfy { $0.end <= chars.count },
                     "高亮区间落在 excerpt 坐标系内 —— 重映射正确")
        } else {
            r.expect(false, "延期那篇应当在结果里")
        }

        // §3.1：anchor 由检索层给出。转写命中要能被区分出来，否则进笔记后不知道要展开。
        if let audio = rows.first(where: { $0.noteID == "audio" }) {
            r.expect(audio.source == .transcript, "来源是转写")
            if case .transcript = audio.anchor {} else { r.expect(false, "转写命中的 anchor 是 .transcript") }
        }

        // Q12：Top 50，不分页。
        let capped = SearchPresentation.rows(from: outcome, limit: 1)
        r.expect(capped.count == 1, "结果上限生效")
    }

    // MARK: 2 · §2.6 顶部说明行

    static func checkSemanticOnlyNotice(_ r: CheckRunner) async {
        r.suite("TD-7 · 整页零高亮时的一行说明（§2.6）")

        let keyword = SearchPresentation.rows(from: await makeOutcome(query: "延期"))
        r.expect(keyword.contains { $0.hasKeywordHit }, "字面 query 有高亮")
        r.expect(!SearchPresentation.needsSemanticOnlyNotice(keyword),
                 "有高亮就不显示说明行 —— 混合是正常状态，不需要解释")

        // §2.6 那一屏的**触发条件没变**（整页零字面命中 → 显示说明行），
        // 变的是什么 query 会落进去。
        //
        // 原来举的例子是「中文自然语言长句」，因为那时 keyword 路对中文长句
        // 一律零命中 —— 而那是 `SearchMatcher.tokens` 只按空白切分的缺陷
        // （见 `QuerySegmentation`），不是产品设计。修好之后中文长句会有高亮。
        //
        // 真正会落进这一屏的是**跨语言**：英文 query 查中文语料，词法路确实
        // 一个词都对不上，只能靠语义路。这才是 24 屏该展示的状态。
        let crossLanguage = SearchPresentation.rows(from: await makeOutcome(query: "graduation deadline"))
        if !crossLanguage.isEmpty {
            r.expect(crossLanguage.allSatisfy { !$0.hasKeywordHit }, "跨语言 query 整页无高亮")
            r.expect(SearchPresentation.needsSemanticOnlyNotice(crossLanguage), "此时显示顶部说明行")
        }

        // 中文自然语言长句**现在**有高亮，因此不该再显示那一行说明。
        let natural = SearchPresentation.rows(from: await makeOutcome(query: "我之前问学校能不能晚一点毕业的事情"))
        if !natural.isEmpty {
            r.expect(natural.contains { $0.hasKeywordHit },
                     "中文自然语言 query 现在有字面命中（CJK 二元组切分）")
            r.expect(!SearchPresentation.needsSemanticOnlyNotice(natural),
                     "有高亮就不再显示说明行")
        }

        r.expect(!SearchPresentation.needsSemanticOnlyNotice([]), "零结果不显示说明行（那是空态的事）")

        // 标题 / 标签命中**是字面命中**，即使 excerpt 里没有可高亮的片段
        // （标题不进语料，excerpt 显示的是正文开头）。
        //
        // 不区分的话，「搜标题里的词」会让整页判成零字面命中，顶部出现一行
        // 「没有完全匹配的关键词」，而用户明明看到标题一模一样。
        // 这是在模拟器上搜一个标签时看到的。
        let titleOnly = SearchPresentation.appendingLexicalMatches(
            [], lexical: [(noteID: "n1", preview: "今天讨论了下个版本的排期与分工")])
        r.expectEqual(titleOnly.count, 1, "标题命中产出一行")
        r.expect(titleOnly[0].excerpt.highlights.isEmpty, "它没有可高亮的片段")
        r.expect(titleOnly[0].hasKeywordHit, "但它仍然算字面命中")
        r.expect(!SearchPresentation.needsSemanticOnlyNotice(titleOnly),
                 "所以整页不显示「没有完全匹配的关键词」")
    }

    // MARK: 3 · 标题 / 标签命中不能消失

    static func checkLexicalMatches(_ r: CheckRunner) async {
        r.suite("TD-7 · 标题与标签是 lexical signal —— 不进语料，但必须仍然搜得到")

        let rows = SearchPresentation.rows(from: await makeOutcome(query: "延期"))
        let merged = SearchPresentation.appendingLexicalMatches(
            rows, lexical: [(noteID: "title-only", preview: "这篇笔记的正文与 query 无关，但标题里有。")]
        )

        r.expect(merged.count == rows.count + 1, "只靠标题命中的笔记被补进结果")
        let appended = merged.last!
        r.expect(appended.noteID == "title-only", "补进来的正是那篇笔记")
        r.expect(appended.anchor == .top, "标题命中落点是笔记顶部，不滚动、不高亮（§3.2）")
        // 原来这一条写的是 `!appended.hasKeywordHit`，把两件事混在了一起：
        //
        //   「excerpt 里没有可高亮的片段」  ← §2.4，标题不进语料，正确
        //   「这一页没有字面命中」          ← §2.6 的输入，**错误**
        //
        // 混用的后果在模拟器上看到了：搜一个标签，结果行标题一模一样，
        // 顶部却写着「没有完全匹配的关键词」。现在两件事分开断言。
        r.expect(appended.excerpt.highlights.isEmpty, "标题命中的 excerpt 不做高亮（§2.4 标题不高亮）")
        r.expect(appended.hasKeywordHit, "但它仍然算字面命中 —— 用户搜的词就印在标题上")
        r.expect(appended.matchedTitleOrTag, "来源标记为标题 / 标签")
        r.expect(appended.excerpt.fallbackLevel == 2, "excerpt 走 fallback 第 2 级：笔记开头")
        r.expect(merged.map(\.rank) == Array(1...merged.count), "rank 仍然连续")

        // 已经因为内容命中出现过的笔记，不能因为标题也命中而出现第二行。
        let deduped = SearchPresentation.appendingLexicalMatches(
            rows, lexical: [(noteID: rows[0].noteID, preview: "任意")]
        )
        r.expect(deduped.count == rows.count, "已在榜上的笔记不重复追加")
    }

    // MARK: 4 · 慢通道门控（§1.2）

    static func checkSemanticGate(_ r: CheckRunner) {
        r.suite("TD-7 · 慢通道门控 —— 极短 query 不触发语义")

        r.expect(!SemanticGate.shouldRunSemantic(query: ""), "空 query 不触发")
        r.expect(!SemanticGate.shouldRunSemantic(query: "   "), "纯空白不触发")
        r.expect(!SemanticGate.shouldRunSemantic(query: "延"), "单个汉字不触发（CJK ≥2）")
        r.expect(SemanticGate.shouldRunSemantic(query: "延期"), "两个汉字触发")
        r.expect(!SemanticGate.shouldRunSemantic(query: "ab"), "两个拉丁字符不触发（拉丁 ≥3）")
        r.expect(SemanticGate.shouldRunSemantic(query: "abc"), "三个拉丁字符触发")
        r.expect(SemanticGate.shouldRunSemantic(query: "延 期"), "空白不计入长度")

        // 混合 query 按主语言判定：取更宽松的那套阈值会让「a 延」这种噪声也触发。
        r.expect(!SemanticGate.shouldRunSemantic(query: "a延"), "混合但过短仍不触发")
        r.expect(SemanticGate.shouldRunSemantic(query: "advisor 延期"), "有实义的混合 query 触发")
    }

    static func run(_ r: CheckRunner) async {
        checkSemanticGate(r)
        await checkRows(r)
        await checkSemanticOnlyNotice(r)
        await checkLexicalMatches(r)
    }
}
