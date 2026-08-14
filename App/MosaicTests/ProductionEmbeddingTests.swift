import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// 生产 embedding 路线：有中文走云端，纯英文走本机英文。
@MainActor
final class ProductionEmbeddingTests: XCTestCase {

    func testEnglishOnlyCorpusPrefersLocalEnglishWhenChineseModelMissing() {
        // 模拟 iOS：无中文模型。decide 里会读 NLEmbedding 真实可用性。
        // 云端故意失败，纯英文库不应因此不可用。
        let decision = ProductionEmbedding.decide(corpusContainsHan: false,
                                                  cloudConfigured: false,
                                                  cloudConsentGranted: false,
                                                  makeCloud: { .failure(.unavailable("no cloud")) })

        if NLEmbeddingProvider.isAvailable(.simplifiedChinese) {
            XCTAssertEqual(decision.route, .localChinese)
            return
        }
        if NLEmbeddingProvider.isAvailable(.english) {
            XCTAssertEqual(decision.route, .localEnglish)
            XCTAssertNotNil(decision.provider)
            XCTAssertTrue(decision.provider!.modelInfo.version.contains("en"))
        } else {
            if case .unavailable = decision.route {
                XCTAssertNil(decision.provider)
            } else {
                XCTFail("本机既无中文也无英文模型时应 unavailable")
            }
        }
    }

    func testChineseCorpusUsesCloudWhenNoLocalChinese() {
        let cloudProvider = CloudEmbeddingProvider(baseURL: "https://example.test/v1",
                                                   apiKey: "k",
                                                   model: "text-embedding-3-small",
                                                   dimension: 1536)
        let decision = ProductionEmbedding.decide(corpusContainsHan: true,
                                                  cloudConfigured: true,
                                                  cloudConsentGranted: true,
                                                  makeCloud: { .success(cloudProvider) })

        if NLEmbeddingProvider.isAvailable(.simplifiedChinese) {
            XCTAssertEqual(decision.route, .localChinese)
        } else {
            XCTAssertEqual(decision.route, .cloud)
            XCTAssertEqual(decision.provider?.modelInfo.identifier, "cloud-text-embedding-3-small")
        }
    }

    func testChineseCorpusWithoutCloudIsUnavailableOnIOS() {
        let decision = ProductionEmbedding.decide(corpusContainsHan: true,
                                                  cloudConfigured: false,
                                                  cloudConsentGranted: false,
                                                  makeCloud: { .failure(.unavailable("no cloud")) })
        if NLEmbeddingProvider.isAvailable(.simplifiedChinese) {
            XCTAssertEqual(decision.route, .localChinese)
        } else {
            if case .unavailable(let reason) = decision.route {
                XCTAssertTrue(reason.contains("中文"))
                XCTAssertTrue(reason.contains("关键词"))
            } else {
                XCTFail("iOS 有中文无云端应 unavailable，得到 \(decision.route)")
            }
            XCTAssertNil(decision.provider)
        }
    }

    // MARK: 隐私闸门 —— 云端那一路必须先拿到明确同意

    /// **这是本文件最重要的一条。** 云端 embedding 会把**整库**笔记发到第三方；
    /// 只要没拿到明确同意，就必须一个请求都发不出去 —— 而「发不出去」的实现方式是
    /// 根本不构造 provider，不是靠调用方记得检查。
    func testCloudRouteRequiresExplicitConsentAndNeverBuildsProvider() throws {
        try XCTSkipIf(NLEmbeddingProvider.isAvailable(.simplifiedChinese),
                      "本机有中文模型时不会走云端（Mac）；这条用例针对 iOS 现状")

        var didBuildCloudProvider = false
        let decision = ProductionEmbedding.decide(
            corpusContainsHan: true,
            cloudConfigured: true,          // Key / 模型 / URL 都配好了
            cloudConsentGranted: false,     // 但用户没同意
            makeCloud: {
                didBuildCloudProvider = true
                return .success(CloudEmbeddingProvider(baseURL: "https://example.test/v1",
                                                       apiKey: "k", model: "m", dimension: 8))
            })

        XCTAssertEqual(decision.route, .cloudNeedsConsent,
                       "配好但没同意 → cloudNeedsConsent，而不是 cloud、也不是笼统的 unavailable")
        XCTAssertNil(decision.provider, "没同意就没有 provider —— 检索层拿不到东西可用，发不出请求")
        XCTAssertFalse(didBuildCloudProvider,
                       "连构造都不该发生 —— 构造会把 API Key 拷进请求对象")
        XCTAssertTrue(decision.route.needsCloudConsent, "UI 据此展示同意入口，而不是「重试」")
    }

    /// 同意之后才真正走云端。
    func testConsentGrantedEnablesCloudRoute() throws {
        try XCTSkipIf(NLEmbeddingProvider.isAvailable(.simplifiedChinese),
                      "本机有中文模型时不会走云端（Mac）")

        let decision = ProductionEmbedding.decide(
            corpusContainsHan: true,
            cloudConfigured: true,
            cloudConsentGranted: true,
            makeCloud: { .success(CloudEmbeddingProvider(baseURL: "https://example.test/v1",
                                                        apiKey: "k", model: "m", dimension: 8)) })
        XCTAssertEqual(decision.route, .cloud)
        XCTAssertNotNil(decision.provider)
    }

    /// 闸门在 `SettingsStore` 里也要成立 —— 那是唯一构造云端 provider 的地方。
    func testSettingsRefusesToBuildCloudProviderWithoutConsent() {
        let defaults = UserDefaults(suiteName: "consent-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults, keychain: InMemoryKeychain())
        settings.currentAPIKey = "sk-test"
        settings.embeddingModel = "text-embedding-3-small"
        settings.embeddingDimension = 8

        XCTAssertTrue(settings.isCloudEmbeddingConfigured, "参数齐了")
        XCTAssertFalse(settings.hasAcceptedCloudEmbeddingNotice, "默认没有同意")
        if case .success = settings.makeCloudEmbeddingProvider() {
            XCTFail("没同意时不能构造出云端 provider")
        }

        settings.hasAcceptedCloudEmbeddingNotice = true
        if case .failure(let error) = settings.makeCloudEmbeddingProvider() {
            XCTFail("同意之后应当可用，得到 \(error)")
        }
    }

    func testCorpusContainsHanReadsTitleAndBody() {
        let notes = ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true)
        let derived = DerivedDataStore(container: ModelContainerFactory.makeDerived(inMemory: true))
        let ctx = notes.mainContext

        let untitled = Card(userTitle: "")
        ctx.insert(untitled)
        let untitledBody = Block(kind: .text, order: 0)
        untitledBody.text = "Talked about deferral"
        untitledBody.card = untitled
        ctx.insert(untitledBody)
        // 空标题的界面回退是「未命名笔记」，不能因此把纯英文库判成含中文。
        XCTAssertFalse(ProductionEmbedding.corpusContainsHan(cards: [untitled], derived: derived))

        let english = Card(userTitle: "Advisor meeting")
        ctx.insert(english)
        let b = Block(kind: .text, order: 0)
        b.text = "Talked about deferral"
        b.card = english
        ctx.insert(b)
        XCTAssertFalse(ProductionEmbedding.corpusContainsHan(cards: [english], derived: derived))

        let chinese = Card(userTitle: "延期")
        ctx.insert(chinese)
        XCTAssertTrue(ProductionEmbedding.corpusContainsHan(cards: [english, chinese], derived: derived))
    }
}
