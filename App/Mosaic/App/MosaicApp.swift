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
    /// **同步的真实状态**，由「构建有没有能力 + 用户开没开 + 容器实际是什么」推导。
    /// 在这里算一次并注入，而不是让设置页去读用户偏好 —— 偏好说明不了数据在哪。
    @State private var cloudSyncState: CloudSyncState

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _summaryService = State(initialValue: SummaryService(settings: settings))
        _transcriptionService = State(initialValue: TranscriptionService(settings: settings))
        let buildSupportsCloudKit = ModelContainerFactory.buildSupportsCloudKit
        let store = ModelContainerFactory.makeNoteStore(
            cloudKitRequested: CloudSyncPolicy.requestsCloudKitContainer(
                buildSupportsCloudKit: buildSupportsCloudKit,
                userEnabled: settings.iCloudSyncEnabled))
        let notes = store.container
        _container = State(initialValue: notes)
        _cloudSyncState = State(initialValue: CloudSyncPolicy.state(
            buildSupportsCloudKit: buildSupportsCloudKit,
            userEnabled: settings.iCloudSyncEnabled,
            containerIsCloudKitBacked: store.isCloudKitBacked))

        // Derived data 走独立 container / 独立 store 文件，不进 CloudKit
        // （RETRIEVAL_ARCHITECTURE.md §2）。
        let derived = ModelContainerFactory.makeDerived()
        _derivedContainer = State(initialValue: derived)
        // Provider 在启动扫描笔记之后才选定（中文 → 云端 / 纯英文 → 本机英文）。
        // 这里先空着，不默认中文本地模型 —— iOS 上那个模型不存在，预先失败会
        // 让纯英文库也用不上本机英文。
        let vectors = InMemoryVectorStore()
        let derivedStore = DerivedDataStore(container: derived)
        // 生产配置从注册表来，不是 `RetrievalConfig.production` 这个常量（backlog 5.1）——
        // 否则 Release Gate 的 Promote 只是改了一行 JSON，线上跑的还是编译期那套。
        let release = ReleaseStore()
        // TD-8：索引服务。在它之前 derived store 只有测试在写，真机上索引永远是空的。
        // 它读的是 `container.mainContext` —— 与视图拿到的 `\.modelContext` 同一个上下文，
        // 所以 StaleGuard 校验读到的就是权威内容（RETRIEVAL_ARCHITECTURE.md §5）。
        let indexing = IndexingService(provider: nil,
                                       vectors: vectors,
                                       derived: derivedStore,
                                       noteContext: notes.mainContext,
                                       extractor: VisionImageTextExtractor(),
                                       config: release.productionConfig)
        _retrieval = State(initialValue: RetrievalEnvironment(
            provider: nil,
            vectors: vectors,
            recorder: RetrievalTraceRecorder(),
            derived: derivedStore,
            indexing: indexing,
            release: release,
            settings: settings
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.cloudSyncState, cloudSyncState)
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

/// 同步的真实状态。默认 `.unavailableInThisBuild` —— Preview / 测试里没注入时
/// 显示「不提供同步」是安全的方向：它不会让任何界面声称数据已经上云。
private struct CloudSyncStateKey: EnvironmentKey {
    static let defaultValue: CloudSyncState = .unavailableInThisBuild
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
    var cloudSyncState: CloudSyncState {
        get { self[CloudSyncStateKey.self] }
        set { self[CloudSyncStateKey.self] = newValue }
    }
}
