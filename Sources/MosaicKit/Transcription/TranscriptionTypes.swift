import Foundation

/// How audio is transcribed (PRD §4.3.2 + the switchable-architecture upgrade).
/// `localAppleSpeech` keeps audio on-device; `cloudAPI` uploads audio to a
/// third-party STT service (requires explicit consent).
public enum TranscriptionMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case localAppleSpeech
    case cloudAPI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localAppleSpeech: return "Apple 本地转写"
        case .cloudAPI: return "API 云端转写"
        }
    }

    /// Whether this mode uploads the original audio off-device.
    public var uploadsAudio: Bool { self == .cloudAPI }
}

/// User language preference for transcription (PRD: prioritize Chinese & English).
public enum TranscriptionLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto
    case chinese
    case english

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    /// Apple Speech locale identifier, or `nil` for "auto" (use system + fallbacks).
    public var appleLocaleIdentifier: String? {
        switch self {
        case .auto: return nil
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        }
    }

    /// Ordered Apple Speech locales to try. For `auto`, prefer the system locale
    /// then Chinese/English fallbacks.
    public func appleLocales(systemLocaleIdentifier: String) -> [String] {
        switch self {
        case .chinese: return ["zh-CN"]
        case .english: return ["en-US"]
        case .auto: return [systemLocaleIdentifier, "zh-CN", "en-US"]
        }
    }

    /// Language hint sent to a cloud STT API (`nil` = omit / let the service auto-detect).
    public var apiLanguageHint: String? {
        switch self {
        case .auto: return nil
        case .chinese: return "zh"
        case .english: return "en"
        }
    }
}
