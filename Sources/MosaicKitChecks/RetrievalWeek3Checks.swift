import Foundation
import MosaicKit

/// Week 3 —— Keyword / Vector / Hybrid 三路检索 · RRF · Excerpt 开窗。
enum RetrievalWeek3Checks {

    typealias F = RetrievalFoundationChecks
    static let version = "mock-v1"

    // 一小份中文语料，覆盖五类出处。
    static func corpus() -> [CardBlockContent] {
        [
            F.textBlock("B1", "我问了 advisor 能不能延期一个学期毕业，他说要先跟系里确认。", order: 0),
            F.audioBlock("B2", transcript: "周会上说延期的事下周开会再定，毕业时间还有缓冲。", order: 1),
            F.fileBlock("B3", extracted: "学生如需延期毕业，应在学期开始前四周向学院提交书面申请。", order: 2),
            CardBlockContent(id: "B4", order: 3, kind: .link,
                             url: "https://neu.test/extended",
                             linkTitle: "Extended Study Option",
                             linkDescription: "students who need additional time to complete degree requirements"),
            F.textBlock("B5", "今天把合同评审的三处修改整理好了，跟毕业无关。", order: 4)
        ]
    }

    static func chunks() -> [NoteChunk] {
        ChunkPipeline.chunks(noteID: "N1", blocks: corpus(), strategy: .block)
    }

    // MARK: 1 · IG-2 —— SearchMatcher 从 Bool 升级为带区间的结果

    static func checkSearchHit(_ r: CheckRunner) {
        r.suite("Week3 · IG-2 —— 命中带区间 / 归属 / 分数")

        // 既有语义必须原样保住：只有一个调用点，但它是线上搜索。
        let hay = "确定了排期与三位负责人，下周三上线"
        r.expect(SearchMatcher.matches(query: "排期", haystack: hay), "既有 matches() 行为不变")
        r.expect(!SearchMatcher.matches(query: "排期 不存在", haystack: hay), "AND 语义不变")

        // 新能力：定位。
        let located = TextMatcher.locate(tokens: ["延期"], in: "我问了能不能延期一个学期毕业，延期要走流程")
        r.expect(located != nil, "命中返回区间")
        r.expect(located?.ranges.count == 2, "找出全部出现位置（\(located?.ranges.count ?? -1) 处）")
        r.expect(located?.counts == [2], "词频正确")
        let first = located!.ranges[0]
        r.expect(first.start == 6 && first.end == 8, "区间按字符计（中文不按字节）")

        // 缺一个 token 就整体不命中。
        r.expect(TextMatcher.locate(tokens: ["延期", "不存在"], in: "延期毕业") == nil, "AND：缺一个 token 整体不命中")

        // 大小写 / 全角半角归一，且不改变字符数（否则偏移会错位）。
        let ci = TextMatcher.locate(tokens: ["mosaic"], in: "项目 MOSAIC 启动")
        r.expect(ci?.ranges.first?.start == 3, "大小写不敏感且偏移正确")
        r.expect(TextMatcher.normalizedForOffsets("ＡＢ").count == "ＡＢ".count, "归一化保持字符数不变")

        // 区间合并。
        let merged = TextMatcher.merge([TextRange(start: 0, end: 3), TextRange(start: 2, end: 5),
                                        TextRange(start: 9, end: 11)])
        r.expect(merged.count == 2 && merged[0].end == 5, "重叠区间被合并")

        // 空 query 不返回结果（UI 显示引导页而不是零结果页）。
        r.expect(KeywordRetriever.retrieve(query: "   ", chunks: chunks(), topK: 10).isEmpty,
                 "空 query 返回空")
    }

    // MARK: 2 · Keyword 检索

