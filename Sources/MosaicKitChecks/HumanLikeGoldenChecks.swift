import Foundation
import MosaicKit

/// Synthetic human-like Golden Set v2：结构防回退 + 真实检索分组跑批。
///
/// 这不是实际用户 ground truth。自动检查只保护实验设计不再次把来源、语种和
/// 长度绑在一起；质量数字仍只能描述这套 synthetic fixture。
enum HumanLikeGoldenChecks {

    static func run(_ r: CheckRunner) async {
        r.suite("Human-like Golden Set v2 · 结构与实验设计")

        let dataset: HumanLikeGoldenFixture.Dataset
        do {
            dataset = try HumanLikeGoldenFixture.load()
        } catch {
            r.expect(false, "fixture 应当可加载：\(error)")
            return
        }

        r.expect(dataset.version == "synthetic-human-v3", "版本明确是 synthetic-human-v3")
        r.expect(dataset.disclaimer.lowercased().contains("not real-user"),
                 "数据自身携带免责声明，不能冒充真人标注")
        r.expect(dataset.notes.count == 150, "语料扩到 150 篇，Top-5 只覆盖 3.3% 的库")
        r.expect(dataset.cases.count == 114, "114 条正向 query")
        r.expect(dataset.negativeQueries.count == 20, "20 条无答案 query 已接入 Runner")

        let noteIDs = Set(dataset.notes.map(\.id))
        let positiveIDs = dataset.cases.map(\.id)
        let negativeIDs = dataset.negativeQueries.map(\.id)
        r.expect(noteIDs.count == dataset.notes.count, "note id 唯一")
        r.expect(Set(positiveIDs).count == positiveIDs.count, "positive case id 唯一")
        r.expect(Set(negativeIDs).count == negativeIDs.count, "negative case id 唯一")
        r.expect(Set(positiveIDs).isDisjoint(with: Set(negativeIDs)), "正负例 id 不冲突")
        r.expect(dataset.cases.allSatisfy { !$0.expectedNoteIDs.isEmpty }, "每条正例至少一个 expected")
        r.expect(dataset.cases.allSatisfy { Set($0.expectedNoteIDs).isSubset(of: noteIDs) },
                 "所有 expected 指向存在的 synthetic note")
        r.expect(dataset.negativeEvalCases.allSatisfy { $0.expectation == .noRelevantResult },
                 "负例全部以 noRelevantResult 表达，不再是假 dangling 正例")

        checkSourceLanguageBalance(dataset, r: r)
        checkCaseLabels(dataset, r: r)
        checkLongNotes(dataset, r: r)
        checkExactQueries(dataset, r: r)
        checkDistractors(dataset, r: r)

        let normalizedKeys = dataset.cases.map {
            $0.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                + "|" + $0.expectedNoteIDs.sorted().joined(separator: ",")
        }
        r.expect(Set(normalizedKeys).count == normalizedKeys.count,
                 "query + expected 组合不重复，分母不会被重复项虚高")
        let positiveQueries = Set(dataset.cases.map { $0.query.lowercased() })
        r.expect(dataset.negativeQueries.allSatisfy { !positiveQueries.contains($0.query.lowercased()) },
                 "负例没有与正向 query 重复")
        r.expect(dataset.negativeQueries.allSatisfy { !$0.reason.isEmpty }, "每条负例都说明为何应无结果")

        let chunks = dataset.chunks
        r.expect(chunks.count > dataset.notes.count, "长文让 fixed(240/40) 真正产出多 chunk")
        r.expect(Set(chunks.map(\.source)) == Set(RetrievalSource.allCases),
                 "真实 ChunkPipeline 跑出五种 source")

        await measure(dataset, r: r)
    }

    private static func checkSourceLanguageBalance(_ dataset: HumanLikeGoldenFixture.Dataset,
                                                   r: CheckRunner) {
        for source in RetrievalSource.allCases {
            let notes = dataset.notes.filter { $0.source == source }
            let zh = notes.filter { $0.language == .zh }.count
            let en = notes.filter { $0.language == .en }.count
            r.expect(notes.count == 30, "\(source.rawValue) 有 30 篇语料")
            r.expect(abs(zh - en) <= 1,
                     "\(source.rawValue) 中英数量差 ≤ 1（zh \(zh) / en \(en)）")
        }
    }

