import SwiftUI
import MosaicKit

/// # 设置 › 高级（`UI_REDESIGN.md` v2 §6）
///
/// 收纳「一辈子只改一次」的项。它们不是不重要，而是**不该和 API Key 抢同一屏的
/// 注意力** —— 第一屏每多一行，用户第一次配置时就多一次「这个要不要动」的犹豫。
///
/// 注意：`Base URL` 与 `模型名` 在「服务商 = 自定义」时**不在这里**，
/// 它们被提升回第一屏（那时是必填项）。这条例外由第一屏实现，这里只显示
/// 非自定义服务商的可选覆盖。
struct AdvancedSettingsView: View {
    @Environment(SettingsStore.self) private var settingsEnv
    /// 同步的**真实**状态，由 `MosaicApp` 注入。设置页不自己推导，也不读用户偏好。
    @Environment(\.cloudSyncState) private var cloudSyncState

    @State private var sttKeyDraft = ""

    /// 这一屏的输入框。**`embeddingDimension` 是关键的一个** ——
    /// 它是 `numberPad`，键盘上**没有 Return 键**，
    /// 所以它只能靠键盘工具条上的「完成」退出。这也是那条工具条存在的理由。
    private enum Field: Hashable {
        case baseURL, model
        case embeddingModel, embeddingDimension, embeddingBaseURL
        case sttModel, sttBaseURL, sttKey
    }
    @FocusState private var focus: Field?

