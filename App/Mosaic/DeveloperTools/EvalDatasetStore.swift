import Foundation
import Observation
import MosaicKit

/// # Golden Set / Regression Set 的持久化
///
/// ## 为什么不放 derived store
///
/// Derived store 的契约是「删掉全部内容不丢任何东西，因为都能重建」
/// （`RETRIEVAL_ARCHITECTURE.md` §2）。Golden Set **不满足这个契约**：
/// 「这条 query 应该找到哪篇笔记」是人工判断，删了就没了，重建要靠人重新标一遍。
/// 把不可重建的数据放进一个明确标着「可以随时清空」的 store，迟早会被一次
/// `deleteAll()` 抹掉。所以它有自己的文件。
///
/// ## 为什么不放 SwiftData
///
/// 它是一个 query 列表，不是一个数据集管理平台（`DEVTOOLS.md` §6.2）。
/// 一个 `Codable` 的 JSON 文件不需要 schema 迁移，而这份数据的形状还会随 Week 5/6 变。
///
/// ## 与用户数据的关系
///
/// 只写这一个文件。**不碰笔记**（`DEVTOOLS.md` §1.2「数据隔离」）。
@Observable
@MainActor
final class EvalDatasetStore {

    private(set) var dataset: EvalDataset
    /// 上一次写盘失败的原因。静默失败会让人以为标注保存了。
    private(set) var lastError: String?

    private let fileURL: URL

    /// - Parameter directory: 默认 Application Support；测试传临时目录。
    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("eval-datasets.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dataset = Self.load(from: fileURL)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MosaicEval", isDirectory: true)
    }

    private static func load(from url: URL) -> EvalDataset {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(EvalDataset.self, from: data) else {
            return EvalDataset()
        }
        return decoded
    }

    // MARK: 写操作（评测侧数据，共三类中的两类）

    @discardableResult
    func addGolden(query: String, expectedNoteIDs: [String], note: String? = nil) -> Bool {
        let added = dataset.addGolden(query: query, expectedNoteIDs: expectedNoteIDs, note: note)
        if added { save() }
        return added
    }

    /// D9 唯一的写操作。幂等由 `EvalDataset` 保证 —— 重复加入会让 Pass Rate 分母虚高。
    @discardableResult
    func addRegression(_ failure: EvalFailure) -> Bool {
        let added = dataset.addRegression(failure)
        if added { save() }
        return added
    }

    func contains(_ failure: EvalFailure) -> Bool { dataset.regressionContains(failure) }

    func removeGolden(id: String) { dataset.removeGolden(id: id); save() }
    func removeRegression(id: String) { dataset.removeRegression(id: id); save() }

    func cases(_ selection: EvalDataset.Selection) -> [EvalCase] { dataset.cases(selection) }
    func count(_ selection: EvalDataset.Selection) -> Int { dataset.count(selection) }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dataset).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
