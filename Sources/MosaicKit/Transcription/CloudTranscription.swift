import Foundation

/// Resolved config for a cloud STT request. Reuses the chat provider's key/base
/// URL by default (assembled by the app), but is its own value type so STT can
/// be pointed at a different OpenAI-compatible `/audio/transcriptions` service.
public struct CloudTranscriptionConfig: Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public var languageHint: String?
    public var maxFileBytes: Int

    public init(
        baseURL: String,
        model: String,
        apiKey: String,
        languageHint: String? = nil,
        maxFileBytes: Int = 25 * 1024 * 1024 // OpenAI Whisper limit
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.languageHint = languageHint
        self.maxFileBytes = maxFileBytes
    }

    /// `/audio/transcriptions` endpoint, tolerant of trailing slashes or an
    /// already-complete path.
    public var audioTranscriptionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var normalized = trimmed
        while normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasSuffix("/audio/transcriptions") {
            return URL(string: normalized)
        }
        return URL(string: normalized + "/audio/transcriptions")
    }

    public var validationError: TranscriptionError? {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingAPIKey }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingAPIKey }
        if audioTranscriptionsURL == nil { return .invalidBaseURL }
        return nil
    }

    /// Best-effort audio MIME type from a file name extension.
    public static func mimeType(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "m4a", "mp4", "aac": return "audio/m4a"
        case "mp3", "mpeg", "mpga": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}

/// Builds the multipart/form-data `/audio/transcriptions` request (OpenAI Whisper
/// compatible). Pure & synchronous so it is fully unit-testable.
public enum CloudTranscriptionRequestBuilder {
    public static let requestTimeout: TimeInterval = 120

    public static func buildRequest(
        config: CloudTranscriptionConfig,
        audioData: Data,
        fileName: String
    ) throws -> URLRequest {
        if let error = config.validationError { throw error }
        guard audioData.count <= config.maxFileBytes else { throw TranscriptionError.fileTooLarge }
        guard let url = config.audioTranscriptionsURL else { throw TranscriptionError.invalidBaseURL }

        let boundary = "MosaicBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        field("model", config.model)
        if let hint = config.languageHint, !hint.isEmpty { field("language", hint) }
        field("response_format", "json")

        let mime = CloudTranscriptionConfig.mimeType(forFileName: fileName)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mime)\r\n\r\n")
        body.append(audioData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body
        return request
    }
}

/// Parses an OpenAI-compatible transcription response: `{ "text": "..." }`.
public enum CloudTranscriptionParser {
    private struct Response: Decodable {
        let text: String?
        struct APIError: Decodable { let message: String? }
        let error: APIError?
    }

    public static func parseTranscript(from data: Data) throws -> String {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TranscriptionError.invalidResponse(raw: String(data: data, encoding: .utf8))
        }
        if let apiError = response.error, let message = apiError.message {
            throw TranscriptionError.requestFailed(message: message)
        }
        guard let text = response.text else {
            throw TranscriptionError.invalidResponse(raw: String(data: data, encoding: .utf8))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Data {
    fileprivate mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