    var body: some View {
        @Bindable var settings = settingsEnv

        Form {
            if settings.provider != .custom {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Base URL", text: $settings.customBaseURL,
                                  prompt: Text(settings.provider.defaultBaseURL ?? "https://.../v1"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focus, equals: .baseURL)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                            .accessibilityIdentifier("advanced.baseURL")
                        if settings.provider == .kimi {
                            Text("Kimi 国内 Key 请改用 https://api.moonshot.cn/v1")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("模型名称", text: $settings.modelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .model)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                            .accessibilityIdentifier("advanced.modelName")
                        if !settings.provider.recommendedModels.isEmpty {
                            Menu {
                                ForEach(settings.provider.recommendedModels, id: \.self) { model in
                                    Button(model) { settings.modelName = model }
                                }
                            } label: { Image(systemName: "list.bullet") }
                        }
                    }
                } header: {
                    Text("服务地址与模型")
                } footer: {
                    Text("留空则使用所选服务商的默认值。")
                }
            }

            Section("摘要生成") {
                Toggle("发送图片给 AI（视觉理解）", isOn: $settings.visionEnabled)
                Toggle("使用 JSON 输出模式", isOn: $settings.jsonModeEnabled)
            }

            // # 「智能搜索」这一段是否出现，取决于**生产配置里有没有语义路**
            //
            // 与 iCloud 那一段同一条原则（也是同一个教训）：
            // 不给一个必然无效的开关。`PRODUCTION_RETRIEVAL = KEYWORD` 之下，
            // 这三个字段与那个同意开关对搜索行为**没有任何影响** ——
            // 语义那一整条不跑。留着它比留一个 iCloud 假开关更糟：
            // 它还要求用户授权一次「把笔记文字发到第三方」，
            // 换来的却是零变化。
            //
            // 判据取 `RetrievalConfig.production.mode`，与搜索页读的是同一个事实。
            if RetrievalConfig.production.mode.usesVector {
                // 注：这一段的字段名刻意保留 Embedding 等英文原词 —— 用户是照着服务商
                // 文档填参数，改成「智能搜索模型」反而对不上。SEARCH_CONTRACT §1.1.1 的
                // 禁用词表约束的是**搜索产品界面**的叙述性文案（标题与说明已按它改写）。
                Section {
                    TextField("Embedding 模型", text: $settings.embeddingModel,
                              prompt: Text("text-embedding-3-small"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .embeddingModel)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                    // **数字键盘没有 Return 键** —— 这一项只能靠键盘工具条的「完成」退出。
                    TextField("Embedding 维度", value: $settings.embeddingDimension, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .embeddingDimension)
                        .accessibilityIdentifier("advanced.embeddingDimension")
                    TextField("Embedding Base URL（留空复用上方）",
                              text: $settings.embeddingBaseURLOverride,
                              prompt: Text(settings.resolvedBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focus, equals: .embeddingBaseURL)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                    Toggle("允许把笔记文字发送到云端以启用智能搜索",
                           isOn: $settings.hasAcceptedCloudEmbeddingNotice)
                        .accessibilityIdentifier("settings.cloudSearchConsent")
                } header: {
                    Text("智能搜索")
                } footer: {
                    Text("纯英文笔记优先使用本机模型（离线、不上传）。笔记含中文且本机没有可离线使用的中文模型时，需要打开上面的开关才会把笔记文字发送到你配置的第三方服务；开关关闭时只按关键词搜索，不会发送任何内容。Kimi / DeepSeek 若未提供 /v1/embeddings 接口，请把 Base URL 指到支持该接口的地址。")
                }
            } else {
                Section {
                    LabeledContent("搜索方式", value: "关键词")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.search.keywordOnly")
                } header: {
                    Text("搜索")
                } footer: {
                    Text("这一版按关键词搜索，全部在本机完成，不会把笔记内容发送到任何服务。")
                }
            }

            if settings.transcriptionMode == .cloudAPI {
                Section {
                    TextField("STT 模型（如 whisper-1）", text: $settings.sttModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .sttModel)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                        .accessibilityIdentifier("advanced.sttModel")
                    TextField("STT Base URL（留空复用上方）", text: $settings.sttBaseURLOverride,
                              prompt: Text(settings.resolvedBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focus, equals: .sttBaseURL)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                    SecureField("STT API Key（留空复用上方 Key）", text: $sttKeyDraft)
                        .focused($focus, equals: .sttKey)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: sttKeyDraft) { _, newValue in settings.sttAPIKey = newValue }
                } header: {
                    Text("云端转写覆盖")
                } footer: {
                    Text("需要该服务支持 OpenAI 兼容的 /audio/transcriptions（如 Whisper）。留空则复用上方 AI 服务商的地址与 Key。")
                }
            }

            // 同步状态由**事实**推导，不是显示用户偏好。
            // 老写法是一个普通 Toggle：用户打开 → 容器申请 CloudKit 失败 →
            // 静默退回本地 → **开关还是开着的**。用户由此相信笔记有云端副本，
            // 而这件事要到换手机或误删之后才会被发现。
            Section {
                if CloudSyncPolicy.isUserToggleable(buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit) {
                    Toggle("启用 iCloud 同步", isOn: $settings.iCloudSyncEnabled)
                    LabeledContent("当前状态", value: cloudSyncState.isActuallySyncing ? "同步中" : "仅本机")
                        .foregroundStyle(cloudSyncState.isActuallySyncing ? Color.primary : .secondary)
                } else {
                    // 不可用时**不给开关**。给一个必然失败的开关不是「保留功能」，
                    // 是留一个陷阱（DECISION_CONFIG: ICLOUD = DISABLE_UNTIL_REAL_CLOUDKIT_READY）。
                    LabeledContent("iCloud 同步", value: "此版本不提供")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.icloud.unavailable")
                }
            } header: {
                Text("同步与数据")
            } footer: {
                Text(cloudSyncState.userFacingSummary
                     + (CloudSyncPolicy.isUserToggleable(buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit)
                        ? "更改后需重启 App 生效。" : "笔记可以用「导出」逐条备份。"))
            }

            Section {
                if settings.hasAcceptedAIPrivacyNotice {
                    Button("重置隐私同意状态") { settings.hasAcceptedAIPrivacyNotice = false }
                }
                if settings.hasAcceptedAudioUploadNotice {
                    Button("重置音频上传同意状态") { settings.hasAcceptedAudioUploadNotice = false }
                }
                if !settings.hasAcceptedAIPrivacyNotice && !settings.hasAcceptedAudioUploadNotice {
                    Text("尚未授予任何内容外发同意。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("隐私")
            } footer: {
                Text("首次生成总结前会弹窗告知：文字内容与图片会通过 HTTPS 发送到你选择的第三方 AI 服务；原始录音不会上传（改用本地转写文字）。智能搜索默认只在本机进行；只有你在上方明确开启后，笔记文字才会发送到同一套服务。")
            }

            // D0 —— Developer Mode 入口（design/DEVTOOLS.md §1.1）。
            // 默认 OFF；关闭时「开发者工具」整行不出现，而不是置灰。
            //
            // **整段在正式 Release 里不编译。** 之前只靠一个默认关闭的开关，
            // 于是 App Store 构建里仍然存在一条通往内部工具的路径 ——
            // 一个 UserDefaults 键就能打开它。现在 Release 里连
            // `DeveloperModeView` 这个类型都不存在。
            #if DEBUG || INTERNAL_BUILD
            Section {
                Toggle("开发者模式", isOn: $settings.developerModeEnabled)
                if settings.developerModeEnabled {
                    NavigationLink("开发者工具") { DeveloperModeView() }
                }
            } header: {
                Text("开发者")
            } footer: {
                Text("仅供开发与评测使用。开启后可进入 Retrieval Lab / Trace。")
            }
            #endif
        }
        .navigationTitle("高级")
        .navigationBarTitleDisplayMode(.inline)
        .settingsKeyboardDismissal(focus: $focus)
        .onAppear { sttKeyDraft = settings.sttAPIKey }
    }
}
