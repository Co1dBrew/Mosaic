#if DEBUG
import Foundation
import SwiftUI
import SwiftData
import MosaicKit

/// DEBUG-only screen (via `--cards-demo`) that seeds data then shows the first
/// folder's card list, for screenshotting tags / pinning UI.
struct CardsDemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var folders: [Folder]

    var body: some View {
        Group {
            if let folder = folders.first {
                CardListView(folder: folder)
            } else {
                ProgressView()
            }
        }
        .task { SampleData.seedIfEmpty(modelContext) }
    }
}

/// DEBUG-only sample data for screenshots/QA (e.g. the `--search-demo` launch
/// argument). Never used in normal or release builds.
enum SampleData {
    /// Seeds a folder with a few cards if the store is empty. Idempotent-ish.
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        guard existing.isEmpty else { return }

        let folder = Folder(name: "工作", colorHex: "#0A84FF", iconName: "briefcase.fill")
        context.insert(folder)

        // Card 1: with text + transcript + AI summary
        let card1 = Card(userTitle: "周三产品评审会要点", folder: folder)
        card1.tags = ["产品评审", "工作"]
        card1.isPinned = true
        context.insert(card1)
        let t1 = Block(kind: .text, order: 0); t1.text = "今天讨论了下个版本的排期与分工"
        context.insert(t1); t1.card = card1
        let a1 = Block(kind: .audio, order: 1); a1.transcript = "我们决定下周三上线新版本"; a1.audioRelativePath = "audio/demo.m4a"
        context.insert(a1); a1.card = card1
        card1.blocks = [t1, a1]
        let s1 = AISummaryEntity(); context.insert(s1); s1.card = card1; card1.summary = s1
        s1.applyBase(
            BaseSummaryDTO(title: "周三产品评审会要点", oneLiner: "记录了本周产品评审会的结论与待办分工。",
                           type: "会议记录", topics: ["产品评审", "排期"], keyPoints: ["确定下周三上线"],
                           summary: "围绕下个版本的取舍与排期展开。"),
            provider: "Kimi (Moonshot)", model: "moonshot-v1-8k")

        // Card 2: text only, different folder-less content
        let card2 = Card(userTitle: "读书笔记:设计模式", folder: folder)
        card2.tags = ["读书", "设计模式"]
        context.insert(card2)
        let t2 = Block(kind: .text, order: 0); t2.text = "关于工厂模式与观察者模式的一些想法"
        context.insert(t2); t2.card = card2
        card2.blocks = [t2]

        try? context.save()
    }
}
#endif