    static func checkKeyword(_ r: CheckRunner) {
        r.suite("Week3 · Keyword —— 打分与排名")

        let cs = chunks()
        let hits = KeywordRetriever.retrieve(query: "延期 毕业", chunks: cs, topK: 10)
        r.expect(hits.count == 3, "三条同时含「延期」「毕业」（得到 \(hits.count) 条）")
        r.expect(!hits.contains { $0.chunkID.hasSuffix("B4/0") }, "英文链接块不含中文词，未命中")
        // B5 含「毕业」但不含「延期」—— AND 语义在真实语料上的体现。
        r.expect(!hits.contains { $0.chunkID.hasSuffix("B5/0") }, "只含其中一个词的块不命中（AND）")
        r.expect(KeywordRetriever.retrieve(query: "毕业", chunks: cs, topK: 10).count == 4,
                 "单词「毕业」命中四条，包含 B5")

        r.expect(hits.map(\.score) == hits.map(\.score).sorted(by: >), "按分数降序")
        r.expect(hits.allSatisfy { !$0.ranges.isEmpty }, "每条都带命中区间")
        r.expect(hits.allSatisfy { $0.ref.noteID == "N1" }, "每条都带归属")

        // 长度归一：同样命中一次，短 chunk 分数更高。
        let shortC = ChunkPipeline.chunks(noteID: "N", block: F.textBlock("S", "延期"), strategy: .block)
        let longC = ChunkPipeline.chunks(noteID: "N", block: F.textBlock("L", "延期" + String(repeating: "啊", count: 200)), strategy: .block)
        let s = KeywordRetriever.retrieve(query: "延期", chunks: shortC, topK: 1).first!.score
        let l = KeywordRetriever.retrieve(query: "延期", chunks: longC, topK: 1).first!.score
        r.expect(s > l, "长度归一：短 chunk 得分更高")

        // 词频截断：重复 20 次不会碾压重复 3 次。
        let tf3 = ChunkPipeline.chunks(noteID: "N", block: F.textBlock("A", String(repeating: "延期", count: 3)), strategy: .block)
        let tf20 = ChunkPipeline.chunks(noteID: "N", block: F.textBlock("B", String(repeating: "延期", count: 20)), strategy: .block)
        let a = KeywordRetriever.retrieve(query: "延期", chunks: tf3, topK: 1).first!.score
        let b = KeywordRetriever.retrieve(query: "延期", chunks: tf20, topK: 1).first!.score
        r.expect(b < a, "词频截断 + 长度归一：堆词不会换来更高排名")

        // 出处权重存在但差距很小。
        r.expect(KeywordRetriever.weight(for: .text) > KeywordRetriever.weight(for: .ocr), "正文权重高于 OCR")
        r.expect(KeywordRetriever.weight(for: .text) - KeywordRetriever.weight(for: .ocr) < 0.2,
                 "权重差距刻意保持很小 —— 目前没有数据支持更大的差距")

        // 自然语言长句 keyword 零命中 —— 这是 24 屏的前提，不是缺陷。
        let nl = KeywordRetriever.retrieve(query: "我之前问学校能不能晚一点毕业的事情", chunks: cs, topK: 10)
        r.expect(nl.isEmpty, "整句自然语言 query 在 keyword 路零命中（交给语义路）")

        // topK 截断 + 可复现。
        r.expect(KeywordRetriever.retrieve(query: "延期", chunks: cs, topK: 2).count == 2, "topK 截断")
        r.expect(KeywordRetriever.retrieve(query: "延期", chunks: cs, topK: 10) ==
                 KeywordRetriever.retrieve(query: "延期", chunks: cs, topK: 10), "结果可复现")
    }

    // MARK: 3 · RRF 融合

