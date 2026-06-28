import SwiftUI
import SwiftData
import MosaicKit

/// Root navigation (PRD §3 stack-based navigation): Folders → Cards → Editor,
/// with Settings reachable from the folder list.
struct RootView: View {
    var body: some View {
        NavigationStack {
            FolderListView()
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore(keychain: InMemoryKeychain()))
        .modelContainer(ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true))
}
