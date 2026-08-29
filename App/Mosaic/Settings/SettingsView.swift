import SwiftUI
import MosaicKit

/// Settings (PRD §4.7 / §4.10): provider, API key (Keychain), model, test
/// connection, auto-update toggle, vision/JSON options, iCloud, and privacy.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsEnv
    /// 同步的**真实**状态，由 `MosaicApp` 注入。设置页不自己推导，也不读用户偏好。
    @Environment(\.cloudSyncState) private var cloudSyncState
    @Environment(\.summaryService) private var summaryService

    @State private var apiKeyDraft = ""
    @State private var sttKeyDraft = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        @Bindable var settings = settingsEnv

        Form {
            Section("AI 服务商") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Base URL", text: $settings.customBaseURL, prompt: Text(settings.provider.defaultBaseURL ?? "https://.../v1"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if settings.provider == .kimi {
                        Text("Kimi 国内 Key 请改用 https://api.moonshot.cn/v1")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    TextField("模型名称", text: $settings.modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !settings.provider.recommendedModels.isEmpty {
                        Menu {
                            ForEach(settings.provider.recommendedModels, id: \.self) { model in
                                Button(model) { settings.modelName = model }
                            }
                        } label: { Image(systemName: "list.bullet") }
                    }
                }
            }

            Section {
                SecureField("API Key", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: apiKeyDraft) { _, newValue in
                        settings.setAPIKey(newValue, for: settings.provider)
                    }
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(testState == .testing)
                if case let .failure(message) = testState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                } else if testState == .success {
                    Text("连接成功!").font(.footnote).foregroundStyle(.green)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Key 仅安全保存在本机钥匙串(Keychain),不会明文落盘或上传我方服务器。调用费用由你的账户承担。")
            }

            // 注：这一段的字段名刻意保留 Embedding 等英文原词 —— 用户是照着服务商
            // 文档填参数，改成「智能搜索模型」反而对不上。§1.1.1 的禁用词表约束的是
            // **搜索产品界面**的叙述性文案（本段的标题与说明已按它改写）。
            Section {
                TextField("Embedding 模型", text: $settings.embeddingModel, prompt: Text("text-embedding-3-small"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Embedding 维度", value: $settings.embeddingDimension, format: .number)
                    .keyboardType(.numberPad)
                TextField("Embedding Base URL（留空复用上方）",
                          text: $settings.embeddingBaseURLOverride,
                          prompt: Text(settings.resolvedBaseURL))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("允许把笔记文字发送到云端以启用智能搜索",
                       isOn: $settings.hasAcceptedCloudEmbeddingNotice)
            } header: {
                Text("智能搜索")
            } footer: {
                // §1.1.1 用户侧禁用词表：这里是用户可见的设置页，
                // 不能出现「语义检索 / 向量 / embedding」。字段名保留英文是因为
                // 它们是用户要照着服务商文档填的参数，不是产品概念。
                Text("纯英文笔记优先使用本机模型(离线、不上传)。笔记含中文且本机没有可离线使用的中文模型时,需要打开上面的开关才会把笔记文字发送到你配置的第三方服务;开关关闭时只按关键词搜索,不会发送任何内容。Kimi / DeepSeek 若未提供 /v1/embeddings 接口,请把 Base URL 指到支持该接口的地址。")
            }

            Section("摘要设置") {
                Toggle("内容变更后自动追加更新总结", isOn: $settings.autoUpdateSummary)
                Toggle("发送图片给 AI(视觉理解)", isOn: $settings.visionEnabled)
                Toggle("使用 JSON 输出模式", isOn: $settings.jsonModeEnabled)
            }

            Section {
                Picker("转写方式", selection: $settings.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("识别语言", selection: $settings.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                if settings.transcriptionMode == .cloudAPI {
                    TextField("STT 模型(如 whisper-1)", text: $settings.sttModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("STT Base URL(留空复用上方)", text: $settings.sttBaseURLOverride, prompt: Text(settings.resolvedBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("STT API Key(留空复用上方 Key)", text: $sttKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: sttKeyDraft) { _, newValue in settings.sttAPIKey = newValue }
                    if settings.hasAcceptedAudioUploadNotice {
                        Button("重置音频上传同意状态") { settings.hasAcceptedAudioUploadNotice = false }
                    }
                }
            } header: {
                Text("语音转写")
            } footer: {
                if settings.transcriptionMode == .cloudAPI {
                    Text("API 云端转写会把录音音频上传到所选服务商进行识别(需该服务支持 OpenAI 兼容的 /audio/transcriptions,如 Whisper)。首次会弹窗征得同意。Apple 本地转写不上传音频。")
                } else {
                    Text("Apple 本地转写在设备上完成,不上传音频,可离线,隐私更好;但准确率可能不及云端。可切换为「API 云端转写」。")
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
                    // 是留一个陷阱（`DECISION_CONFIG: ICLOUD = DISABLE_UNTIL_REAL_CLOUDKIT_READY`）。
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
                    Button("重置隐私同意状态") {
                        settings.hasAcceptedAIPrivacyNotice = false
                    }
                }
            } header: {
                Text("隐私")
            } footer: {
                Text("首次生成总结前会弹窗告知:文字内容与图片会通过 HTTPS 发送到你选择的第三方 AI 服务;原始录音不会上传(改用本地转写文字)。智能搜索默认只在本机进行;只有你在上方明确开启后,笔记文字才会发送到同一套服务。")
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

            Section("关于") {
                LabeledContent("应用", value: "万象记 Mosaic")
                LabeledContent("版本", value: appVersion)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKeyDraft = settings.currentAPIKey; sttKeyDraft = settings.sttAPIKey }
        .onChange(of: settings.provider) { _, _ in
            apiKeyDraft = settings.currentAPIKey
            testState = .idle
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    private func testConnection() {
        // Test connection sends only a trivial "ping" (no card content or images),
        // so it is intentionally not behind the content privacy notice (PRD §6.1
        // frames consent around card-content egress).
        guard let summaryService else { testState = .failure("服务不可用"); return }
        testState = .testing
        Task { @MainActor in
            do {
                try await summaryService.testConnection()
                testState = .success
            } catch let error as AIError {
                testState = .failure(error.userMessage)
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