    static func checkRRF(_ r: CheckRunner) {
        r.suite("Week3 · RRF —— 融合与单路缺失")

        let kw = ["A", "B", "C"]
        let vec = ["C", "D", "A"]
        let fused = RRFFusion.fuse(keywordOrder: kw, vectorOrder: vec, method: .rrf(k: 60))

        r.expect(fused.count == 4, "并集去重（A B C D）")
        r.expect(Set(fused.map(\.chunkID)) == Set(["A", "B", "C", "D"]), "两路结果都进入候选")

        let a = fused.first { $0.chunkID == "A" }!
        r.expect(a.keywordRank == 1 && a.vectorRank == 3, "A 的两路名次都被保留")
        let d = fused.first { $0.chunkID == "D" }!
        r.expect(d.keywordRank == nil && d.vectorRank == 2, "D 只被 vector 命中")
        r.expect(d.isUniqueHit, "单路命中被标记")
        r.expect(!a.isUniqueHit, "两路命中不算 unique")

        // 两路都命中的应当排在只被一路命中的前面 —— RRF 的核心行为。
        r.expect(fused.first?.chunkID == "A" || fused.first?.chunkID == "C",
                 "两路都投票的排在最前（第一名是 \(fused.first?.chunkID ?? "?")）")
        let rankOf = { (id: String) in fused.firstIndex { $0.chunkID == id }! }
        r.expect(rankOf("A") < rankOf("B"), "两路命中的 A 高于单路命中的 B")

        // 单路缺失 = 不贡献分数，而不是罚分 —— 否则纯语义结果永远进不了榜。
        let onlyVector = RRFFusion.fuse(keywordOrder: [], vectorOrder: ["X", "Y"], method: .rrf(k: 60))
        r.expect(onlyVector.count == 2 && onlyVector[0].chunkID == "X",
                 "keyword 完全无命中时，纯语义结果仍然成榜（24 屏的前提）")
        r.expect(RRFFusion.fuse(keywordOrder: ["X"], vectorOrder: [], method: .rrf(k: 60)).count == 1,
                 "vector 不可用时，纯 keyword 结果照常成榜")
        r.expect(RRFFusion.fuse(keywordOrder: [], vectorOrder: [], method: .rrf(k: 60)).isEmpty, "两路都空 → 空")

        // k 越大，头部差距越平缓。
        let k1 = RRFFusion.fuse(keywordOrder: kw, vectorOrder: vec, method: .rrf(k: 1))
        let k600 = RRFFusion.fuse(keywordOrder: kw, vectorOrder: vec, method: .rrf(k: 600))
        let spread = { (f: [FusedRanking]) in (f.first!.fusedScore - f.last!.fusedScore) / f.first!.fusedScore }
        r.expect(spread(k600) < spread(k1), "k 越大，分数越平缓（k 是 tuning value）")

        // 同分按 chunkID 升序，保证评测可复现。
        let tie = RRFFusion.fuse(keywordOrder: ["Z", "A"], vectorOrder: ["A", "Z"], method: .rrf(k: 60))
        r.expect(tie.map(\.chunkID) == ["A", "Z"], "同分按 chunkID 升序 —— 评测必须可复现")
    }

    // MARK: 4 · RetrievalService 三路统一入口

