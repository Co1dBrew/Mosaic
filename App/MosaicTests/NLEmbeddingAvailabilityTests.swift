import XCTest
import NaturalLanguage
import MosaicKit
@testable import Mosaic

/// # TD-9 —— 这台设备上到底有没有句向量模型
///
/// `NLEmbedding` 的模型是**随系统走的**，不是随 App 走的：同一份代码在 macOS 上
/// 拿得到 zh-Hans（640 维），在 iOS 模拟器上拿不到。所以「语义检索可用」不是一个
/// 可以假设的前提，必须在目标平台上**实测**。
///
/// 这个用例把可用性矩阵打印出来，并守住一条契约：
/// **拿得到的模型必须真的能产出声明维度的向量** —— 一个存在但产不出向量的 provider
/// 比没有 provider 更糟，它会让索引看起来在工作。
final class NLEmbeddingAvailabilityTests: XCTestCase {

    func testSentenceEmbeddingAvailabilityMatrix() throws {
        let languages: [NLLanguage] = [.simplifiedChinese, .traditionalChinese, .english, .japanese]
        var available: [String] = []

        for language in languages {
            let embedding = NLEmbedding.sentenceEmbedding(for: language)
            print("NLEmbedding \(language.rawValue): sentence=\(embedding != nil) dim=\(embedding?.dimension ?? 0)")
            if embedding != nil { available.append(language.rawValue) }
        }
        print("NLEmbedding available on this platform: \(available)")

        // 实测记录（2026-08-10）：
        //   macOS 26          zh-Hans ✅ 640 维
        //   iOS 26 模拟器      zh-Hans ❌ / zh-Hant ❌ / ja ❌ / **en ✅ 512 维**
        // 真机尚未验证（Week 6 真机复测）。所以这里不断言「中文一定可用」——
        // 断言一个平台事实会让用例在另一个平台上无谓地红。
        XCTAssertFalse(available.isEmpty, "一门语言的句向量都没有的话，语义检索在这个平台上根本不成立")
    }

    /// 拿得到的 provider 必须真的能用。
    func testAvailableProviderActuallyProducesVectors() async throws {
        let candidates: [(NLEmbeddingProvider.Language, String)] = [(.simplifiedChinese, "延期毕业的申请流程"),
                                                                    (.english, "graduation deferral request")]
        var tested = 0
        for (language, sample) in candidates {
            guard let provider = NLEmbeddingProvider(language: language) else { continue }
            tested += 1
            let vector = try await provider.embed(sample)
            XCTAssertEqual(vector.count, provider.modelInfo.dimension,
                           "\(language.rawValue) 的向量维度必须与声明一致")
            XCTAssertTrue(vector.contains { $0 != 0 }, "全零向量等于没有语义信息")
            XCTAssertTrue(provider.modelInfo.version.contains(language.rawValue),
                          "语言编进 version —— 不同语言是不同的向量空间，混用会静默出错")
        }
        XCTAssertGreaterThan(tested, 0, "至少要有一门语言可用")
    }

    /// App 的取用口：拿不到中文模型时**必须失败**，不能悄悄换成别的语言或 mock。
    /// 换语言 = 换向量空间，中文笔记配英文模型排出来的顺序没有意义。
    func testLocalEmbeddingFailsLoudlyWhenChineseModelIsMissing() {
        let provider = try? LocalEmbedding.make(language: .simplifiedChinese)
        if NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) == nil {
            XCTAssertNil(provider, "没有中文模型时不得返回任何 provider —— 静默降级会让 Recall 看起来正常")
        } else {
            XCTAssertNotNil(provider)
        }
    }
}
