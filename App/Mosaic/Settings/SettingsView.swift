import SwiftUI
import MosaicKit

/// Settings (PRD §4.7 / §4.10): provider, API key (Keychain), model, test
/// connection, auto-update toggle, vision/JSON options, iCloud, and privacy.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsEnv
    @Environment(\.summaryService) private var summaryService

    @State private var apiKeyDraft = ""
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

            Section("摘要设置") {
                Toggle("内容变更后自动追加更新总结", isOn: $settings.autoUpdateSummary)
                Toggle("发送图片给 AI(视觉理解)", isOn: $settings.visionEnabled)
                Toggle("使用 JSON 输出模式", isOn: $settings.jsonModeEnabled)
            }

            Section {
                Toggle("启用 iCloud 同步", isOn: $settings.iCloudSyncEnabled)
            } header: {
                Text("同步与数据")
            } footer: {
                Text("iCloud 同步需要付费 Apple 开发者账号(并在工程中开启 iCloud/CloudKit 能力)。免费个人账号请保持关闭。更改后需重启 App 生效。")
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
                Text("首次生成总结前会弹窗告知:文字内容与图片会通过 HTTPS 发送到你选择的第三方 AI 服务;原始录音不会上传(改用本地转写文字)。")
            }

            Section("关于") {
                LabeledContent("应用", value: "万象记 Mosaic")
                LabeledContent("版本", value: appVersion)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKeyDraft = settings.currentAPIKey }
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
