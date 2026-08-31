import XCTest
import SwiftData
import MosaicKit
@testable import Mosaic

/// 生产 embedding 路线：有中文走云端，纯英文走本机英文。
@MainActor
final class ProductionEmbeddingTests: XCTestCase {

    /// # 为什么这些用例把「本机有没有模型」显式传进去
    ///
    /// 它们原来读真实可用性，再用 `if NLEmbeddingProvider.isAvailable(...)` 分支断言。
    /// 结果是每条用例只有一个分支会执行，**而另一个分支从来没跑过**——
    /// 于是里面写错的期望没有任何东西会发现。
    ///
    /// 真机第一次跑这套的时候两条就红了：模拟器上没有中文模型，
    /// iPhone Air / iOS 27 上有（640 维），于是那两个「从没执行过」的分支
    /// 第一次被执行，两个期望都是错的（详见每条用例上的说明）。
    ///
    /// 显式传入之后，两条路线在**任何机器上都验得动**，
    /// 而「这台设备上实际有哪些模型」由 `MosaicBench.test1` 如实记录 —— 那是事实，不是断言。

    /// 纯英文语料：**即使本机有中文模型**也走本机英文。
    ///
    /// 原来这条在「有中文模型」时断言 `.localChinese`，那是错的 ——
    /// 路由第二步按**语料语种**选模型，给英文语料配中文模型排出来的顺序没有意义。
    /// 这个错误分支在模拟器上永远执行不到，真机上一跑就红。
    func testEnglishOnlyCorpusPrefersLocalEnglishEvenWhenChineseModelExists() {
        for chineseAvailable in [true, false] {
            let decision = ProductionEmbedding.decide(corpusContainsHan: false,
                                                      cloudConfigured: false,
                                                      cloudConsentGranted: false,
                                                      localChineseAvailable: chineseAvailable,
                                                      localEnglishAvailable: true,
                                                      makeCloud: { .failure(.unavailable("no cloud")) })
            XCTAssertEqual(decision.route, .localEnglish,
                           "纯英文语料按语料语种选模型（本机中文模型 available=\(chineseAvailable)）")
        }
    }

    /// 两种模型都没有：语义整条缺席，keyword 不受影响。
    func testNoLocalModelAndNoCloudIsUnavailable() {
        let decision = ProductionEmbedding.decide(corpusContainsHan: false,
                                                  cloudConfigured: false,
                                                  cloudConsentGranted: false,
                                                  localChineseAvailable: false,
                                                  localEnglishAvailable: false,
                                                  makeCloud: { .failure(.unavailable("no cloud")) })
        guard case .unavailable(let reason) = decision.route else {
            return XCTFail("既无本机模型也无云端时应 unavailable，得到 \(decision.route)")
        }
        XCTAssertNil(decision.provider)
        XCTAssertTrue(reason.contains("关键词"), "文案要告诉用户 keyword 仍然可用")
    }

    /// 云端已配置且已授权时**优先云端**，即使本机有中文模型。
    ///
    /// 原来这条在「有中文模型」时断言 `.localChinese` —— 与 `EmbeddingRouter.choose`
    /// 的第一步（`cloudConfigured && cloudConsentGranted → .cloud`）直接矛盾。
    /// 同样是一个在模拟器上执行不到的分支。
    func testCloudWinsOverLocalWhenConfiguredAndConsented() {
        let cloudProvider = CloudEmbeddingProvider(baseURL: "https://example.test/v1",
                                                   apiKey: "k",
                                                   model: "text-embedding-3-small",
                                                   dimension: 1536)
        for chineseAvailable in [true, false] {
            let decision = ProductionEmbedding.decide(corpusContainsHan: true,
                                                      cloudConfigured: true,
                                                      cloudConsentGranted: true,
                                                      localChineseAvailable: chineseAvailable,
                                                      localEnglishAvailable: true,
                                                      makeCloud: { .success(cloudProvider) })
            XCTAssertEqual(decision.route, .cloud,
                           "已配置 + 已授权时云端优先（本机中文模型 available=\(chineseAvailable)）")
            XCTAssertEqual(decision.provider?.modelInfo.identifier, "cloud-text-embedding-3-small")
        }
    }

    /// 本机有中文模型时，**中文语料不必去云端** —— 本地顶得上就不打扰用户。
    func testChineseCorpusStaysLocalWhenChineseModelExistsAndCloudNotConsented() {
        let decision = ProductionEmbedding.decide(corpusContainsHan: true,
                                                  cloudConfigured: true,
                                                  cloudConsentGranted: false,
                                                  localChineseAvailable: true,
                                                  localEnglishAvailable: true,
                                                  makeCloud: { .failure(.unavailable("不该走到这里")) })
        XCTAssertEqual(decision.route, .localChinese,
                       "本地顶得上时不返回 cloudNeedsConsent —— 不该为一个不需要的能力弹窗")
    }

    /// 中文语料 + 本机无中文模型 + 无云端 → unavailable，且文案说明 keyword 不受影响。
    func testChineseCorpusWithoutLocalChineseOrCloudIsUnavailable() {
        let decision = ProductionEmbedding.decide(corpusContainsHan: true,
                                                  cloudConfigured: false,
                                                  cloudConsentGranted: false,
                                                  localChineseAvailable: false,
                                                  localEnglishAvailable: true,
                                                  makeCloud: { .failure(.unavailable("no cloud")) })
        guard case .unavailable(let reason) = decision.route else {
            return XCTFail("有中文无云端应 unavailable，得到 \(decision.route)")
        }
        XCTAssertTrue(reason.contains("中文"))
        XCTAssertTrue(reason.contains("关键词"))
        XCTAssertNil(decision.provider)
    }

    // MARK: 隐私闸门 —— 云端那一路必须先拿到明确同意

    /// **这是本文件最重要的一条。** 云端 embedding 会把**整库**笔记发到第三方；
    /// 只要没拿到明确同意，就必须一个请求都发不出去 —— 而「发不出去」的实现方式是
    /// 根本不构造 provider，不是靠调用方记得检查。
    ///
    /// **这条以前在真机上被 skip 掉。** 它的 `XCTSkipIf` 条件是「本机有中文模型」——
    /// 而 iPhone 上恰恰有。也就是说，一条关于「整库笔记会不会被发出去」的断言，
    /// 在用户真正会用的那台机器上从来没有验证过。现在把可用性显式传进去，
    /// 它在任何机器上都跑。
    func testCloudRouteRequiresExplicitConsentAndNeverBuildsProvider() throws {
        var didBuildCloudProvider = false
        let decision = ProductionEmbedding.decide(
            corpusContainsHan: true,
            cloudConfigured: true,          // Key / 模型 / URL 都配好了
            cloudConsentGranted: false,     // 但用户没同意
            localChineseAvailable: false,   // 本地顶不上 —— 只有这时才轮到问用户
            localEnglishAvailable: true,
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
        let decision = ProductionEmbedding.decide(
            corpusContainsHan: true,
            cloudConfigured: true,
            cloudConsentGranted: true,
            localChineseAvailable: false,
            localEnglishAvailable: true,
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
