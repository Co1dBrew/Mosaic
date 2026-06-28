import Foundation

/// A fully resolved configuration used to make a single AI request.
/// The API key is passed explicitly (loaded from Keychain by the app) and is
/// never persisted as part of this value.
public struct ProviderConfig: Equatable, Sendable {
    public var provider: AIProvider
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public var supportsVision: Bool
    public var useJSONMode: Bool
    public var temperature: Double

    public init(
        provider: AIProvider,
        baseURL: String,
        model: String,
        apiKey: String,
        supportsVision: Bool,
        useJSONMode: Bool,
        temperature: Double = 0.2
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.supportsVision = supportsVision
        self.useJSONMode = useJSONMode
        // Clamp temperature into the provider's allowed range.
        self.temperature = min(max(temperature, 0), provider.temperatureMax)
    }

    /// Builds the `/chat/completions` endpoint URL from `baseURL`, tolerating
    /// trailing slashes and base URLs that already include the endpoint path.
    public var chatCompletionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = trimmed
        while normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasSuffix("/chat/completions") {
            return URL(string: normalized)
        }
        return URL(string: normalized + "/chat/completions")
    }

    /// Validates that the configuration has the minimum required fields.
    public var validationError: AIError? {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingAPIKey
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingModel
        }
        if chatCompletionsURL == nil {
            return .invalidBaseURL
        }
        return nil
    }
}
