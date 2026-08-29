import Foundation

/// User-facing AI errors. Each case carries a localized, actionable message
/// (PRD §4.5 failure/edge handling, §4.7 test connection).
public enum AIError: Error, Equatable, Sendable {
    case offline
    case missingAPIKey
    case missingModel
    case invalidBaseURL
    case unauthorized            // 401/403 — bad key
    case rateLimited             // 429 / quota
    case serverError(status: Int, body: String?)
    case emptyContent            // nothing to summarize
    case changeTooSmall          // skipped auto update
    case invalidJSON(raw: String?)
    case visionUnsupported       // model can't accept images
    case requestFailed(message: String)
    case timedOut
    case cancelled

    /// Short, user-facing description (Chinese-first, matching app UI language).
    public var userMessage: String {
        switch self {
        case .offline:
            return "网络未连接，AI 总结需要联网。请检查网络后重试。"
        case .missingAPIKey:
            return "尚未设置 API Key，请前往「设置」填写。"
        case .missingModel:
            return "尚未选择模型，请前往「设置」配置。"
        case .invalidBaseURL:
            return "服务地址(Base URL)无效，请前往「设置」检查。"
        case .unauthorized:
            return "API Key 无效或无权限，请前往「设置」检查 Key。"
        case .rateLimited:
            return "请求过于频繁或额度不足,请稍后重试或检查账户额度。"
        case let .serverError(status, _):
            return "服务返回错误(HTTP \(status))，请稍后重试。"
        case .emptyContent:
            return "内容太少,暂无可总结的内容。"
        case .changeTooSmall:
            return "本次改动较小,已跳过自动更新总结。"
        case .invalidJSON:
            return "AI 返回的内容无法解析,请重试。"
        case .visionUnsupported:
            return "当前模型不支持图片输入,已改为仅用文字总结。"
        case let .requestFailed(message):
            return "请求失败:\(message)"
        case .timedOut:
            return "请求超时,请重试。"
        case .cancelled:
            return "已取消。"
        }
    }

    /// 这条错误要不要给「去设置」。
    ///
    /// 判断从 `SummaryStickerView` 里搬上来：它原本是 View 里的一个 `switch`，
    /// 而「哪些错误是配置问题」是错误自身的性质 —— 放在 View 里意味着每个消费它的
    /// 界面都要再写一遍，两处迟早会不一致（v2 的笔记页就是第二处）。
    public var isConfiguration: Bool {
        switch self {
        case .missingAPIKey, .missingModel, .invalidBaseURL, .unauthorized:
            return true
        case .offline, .rateLimited, .serverError, .emptyContent, .changeTooSmall,
             .invalidJSON, .visionUnsupported, .requestFailed, .timedOut, .cancelled:
            return false
        }
    }

    /// Whether offering a "retry" action makes sense for this error.
    public var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited, .serverError, .invalidJSON, .requestFailed, .timedOut:
            return true
        case .missingAPIKey, .missingModel, .invalidBaseURL, .unauthorized,
             .emptyContent, .changeTooSmall, .visionUnsupported, .cancelled:
            return false
        }
    }
}
