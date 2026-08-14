import Foundation

/// 词法检索：在已切好的 chunk 上做子串定位 + 打分 + 排名。
///
/// ## 打分公式
///
/// ```
/// score = Σ_token  min(tf, 3) / sqrt(chunkLength)  ×  sourceWeight
/// ```
///
/// 三个部分各自有理由：
///
/// - **`min(tf, 3)`** —— 词频截断。同一个词出现 20 次的 chunk 不比出现 3 次的更相关，
///   通常只是列表或模板。不截断的话，一份重复词很多的文档会霸占整个结果页。
/// - **`/ sqrt(len)`** —— 长度归一。不归一的话长 chunk 天然占优（词更多），
///   短而精准的一句会被埋掉。开平方而不是直接除以长度，是为了不过度惩罚长文本。
/// - **`sourceWeight`** —— 出处权重。见下。
///
/// 刻意**不做 BM25**：BM25 的 IDF 需要一个稳定的语料统计，而个人笔记库既小又一直在
/// 变，IDF 会随每次编辑抖动，使评测结果不可复现。等 Golden Set 跑起来、真的证明
/// 排序不够用了，再引入才有依据。
public enum KeywordRetriever {

    /// 出处权重。
    ///
    /// 差距刻意压得很小（1.0 ~ 0.85），因为**没有数据支持更大的差距**。
    /// 这些值是 Week 4 Eval 的第一批调参对象，不是产品结论。
    public static func weight(for source: RetrievalSource) -> Double {
        switch source {
        case .text:       return 1.00   // 用户亲手写的，意图最明确
        case .transcript: return 0.95   // 口语，噪声略多
        case .extracted:  return 0.90   // 文档正文，常含页眉页脚等无关文本
        case .link:       return 0.90   // 标题+描述，通常很短
        case .ocr:        return 0.85   // 识别可能有错字
        }
    }

    /// 在一组 chunk 上执行关键词检索。
    ///
    /// - Returns: 按分数降序、同分按 chunkID 升序（保证可复现）。
    public static func retrieve(query: String,
                                chunks: [NoteChunk],
                                topK: Int) -> [KeywordHit] {
        let tokens = SearchMatcher.tokens(from: query)
        guard !tokens.isEmpty, topK > 0 else { return [] }

        var hits: [KeywordHit] = []
        for chunk in chunks {
            guard let (ranges, counts) = TextMatcher.locate(tokens: tokens, in: chunk.text) else { continue }
            let length = max(1, chunk.text.count)
            let norm = Double(length).squareRoot()
            var score = 0.0
            for c in counts { score += Double(min(c, 3)) / norm }
            score *= weight(for: chunk.source)

            hits.append(KeywordHit(chunkID: chunk.id, ref: chunk.ref, source: chunk.source,
                                   text: chunk.text, ranges: ranges, score: score))
        }

        hits.sort { $0.score == $1.score ? $0.chunkID < $1.chunkID : $0.score > $1.score }
        return Array(hits.prefix(topK))
    }
}
