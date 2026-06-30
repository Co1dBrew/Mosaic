import Foundation

/// Abstraction over a cloud STT service so the app and tests can swap impls.
public protocol CloudTranscriber: Sendable {
    func transcribe(config: CloudTranscriptionConfig, audioData: Data, fileName: String) async throws -> String
}

/// `URLSession`-backed cloud transcriber for OpenAI-compatible
/// `/audio/transcriptions`. All work is async/off the main thread (PRD §6.3).
public struct URLSessionCloudTranscriber: CloudTranscriber {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func transcribe(config: CloudTranscriptionConfig, audioData: Data, fileName: String) async throws -> String {
        let request = try CloudTranscriptionRequestBuilder.buildRequest(config: config, audioData: audioData, fileName: fileName)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw TranscriptionError.offline
            case .timedOut:
                throw TranscriptionError.timedOut
            case .cancelled:
                throw TranscriptionError.cancelled
            default:
                throw TranscriptionError.requestFailed(message: urlError.localizedDescription)
            }
        } catch {
            throw TranscriptionError.requestFailed(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.requestFailed(message: "Invalid response")
        }
        switch http.statusCode {
        case 200...299:
            return try CloudTranscriptionParser.parseTranscript(from: data)
        case 401, 403:
            throw TranscriptionError.unauthorized
        case 404:
            throw TranscriptionError.unsupportedProvider
        case 413:
            throw TranscriptionError.fileTooLarge
        case 415:
            throw TranscriptionError.unsupportedFormat
        case 429:
            throw TranscriptionError.rateLimited
        default:
            throw TranscriptionError.serverError(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }
}
