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
            } else if ProcessInfo.processInfo.arguments.contains("--cards-demo") {
                CardsDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("--markdown-demo") {
                ScrollView {
                    MarkdownBlockView(markdown: """
                    # 会议纪要
                    今天讨论了**排期**与*分工*。
                    - 确定下周三上线
                    - 新增三位负责人
                    1. 设计先行
                    2. 后端跟进
                    ---
                    详见 [产品文档](https://example.com)
                    """)
                    .appCard(background: Color(.tertiarySystemBackground))
                    .padding()
                }
                .navigationTitle("Markdown 预览")
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
