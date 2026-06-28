import Foundation

/// Abstraction over the AI service so the app and tests can swap implementations.
public protocol AIClient: Sendable {
    func generateBaseSummary(config: ProviderConfig, aggregatedText: String, images: [AIImage]) async throws -> BaseSummaryDTO
    func generateUpdateSummary(config: ProviderConfig, previousSummaryText: String, changeSetText: String, images: [AIImage]) async throws -> UpdateSummaryDTO
    func testConnection(config: ProviderConfig) async throws
}

/// `URLSession`-backed client for any OpenAI-compatible Chat Completions service.
/// All work happens off the main thread via async URLSession APIs (PRD §6.3).
public struct URLSessionAIClient: AIClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func generateBaseSummary(config: ProviderConfig, aggregatedText: String, images: [AIImage]) async throws -> BaseSummaryDTO {
        guard !aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            throw AIError.emptyContent
        }
        let request = try AIRequestBuilder.baseSummaryRequest(config: config, aggregatedText: aggregatedText, images: images)
        let content = try await performAndExtract(request)
        return try AIResponseParser.parseBaseSummary(fromMessage: content)
    }

    public func generateUpdateSummary(config: ProviderConfig, previousSummaryText: String, changeSetText: String, images: [AIImage]) async throws -> UpdateSummaryDTO {
        guard !changeSetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            throw AIError.changeTooSmall
        }
        let request = try AIRequestBuilder.updateSummaryRequest(config: config, previousSummaryText: previousSummaryText, changeSetText: changeSetText, images: images)
        let content = try await performAndExtract(request)
        return try AIResponseParser.parseUpdateSummary(fromMessage: content)
    }

    public func testConnection(config: ProviderConfig) async throws {
        let request = try AIRequestBuilder.testConnectionRequest(config: config)
        _ = try await performRaw(request) // status validated inside; body ignored
    }

    // MARK: - Networking

    private func performAndExtract(_ request: URLRequest) async throws -> String {
        let data = try await performRaw(request)
        return try AIResponseParser.messageContent(from: data)
    }

    /// Performs the request, mapping transport and HTTP-status failures to `AIError`.
    private func performRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw AIError.offline
            case .timedOut:
                throw AIError.timedOut
            case .cancelled:
                throw AIError.cancelled
            default:
                throw AIError.requestFailed(message: urlError.localizedDescription)
            }
        } catch {
            throw AIError.requestFailed(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.requestFailed(message: "Invalid response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw AIError.unauthorized
        case 429:
            throw AIError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8)
            // Some providers return a structured error body even on non-2xx.
            if let body, let parsed = Self.extractAPIErrorMessage(body) {
                throw AIError.serverError(status: http.statusCode, body: parsed)
            }
            throw AIError.serverError(status: http.statusCode, body: body)
        }
    }

    private static func extractAPIErrorMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? [String: Any],
              let msg = err["message"] as? String else { return nil }
        return msg
    }
}