    private static func checkCaseLabels(_ dataset: HumanLikeGoldenFixture.Dataset,
                                        r: CheckRunner) {
        let notesByID = Dictionary(uniqueKeysWithValues: dataset.notes.map { ($0.id, $0) })
        for candidate in dataset.cases {
            let languages = Set(candidate.expectedNoteIDs.compactMap { notesByID[$0]?.language })
            let derivedExpected: HumanLikeGoldenFixture.Language = languages.count == 1
                ? languages.first!
                : .mixed
            let derivedScope: HumanLikeGoldenFixture.Scope = candidate.queryLanguage == derivedExpected
                ? .inScope
                : .crossLanguage
            r.expect(candidate.expectedLanguage == derivedExpected,
                     "\(candidate.id) expectedLanguage 与 expected note 一致")
            r.expect(candidate.scope == derivedScope,
                     "\(candidate.id) scope 可由 query / expected 语种稳定推导")
        }
        let inScope = dataset.cases.filter { $0.scope == .inScope }.count
        let cross = dataset.cases.filter { $0.scope == .crossLanguage }.count
        r.expect(inScope == 67 && cross == 47,
                 "分组固定为 67 in-scope / 47 cross-language（实际 \(inScope) / \(cross)）")

        let originalCross = Set(dataset.cases.prefix(42)
            .filter { $0.scope == .crossLanguage }.map(\.id))
        let reviewedCross: Set<String> = [
            "HG003", "HG010", "HG012", "HG014", "HG016", "HG017", "HG021",
            "HG026", "HG028", "HG030", "HG032", "HG034", "HG038", "HG042"
        ]
        r.expect(originalCross == reviewedCross, "评审确认的 14 条原始跨语言 case 未漂移")
    }

    private static func checkLongNotes(_ dataset: HumanLikeGoldenFixture.Dataset,
                                       r: CheckRunner) {
        let longNotes = dataset.notes.filter { $0.content.count > 600 }
        r.expect(longNotes.count >= 6, "至少 6 篇正文 > 600 字符（实际 \(longNotes.count)）")
        for source in RetrievalSource.allCases {
            r.expect(longNotes.contains { $0.source == source },
                     "\(source.rawValue) 至少有一篇长语料")
        }
        for note in longNotes {
            guard let middle = note.middleMarker,
                  let middleRange = note.content.range(of: middle),
                  let end = note.endMarker,
                  let endRange = note.content.range(of: end) else {
                r.expect(false, "\(note.id) 长文必须提供中段与末段锚点")
                continue
            }
            let count = Double(note.content.count)
            let middlePosition = Double(note.content.distance(from: note.content.startIndex,
                                                               to: middleRange.lowerBound)) / count
            let endPosition = Double(note.content.distance(from: note.content.startIndex,
                                                            to: endRange.lowerBound)) / count
            r.expect((0.40...0.60).contains(middlePosition),
                     "\(note.id) 中段答案在 40%–60%（\(percent(middlePosition))）")
            r.expect(endPosition >= 0.80,
                     "\(note.id) 末段答案在 80% 之后（\(percent(endPosition))）")

            let cases = dataset.cases.filter { $0.expectedNoteIDs == [note.id] }
            r.expect(cases.filter { $0.longRegion == .middle }.count == 1,
                     "\(note.id) 有一条中段 query")
            r.expect(cases.filter { $0.longRegion == .end }.count == 1,
                     "\(note.id) 有一条末段 query")
        }
    }

    private static func checkExactQueries(_ dataset: HumanLikeGoldenFixture.Dataset,
                                          r: CheckRunner) {
        let notesByID = Dictionary(uniqueKeysWithValues: dataset.notes.map { ($0.id, $0) })
        for candidate in dataset.cases where candidate.style == .exact {
            let expectedText = candidate.expectedNoteIDs.compactMap { notesByID[$0]?.content }
                .joined(separator: " ").lowercased()
            let tokens = candidate.query.lowercased().split(whereSeparator: { $0.isWhitespace })
            let missing = tokens.filter { !expectedText.contains($0) }
            r.expect(missing.isEmpty,
                     "\(candidate.id) exact 的每个空格分词都存在于 expected（缺 \(missing.joined(separator: ","))）")
        }
    }

