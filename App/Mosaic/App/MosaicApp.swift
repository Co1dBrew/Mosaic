import SwiftUI
import SwiftData

@main
struct MosaicApp: App {
    @State private var settings: SettingsStore
    @State private var summaryService: SummaryService
    @State private var container: ModelContainer

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _summaryService = State(initialValue: SummaryService(settings: settings))
        _container = State(initialValue: ModelContainerFactory.make(cloudKitEnabled: settings.iCloudSyncEnabled))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.summaryService, summaryService)
        }
        .modelContainer(container)
    }
}

// MARK: - SummaryService environment injection

private struct SummaryServiceKey: EnvironmentKey {
    static let defaultValue: SummaryService? = nil
}

extension EnvironmentValues {
    var summaryService: SummaryService? {
        get { self[SummaryServiceKey.self] }
        set { self[SummaryServiceKey.self] = newValue }
    }
}
