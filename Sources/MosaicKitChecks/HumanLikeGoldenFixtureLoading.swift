import Foundation
import MosaicKit

/// 保留原名，避免动 13 处调用点。类型与解析已搬到 `MosaicKit.GoldenSetFixture`
/// —— 因为真机 bench 也要用同一套（见那边的类型注释）。
typealias HumanLikeGoldenFixture = GoldenSetFixture

extension GoldenSetFixture {
    /// Mac 侧的加载入口：从 checks 自己的 resource bundle 读那唯一一份 JSON。
    /// 真机侧有对应的一个入口，从测试 bundle 读**同一个文件**。
    static func load() throws -> Dataset {
        guard let url = Bundle.module.url(forResource: "HumanLikeGoldenSet",
                                          withExtension: "json",
                                          subdirectory: "Fixtures") else {
            throw FixtureError.resourceMissing
        }
        return try decode(Data(contentsOf: url))
    }
}
