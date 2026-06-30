import SwiftUI
import SwiftData
import MosaicKit

/// Root navigation (PRD §3 stack-based navigation): Folders → Cards → Editor,
/// with Settings reachable from the folder list.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-gallery") {
                DebugGalleryView()
            } else if ProcessInfo.processInfo.arguments.contains("--search-demo") {
                SearchView(initialQuery: "评审")
                    .task { SampleData.seedIfEmpty(modelContext) }
            } else {
                FolderListView()
            }
            #else
            FolderListView()
            #endif
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore(keychain: InMemoryKeychain()))
        .modelContainer(ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true))
}
