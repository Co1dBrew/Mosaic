import Foundation

/// Assembles `URLRequest`s for the AI endpoints from a `ProviderConfig` and the
/// aggregated card content. Pure and synchronous so it is fully unit-testable.
public enum AIRequestBuilder {

    public static let baseMaxTokens = 1024
    public static let updateMaxTokens = 512
    public static let requestTimeout: TimeInterval = 60

    /// Builds the request for the initial/base summary (PRD §4.6, §5.1, §5.3).
    public static func baseSummaryRequest(
        config: ProviderConfig,
        aggregatedText: String,
        images: [AIImage]
    ) throws -> URLRequest {
        let userText = Prompts.baseUser(aggregatedCardContent: aggregatedText)
        let messages = [
            ChatRequest.Message(role: "system", content: .text(Prompts.baseSystem)),
            userMessage(text: userText, images: images, config: config)
        ]
        let body = ChatRequest(
            model: config.model,
            temperature: config.temperature,
            maxTokens: baseMaxTokens,
            responseFormatJSON: config.useJSONMode,
            messages: messages
        )
        return try makeRequest(config: config, body: body)
    }

    /// Builds the request for an incremental update summary (PRD §4.6, §5.2, §5.3).
    public static func updateSummaryRequest(
        config: ProviderConfig,
        previousSummaryText: String,
        changeSetText: String,
        images: [AIImage]
    ) throws -> URLRequest {
        let userText = Prompts.updateUser(
            previousSummaryText: previousSummaryText,
            changeSetText: changeSetText
        )
        let messages = [
            ChatRequest.Message(role: "system", content: .text(Prompts.updateSystem)),
            userMessage(text: userText, images: images, config: config)
        ]
        let body = ChatRequest(
            model: config.model,
            temperature: config.temperature,
            maxTokens: updateMaxTokens,
            responseFormatJSON: config.useJSONMode,
            messages: messages
        )
        return try makeRequest(config: config, body: body)
    }

    /// A minimal request used by "Test connection" (PRD §4.7).
    public static func testConnectionRequest(config: ProviderConfig) throws -> URLRequest {
        let body = ChatRequest(
            model: config.model,
            temperature: 0,
            maxTokens: 1,
            responseFormatJSON: false,
            messages: [ChatRequest.Message(role: "user", content: .text("ping"))]
        )
        return try makeRequest(config: config, body: body)
    }

    // MARK: - Helpers

    /// Builds a user message, attaching images only when the model supports vision.
    private static func userMessage(text: String, images: [AIImage], config: ProviderConfig) -> ChatRequest.Message {
        if config.supportsVision, !images.isEmpty {
            var parts: [ChatRequest.Part] = [.text(text)]
            parts.append(contentsOf: images.map { .imageURL($0.dataURL) })
            return ChatRequest.Message(role: "user", content: .parts(parts))
        }
        return ChatRequest.Message(role: "user", content: .text(text))
    }

    private static func makeRequest(config: ProviderConfig, body: ChatRequest) throws -> URLRequest {
        if let error = config.validationError { throw error }
        guard let url = config.chatCompletionsURL else { throw AIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }
}
