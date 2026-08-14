import SwiftUI
import SwiftData
import MosaicKit

@main
struct MosaicApp: App {
    @State private var settings: SettingsStore
    @State private var summaryService: SummaryService
    @State private var transcriptionService: TranscriptionService
    @State private var container: ModelContainer
    @State private var derivedContainer: ModelContainer
    @State private var retrieval: RetrievalEnvironment

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _summaryService = State(initialValue: SummaryService(settings: settings))
        _transcriptionService = State(initialValue: TranscriptionService(settings: settings))
        let notes = ModelContainerFactory.make(cloudKitEnabled: settings.iCloudSyncEnabled)
        _container = State(initialValue: notes)

        // Derived data 走独立 container / 独立 store 文件，不进 CloudKit
        // （RETRIEVAL_ARCHITECTURE.md §2）。
        let derived = ModelContainerFactory.makeDerived()
        _derivedContainer = State(initialValue: derived)
        // 真实本地 embedding（Apple NaturalLanguage，zh-Hans 640 维，完全离线）。
        // 拿不到时**不退回 mock** —— 静默退回会让评测数字看起来正常但毫无意义。
        // 宁可让 Developer Mode 明确显示 provider 不可用。
        let embedding: (any EmbeddingProvider)? = try? LocalEmbedding.make()
        let vectors = InMemoryVectorStore()
        let derivedStore = DerivedDataStore(container: derived)
        // 生产配置从注册表来，不是 `RetrievalConfig.production` 这个常量（backlog 5.1）——
        // 否则 Release Gate 的 Promote 只是改了一行 JSON，线上跑的还是编译期那套。
        let release = ReleaseStore()
        // TD-8：索引服务。在它之前 derived store 只有测试在写，真机上索引永远是空的。
        // 它读的是 `container.mainContext` —— 与视图拿到的 `\.modelContext` 同一个上下文，
        // 所以 StaleGuard 校验读到的就是权威内容（RETRIEVAL_ARCHITECTURE.md §5）。
        let indexing = IndexingService(provider: embedding,
                                       vectors: vectors,
                                       derived: derivedStore,
                                       noteContext: notes.mainContext,
                                       extractor: VisionImageTextExtractor(),
                                       config: release.productionConfig)
        _retrieval = State(initialValue: RetrievalEnvironment(
            provider: embedding,
            vectors: vectors,
            recorder: RetrievalTraceRecorder(),
            derived: derivedStore,
            indexing: indexing,
            release: release
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.summaryService, summaryService)
                .environment(\.transcriptionService, transcriptionService)
                .environment(retrieval)
                // 启动：灌回已落盘的向量，再补齐这次启动前发生的改动
                // （重启不恢复队列，而是重新推导要做什么 —— `DerivedWorkScanner`）。
                .task { await retrieval.startIndexing() }
        }
        .modelContainer(container)
    }
}

// MARK: - SummaryService environment injection

private struct SummaryServiceKey: EnvironmentKey {
    static let defaultValue: SummaryService? = nil
}

private struct TranscriptionServiceKey: EnvironmentKey {
    static let defaultValue: TranscriptionService? = nil
}

extension EnvironmentValues {
    var summaryService: SummaryService? {
        get { self[SummaryServiceKey.self] }
        set { self[SummaryServiceKey.self] = newValue }
    }
    var transcriptionService: TranscriptionService? {
        get { self[TranscriptionServiceKey.self] }
        set { self[TranscriptionServiceKey.self] = newValue }
    }
}
