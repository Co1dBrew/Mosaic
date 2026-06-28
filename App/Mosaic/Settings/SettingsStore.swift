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
            // Reset model & vision to the new provider's defaults if appropriate.
            if provider != .custom, !provider.recommendedModels.contains(modelName) {
                modelName = provider.defaultModel
            }
            visionEnabled = provider.defaultSupportsVision
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

    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloudSync) }
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

    init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainService()) {
        self.defaults = defaults
        self.keychain = keychain

        let providerRaw = defaults.string(forKey: Keys.provider) ?? AIProvider.kimi.rawValue
        let resolvedProvider = AIProvider(rawValue: providerRaw) ?? .kimi
        self.provider = resolvedProvider
        self.modelName = defaults.string(forKey: Keys.modelName) ?? resolvedProvider.defaultModel
        self.customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        self.autoUpdateSummary = defaults.object(forKey: Keys.autoUpdate) as? Bool ?? true
        self.hasAcceptedAIPrivacyNotice = defaults.bool(forKey: Keys.privacyAccepted)
        self.iCloudSyncEnabled = defaults.object(forKey: Keys.iCloudSync) as? Bool ?? true
        self.visionEnabled = defaults.object(forKey: Keys.visionEnabled) as? Bool ?? resolvedProvider.defaultSupportsVision
        self.jsonModeEnabled = defaults.object(forKey: Keys.jsonMode) as? Bool ?? true
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

    var hasAPIKey: Bool {
        !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Resolved config

    /// The resolved base URL for the current provider.
    var resolvedBaseURL: String {
        provider.defaultBaseURL ?? customBaseURL
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
        static let visionEnabled = "settings.visionEnabled"
        static let jsonMode = "settings.jsonModeEnabled"
    }
}
