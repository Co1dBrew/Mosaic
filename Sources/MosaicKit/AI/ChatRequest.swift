import Foundation

/// A compressed image ready to be embedded as a data URL in a multimodal
/// request (PRD §5.4). `base64` excludes the `data:` prefix.
public struct AIImage: Equatable, Sendable {
    public var base64: String
    public var mimeType: String

    public init(base64: String, mimeType: String = "image/jpeg") {
        self.base64 = base64
        self.mimeType = mimeType
    }

    public var dataURL: String { "data:\(mimeType);base64,\(base64)" }
}

/// Encodable OpenAI-compatible Chat Completions request body (PRD §7.2).
public struct ChatRequest: Encodable, Sendable {
    public var model: String
    public var temperature: Double
    public var maxTokens: Int
    public var responseFormatJSON: Bool
    public var messages: [Message]

    public init(model: String, temperature: Double, maxTokens: Int, responseFormatJSON: Bool, messages: [Message]) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.responseFormatJSON = responseFormatJSON
        self.messages = messages
    }

    public struct Message: Encodable, Sendable {
        public var role: String
        public var content: Content

        public init(role: String, content: Content) {
            self.role = role
            self.content = content
        }
    }

    /// Message content is either a plain string or an array of typed parts
    /// (text + images) for multimodal requests.
    public enum Content: Encodable, Sendable {
        case text(String)
        case parts([Part])

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(s): try container.encode(s)
            case let .parts(parts): try container.encode(parts)
            }
        }
    }

    public enum Part: Encodable, Sendable {
        case text(String)
        case imageURL(String)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
        struct ImageURL: Encodable { let url: String }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .text(t):
                try c.encode("text", forKey: .type)
                try c.encode(t, forKey: .text)
            case let .imageURL(url):
                try c.encode("image_url", forKey: .type)
                try c.encode(ImageURL(url: url), forKey: .imageURL)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }

    struct ResponseFormat: Encodable { let type = "json_object" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(messages, forKey: .messages)
        if responseFormatJSON {
            try c.encode(ResponseFormat(), forKey: .responseFormat)
        }
    }
}