    private static func checkDistractors(_ dataset: HumanLikeGoldenFixture.Dataset,
                                         r: CheckRunner) {
        let expected = Set(dataset.cases.flatMap(\.expectedNoteIDs))
        let distractors = dataset.notes.filter { $0.role == .distractor }
        r.expect(distractors.count >= 60, "至少 60 篇近似或规模干扰项（实际 \(distractors.count)）")
        r.expect(distractors.allSatisfy { !expected.contains($0.id) },
                 "干扰项从不被标成 expected")
        let requiredDistractors: Set<String> = ["T05", "T06", "T07", "D05", "I05", "A05", "A06", "A07"]
        r.expect(requiredDistractors.isSubset(of: Set(distractors.map(\.id))),
                 "覆盖三篇搬家、第二份租约、第二张停车牌和三篇产品会议干扰项")

        // v3 的核心：**近似干扰簇**。租约 vs 课程笔记不算干扰，
        // 四份条款各不相同的租约才算 —— 它逼着排序层真的去理解问的是哪一条。
        let ids = Set(dataset.notes.map(\.id))
        let leaseCluster: Set<String> = ["D01", "D20", "D21", "D22", "D23", "D24"]
        let graduationCluster: Set<String> = ["T20", "T21", "T22", "T23", "T24"]
        let deductibleCluster: Set<String> = ["D02", "D25", "D26", "T34"]
        r.expect(leaseCluster.isSubset(of: ids),
                 "租约簇：六份条款各不相同的租约（通知期 / 宠物 / 解约 / 车位 / 押金 / 过期）")
        r.expect(graduationCluster.isSubset(of: ids),
                 "毕业簇：五封同主题不同答案的学校邮件（学位授予 / OPT / 休学 / SEVIS / 典礼）")
        r.expect(deductibleCluster.isSubset(of: ids),
                 "自付额簇：车险 / 租客险 / 健康险 / 牙科，字面都写 deductible")

        // 误导性词法重合：真答案与高字面重合的干扰项分属不同笔记。
        let misleading: Set<String> = ["T31", "T32", "T33"]
        r.expect(misleading.isSubset(of: Set(distractors.map(\.id))),
                 "误导簇：手机 / 健身房「提前解约」与共享单车「押金」都是干扰项，不是答案")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    /// 真实 NLEmbedding 上分别跑 in-scope / cross-language / overall，并让负例
    /// 走同一个 Runner。只报告测量值，不给 synthetic 数据设置质量门槛。
    private static func measure(_ dataset: HumanLikeGoldenFixture.Dataset,
                                r: CheckRunner) async {
        r.suite("Human-like Golden Set v2 · 分组质量与负例实测")

        guard let provider = try? LocalEmbedding.make() else {
            r.expect(true, "本机没有句向量模型，跳过质量跑批；结构检查仍有效")
            return
        }

        let chunks = dataset.chunks
        let store = InMemoryVectorStore()
        for chunk in chunks {
            do {
                let vector = try await provider.embed(chunk.text)
                await store.upsert(EmbeddingRecord(ref: chunk.ref, chunkID: chunk.id,
                                                   chunkIndex: chunk.indexInBlock,
                                                   contentHash: chunk.contentHash,
                                                   embeddingVersion: provider.modelInfo.version,
                                                   chunkStrategy: chunk.strategy,
                                                   dimension: provider.modelInfo.dimension,
                                                   vector: vector))
            } catch {
                r.expect(false, "\(chunk.id) 应可嵌入：\(error)")
                return
            }
        }

        let overall = dataset.evalCases
        var rows: [(mode: String, group: String, metrics: EvalMetrics)] = []
        var negativeRows: [(mode: String, metrics: EvalMetrics)] = []

        for mode in [RetrievalMode.keyword, .vector, .hybrid] {
            let config = RetrievalConfig(version: "human-v2-\(mode.rawValue)", mode: mode,
                                         embeddingProvider: provider.modelInfo.identifier,
                                         embeddingVersion: provider.modelInfo.version,
                                         chunkStrategy: .default, topK: 10)
            let runner = EvalRunner(service: RetrievalService(provider: provider, vectors: store),
                                    chunksProvider: { chunks })
            do {
                let overallRun = try await runner.run(cases: overall, config: config)
                let negativeRun = try await runner.run(cases: dataset.negativeEvalCases, config: config)
                rows += [(mode.rawValue, "in-scope", overallRun.inScopeMetrics),
                         (mode.rawValue, "cross", overallRun.crossLanguageMetrics),
                         (mode.rawValue, "overall", overallRun.metrics)]
                negativeRows.append((mode.rawValue, negativeRun.metrics))
                r.expect(overallRun.inScopeMetrics.caseCount == 67
                         && overallRun.crossLanguageMetrics.caseCount == 47,
                         "\(mode.rawValue) 核心 Runner 正确拆出两个语言分组")
                r.expect(negativeRun.metrics.noResultCaseCount == 20,
                         "\(mode.rawValue) 完整跑完 20 条负例")
            } catch {
                r.expect(false, "\(mode.rawValue) 跑批失败：\(error)")
            }
        }

        print("\n    ── synthetic-human-v2 · 60 notes / 54 positive / 10 negative ──")
        print("    mode       group       R@1    R@3    R@5    MRR     P95")
        for row in rows {
            print(String(format: "    %-8s   %-9s   %.3f  %.3f  %.3f  %.3f  %6.2fms",
                         (row.mode as NSString).utf8String!, (row.group as NSString).utf8String!,
                         row.metrics.recallAt1, row.metrics.recallAt3, row.metrics.recallAt5,
                         row.metrics.mrr, row.metrics.p95Ms))
        }
        print("    negative   no-result accuracy   false-positive rate")
        for row in negativeRows {
            print(String(format: "    %-8s   %6.1f%%              %6.1f%%",
                         (row.mode as NSString).utf8String!,
                         row.metrics.noResultAccuracy * 100,
                         row.metrics.falsePositiveRate * 100))
        }
        print("    Gate 只读取 in-scope 正例；cross-language 与负例暂不进入 Gate。")
        print("    ⚠️ synthetic fixture，不是实际用户质量结论。\n")
    }
}