    static func checkService(_ r: CheckRunner) async {
        r.suite("Week3 · RetrievalService —— 三路排名同时返回")

        let provider = MockEmbeddingProvider(dimension: 32)
        let store = InMemoryVectorStore()
        let recorder = RetrievalTraceRecorder()
        let cs = chunks()
        for c in cs {
            let v = try! await provider.embed(c.text)
            await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, chunkIndex: c.indexInBlock,
                                               contentHash: c.contentHash, embeddingVersion: version,
                                               dimension: 32, vector: v))
        }
        let service = RetrievalService(provider: provider, vectors: store, recorder: recorder)

        // ── Hybrid ──
        var config = RetrievalConfig(mode: .hybrid, embeddingVersion: version, chunkStrategy: .block, topK: 5)
        let hybrid = await service.retrieve(query: "延期 毕业", chunks: cs, config: config)
        r.expect(!hybrid.results.isEmpty, "hybrid 有结果")
        r.expect(hybrid.results.map(\.fusedRank) == Array(1...hybrid.results.count), "fusedRank 从 1 连续")
        r.expect(hybrid.results.contains { $0.keywordRank != nil && $0.vectorRank != nil },
                 "存在两路都命中的结果")

        // 三路证据齐全 —— D-UI-DEV-007 对检索层的硬要求。
        let evidence = hybrid.results[0].rankEvidence
        r.expect(evidence.contains("K") && evidence.contains("V") && evidence.contains("→"),
                 "排名证据格式为 K #x · V #y → #z（得到 \(evidence)）")
        r.expect(hybrid.results.allSatisfy { $0.keywordRank != nil || $0.vectorRank != nil },
                 "每条结果至少来自一路")

        // ── Keyword only ──
        config.mode = .keyword
        let kw = await service.retrieve(query: "延期 毕业", chunks: cs, config: config)
        r.expect(kw.results.allSatisfy { $0.vectorRank == nil }, "keyword 模式不产生 vector 名次")
        r.expect(kw.results.allSatisfy { !$0.matchedRanges.isEmpty }, "keyword 结果都带高亮区间")

        // ── Vector only ──
        config.mode = .vector
        let vec = await service.retrieve(query: "延期 毕业", chunks: cs, config: config)
        r.expect(vec.results.allSatisfy { $0.keywordRank == nil }, "vector 模式不产生 keyword 名次")
        r.expect(vec.results.allSatisfy { $0.similarity != nil }, "vector 结果都带相似度")

        // ── Compare 分组 ──
        config.mode = .hybrid
        let cmp = await service.retrieve(query: "延期", chunks: cs, config: config)
        r.expect(cmp.keywordOnly.allSatisfy(\.isKeywordOnly), "keywordOnly 分组正确")
        r.expect(cmp.vectorOnly.allSatisfy(\.isVectorOnly), "vectorOnly 分组正确")
        r.expect(cmp.bothCount + cmp.keywordOnly.count + cmp.vectorOnly.count == cmp.results.count,
                 "三组之和等于结果总数")

        // ── 自然语言 query：keyword 零命中，vector 兜底 ──
        let nl = await service.retrieve(query: "我之前问学校能不能晚一点毕业的事情", chunks: cs, config: config)
        r.expect(!nl.results.isEmpty, "自然语言 query 仍有结果（语义路兜底）")
        r.expect(nl.results.allSatisfy { $0.keywordRank == nil }, "自然语言 query 全是纯语义命中")
        r.expect(nl.results.allSatisfy { $0.matchedRanges.isEmpty },
                 "纯语义命中没有高亮区间 —— 24 屏「整页零高亮」的来源")

        // ── Progressive Enhancement：索引不可用时自动降级 ──
        let degraded = await service.retrieve(query: "延期 毕业", chunks: cs, config: config,
                                              indexState: .failed(reason: "provider offline"))
        r.expect(!degraded.results.isEmpty, "语义不可用时仍然有结果")
        r.expect(degraded.results.allSatisfy { $0.vectorRank == nil }, "自动降级为纯 keyword")
        r.expect(degraded.trace.isStale, "trace 标记本次结果未用到语义路")

        let building = await service.retrieve(query: "延期 毕业", chunks: cs, config: config,
                                              indexState: .building(progress: 0.3))
        r.expect(!building.results.isEmpty, "索引建立中，keyword 照常工作")

        // ── 本机根本没有句向量模型：provider = nil，**不退回 mock** ──
        // 与 IndexState 降级走同一个出口，不是第二套逻辑。
        let noProvider = RetrievalService(provider: nil, vectors: store)
        let withoutModel = await noProvider.retrieve(query: "延期 毕业", chunks: cs, config: config)
        r.expect(!withoutModel.results.isEmpty, "没有句向量模型时 keyword 路照常工作")
        r.expect(withoutModel.results.allSatisfy { $0.vectorRank == nil }, "vector 路整条跳过")
        r.expect(withoutModel.trace.vectorCandidates == 0, "trace 如实记录 vector 路零候选")

        // ── 空 query ──
        let empty = await service.retrieve(query: "   ", chunks: cs, config: config)
        r.expect(empty.results.isEmpty, "空 query 返回空结果")

        // ── chunk 已删但索引未清：跳过而不是崩溃 ──
        let stale = await service.retrieve(query: "延期 毕业", chunks: Array(cs.prefix(1)), config: config)
        r.expect(stale.results.allSatisfy { $0.chunkID == cs[0].id },
                 "索引里有但语料里没有的 chunk 被安全跳过")
    }

    // MARK: 5 · Trace 接入真实管线

    static func checkTraceWiring(_ r: CheckRunner) async {
        r.suite("Week3 · Trace —— 接入真实管线")

        let provider = MockEmbeddingProvider(dimension: 16)
        let store = InMemoryVectorStore()
        let recorder = RetrievalTraceRecorder()
        let cs = chunks()
        for c in cs {
            let v = try! await provider.embed(c.text)
            await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, contentHash: c.contentHash,
                                               embeddingVersion: version, dimension: 16, vector: v))
        }
        let service = RetrievalService(provider: provider, vectors: store, recorder: recorder)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: version, chunkStrategy: .block, topK: 5)

        let outcome = await service.retrieve(query: "延期 毕业", chunks: cs, config: config)
        let t = outcome.trace

        r.expect(t.query == "延期 毕业", "trace 记录 query")
        r.expect(t.configVersion == config.version, "记录 config 版本")
        r.expect(t.embeddingVersion == version, "记录 embedding 版本")

        // 七段耗时都被真实测量（可能极小，但必须 ≥ 0 且总时长覆盖各段）。
        r.expect(t.totalMs > 0, "总耗时被测量")
        r.expect(t.queryEmbeddingMs > 0, "query embedding 段被测量")
        r.expect(t.keywordRetrievalMs >= 0 && t.vectorRetrievalMs >= 0, "两路检索耗时被测量")
        let parts = t.queryProcessingMs + t.queryEmbeddingMs + t.keywordRetrievalMs
                  + t.vectorRetrievalMs + t.fusionMs + t.rankingMs
        r.expect(parts <= t.totalMs + 1.0, "各段之和不超过总时长（\(String(format: "%.2f", parts)) vs \(String(format: "%.2f", t.totalMs))）")

        // 四项 index metadata。
        r.expect(t.chunkCount == cs.count, "chunkCount 真实")
        r.expect(t.candidateCount >= t.resultCount, "候选数不小于结果数")
        r.expect(t.resultCount == outcome.results.count, "resultCount 与实际结果一致")
        r.expect(!t.contentHash.isEmpty, "contentHash 已记录")
        r.expect(t.keywordCandidates > 0 && t.vectorCandidates > 0, "两路候选数分别记录")

        // 「候选很多但结果很少」是 Trace 要回答的典型问题。
        r.expect(t.candidateCount > 0, "候选集非空 —— 候选为 0 说明问题在检索层而非排序层")

        // recorder 收到了记录。
        let recorded = await recorder.count()
        r.expect(recorded >= 1, "recorder 收到 trace")
        let latest = await recorder.latest()
        r.expect(latest?.query == "延期 毕业", "最近一条可读")
    }

    // MARK: 6 · ExcerptBuilder —— W1–W7 逐条

    static func checkExcerpt(_ r: CheckRunner) {
        r.suite("Week3 · ExcerptBuilder —— W1–W7 逐条验证")

        let long = "开头的一些背景交代。我问了 advisor 能不能延期一个学期毕业，他说要先跟系里的 graduate advisor 确认，让我别急着提交材料。后面还有很多无关的内容。"
        let hit = TextMatcher.locate(tokens: ["延期"], in: long)!
        let e = ExcerptBuilder.build(text: long, ranges: hit.ranges, budget: 44)

        // W1：窗口包含第一个命中。
        r.expect(e.text.contains("延期"), "W1：窗口包含命中词")
        // W2：命中不在最开头（左侧留了上下文），也不在最末尾。
        let hitPos = Array(e.text).firstIndex(of: "延") ?? 0
        r.expect(hitPos > 0, "W2：命中左侧保留了上下文")
        r.expect(hitPos < e.text.count / 2 + 4, "W2：右侧留的比左侧多（向后读更重要）")
        // W5：两端省略号。
        r.expect(e.text.hasPrefix("…"), "W5：非从头开始 → 前置省略号")
        r.expect(e.text.hasSuffix("…"), "W5：未到结尾 → 后置省略号")
        // 预算。
        r.expect(e.text.count <= 44 + 2, "长度不超过预算 + 两个省略号")
        // 高亮重映射到 excerpt 坐标。
        r.expect(!e.highlights.isEmpty, "高亮区间存在")
        let h = e.highlights[0]
        let sub = String(Array(e.text)[h.start..<h.end])
        r.expect(sub == "延期", "高亮区间已重映射到 excerpt 坐标（取到「\(sub)」）")

        // W6：全文短于预算 → 原样返回，无省略号。
        let short = ExcerptBuilder.build(text: "很短的一句话", ranges: [], budget: 44)
        r.expect(short.text == "很短的一句话", "W6：短文本原样返回")
        r.expect(!short.text.contains("…"), "W6：不加省略号")

        // W7：折叠空白与换行。
        let messy = ExcerptBuilder.build(text: "第一行\n\n\n第二行   有很多   空格", ranges: [], budget: 44)
        r.expect(!messy.text.contains("\n"), "W7：换行被折叠")
        r.expect(!messy.text.contains("   "), "W7：连续空格被折叠")

        // W7 + 偏移：折叠后高亮仍然对准。
        let w7 = "前面\n\n延期\n\n后面"
        let w7hits = TextMatcher.locate(tokens: ["延期"], in: w7)!
        let w7e = ExcerptBuilder.build(text: w7, ranges: w7hits.ranges, budget: 44)
        let w7h = w7e.highlights[0]
        r.expect(String(Array(w7e.text)[w7h.start..<w7h.end]) == "延期",
                 "W7：折叠空白后高亮偏移仍然正确")

        // W4：高亮词绝不被截断 —— 每个高亮区间都完整落在文本内且内容正确。
        let dense = String(repeating: "无关内容", count: 20) + "延期毕业" + String(repeating: "无关内容", count: 20)
        let denseHits = TextMatcher.locate(tokens: ["延期毕业"], in: dense)!
        let denseE = ExcerptBuilder.build(text: dense, ranges: denseHits.ranges, budget: 30)
        for hl in denseE.highlights {
            let chars = Array(denseE.text)
            r.expect(hl.start >= 0 && hl.end <= chars.count, "W4：高亮区间在文本范围内")
            r.expect(String(chars[hl.start..<hl.end]) == "延期毕业", "W4：高亮词未被截断")
        }

        // 纯语义命中：无区间 → 从开头开窗，无高亮。
        let semantic = ExcerptBuilder.build(text: long, ranges: [], budget: 44)
        r.expect(semantic.highlights.isEmpty, "纯语义命中无高亮")
        r.expect(!semantic.text.hasPrefix("…"), "无命中时从开头开窗")

        // §2.4：最多 6 段高亮。
        let many = String(repeating: "延期 ", count: 20)
        let manyHits = TextMatcher.locate(tokens: ["延期"], in: many)!
        let manyE = ExcerptBuilder.build(text: many, ranges: manyHits.ranges, budget: 200)
        r.expect(manyE.highlights.count <= ExcerptBuilder.maxHighlights,
                 "高亮段数上限 6（得到 \(manyE.highlights.count)）")

        // §2.7 fallback 链：逐级降级，不跳级。
        let l1 = ExcerptBuilder.buildWithFallback(matchedText: "命中文本", ranges: [],
                                                  firstBlockText: "首块", oneLiner: "一句话")
        r.expect(l1.fallbackLevel == 1 && l1.text == "命中文本", "fallback 1：命中窗口")
        let l2 = ExcerptBuilder.buildWithFallback(matchedText: nil, ranges: [],
                                                  firstBlockText: "首块内容", oneLiner: "一句话")
        r.expect(l2.fallbackLevel == 2 && l2.text == "首块内容", "fallback 2：首个文字块")
        let l3 = ExcerptBuilder.buildWithFallback(matchedText: "  ", ranges: [],
                                                  firstBlockText: nil, oneLiner: "AI 一句话")
        r.expect(l3.fallbackLevel == 3 && l3.text == "AI 一句话", "fallback 3：one_liner")
        let l4 = ExcerptBuilder.buildWithFallback(matchedText: nil, ranges: [],
                                                  firstBlockText: nil, oneLiner: nil)
        r.expect(l4.fallbackLevel == 4 && l4.text == "无预览内容", "fallback 4：占位文案")
        r.expect(l2.highlights.isEmpty && l3.highlights.isEmpty, "降级后不产生高亮")

        // 边界：空文本、纯空白。
        r.expect(ExcerptBuilder.build(text: "", ranges: [], budget: 44).text.isEmpty, "空文本安全")
        r.expect(ExcerptBuilder.build(text: "    ", ranges: [], budget: 44).text.isEmpty, "纯空白折叠为空")
    }

    // MARK: 7 · 端到端：检索 → excerpt

    static func checkEndToEnd(_ r: CheckRunner) async {
        r.suite("Week3 · 端到端 —— 检索结果直接产出 Matched Excerpt")

        let provider = MockEmbeddingProvider(dimension: 32)
        let store = InMemoryVectorStore()
        let cs = ChunkPipeline.chunks(noteID: "N1", blocks: corpus(), strategy: .fixed(maxChars: 60, overlap: 10))
        for c in cs {
            let v = try! await provider.embed(c.text)
            await store.upsert(EmbeddingRecord(ref: c.ref, chunkID: c.id, chunkIndex: c.indexInBlock,
                                               contentHash: c.contentHash, embeddingVersion: version,
                                               dimension: 32, vector: v))
        }
        let service = RetrievalService(provider: provider, vectors: store)
        let config = RetrievalConfig(mode: .hybrid, embeddingVersion: version,
                                     chunkStrategy: .fixed(maxChars: 60, overlap: 10), topK: 5)

        let outcome = await service.retrieve(query: "延期 毕业", chunks: cs, config: config)
        r.expect(!outcome.results.isEmpty, "有结果")

        // 每条结果都能产出一个 excerpt，且 keyword 命中的带高亮。
        for result in outcome.results {
            let e = ExcerptBuilder.build(text: result.text, ranges: result.matchedRanges, budget: 44)
            r.expect(!e.text.isEmpty, "结果 #\(result.fusedRank) 产出非空 excerpt")
            if result.keywordRank != nil {
                r.expect(!e.highlights.isEmpty, "keyword 命中的结果带高亮")
                let chars = Array(e.text)
                for h in e.highlights {
                    r.expect(h.end <= chars.count, "高亮区间在 excerpt 范围内")
                }
            } else {
                r.expect(e.highlights.isEmpty, "纯语义命中无高亮")
            }
        }

        // 这一整条链路就是 06 屏那一行的来源。
        let top = outcome.results[0]
        let e = ExcerptBuilder.build(text: top.text, ranges: top.matchedRanges, budget: 44)
        print("\n    ── 06 屏一行结果的真实产出 ──")
        print("    #\(top.fusedRank)  \(top.ref.blockID) · \(top.source.rawValue)")
        print("    \(e.text)")
        print("    \(top.rankEvidence)" + (top.similarity.map { String(format: "   similarity %.3f", $0) } ?? ""))
        print("")
        r.expect(true, "端到端产出可读的结果行")
    }

    static func run(_ r: CheckRunner) async {
        checkSearchHit(r)
        checkKeyword(r)
        checkRRF(r)
        await checkService(r)
        await checkTraceWiring(r)
        checkExcerpt(r)
        await checkEndToEnd(r)
    }
}
