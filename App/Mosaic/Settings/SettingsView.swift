import SwiftUI
import MosaicKit

/// # 设置（第一屏 · `UI_REDESIGN.md` v2 §6）
///
/// v2 把设置分成两层：**第一屏只放真正需要决策的项**，其余进「高级」。
/// 之前是一屏平铺 8 个 Section，其中大部分（视觉开关 / JSON 模式 / STT 覆盖 /
/// Embedding 维度）一辈子只会被改一次，却和「API Key」抢同一屏的注意力。
///
/// **例外**：服务商 = 自定义时，`Base URL` 与 `模型名` 自动提升回第一屏 ——
/// 那时它们不是高级选项，而是必填项，藏起来会让人以为填了 Key 就能用。
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsEnv
    @Environment(AppRouter.self) private var router
    @Environment(\.summaryService) private var summaryService

    @State private var apiKeyDraft = ""
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        @Bindable var settings = settingsEnv

        Form {
            Section {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .accessibilityIdentifier("settings.provider")

                // 自定义服务商：Base URL 与模型名是必填项，提升回第一屏。
                if settings.provider == .custom {
                    TextField("Base URL", text: $settings.customBaseURL,
                              prompt: Text("https://.../v1"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("模型名称", text: $settings.modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                SecureField("API Key", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: apiKeyDraft) { _, newValue in
                        settings.setAPIKey(newValue, for: settings.provider)
                    }
                    .accessibilityIdentifier("settings.apiKey")

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
                    Text("连接成功！").font(.footnote).foregroundStyle(.green)
                }
            } header: {
                Text("AI 服务商")
            } footer: {
                Text("Key 仅安全保存在本机钥匙串（Keychain），不会明文落盘或上传我方服务器。调用费用由你的账户承担。")
            }

            Section("摘要") {
                Toggle("内容变更后自动追加更新总结", isOn: $settings.autoUpdateSummary)
                    .accessibilityIdentifier("settings.autoUpdate")
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
            } header: {
                Text("语音转写")
            } footer: {
                if settings.transcriptionMode == .cloudAPI {
                    Text("API 云端转写会把录音音频上传到所选服务商进行识别。首次会弹窗征得同意。Apple 本地转写不上传音频。")
                } else {
                    Text("Apple 本地转写在设备上完成，不上传音频，可离线，隐私更好；但准确率可能不及云端。")
                }
            }

            Section {
                Button {
                    router.push(.advancedSettings)
                } label: {
                    HStack {
                        Text("高级").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("settings.advanced")
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func testConnection() {
        // 「测试连接」只发一个无内容的 ping（不含笔记正文与图片），
        // 所以它**不**走内容隐私同意闸门 —— PRD §6.1 的同意是围绕内容外发的。
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
