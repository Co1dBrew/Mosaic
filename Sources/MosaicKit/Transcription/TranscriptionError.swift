import Foundation

/// User-facing transcription errors covering both local and cloud modes.
public enum TranscriptionError: Error, Equatable, Sendable {
    // Consent / config
    case consentMissing          // cloud mode without audio-upload consent
    case missingAPIKey
    case invalidBaseURL
    // Local (Apple Speech)
    case notAuthorized
    case localUnavailable        // on-device recognizer/locale not available
    // Cloud transport / HTTP
    case offline
    case timedOut
    case cancelled
    case unauthorized            // 401/403
    case unsupportedProvider     // 404 / endpoint missing — provider has no STT
    case unsupportedFormat       // 415
    case fileTooLarge            // 413 or local size check
    case rateLimited             // 429
    case serverError(status: Int, body: String?)
    case invalidResponse(raw: String?)
    case audioUnreadable
    case requestFailed(message: String)

    public var userMessage: String {
        switch self {
        case .consentMissing:
            return "API 云端转写会上传音频到第三方服务,请先在弹窗中同意。"
        case .missingAPIKey:
            return "尚未设置 API Key,云端转写无法进行,请前往「设置」填写。"
        case .invalidBaseURL:
            return "转写服务地址无效,请前往「设置」检查。"
        case .notAuthorized:
            return "未获得语音识别权限,请在系统设置中开启。"
        case .localUnavailable:
            return "当前语言不支持本地离线识别,可在「设置」改用 API 云端转写。"
        case .offline:
            return "网络未连接,云端转写需要联网。"
        case .timedOut:
            return "转写请求超时,请重试。"
        case .cancelled:
            return "已取消转写。"
        case .unauthorized:
            return "API Key 无效或无权限,请前往「设置」检查。"
        case .unsupportedProvider:
            return "当前服务商不支持语音转写(STT),请在「设置」改用支持的服务或本地转写。"
        case .unsupportedFormat:
            return "音频格式不受支持,无法转写。"
        case .fileTooLarge:
            return "音频文件过大,无法上传转写。"
        case .rateLimited:
            return "请求过于频繁或额度不足,请稍后重试。"
        case let .serverError(status, _):
            return "转写服务返回错误(HTTP \(status)),请稍后重试。"
        case .invalidResponse:
            return "转写返回的内容无法解析,请重试。"
        case .audioUnreadable:
            return "无法读取音频文件。"
        case let .requestFailed(message):
            return "转写失败:\(message)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .serverError, .invalidResponse, .requestFailed, .localUnavailable:
            return true
        case .consentMissing, .missingAPIKey, .invalidBaseURL, .notAuthorized, .unauthorized,
             .unsupportedProvider, .unsupportedFormat, .fileTooLarge, .cancelled, .audioUnreadable:
            return false
        }
    }
}
