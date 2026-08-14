import SwiftUI
import MosaicKit

/// # D4 —— Retrieval Trace
///
/// 三段固定顺序：**身份 → Pipeline → Index**。
///
/// 顺序不是随手排的：排查的第一步永远是「这是哪一次、哪套配置」，第二步才是
/// 「慢在哪一层」，第三步是「数据对不对」。
///
/// **禁止 waterfall chart**（`DECISION_LOG.md` D-UI-DEV-004）。七行
/// `LabeledContent` 已经能回答全部问题，火焰图只增加实现成本。
struct RetrievalTraceView: View {
    let trace: RetrievalTrace

    var body: some View {
        List {
            Section("QUERY") {
                LabeledContent("Query", value: trace.query)
                LabeledContent("Config Version", value: trace.configVersion)
                LabeledContent("Embedding Version", value: trace.embeddingVersion)
                LabeledContent("Index Version", value: trace.indexVersion)
            }

            Section("PIPELINE") {
                stage("Query Processing", trace.queryProcessingMs)
                stage("Query Embedding", trace.queryEmbeddingMs)
                stage("Keyword Retrieval", trace.keywordRetrievalMs)
                stage("Vector Retrieval", trace.vectorRetrievalMs)
                stage("Fusion", trace.fusionMs)
                stage("Ranking", trace.rankingMs)
                stage("Total", trace.totalMs, emphasised: true)
            }

            Section("INDEX") {
                LabeledContent("chunkCount", value: "\(trace.chunkCount)").monospacedDigit()
                LabeledContent("keywordCandidates", value: "\(trace.keywordCandidates)").monospacedDigit()
                LabeledContent("vectorCandidates", value: "\(trace.vectorCandidates)").monospacedDigit()
                LabeledContent("candidateCount", value: "\(trace.candidateCount)").monospacedDigit()
                LabeledContent("resultCount", value: "\(trace.resultCount)").monospacedDigit()
                LabeledContent("contentHash", value: String(trace.contentHash.prefix(12)))
                    .monospacedDigit()
                LabeledContent("staleness", value: trace.isStale ? "STALE / 已降级" : "fresh")
                    .foregroundStyle(trace.isStale ? .red : .primary)
            }

            Section {
                // 这一段是 Trace 存在的理由：把「慢」和「错」分开。
                Text(diagnosis)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("READING THIS")
            }
        }
        .navigationTitle("Trace")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stage(_ label: String, _ ms: Double, emphasised: Bool = false) -> some View {
        LabeledContent(label, value: String(format: "%.2f ms", ms))
            .monospacedDigit()
            .fontWeight(emphasised ? .semibold : .regular)
    }

    /// 把常见结论直接写出来，省掉「盯着数字猜」的一步。
    private var diagnosis: String {
        if trace.isStale {
            return "本次未使用语义路（索引未就绪或 provider 不可用），结果仅来自关键词。这不是失败 —— 关键词搜索照常工作。"
        }
        if trace.candidateCount == 0 {
            return "候选集为 0：问题在检索层，不在排序层。检查索引是否已建立、query 是否被切成了不可能命中的 token。"
        }
        if trace.resultCount == 0 {
            return "有候选但无结果：问题在融合或截断。检查 topK 与融合方式。"
        }
        if trace.queryEmbeddingMs > trace.totalMs * 0.6 {
            return "耗时主要花在 query embedding 上，检索本身很快。若要压延迟，先看 provider 而不是索引。"
        }
        return "候选 \(trace.candidateCount) → 结果 \(trace.resultCount)，contentHash 与索引一致，说明本次结果未用到过期 embedding。"
    }
}
