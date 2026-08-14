import SwiftUI
import SwiftData
import MosaicKit

/// # 生产搜索（TD-7 / backlog 5.5–5.8）
///
/// 按 `design/SEARCH_CONTRACT.md`（RE-FROZEN）实现：
///
/// - **隐式 Hybrid，用户侧没有任何 mode 控件**（§1.1）。三个技术词一个都不出现。
/// - 结果三槽位：Title · **Matched Excerpt** · Folder · Time（§2.1）。
///   Excerpt 的唯一职责是回答「为什么这条与我搜的有关系」，它不是笔记摘要。
/// - 状态条与结果区**互不干涉**（§4.1）：语义不可用时结果照常显示（I1–I5）。
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RetrievalEnvironment.self) private var retrieval: RetrievalEnvironment?

    var initialQuery: String = ""

    @State private var query = ""
    @State private var viewModel: SearchViewModel?
    /// §3.1 的导航载荷：**笔记 + 落点**，不只是笔记。
    /// 只带 noteID 的话，进笔记后只能停在顶部 —— 那正是 5.10 之前的行为。
    @State private var selection: Selection?
    @State private var showCloudConsent = false

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                // §4.4：状态条紧贴搜索框下方，最高 44pt，非模态，绝不覆盖结果（I4）。
                SearchStatusBar(capability: viewModel.capability,
                                needsCloudConsent: needsCloudConsent) {
                    if needsCloudConsent { showCloudConsent = true } else { viewModel.retrySemantic() }
                }
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全部笔记")
        .onAppear {
            if viewModel == nil { viewModel = makeViewModel() }
            if query.isEmpty && !initialQuery.isEmpty { query = initialQuery }
            // §3.5：从笔记返回时重新读取能力 —— 离开期间索引可能已经就绪。
            viewModel?.refreshCapability()
            retrieval?.refreshDesiredRoute()
        }
        .onChange(of: query) { _, newValue in viewModel?.queryChanged(newValue) }
        .onDisappear { viewModel?.cancelPendingWork() }
        // 云端上传的**唯一**同意入口（另一个是设置里的开关）。
        // 用户侧文案遵守 §1.1.1 禁用词表：不出现 embedding / 向量 / 语义检索。
        .alert("开启更聪明的搜索？", isPresented: $showCloudConsent) {
            Button("取消", role: .cancel) { }
            Button("同意并开启") {
                Task { await retrieval?.grantCloudEmbeddingConsent() ; viewModel?.refreshCapability() }
            }
        } message: {
            Text("你的笔记里有中文，而这台设备上没有可离线使用的中文模型。开启后，笔记中的文字会通过 HTTPS 发送到你在「设置」里配置的第三方服务来建立索引;不开启则只按关键词搜索,不会发送任何内容。调用费用由你的账户承担。")
        }
        .navigationDestination(item: $selection) { selection in
            CardEditorView(card: selection.card, landing: selection.anchor)
        }
    }

    /// 云端已配好、只差用户点头。此时状态条上的动作是「开启」而不是「重试」——
    /// 「重试」会让人以为是网络出了问题，而实际上是**我们在等他授权**。
    private var needsCloudConsent: Bool {
        guard let retrieval else { return false }
        return retrieval.route.needsCloudConsent || retrieval.desiredRoute?.needsCloudConsent == true
    }

    /// 一次点击选中的「笔记 + 落点」。
    ///
    /// `id` 里带上 anchor：§3.6 明确要求**再次进入同一条结果时重复 highlight**，
    /// 而 `navigationDestination(item:)` 只在 `id` 变化时重建目标视图。
    private struct Selection: Identifiable, Hashable {
        let card: Card
        let anchor: SearchAnchor
        var id: String { SearchDestination(noteID: card.id.uuidString, anchor: anchor).id }

        static func == (lhs: Selection, rhs: Selection) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    @ViewBuilder
    private func content(_ viewModel: SearchViewModel) -> some View {
        switch viewModel.phase {
        case .idle:
            IdleSuggestions { query = $0 }
        case .noResults:
            EmptyStateView(icon: "doc.text.magnifyingglass",
                           title: Copy.noResultsTitle(viewModel.capability),
                           message: Copy.noResultsMessage(viewModel.capability))
        case .searching, .ready:
            // §4.3：`.searching` 保留上一次结果 —— 清空会造成每次按键的白屏闪烁。
            resultList(viewModel)
        }
    }

    @ViewBuilder
    private func resultList(_ viewModel: SearchViewModel) -> some View {
        List {
            // §2.6：整页零字面命中时的唯一说明行。不是状态条、不可点、无 CTA。
            if viewModel.showsSemanticOnlyNotice {
                Text("没有完全匹配的关键词，以下是相关内容")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .listRowSeparator(.hidden)
            }
            ForEach(viewModel.rows) { row in
                if let card = viewModel.card(for: row.noteID) {
                    // anchor 由检索层给出，UI 不猜（§3.1）。
                    Button { selection = Selection(card: card, anchor: row.anchor) } label: {
                        SearchResultRow(row: row, card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        // R5：结果就地升级为融合顺序时**不做重排动画** —— 行的位移在搜索结果里
        // 只会造成误触。行的身份是 noteID（R1），所以点击目标不会因重排而改变。
        .animation(nil, value: viewModel.rows.map(\.noteID))
    }

    private func makeViewModel() -> SearchViewModel {
        let vm = SearchViewModel(provider: retrieval?.provider,
                                 vectors: retrieval?.vectors ?? InMemoryVectorStore(),
                                 recorder: retrieval?.recorder,
                                 indexing: retrieval?.indexing,
                                 derived: retrieval?.derived ?? DerivedDataStore(
                                    container: ModelContainerFactory.makeDerived(inMemory: true)),
                                 noteContext: modelContext)
        vm.onRetrySemantic = { await retrieval?.applyDesiredRoute() }
        return vm
    }
}

// MARK: - 结果行（SEARCH_CONTRACT §2.9）

private struct SearchResultRow: View {
    let row: NoteSearchResult
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // 标题**不做命中高亮**（§2.4）：标题本身就是 primary 色，
            // 把命中区间也提为 primary 是零效果。
            Text(card.displayTitle).font(.headline).lineLimit(1)

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                // G2：出处图标放常驻 20pt 槽位，只有图标本身显隐 ——
                // 否则有无出处的行之间 excerpt 左边缘会来回跳。
                ZStack {
                    if let icon = Self.sourceIcon(row.source) {
                        Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 20, height: 20)

                highlighted(row.excerpt)
                    .font(.subheadline)
                    .lineLimit(2)          // §2.2：恒为 2 行，Dynamic Type 下也不增行
            }

            HStack(spacing: AppSpacing.sm) {
                if let folder = card.folder {
                    Label(folder.name, systemImage: folder.iconName)
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(Format.relative(card.updatedAt)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        // 6.6：整行合成**一个**可聚焦元素，朗读顺序由检索层给定
        // （标题 → 来源 → 命中片段 → 文件夹 → 时间）。
        // 不合并的话，来源图标会被读成一个没有标签的元素，而且一行要划五次。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SearchPresentation.accessibilityLabel(
            row: row,
            title: card.displayTitle,
            folderName: card.folder?.name,
            relativeTime: Format.relative(card.updatedAt)))
        .accessibilityHint("打开这条笔记并定位到命中的位置")
        .accessibilityAddTraits(.isButton)
    }

    /// §2.8：来源图标标示「这段文字来自哪里」—— 它是内容出处，不是 AI 术语。
    /// 纯文本命中没有图标（默认形态）。
    private static func sourceIcon(_ source: RetrievalSource) -> String? {
        switch source {
        case .text: return nil
        case .transcript: return "waveform"
        case .ocr: return "photo"
        case .extracted: return "doc"
        case .link: return "link"
        }
    }

    /// §2.4 对比式前景高亮：命中片段用 `primary`，上下文压暗为 `secondary`，
    /// **无背景色块、字重不变**。高亮区间由检索层给出，UI 侧不重新做字符串搜索 ——
    /// 否则高亮会与实际命中不一致，而"解释相关性"的可信度全在这里。
    private func highlighted(_ excerpt: Excerpt) -> Text {
        let chars = Array(excerpt.text)
        var out = AttributedString()
        var cursor = 0
        for range in excerpt.highlights {
            if range.start > cursor {
                var seg = AttributedString(String(chars[cursor..<min(range.start, chars.count)]))
                seg.foregroundColor = .secondary
                out += seg
            }
            let end = min(range.end, chars.count)
            if range.start < end {
                var seg = AttributedString(String(chars[range.start..<end]))
                seg.foregroundColor = .primary
                out += seg
            }
            cursor = max(cursor, end)
        }
        if cursor < chars.count {
            var seg = AttributedString(String(chars[cursor...]))
            seg.foregroundColor = .secondary
            out += seg
        }
        return Text(out)
    }
}

// MARK: - 状态条（SEARCH_CONTRACT §4.4）

private struct SearchStatusBar: View {
    let capability: RetrievalCapability
    /// 云端已配好、只差同意。改变的是**动作的名字**，不是状态本身 ——
    /// capability 仍然是 `semanticUnavailable`（对结果区的含义完全一样）。
    var needsCloudConsent: Bool = false
    let onRetry: () -> Void

    var body: some View {
        // `full` 时组件**不存在于层级中**，不是"隐藏变体" —— 避免零高度幽灵视图。
        if capability != .full {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.tertiary)
                Text(Copy.statusMessage(capability)).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if capability == .semanticUnavailable {
                    Button(needsCloudConsent ? "开启" : "重试", action: onRetry).font(.footnote)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
        }
    }

    private var icon: String {
        switch capability {
        case .full: return ""
        case .indexBuilding, .indexRebuilding: return "clock"
        case .semanticUnavailable: return "exclamationmark.triangle"
        case .offline: return "wifi.slash"
        }
    }
}

// MARK: - 空 query 的建议区

/// 空 query 是教会用户「这个框不止能搜关键词」的**唯一时机**
/// （`SEARCH_CONTRACT.md` §10 的 12 屏定案）。三条示例可直接点。
private struct IdleSuggestions: View {
    let onPick: (String) -> Void

    private let examples = [
        "我之前问学校能不能晚一点毕业的事情",
        "上次会议说的排期结论",
        "那张写着答辩时间的照片"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("试试这样搜").font(.subheadline).foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button { onPick(example) } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "text.bubble").font(.system(size: 14)).foregroundStyle(.tertiary)
                        Text(example).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("可以搜标题、文字、转写稿、图片里的字、文档正文与链接。")
                .font(.footnote).foregroundStyle(.tertiary)
                .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 用户侧文案

/// §1.1.1 禁用词表：`embedding` / 向量 / 余弦 / RRF / 融合 / chunk / 分块 /
/// Recall@K / index / rerank / top-k / 语义检索 / semantic / contentHash / stale
/// **不得出现在任何用户可见文案里**。这里只用「智能搜索」「相关内容」「正在准备」
/// 「按关键词搜索」。
private enum Copy {

    static func statusMessage(_ capability: RetrievalCapability) -> String {
        switch capability {
        case .full: return ""
        // Correction 3：不显示百分比，用 indeterminate 文案。
        case .indexBuilding: return "正在准备智能搜索…"
        case .indexRebuilding: return "正在更新搜索数据…"
        case .semanticUnavailable: return "智能搜索暂不可用，已按关键词搜索"
        case .offline: return "离线中，已按关键词搜索"
        }
    }

    /// §4.5：空结果文案**必须按能力分叉** —— 否则用户无法区分「真的没有」和
    /// 「系统还没准备好」。这是搜索类产品最常见的信任流失点。
    static func noResultsTitle(_ capability: RetrievalCapability) -> String {
        switch capability {
        case .indexBuilding, .indexRebuilding: return "暂时没有找到"
        case .full, .semanticUnavailable, .offline: return "没有找到匹配的笔记"
        }
    }

    static func noResultsMessage(_ capability: RetrievalCapability) -> String {
        switch capability {
        case .full: return "换个说法试试。"
        case .indexBuilding, .indexRebuilding: return "智能搜索还在准备中，稍后可能会有更多结果。"
        case .semanticUnavailable, .offline: return "当前只能按关键词搜索，换个关键词试试。"
        }
    }
}
