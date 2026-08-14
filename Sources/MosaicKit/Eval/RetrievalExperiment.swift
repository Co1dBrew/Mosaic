import Foundation

/// # 对照实验（backlog 6.1 / 6.2）
///
/// Week 6 的两个实验（Local vs Cloud embedding · Chunk 策略对比）形状完全一样：
/// **同一批用例，换一个变量，看四个数字怎么动。** 所以它们共用一个跑法，
/// 而不是各写一遍 —— 两份实现意味着两处可以各自跑偏，那时比出来的可能是
/// 实现差异而不是变量差异（与 `RetrievalService` 三种 mode 共用一条管线同一个理由）。
///
/// ## 一条纪律：同一批用例
///
/// 每一臂跑的必须是**同一批** `EvalCase`。这是 §14.3 在 D6 上抓到过的缺陷：
/// 用例集变了之后，表格里的 delta 里混进了「分母变了」，看起来像变量起了作用。
public enum RetrievalExperiment {

    /// 实验的一臂：一个变量取值 + 它对应的检索环境。
    ///
    /// 环境由闭包现建，因为换 chunk 策略要重新切分与重新嵌入 ——
    /// 不能几臂共用一份索引（那正是 §14.2 说的「索引对不上」）。
    public struct Arm: Sendable {
        public let label: String
        public let config: RetrievalConfig
        public let makeEnvironment: @Sendable () async throws -> (service: RetrievalService, chunks: [NoteChunk])

        public init(label: String,
                    config: RetrievalConfig,
                    makeEnvironment: @escaping @Sendable () async throws -> (service: RetrievalService, chunks: [NoteChunk])) {
            self.label = label
            self.config = config
            self.makeEnvironment = makeEnvironment
        }
    }

    public struct ArmResult: Sendable, Equatable {
        public let label: String
        public let configVersion: String
        public let metrics: EvalMetrics
        /// 建索引的耗时。**不计入 P50 / P95** —— 那两个数只统计检索本身
        /// （与 PRD 的 SLO 同口径）。但换 provider 时它本身就是一项成本，要单独看得见。
        public let indexBuildMs: Double
        public let failureQueries: [String]
    }

    public struct Report: Sendable, Equatable {
        public let title: String
        public let caseCount: Int
        public let arms: [ArmResult]

        /// 按 Recall@5 排最好的一臂；并列时看 MRR。
        ///
        /// **不给「推荐」两个字**：这里只说哪一臂在这批用例上的数字更高。
        /// 是否换配置是 Release Gate 的事。
        public var leader: ArmResult? {
            arms.max { a, b in
                a.metrics.recallAt5 == b.metrics.recallAt5
                    ? a.metrics.mrr < b.metrics.mrr
                    : a.metrics.recallAt5 < b.metrics.recallAt5
            }
        }

        /// 可直接贴进文档的表格。**只输出实测数字**，不补任何解释性的估计值。
        public func markdownTable() -> String {
            var lines: [String] = []
            lines.append("| \(title) | Recall@1 | Recall@3 | Recall@5 | MRR | P50 | P95 | 建索引 |")
            lines.append("|---|---|---|---|---|---|---|---|")
            for arm in arms {
                lines.append(String(format: "| %@ | %.3f | %.3f | %.3f | %.3f | %.2f ms | %.2f ms | %.0f ms |",
                                    arm.label,
                                    arm.metrics.recallAt1, arm.metrics.recallAt3, arm.metrics.recallAt5,
                                    arm.metrics.mrr, arm.metrics.p50Ms, arm.metrics.p95Ms,
                                    arm.indexBuildMs))
            }
            return lines.joined(separator: "\n")
        }
    }

    /// 跑一次对照实验。
    ///
    /// - Note: 任何一臂抛错就整个实验抛错 —— 少一臂的对照表比没有表更危险，
    ///   它看起来像个完整的结论。
    public static func run(title: String,
                           cases: [EvalCase],
                           arms: [Arm]) async throws -> Report {
        var results: [ArmResult] = []
        for arm in arms {
            try Task.checkCancellation()
            let t0 = DispatchTime.now().uptimeNanoseconds
            let env = try await arm.makeEnvironment()
            let buildMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

            let runner = EvalRunner(service: env.service, chunksProvider: { env.chunks })
            let run = try await runner.run(cases: cases, config: arm.config)
            results.append(ArmResult(label: arm.label,
                                     configVersion: arm.config.version,
                                     metrics: run.metrics,
                                     indexBuildMs: buildMs,
                                     failureQueries: run.failures.map(\.evalCase.query)))
        }
        return Report(title: title, caseCount: cases.count, arms: results)
    }
}
