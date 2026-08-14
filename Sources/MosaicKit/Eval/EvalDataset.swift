import Foundation

/// # 评测数据集
///
/// Golden Set 与 Regression Set 放在同一个结构里，因为它们**本来就是同一种东西**
/// （`DECISION_LOG.md` D-UI-DEV-009）：同一个 `EvalCase`、同一个 `EvalRunner`、
/// 同一套口径。区别只有 `EvalCase.source` 一个字段，而那个字段的唯一作用是让
/// `EvalRun` 能把指标分开统计。
///
/// **不做**版本化 / 分支 / 导入导出 / 协作 / 标签（`DEVTOOLS.md` §6.2）。
/// 它是一个 query 列表，不是一个数据集管理平台。
public struct EvalDataset: Sendable, Equatable, Codable {

    /// D5 的 Dataset 选择器。三个选项，不多。
    public enum Selection: String, Sendable, Equatable, Codable, CaseIterable {
        case golden
        case regression
        case both

        public var label: String {
            switch self {
            case .golden:     return "Golden Set"
            case .regression: return "Regression Set"
            case .both:       return "Golden + Regression"
            }
        }
    }

    public private(set) var golden: [EvalCase]
    public private(set) var regression: RegressionSet

    public init(golden: [EvalCase] = [], regression: RegressionSet = RegressionSet()) {
        self.golden = golden
        self.regression = regression
    }

    /// 参与本次评测的用例。
    ///
    /// `.golden` / `.regression` 也返回带正确 `source` 的用例，所以 `EvalRun` 的
    /// `goldenMetrics` / `regressionMetrics` 在任何一种选择下都成立 —— 不需要第二套统计。
    public func cases(_ selection: Selection) -> [EvalCase] {
        switch selection {
        case .golden:     return golden
        case .regression: return regression.cases
        case .both:       return golden + regression.cases
        }
    }

    public func count(_ selection: Selection) -> Int { cases(selection).count }

    /// 加一条 Golden 用例。
    ///
    /// **幂等**，判重口径与 `RegressionSet.add` 完全一致（trim 后的 query + 期望笔记集合）：
    /// 两处用不同口径判重，迟早会出现「Golden 里去重了、Regression 里没去重」的分母差异。
    @discardableResult
    public mutating func addGolden(query: String, expectedNoteIDs: [String], note: String? = nil) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !expectedNoteIDs.isEmpty else { return false }
        let expected = Set(expectedNoteIDs)
        guard !golden.contains(where: {
            $0.query.trimmingCharacters(in: .whitespacesAndNewlines) == q && Set($0.expectedNoteIDs) == expected
        }) else { return false }

        golden.append(EvalCase(query: q, expectedNoteIDs: expectedNoteIDs, source: .golden, note: note))
        return true
    }

    @discardableResult
    public mutating func addRegression(_ failure: EvalFailure) -> Bool {
        regression.add(failure)
    }

    public func regressionContains(_ failure: EvalFailure) -> Bool {
        regression.contains(failure)
    }

    public mutating func removeGolden(id: String) { golden.removeAll { $0.id == id } }
    public mutating func removeRegression(id: String) { regression.remove(id: id) }

    /// 一条用例引用的笔记是否还在。笔记被删掉之后，这条用例就永远失败，
    /// 而那不是检索质量的问题 —— UI 要能把这种「用例本身坏了」标出来。
    public static func danglingCases(_ cases: [EvalCase], existingNoteIDs: Set<String>) -> [EvalCase] {
        cases.filter { !$0.expectedNoteIDs.allSatisfy(existingNoteIDs.contains) }
    }
}
