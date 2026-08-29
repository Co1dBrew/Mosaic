import SwiftUI
import SwiftData
import MosaicKit

/// 根导航（`UI_REDESIGN.md` v2 §1.1）。
///
/// v2 的信息架构是 **2 级**：笔记流 → 笔记页。
/// 文件夹不再是首页，它降级为首页顶部的一行筛选 chip，管理页在 chip 行末尾的 `⋯`。
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    /// 唯一的导航路径。目的地也只声明一处 —— 见 `AppRouter` 里记的那次实测。
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            // `navigationDestination` 必须挂在**栈内容里**，挂在 `NavigationStack`
            // 自己身上不会被这个栈注册（同样没有任何警告）。
            rootContent
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
        .environment(router)
    }

    @ViewBuilder private var rootContent: some View {
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
                NoteListView()
            }
            #else
            NoteListView()
            #endif
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case let .note(card, anchor):  NoteDetailView(card: card, landing: anchor)
        case .search:                  SearchView()
        case .settings:                SettingsView()
        case .advancedSettings:        AdvancedSettingsView()
        case .folders:                 FolderManageView()
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore(keychain: InMemoryKeychain()))
        .modelContainer(ModelContainerFactory.make(cloudKitEnabled: false, inMemory: true))
}
