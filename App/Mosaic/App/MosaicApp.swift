import SwiftUI
import SwiftData

@main
struct MosaicApp: App {
    @State private var settings: SettingsStore
    @State private var summaryService: SummaryService
    @State private var transcriptionService: TranscriptionService
    @State private var container: ModelContainer

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _summaryService = State(initialValue: SummaryService(settings: settings))
        _transcriptionService = State(initialValue: TranscriptionService(settings: settings))
        _container = State(initialValue: ModelContainerFactory.make(cloudKitEnabled: settings.iCloudSyncEnabled))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.summaryService, summaryService)
                .environment(\.transcriptionService, transcriptionService)
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
