import Foundation

/// The selectable AI service providers. All are OpenAI Chat Completions compatible.
/// See PRD §4.7 / §7.2.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case kimi
    case deepseek
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kimi: return "Kimi (Moonshot)"
        case .deepseek: return "DeepSeek"
        case .custom: return "自定义 / Custom"
        }
    }

    /// Default base URL up to (but not including) `/chat/completions`.
    /// `nil` for `.custom`, where the user supplies it.
    public var defaultBaseURL: String? {
        switch self {
        case .kimi: return "https://api.moonshot.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .custom: return nil
        }
    }

    /// Recommended model names (developer should verify against latest docs).
    public var recommendedModels: [String] {
        switch self {
        case .kimi: return ["kimi-k2.6"]
        case .deepseek: return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .custom: return []
        }
    }

    public var defaultModel: String {
        recommendedModels.first ?? ""
    }

    /// Whether the provider's recommended model is known to accept image input.
    /// Kimi K2.x supports vision; DeepSeek vision must be verified, so we default
    /// to `false` (safe degradation per PRD §5.4). Custom is user-configurable.
    public var defaultSupportsVision: Bool {
        switch self {
        case .kimi: return true
        case .deepseek: return false
        case .custom: return false
        }
    }

    /// Maximum allowed `temperature`. Kimi/Moonshot caps at 1.0 (PRD §5.6).
    public var temperatureMax: Double {
        switch self {
        case .kimi: return 1.0
        case .deepseek, .custom: return 2.0
        }
    }

    /// Whether `response_format: {"type":"json_object"}` should be sent by default.
    /// Built-in providers support it. For custom providers the user can disable it.
    public var defaultSupportsJSONMode: Bool {
        switch self {
        case .kimi, .deepseek: return true
        case .custom: return true
        }
    }
}
