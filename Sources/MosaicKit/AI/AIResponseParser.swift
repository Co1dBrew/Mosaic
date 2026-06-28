import Foundation

/// Defensive parsing of OpenAI-compatible Chat Completions responses and the
/// strict-JSON summary payloads they carry (PRD §5.6 "trim, strip ```json
/// fences, then JSON.parse; on failure prompt retry").
public enum AIResponseParser {

    // MARK: Chat Completions envelope

    private struct ChatCompletionEnvelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: MessageContent? }
            let message: Message?
        }
        struct ErrorBody: Decodable { let message: String?; let type: String?; let code: String? }
        let choices: [Choice]?
        let error: ErrorBody?
    }

    /// `content` may be a plain string or (rarely) an array of typed parts.
    private enum MessageContent: Decodable {
        case text(String)

        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(s)
                return
            }
            // Array form: [{ "type": "text", "text": "..." }, ...]
            struct Part: Decodable { let type: String?; let text: String? }
            if let parts = try? decoder.singleValueContainer().decode([Part].self) {
                let joined = parts.compactMap { $0.text }.joined()
                self = .text(joined)
                return
            }
            self = .text("")
        }

        var string: String { if case let .text(s) = self { return s }; return "" }
    }

    /// Extracts the assistant message text from a Chat Completions response body.
    /// Throws `AIError` for API-level error envelopes or unparseable bodies.
    public static func messageContent(from data: Data) throws -> String {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(ChatCompletionEnvelope.self, from: data) else {
            throw AIError.invalidJSON(raw: String(data: data, encoding: .utf8))
        }
        if let apiError = envelope.error, let msg = apiError.message {
            throw AIError.requestFailed(message: msg)
        }
        guard let content = envelope.choices?.first?.message?.content?.string,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidJSON(raw: String(data: data, encoding: .utf8))
        }
        return content
    }

    // MARK: JSON object extraction

    /// Normalizes raw model output into a parseable JSON object string:
    /// trims whitespace, removes ```json / ``` fences, and isolates the first
    /// balanced `{ ... }` object (ignoring braces inside strings).
    public static func extractJSONObject(from raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        // Strip Markdown code fences if present.
        if s.hasPrefix("```") {
            // Drop the opening fence line (``` or ```json).
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let fenceRange = s.range(of: "```", options: .backwards) {
                s = String(s[..<fenceRange.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = s.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < s.endIndex {
            let ch = s[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(s[start...idx])
                    }
                default: break
                }
            }
            idx = s.index(after: idx)
        }
        return nil // unbalanced
    }

    // MARK: Typed payload parsing

    public static func parseBaseSummary(fromMessage content: String) throws -> BaseSummaryDTO {
        guard let json = extractJSONObject(from: content),
              let data = json.data(using: .utf8) else {
            throw AIError.invalidJSON(raw: content)
        }
        guard let dto = try? JSONDecoder().decode(BaseSummaryDTO.self, from: data) else {
            throw AIError.invalidJSON(raw: content)
        }
        if dto.isEmpty { throw AIError.invalidJSON(raw: content) }
        return dto
    }

    public static func parseUpdateSummary(fromMessage content: String) throws -> UpdateSummaryDTO {
        guard let json = extractJSONObject(from: content),
              let data = json.data(using: .utf8) else {
            throw AIError.invalidJSON(raw: content)
        }
        guard let dto = try? JSONDecoder().decode(UpdateSummaryDTO.self, from: data) else {
            throw AIError.invalidJSON(raw: content)
        }
        if dto.isEmpty { throw AIError.invalidJSON(raw: content) }
        return dto
    }
}
