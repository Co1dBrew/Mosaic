import Foundation
import Observation
import MosaicKit

/// App settings (PRD §4.7 / §8 Settings). Backed by `UserDefaults`, with the
/// API key kept in the Keychain (PRD §6.1 — never in plain text). The key is
/// stored per provider so switching providers does not clobber a saved key.
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStoring

    // MARK: Persisted values

    var provider: AIProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Keys.provider)
            // Reset model, vision, and base URL to the new provider's defaults.
            if provider != .custom, !provider.recommendedModels.contains(modelName) {
                modelName = provider.defaultModel
            }
            visionEnabled = provider.defaultSupportsVision
            // Prefill the editable base URL with the new provider's default so the
            // user can see and (if needed) override it — e.g. switch a China-region
            // Kimi key to https://api.moonshot.cn/v1.
            customBaseURL = provider.defaultBaseURL ?? ""
        }
    }

    var modelName: String {
        didSet { defaults.set(modelName, forKey: Keys.modelName) }
    }

    var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Keys.customBaseURL) }
    }

    var autoUpdateSummary: Bool {
        didSet { defaults.set(autoUpdateSummary, forKey: Keys.autoUpdate) }
    }

    var hasAcceptedAIPrivacyNotice: Bool {
        didSet { defaults.set(hasAcceptedAIPrivacyNotice, forKey: Keys.privacyAccepted) }
    }

    /// Developer Mode。**默认 OFF** —— 首次安装 / TestFlight / App Store 一律关闭
    /// （`design/DEVTOOLS.md` §1.2）。关闭时「开发者工具」整行不出现，而不是置灰：
    /// 置灰会让普通用户去猜它是什么，反而制造好奇。
    var developerModeEnabled: Bool {
        didSet { defaults.set(developerModeEnabled, forKey: Keys.developerMode) }
    }

    /// 用户的**意愿**。它不是「有没有在同步」—— 后者要看容器实际上是不是
    /// CloudKit 支撑的，读 `MosaicApp` 注入的 `cloudSyncState`。
    ///
    /// 写入时收敛到这个构建允许的取值：装了不带 CloudKit 的构建之后，
    /// 上一个构建存下的 `true` 不能继续让 UI 显示「已开启」。
    var iCloudSyncEnabled: Bool {
        didSet {
            let sanitized = CloudSyncPolicy.sanitizedUserPreference(
                iCloudSyncEnabled, buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit)
            if sanitized != iCloudSyncEnabled { iCloudSyncEnabled = sanitized; return }
            defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSync)
        }
    }

    /// Whether to send images as vision input. Defaults to the provider's known
    /// capability; user-adjustable for custom/uncertain providers (PRD §5.4).
    var visionEnabled: Bool {
        didSet { defaults.set(visionEnabled, forKey: Keys.visionEnabled) }
    }

    /// Whether to request `response_format: json_object` (PRD §5.6).
    var jsonModeEnabled: Bool {
        didSet { defaults.set(jsonModeEnabled, forKey: Keys.jsonMode) }
    }

    // MARK: Transcription (PRD §4.3.2 + switchable architecture)

    /// Local Apple Speech (default, privacy-friendly) vs cloud API STT.
    var transcriptionMode: TranscriptionMode {
        didSet { defaults.set(transcriptionMode.rawValue, forKey: Keys.transcriptionMode) }
    }

    var transcriptionLanguage: TranscriptionLanguage {
        didSet { defaults.set(transcriptionLanguage.rawValue, forKey: Keys.transcriptionLanguage) }
    }

    /// Cloud STT model (e.g. "whisper-1").
    var sttModel: String {
        didSet { defaults.set(sttModel, forKey: Keys.sttModel) }
    }

    /// Optional cloud STT base URL; empty = reuse the AI provider's base URL.
    var sttBaseURLOverride: String {
        didSet { defaults.set(sttBaseURLOverride, forKey: Keys.sttBaseURLOverride) }
    }

    /// Consent to upload audio for cloud transcription (separate from the content
    /// privacy notice — audio leaves the device only in cloud mode).
    var hasAcceptedAudioUploadNotice: Bool {
        didSet { defaults.set(hasAcceptedAudioUploadNotice, forKey: Keys.audioUploadAccepted) }
    }

    // MARK: Cloud embedding（中文语义在 iOS 上的退路）

    /// OpenAI 兼容 `/v1/embeddings` 的模型名。留空则云端路线不可用。
    var embeddingModel: String {
        didSet { defaults.set(embeddingModel, forKey: Keys.embeddingModel) }
    }

    /// 声明维度，必须与服务端返回一致。维度不符宁可不写进索引。
    var embeddingDimension: Int {
        didSet { defaults.set(embeddingDimension, forKey: Keys.embeddingDimension) }
    }

    /// 可选；空 = 复用上方 AI 服务商的 Base URL。
    var embeddingBaseURLOverride: String {
        didSet { defaults.set(embeddingBaseURLOverride, forKey: Keys.embeddingBaseURLOverride) }
    }

    /// 用户是否已明确同意「把笔记文字发到云端做智能搜索」。
    ///
    /// **与 `hasAcceptedAIPrivacyNotice` 分开**：摘要是用户主动点一次、发一篇；
    /// 这里是启动后台自动跑、发**整库**。用较轻的授权去换较重的行为，
    /// 是这类隐私事故最常见的形态。默认 false。
    var hasAcceptedCloudEmbeddingNotice: Bool {
        didSet { defaults.set(hasAcceptedCloudEmbeddingNotice, forKey: Keys.cloudEmbeddingAccepted) }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainService()) {
        self.defaults = defaults
        self.keychain = keychain

        let providerRaw = defaults.string(forKey: Keys.provider) ?? AIProvider.kimi.rawValue
        let resolvedProvider = AIProvider(rawValue: providerRaw) ?? .kimi
        self.provider = resolvedProvider
        self.modelName = defaults.string(forKey: Keys.modelName) ?? resolvedProvider.defaultModel
        let storedBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        // Prefill from the provider default on first run so the field is never blank.
        self.customBaseURL = storedBaseURL.isEmpty ? (resolvedProvider.defaultBaseURL ?? "") : storedBaseURL
        self.autoUpdateSummary = defaults.object(forKey: Keys.autoUpdate) as? Bool ?? true
        self.hasAcceptedAIPrivacyNotice = defaults.bool(forKey: Keys.privacyAccepted)
        // Default OFF: iCloud/CloudKit requires a paid Apple Developer account.
        // The schema stays CloudKit-ready; enable this after adding the iCloud
        // capability + entitlements (see Mosaic.entitlements) and flipping
        // `MosaicCloudKitEnabled` in project.yml.
        self.iCloudSyncEnabled = CloudSyncPolicy.sanitizedUserPreference(
            defaults.object(forKey: Keys.iCloudSync) as? Bool ?? false,
            buildSupportsCloudKit: ModelContainerFactory.buildSupportsCloudKit)
        self.developerModeEnabled = defaults.object(forKey: Keys.developerMode) as? Bool ?? false
        self.visionEnabled = defaults.object(forKey: Keys.visionEnabled) as? Bool ?? resolvedProvider.defaultSupportsVision
        self.jsonModeEnabled = defaults.object(forKey: Keys.jsonMode) as? Bool ?? true

        self.transcriptionMode = TranscriptionMode(rawValue: defaults.string(forKey: Keys.transcriptionMode) ?? "") ?? .localAppleSpeech
        self.transcriptionLanguage = TranscriptionLanguage(rawValue: defaults.string(forKey: Keys.transcriptionLanguage) ?? "") ?? .auto
        self.sttModel = defaults.string(forKey: Keys.sttModel) ?? "whisper-1"
        self.sttBaseURLOverride = defaults.string(forKey: Keys.sttBaseURLOverride) ?? ""
        self.hasAcceptedAudioUploadNotice = defaults.bool(forKey: Keys.audioUploadAccepted)

        self.embeddingModel = defaults.string(forKey: Keys.embeddingModel) ?? "text-embedding-3-small"
        self.embeddingDimension = defaults.object(forKey: Keys.embeddingDimension) as? Int ?? 1536
        self.embeddingBaseURLOverride = defaults.string(forKey: Keys.embeddingBaseURLOverride) ?? ""
        self.hasAcceptedCloudEmbeddingNotice = defaults.bool(forKey: Keys.cloudEmbeddingAccepted)
    }

    // MARK: Cloud transcription config

    /// Builds a `CloudTranscriptionConfig`, reusing the AI provider's API key and
    /// (unless overridden) base URL.
    func makeCloudTranscriptionConfig() -> Result<CloudTranscriptionConfig, TranscriptionError> {
        let base = sttBaseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let sttKey = sttAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = CloudTranscriptionConfig(
            baseURL: base.isEmpty ? resolvedBaseURL : base,
            model: sttModel,
            apiKey: sttKey.isEmpty ? currentAPIKey : sttKey,
            languageHint: transcriptionLanguage.apiLanguageHint
        )
        if let error = config.validationError { return .failure(error) }
        return .success(config)
    }

    // MARK: API key (Keychain)

    func apiKey(for provider: AIProvider) -> String {
        keychain.string(for: KeychainAccount.apiKey(for: provider)) ?? ""
    }

    var currentAPIKey: String {
        get { apiKey(for: provider) }
        set { try? keychain.setString(newValue, for: KeychainAccount.apiKey(for: provider)) }
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        try? keychain.setString(key, for: KeychainAccount.apiKey(for: provider))
    }

    /// Optional separate API key for cloud STT (empty = reuse the chat provider key).
    var sttAPIKey: String {
        get { keychain.string(for: KeychainAccount.sttAPIKey) ?? "" }
        set { try? keychain.setString(newValue, for: KeychainAccount.sttAPIKey) }
    }

    var hasAPIKey: Bool {
        !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 云端 embedding 是否具备最小配置（Key + 模型 + URL）。
    /// 不在这里构造 provider —— 构造会把 Key 拷进内存里的请求对象。
    var isCloudEmbeddingConfigured: Bool {
        let key = currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = embeddingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && !model.isEmpty && !base.isEmpty && embeddingDimension > 0
    }

    var embeddingBaseURL: String {
        let override = embeddingBaseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? resolvedBaseURL : override
    }

    /// 构造云端 provider。**同意闸门在这里，不在调用方** ——
    /// 放在调用方就意味着「每一个新调用点都要记得检查」，那种约定迟早会漏。
    func makeCloudEmbeddingProvider() -> Result<any EmbeddingProvider, EmbeddingProviderError> {
        guard isCloudEmbeddingConfigured else {
            return .failure(.unavailable("未配置云端 embedding（需要 API Key、模型名和 Base URL）"))
        }
        guard hasAcceptedCloudEmbeddingNotice else {
            return .failure(.unavailable("尚未同意把笔记文字发送到云端"))
        }
        return .success(CloudEmbeddingProvider(baseURL: embeddingBaseURL,
                                               apiKey: currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                               model: embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines),
                                               dimension: embeddingDimension))
    }

    // MARK: Resolved config

    /// The resolved base URL: the user's (possibly edited) value, falling back to
    /// the provider default. Editable for all providers so region-specific keys
    /// (e.g. Kimi 国内 → https://api.moonshot.cn/v1) work.
    var resolvedBaseURL: String {
        let trimmed = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (provider.defaultBaseURL ?? "") : trimmed
    }

    /// Builds a `ProviderConfig` for an AI request, or returns the validation
    /// error explaining what's missing.
    func makeProviderConfig() -> Result<ProviderConfig, AIError> {
        let config = ProviderConfig(
            provider: provider,
            baseURL: resolvedBaseURL,
            model: modelName,
            apiKey: currentAPIKey,
            supportsVision: visionEnabled,
            useJSONMode: jsonModeEnabled,
            temperature: 0.2
        )
        if let error = config.validationError { return .failure(error) }
        return .success(config)
    }

    private enum Keys {
        static let provider = "settings.provider"
        static let modelName = "settings.modelName"
        static let customBaseURL = "settings.customBaseURL"
        static let autoUpdate = "settings.autoUpdateSummary"
        static let privacyAccepted = "settings.hasAcceptedAIPrivacyNotice"
        static let iCloudSync = "settings.iCloudSyncEnabled"
        static let developerMode = "settings.developerModeEnabled"
        static let visionEnabled = "settings.visionEnabled"
        static let jsonMode = "settings.jsonModeEnabled"
        static let transcriptionMode = "settings.transcriptionMode"
        static let transcriptionLanguage = "settings.transcriptionLanguage"
        static let sttModel = "settings.sttModel"
        static let sttBaseURLOverride = "settings.sttBaseURLOverride"
        static let audioUploadAccepted = "settings.hasAcceptedAudioUploadNotice"
        static let embeddingModel = "settings.embeddingModel"
        static let embeddingDimension = "settings.embeddingDimension"
        static let embeddingBaseURLOverride = "settings.embeddingBaseURLOverride"
        static let cloudEmbeddingAccepted = "settings.hasAcceptedCloudEmbeddingNotice"
    }
}
